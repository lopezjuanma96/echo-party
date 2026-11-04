extends SceneTree


const EchoScene := preload("res://src/echo/echo.tscn")
const MainScene := preload("res://src/main/main.tscn")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_run_tests")


func _run_tests() -> void:
	_test_mender_progression_round_trip()
	_test_mender_loadout()
	_test_heal_target_selection_and_self_heal()
	_test_no_wounded_target_spends_no_cooldown()
	_test_ability_cooldown_ticks_and_resets()
	_test_mender_damage_multiplier()
	_test_echo_mender_cast_threshold()
	_test_apply_scenario()

	if _failures.is_empty():
		print("Mender, Mend, and scenario tests passed (8 cases).")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_mender_progression_round_trip() -> void:
	_expect(
		HeroProgression.JOB_IDS == [
			HeroProgression.JOB_VANGUARD,
			HeroProgression.JOB_ARCANIST,
			HeroProgression.JOB_MENDER,
		],
		"job choice order is Vanguard, Arcanist, Mender"
	)
	var progression := _mender_progression()
	var parsed: Variant = JSON.parse_string(JSON.stringify(progression.to_dict()))
	var replayed := HeroProgression.from_dict(parsed)
	_expect(
		replayed != null
		and replayed.to_dict() == progression.to_dict()
		and replayed.get_job_id() == HeroProgression.JOB_MENDER,
		"Mender progression survives a JSON round-trip"
	)


func _test_mender_loadout() -> void:
	_expect(WeaponCatalog.get_loadout(&"mender") == [&"mace", &"sling"], "Mender has Mace and Sling")
	var mace := WeaponCatalog.get_weapon(&"mace")
	var sling := WeaponCatalog.get_weapon(&"sling")
	_expect(
		mace != null
		and sling != null
		and is_equal_approx(mace.damage_multiplier, 0.8)
		and is_equal_approx(sling.damage_multiplier, 0.8),
		"both Mender weapons use the 0.8 damage multiplier"
	)
	_expect(
		JobCatalog.get_ability_id(&"mender") == &"mend"
		and JobCatalog.get_posture(&"mender") == &"support",
		"the job catalog identifies Mender support and Mend"
	)


func _test_heal_target_selection_and_self_heal() -> void:
	var caster := _friendly_actor("Mender")
	var ally_b := _friendly_actor("AllyB")
	var ally_a := _friendly_actor("AllyA")
	caster.apply_job_loadout(HeroProgression.JOB_MENDER)
	caster.health = 50.0
	ally_a.health = 40.0
	ally_b.health = 50.0
	_expect(caster.use_ability(), "Mend casts with a wounded ally in range")
	_expect(
		ally_a.health == 100.0
		and caster.health == 50.0
		and caster.total_healing_done == 60.0
		and ally_a.total_healing_done == 0.0,
		"lowest health fraction receives 60 healing and the caster tracks healing done"
	)

	ally_a.health = ally_a.max_health
	caster.ability_cooldown_left = 0.0
	caster.use_ability()
	_expect(caster.health == 80.0, "Mender self-heal is 50 percent")

	ally_a.health = 50.0
	caster.health = 50.0
	caster.ability_cooldown_left = 0.0
	caster.use_ability()
	_expect(caster.health == 80.0 and ally_a.health == 50.0, "equal fractions favor the active hero")

	caster.health = caster.max_health
	caster.ability_cooldown_left = 0.0
	caster.use_ability()
	_expect(ally_a.health == 100.0 and ally_b.health == 50.0, "remaining ties use natural node-name order")
	caster.free()
	ally_a.free()
	ally_b.free()


func _test_no_wounded_target_spends_no_cooldown() -> void:
	var caster := _friendly_actor("HealthyMender")
	caster.apply_job_loadout(HeroProgression.JOB_MENDER)
	var messages: Array[String] = []
	caster.ability_feedback.connect(func(message: String) -> void: messages.append(message))
	_expect(not caster.use_ability(), "Mend does nothing when nobody is wounded")
	_expect(
		caster.ability_cooldown_left == 0.0 and messages == ["No one needs healing"],
		"no-target Mend spends no cooldown and reports why"
	)
	caster.free()


