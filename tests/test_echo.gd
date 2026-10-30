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
	_test_echo_commands()
	_test_new_run_reset()
	_test_run_transition_clears_stale_choice()
	_test_third_job_choice()
	await _test_hud_panels_do_not_overlap()

	if _failures.is_empty():
		print("Hero record, echo, and run reset tests passed (10 cases).")
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
	var mender_progression := HeroProgression.new()
	mender_progression.grant_experience(200)
	mender_progression.apply_attribute_choice(2, HeroProgression.ATTRIBUTE_MIGHT)
	mender_progression.apply_job_choice(3, HeroProgression.JOB_MENDER)
	var mender_echo := EchoScene.instantiate() as EchoActor
	root.add_child(mender_echo)
	mender_echo.configure(HeroRecord.capture("hero-mender", "Hero Mender", mender_progression), active)
	mender_echo.grant_shared_experience(200)
	_expect(mender_echo.choose_weapon_for_distance(70.0) == &"mace", "Mender echo uses Mace in melee range")
	_expect(mender_echo.choose_weapon_for_distance(100.0) == &"sling", "Mender echo uses Sling beyond melee range")
	mender_echo.free()
	echo.free()
	later.free()
	earlier.free()
	active.free()


func _test_echo_commands() -> void:
	var active := Node2D.new()
	root.add_child(active)
	var echo := EchoScene.instantiate() as EchoActor
	root.add_child(echo)
	echo.configure(HeroRecord.capture("hero-6", "Hero 6", _arcanist_progression()), active)
	echo.grant_shared_experience(200)
	var nearest := EnemyScene.instantiate()
	nearest.stable_spawn_order = 1
	nearest.position = Vector2(-100.0, 0.0)
	root.add_child(nearest)
	var focused := EnemyScene.instantiate()
	focused.stable_spawn_order = 2
	focused.position = Vector2(300.0, 0.0)
	root.add_child(focused)
	var candidates: Array[Node] = [nearest, focused]
	_expect(echo.command_focus(focused), "focus command accepts a live enemy inside the leash")
	_expect(
		echo.choose_target(candidates) == focused
		and echo.get_command_status() == &"focus",
		"focused target overrides nearest-target selection"
	)
	_expect(echo.toggle_hold_position() and echo.is_holding_position, "hold stance can be enabled")
	echo.attack_cooldowns[&"wand"] = 1.0
	echo.attack_cooldowns[&"staff"] = 1.0
	echo.current_target = focused
	echo._fight_target()
	_expect(
		echo.velocity == Vector2.ZERO and echo.current_intent in [&"hold", &"attack"],
		"hold stance attacks without approach or retreat movement"
	)
	echo.command_regroup()
	_expect(
		echo.focused_target == null
		and not echo.is_holding_position
		and echo.is_regrouping,
		"regroup clears focus and hold stance"
	)
	echo.position = Vector2(300.0, 0.0)
	echo._physics_process(0.0)
	_expect(
		echo.current_intent == &"regroup" and echo.velocity.x < 0.0,
		"regroup moves toward the active hero instead of fighting"
	)
	echo.position = Vector2(10.0, 0.0)
	echo._physics_process(0.0)
	_expect(not echo.is_regrouping, "regroup completes after reaching the active hero")
	echo.toggle_hold_position()
	echo.position = Vector2(300.0, 0.0)
	nearest.position = Vector2(2000.0, 0.0)
	focused.position = Vector2(2000.0, 0.0)
	echo._physics_process(0.0)
	_expect(
		echo.velocity == Vector2.ZERO and echo.current_intent == &"hold",
		"hold stance stays in place when no target is available"
	)
	echo.free()
	nearest.free()
	focused.free()
	active.free()


