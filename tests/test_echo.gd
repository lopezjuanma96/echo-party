extends SceneTree


const EchoScene := preload("res://src/echo/echo.tscn")
const EnemyScene := preload("res://src/enemy/enemy.tscn")
const MainScene := preload("res://src/main/main.tscn")
const PlayerScript := preload("res://src/player/player.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_run_tests")


func _run_tests() -> void:
	_test_hero_record_round_trip_and_independence()
	_test_hero_record_rejection()
	_test_echo_replays_history_by_level()
	_test_multi_level_replay_and_incomplete_history()
	_test_deterministic_target_and_weapon_selection()
	_test_new_run_reset()
	_test_run_transition_clears_stale_choice()

	if _failures.is_empty():
		print("Hero record, echo, and run reset tests passed (7 cases).")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
	return


func _test_hero_record_round_trip_and_independence() -> void:
	var progression := _arcanist_progression()
	var record := HeroRecord.capture("hero-7", "Hero 7", progression)
	var original := record.to_dict()
	var parsed: Variant = JSON.parse_string(JSON.stringify(original))
	var replayed := HeroRecord.from_dict(parsed)
	_expect(replayed != null and replayed.to_dict() == original, "HeroRecord JSON round-trip is lossless")
	progression.grant_experience(100)
	progression.apply_attribute_choice(4, HeroProgression.ATTRIBUTE_MIGHT)
	_expect(record.to_dict() == original, "HeroRecord is independent from later progression mutation")


func _test_hero_record_rejection() -> void:
	_expect(HeroRecord.from_dict({}) == null, "HeroRecord rejects missing fields")
	_expect(
		HeroRecord.from_dict({
			"runtime_id": "hero-1",
			"display_name": "Hero 1",
			"progression": {"level": 2, "experience": 0, "choices": []},
		}) == null,
		"HeroRecord rejects progression that cannot be replayed"
	)
	_expect(
		HeroRecord.from_dict({
			"runtime_id": "hero-1",
			"display_name": "Hero 1",
			"progression": HeroProgression.new().to_dict(),
			"extra": true,
		}) == null,
		"HeroRecord rejects unknown fields"
	)


func _test_echo_replays_history_by_level() -> void:
	var active := Node2D.new()
	root.add_child(active)
	var progression := _arcanist_progression()
	var record := HeroRecord.capture("hero-2", "Hero 2", progression)
	var echo := EchoScene.instantiate() as EchoActor
	root.add_child(echo)
	_expect(echo.configure(record, active), "echo accepts a valid HeroRecord")
	_expect(
		echo.progression.level == 1
		and echo.job_id == HeroProgression.JOB_NOVICE
		and echo.get_weapon_loadout() == [&"knife"]
		and echo.max_health == HeroProgression.BASE_MAX_HEALTH,
		"echo restarts as a level-1 Novice"
	)
	echo.grant_shared_experience(100)
	_expect(
		echo.progression.level == 2
		and echo.job_id == HeroProgression.JOB_NOVICE
		and echo.max_health == progression.get_max_health(),
		"echo replays its recorded level-2 Vitality choice"
	)
	echo.grant_shared_experience(100)
	_expect(
		echo.progression.level == 3
		and echo.job_id == HeroProgression.JOB_ARCANIST
		and echo.get_weapon_loadout() == [&"wand", &"staff"],
		"echo replays its recorded level-3 job choice"
	)
	_expect(
		echo.grant_shared_experience(100) == 0
		and echo.progression.level == 3
		and echo.progression.experience == 200,
		"echo stops at its highest fully recorded level"
	)
	echo.free()
	active.free()


func _test_multi_level_replay_and_incomplete_history() -> void:
	var active := Node2D.new()
	root.add_child(active)
	var progression := HeroProgression.new()
	progression.grant_experience(250)
	progression.apply_attribute_choice(2, HeroProgression.ATTRIBUTE_MIGHT)
	progression.apply_job_choice(3, HeroProgression.JOB_VANGUARD)
	var echo := EchoScene.instantiate() as EchoActor
	root.add_child(echo)
	echo.configure(HeroRecord.capture("hero-4", "Hero 4", progression), active)
	_expect(
		echo.grant_shared_experience(250) == 2
		and echo.progression.experience == 200
		and echo.attack_damage == 30.0
		and echo.job_id == HeroProgression.JOB_VANGUARD
		and echo.get_weapon_loadout() == [&"sword", &"lance"],
		"one large grant replays Might and Vanguard before clamping to recorded level"
	)
	var incomplete_progression := HeroProgression.new()
	incomplete_progression.grant_experience(100)
	var incomplete_echo := EchoScene.instantiate() as EchoActor
	root.add_child(incomplete_echo)
	incomplete_echo.configure(
		HeroRecord.capture("hero-5", "Hero 5", incomplete_progression),
		active
	)
	_expect(
		incomplete_echo.get_replay_level_limit() == 1
		and incomplete_echo.grant_shared_experience(100) == 0
		and incomplete_echo.progression.level == 1,
		"incomplete history stops before its unresolved level"
	)
	echo.free()
	incomplete_echo.free()
	active.free()