func _test_ability_cooldown_ticks_and_resets() -> void:
	var actor := HeroActor.new()
	actor.apply_job_loadout(HeroProgression.JOB_MENDER)
	actor.ability_cooldown_left = 6.0
	actor.tick_combat(2.5)
	_expect(is_equal_approx(actor.ability_cooldown_left, 3.5), "combat ticks reduce ability cooldown")
	actor.reset_actor(Vector2.ZERO, false)
	_expect(actor.ability_cooldown_left == 0.0, "actor reset clears ability cooldown")
	actor.ability_cooldown_left = 4.0
	actor.apply_job_loadout(HeroProgression.JOB_MENDER)
	_expect(actor.ability_cooldown_left == 0.0, "applying a job resets ability cooldown")
	actor.free()


func _test_mender_damage_multiplier() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	current_scene = main
	main.player.apply_job_loadout(HeroProgression.JOB_MENDER)
	main.player.attack_damage = 25.0
	main.player.set_aim_direction(Vector2.RIGHT)
	var enemy := main.get_node("Enemies").get_child(0)
	enemy.set_physics_process(false)
	enemy.position = main.player.position + Vector2(50.0, 0.0)
	main.player._swing_melee(WeaponCatalog.get_weapon(&"mace"))
	_expect(enemy.health == 30.0, "25 base damage becomes 20 with Mace")
	main.free()
	current_scene = null


func _test_echo_mender_cast_threshold() -> void:
	var active := _friendly_actor("Hero")
	var echo := EchoScene.instantiate() as EchoActor
	echo.set_physics_process(false)
	root.add_child(echo)
	echo.configure(HeroRecord.capture("hero-mender", "Hero Mender", _mender_progression()), active)
	echo.grant_shared_experience(200)
	echo.position = Vector2(50.0, 0.0)
	active.health = 50.0
	echo._physics_process(0.0)
	_expect(
		active.health == 100.0
		and echo.current_intent == &"heal"
		and echo.intent_target == active
		and echo.ability_cooldown_left == 6.0,
		"echo Mender heals the active hero at 50 percent health"
	)
	active.health = 80.0
	echo.ability_cooldown_left = 0.0
	echo._physics_process(0.0)
	_expect(
		active.health == 80.0
		and echo.current_intent != &"heal"
		and echo.ability_cooldown_left == 0.0,
		"echo Mender does not cast at 80 percent health"
	)
	echo.free()
	active.free()


func _test_apply_scenario() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	_expect(
		main.apply_scenario(&"mender", &"vanguard", 5, &""),
		"scenario setup accepts a Mender player and Vanguard echo"
	)
	_expect(
		main.progression.level == 5
		and main.progression.get_job_id() == HeroProgression.JOB_MENDER
		and main.player.ability_id == &"mend"
		and main.player.attack_damage == 35.0
		and main.player.max_health == 120.0,
		"scenario player has deterministic level-5 progression and loadout"
	)
	_expect(
		is_instance_valid(main.echo)
		and main.echo.progression.level == 5
		and main.echo.job_id == HeroProgression.JOB_VANGUARD
		and main.echo.get_weapon_loadout() == [&"sword", &"lance"],
		"scenario records, spawns, and replays the echo to the requested level"
	)
	var player_state: Dictionary = main.player._mcp_state()
	var echo_state: Dictionary = main.echo._mcp_state()
	var enemy_state: Dictionary = main.get_node("Enemies").get_child(0)._mcp_state()
	_expect(
		player_state.has("ability_cooldown_left")
		and echo_state.get("command_status") == &"follow"
		and enemy_state.get("enemy_id") == &"drifter",
		"scenario actors expose live structured state"
	)
	main.free()


func _friendly_actor(actor_name: String) -> HeroActor:
	var actor := HeroActor.new()
	actor.name = actor_name
	root.add_child(actor)
	actor.add_to_group(&"friendly_actors")
	return actor


func _mender_progression() -> HeroProgression:
	var progression := HeroProgression.new()
	progression.grant_experience(200)
	progression.apply_attribute_choice(2, HeroProgression.ATTRIBUTE_MIGHT)
	progression.apply_job_choice(3, HeroProgression.JOB_MENDER)
	return progression


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