func _test_new_run_reset() -> void:
	var player = PlayerScript.new()
	player.max_health = 160.0
	player.health = 12.0
	player.attack_damage = 55.0
	player.apply_job_loadout(HeroProgression.JOB_VANGUARD)
	player.attack_cooldowns[&"sword"] = 2.0
	player.apply_job_loadout(HeroProgression.JOB_MENDER)
	player.ability_cooldown_left = 3.0
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
		and float(player.attack_cooldowns[&"knife"]) == 0.0
		and player.ability_id == &""
		and player.ability_cooldown_left == 0.0,
		"new run restores Knife and clears attack and ability cooldowns"
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
	var focus_target := main.get_node("Enemies").get_child(0) as Node2D
	focus_target.position = Vector2(320.0, 0.0)
	_expect(
		main.command_echo_focus_at(focus_target.global_position)
		and main.echo.focused_target == focus_target,
		"mouse-world focus command selects the intended arena enemy"
	)
	main._process(0.0)
	_expect(
		main.focus_marker.get("target") == focus_target
		and main.echo_command_value.text.begins_with("Command: Focus"),
		"focus command updates its target marker and HUD status"
	)
	main.echo.command_regroup()
	main._update_run_hud()
	_expect(
		main.echo_command_value.text.begins_with("Command: Regroup"),
		"regroup command is visible in the HUD"
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


func _test_third_job_choice() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	main.progression.grant_experience(200)
	main.progression.apply_attribute_choice(2, HeroProgression.ATTRIBUTE_MIGHT)
	main._show_next_choice_if_needed()
	var shortcut_event := main.choice_three_button.shortcut.events[0] as InputEventKey
	_expect(
		main.choice_three_button.visible
		and shortcut_event != null
		and shortcut_event.physical_keycode == KEY_3,
		"advancement shows the third job button with shortcut 3"
	)
	main._on_choice_three_pressed()
	_expect(
		main.progression.get_job_id() == HeroProgression.JOB_MENDER
		and main.player.get_weapon_loadout() == [&"mace", &"sling"]
		and main.player.ability_id == &"mend",
		"third choice applies the Mender job and ability"
	)
	main.free()
	paused = false


func _test_hud_panels_do_not_overlap() -> void:
	root.size = Vector2i(1280, 720)
	var main := MainScene.instantiate()
	root.add_child(main)
	current_scene = main
	main.apply_scenario(&"mender", &"mender", 5, &"")
	await process_frame
	await process_frame
	var instructions := main.get_node("HUD/Instructions") as Control
	var run_status := main.get_node("HUD/RunStatus") as Control
	var progression := main.get_node("HUD/Progression") as Control
	var weapon := main.get_node("HUD/Weapon") as Control
	var health := main.get_node("HUD/Health") as Control
	_expect(
		instructions.get_rect().end.y + 12.0 <= run_status.get_rect().position.y,
		"controls and run/echo panels retain vertical separation"
	)
	_expect(
		run_status.get_rect().end.y + 12.0 <= progression.get_rect().position.y,
		"run/echo and progression panels retain vertical separation"
	)
	_expect(
		progression.get_rect().end.y <= root.size.y,
		"left-hand HUD panels fit inside the viewport"
	)
	_expect(
		run_status.get_rect().size.y >= run_status.get_combined_minimum_size().y
		and instructions.get_rect().size.y >= instructions.get_combined_minimum_size().y,
		"left-hand panels are tall enough for their content"
	)
	_expect(
		weapon.get_rect().position.y >= 0.0
		and weapon.get_rect().end.y <= root.size.y
		and not weapon.get_rect().intersects(health.get_rect())
		and not weapon.get_rect().intersects(run_status.get_rect())
		and not weapon.get_rect().intersects(progression.get_rect()),
		"weapon panel fits the viewport and overlaps no other panel"
	)
	var trial := main.get_node("HUD/Trial") as Control
	var banner := main.get_node("HUD/TrialBanner") as Control
	var report := main.get_node("HUD/TrialReport") as Control
	main.encounter_director.state = EncounterDirector.STATE_WARNING
	main.encounter_director.state_time_left = 3.0
	main._update_trial_hud()
	main._on_trial_report_ready({
		"display_name": "Bell Court",
		"outcome": "failed",
		"time": 31.0,
		"casts_landed": 3,
		"casts_broken": 1,
		"damage_taken": {
			"brute": {"hero": 80.0, "echo": 40.0},
			"hexcaller": {"hero": 45.0, "echo": 45.0},
			"skitter": {"hero": 60.0, "echo": 30.0},
			"slinger": {"hero": 15.0, "echo": 15.0},
		},
		"healing_done": 0.0,
		"had_echo": true,
		"echo_survived": false,
		"uncovered": ["interrupt", "area", "sustain"],
	})
	await process_frame
	await process_frame
	var panels: Array[Control] = [instructions, run_status, progression, weapon, health]
	_expect(
		trial.visible
		and trial.get_rect().position.y >= 0.0
		and trial.get_rect().size.y >= trial.get_combined_minimum_size().y
		and trial.get_rect().end.y + 12.0 <= banner.get_rect().position.y,
		"Trial panel is visible, fits its content, and sits above the warning banner"
	)
	var trial_clear := true
	var report_clear := true
	for other in panels:
		trial_clear = trial_clear and not trial.get_rect().grow(8.0).intersects(other.get_rect())
		report_clear = report_clear and not report.get_rect().grow(8.0).intersects(other.get_rect())
	_expect(trial_clear, "Trial panel keeps 8 px clear of every existing panel")
	_expect(
		banner.visible
		and banner.get_rect().end.y <= root.size.y
		and not banner.get_rect().grow(8.0).intersects(instructions.get_rect())
		and not banner.get_rect().intersects(health.get_rect())
		and not banner.get_rect().intersects(trial.get_rect()),
		"warning banner overlaps no panel"
	)
	_expect(
		report.visible
		and report.get_rect().position.y >= 0.0
		and report.get_rect().end.y <= root.size.y
		and report.get_rect().end.x <= root.size.x
		and report.get_rect().size.y >= report.get_combined_minimum_size().y
		and report_clear
		and not report.get_rect().intersects(trial.get_rect())
		and not report.get_rect().intersects(banner.get_rect()),
		"worst-case Trial report fits the viewport and overlaps no panel: %s" % [report.get_rect()]
	)
	main.encounter_director.state = EncounterDirector.STATE_IDLE
	current_scene = null
	main.free()


func _arcanist_progression() -> HeroProgression:
	var progression := HeroProgression.new()
	progression.grant_experience(200)
	progression.apply_attribute_choice(2, HeroProgression.ATTRIBUTE_VITALITY)
	progression.apply_job_choice(3, HeroProgression.JOB_ARCANIST)
	return progression


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