func _test_deterministic_target_and_weapon_selection() -> void:
	var active := Node2D.new()
	root.add_child(active)
	var echo := EchoScene.instantiate() as EchoActor
	root.add_child(echo)
	echo.configure(HeroRecord.capture("hero-3", "Hero 3", _arcanist_progression()), active)
	echo.grant_shared_experience(200)
	var later := EnemyScene.instantiate()
	later.name = "EnemyA"
	later.stable_spawn_order = 9
	later.position = Vector2(100.0, 0.0)
	root.add_child(later)
	var earlier := EnemyScene.instantiate()
	earlier.name = "EnemyZ"
	earlier.stable_spawn_order = 4
	earlier.position = Vector2(-100.0, 0.0)
	root.add_child(earlier)
	var candidates: Array[Node] = [later, earlier]
	_expect(echo.choose_target(candidates) == earlier, "equal-distance targets use stable spawn order")
	_expect(echo.choose_weapon_for_distance(300.0) == &"wand", "echo chooses shortest ranged weapon that reaches")
	_expect(echo.choose_weapon_for_distance(600.0) == &"staff", "echo chooses long-range weapon when needed")
	echo.free()
	later.free()
	earlier.free()
	active.free()


func _test_new_run_reset() -> void:
	var player = PlayerScript.new()
	player.max_health = 160.0
	player.health = 12.0
	player.attack_damage = 55.0
	player.apply_job_loadout(HeroProgression.JOB_VANGUARD)
	player.attack_cooldowns[&"sword"] = 2.0
	player.dodge_time_left = 0.1
	player.dodge_cooldown_left = 0.4
	player.suppress_combat_input = true
	player.reset_for_new_run(Vector2(12.0, 8.0))
	_expect(player.position == Vector2(12.0, 8.0), "new run moves active hero to spawn")
	_expect(
		player.max_health == 100.0 and player.health == 100.0 and player.attack_damage == 25.0,
		"new run restores level-1 Novice stats and full health"
	)
	_expect(
		player.get_weapon_loadout() == [&"knife"]
		and player.get_selected_weapon_id() == &"knife"
		and float(player.attack_cooldowns[&"knife"]) == 0.0,
		"new run restores Knife and clears attack cooldown"
	)
	_expect(
		player.dodge_time_left == 0.0
		and player.dodge_cooldown_left == 0.0
		and not player.suppress_combat_input,
		"new run clears dodge and input state"
	)
	player.free()


func _test_run_transition_clears_stale_choice() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	main.progression = _arcanist_progression()
	main._defeat_transition_pending = true
	main.choice_modal.show()
	paused = true
	main._on_enemy_defeated(50)
	_expect(main.progression.experience == 200, "old-run rewards are ignored during defeat transition")
	main._start_next_run()
	_expect(not paused and not main.choice_modal.visible, "new run clears stale modal pause state")
	_expect(
		main.run_number == 2
		and main.progression.level == 1
		and main.progression.experience == 0,
		"defeat transition starts a fresh numbered run"
	)
	_expect(
		main.latest_echo_record != null
		and main.latest_echo_record.replay_progression().experience == 200
		and is_instance_valid(main.echo),
		"defeat transition records the old build and spawns its echo"
	)
	_expect(
		main.echo.progression.level == 1
		and main.echo.job_id == HeroProgression.JOB_NOVICE,
		"new echo starts its recorded history from level 1"
	)
	main._defeat_transition_pending = false
	main._on_enemy_defeated(50)
	main._on_enemy_defeated(50)
	_expect(
		main.progression.level == 2
		and main.echo.progression.level == 2
		and main.echo.max_health == 120.0,
		"active hero and echo gain shared XP while echo replays its choice"
	)
	main._apply_pending_choice(0)
	main._on_echo_defeated()
	main._on_enemy_defeated(50)
	_expect(main.echo_value.text == "Echo: Defeated", "echo defeat status persists for the run")
	main.free()
	paused = false


func _arcanist_progression() -> HeroProgression:
	var progression := HeroProgression.new()
	progression.grant_experience(200)
	progression.apply_attribute_choice(2, HeroProgression.ATTRIBUTE_VITALITY)
	progression.apply_job_choice(3, HeroProgression.JOB_ARCANIST)
	return progression


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
