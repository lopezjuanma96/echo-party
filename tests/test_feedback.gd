extends SceneTree


const EchoScene := preload("res://src/echo/echo.tscn")
const EnemyScene := preload("res://src/enemy/enemy.tscn")
const HexcallerScene := preload("res://src/enemy/hexcaller.tscn")
const MainScene := preload("res://src/main/main.tscn")
const PHYSICS_STEP := 1.0 / 60.0

var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_run_tests")


func _run_tests() -> void:
	_test_cooldown_fractions()
	_test_intent_summaries()
	_test_display_dwell_and_cooldown_mapping()
	_test_hold_stance_displays_hold()
	_test_heal_intent_stays_visible()
	_test_target_heal_feedback()
	_test_overlay_glyphs_are_distinct()
	await _test_hud_text_and_state()

	if _failures.is_empty():
		print("Echo intent and cooldown feedback tests passed (8 cases).")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_cooldown_fractions() -> void:
	var actor := HeroActor.new()
	actor.apply_job_loadout(HeroProgression.JOB_MENDER)
	_expect(
		actor.get_weapon_cooldown_fraction() == 0.0 and actor.get_ability_cooldown_fraction() == 0.0,
		"ready weapon and ability report a 0 cooldown fraction"
	)
	var mace := WeaponCatalog.get_weapon(&"mace")
	actor.attack_cooldowns[&"mace"] = mace.cooldown
	actor.ability_cooldown_left = AbilityCatalog.get_ability(&"mend").cooldown
	_expect(
		actor.get_weapon_cooldown_fraction() == 1.0 and actor.get_ability_cooldown_fraction() == 1.0,
		"a just-used weapon and ability report a 1 cooldown fraction"
	)
	actor.tick_combat(mace.cooldown / 2.0)
	_expect(
		is_equal_approx(actor.get_weapon_cooldown_fraction(), 0.5)
		and is_equal_approx(actor.get_weapon_cooldown_fraction(&"mace"), 0.5),
		"cooldown fraction falls linearly as the weapon recharges"
	)
	var novice := HeroActor.new()
	_expect(
		novice.get_ability_cooldown_fraction() == 0.0
		and novice.get_weapon_cooldown_fraction(&"missing") == 0.0
		and HeroActor.format_cooldown(0.0) == "Ready"
		and HeroActor.format_cooldown(3.44) == "3.4s",
		"no ability, unknown weapon, and cooldown text are handled"
	)
	actor.free()
	novice.free()


func _test_intent_summaries() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var active := Node2D.new()
	arena.add_child(active)
	var echo := _echo_with_job(HeroProgression.JOB_VANGUARD, active, arena)
	echo.active_hero_label = "Hero 2"
	var drifter := _enemy(arena, Vector2(60.0, 0.0))
	echo._physics_process(PHYSICS_STEP)
	_expect(
		echo.current_intent == &"attack" and echo.get_intent_summary() == "Attack → Drifter · 60 px",
		"attack summary names the target and distance: %s" % echo.get_intent_summary()
	)
	drifter.free()
	_advance(echo, 0.6)

	var hexcaller := HexcallerScene.instantiate() as EnemyActor
	hexcaller.set_physics_process(false)
	hexcaller.position = Vector2(212.0, 0.0)
	arena.add_child(hexcaller)
	hexcaller.state = &"cast"
	hexcaller.state_time_left = hexcaller.CAST_DURATION
	echo.position = Vector2.ZERO
	echo._physics_process(PHYSICS_STEP)
	_expect(
		echo.current_intent == &"interrupt"
		and echo.get_display_intent() == &"interrupt"
		and echo.get_intent_summary() == "Interrupt → Hexcaller · %d px" % roundi(
			echo.global_position.distance_to(hexcaller.global_position)
		),
		"interrupt summary names the casting target: %s" % echo.get_intent_summary()
	)
	hexcaller.free()

	active.position = Vector2(400.0, 0.0)
	echo.position = Vector2(200.0, 0.0)
	_advance(echo, 0.3)
	var follow_distance := roundi(echo.global_position.distance_to(active.global_position))
	_expect(
		echo.get_display_intent() == &"follow"
		and echo.get_intent_summary() == "Follow → Hero 2 · %d px" % follow_distance,
		"follow summary names the active hero: %s" % echo.get_intent_summary()
	)
	current_scene = null
	arena.free()
	_clear_friendlies()


func _test_display_dwell_and_cooldown_mapping() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var active := Node2D.new()
	arena.add_child(active)
	var echo := _echo_with_job(HeroProgression.JOB_VANGUARD, active, arena)
	var drifter := _enemy(arena, Vector2(60.0, 0.0))
	echo.attack_cooldowns[&"sword"] = 10.0
	echo._physics_process(PHYSICS_STEP)
	_expect(
		echo.current_intent == &"hold" and echo.get_display_intent() == &"attack",
		"in-fight cooldown wait keeps raw hold but displays attack"
	)
	_expect(echo.intent_target == null, "raw cooldown hold has no intent target")

	# Dwell: an intent shown less than 0.25 s ago is not replaced.
	active.position = Vector2(900.0, 0.0)
	drifter.position = Vector2(2000.0, 0.0)
	echo._physics_process(PHYSICS_STEP)
	_expect(
		echo.current_intent == &"follow" and echo.get_display_intent() == &"attack",
		"display intent holds through the 0.25 s dwell"
	)
	_advance(echo, 0.2)
	_expect(echo.get_display_intent() == &"attack", "display intent still holds just before 0.25 s")
	_advance(echo, 0.1)
	_expect(echo.get_display_intent() == &"follow", "display intent changes after the dwell")
	current_scene = null
	arena.free()
	_clear_friendlies()


func _test_hold_stance_displays_hold() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var active := Node2D.new()
	arena.add_child(active)
	var echo := _echo_with_job(HeroProgression.JOB_VANGUARD, active, arena)
	var drifter := _enemy(arena, Vector2(60.0, 0.0))
	echo.attack_cooldowns[&"sword"] = 10.0
	echo.toggle_hold_position()
	echo._physics_process(PHYSICS_STEP)
	_expect(
		echo.current_intent == &"hold" and echo.get_display_intent() == &"hold",
		"hold stance on cooldown still displays hold"
	)
	drifter.free()
	_advance(echo, 0.3)
	_expect(
		echo.current_intent == &"hold" and echo.get_display_intent() == &"hold",
		"hold stance with no target displays hold"
	)
	current_scene = null
	arena.free()
	_clear_friendlies()


func _test_heal_intent_stays_visible() -> void:
	var active := _friendly_actor("Hero")
	var echo := _echo_with_job(HeroProgression.JOB_MENDER, active, root)
	echo.active_hero_label = "Hero 2"
	echo.position = Vector2(50.0, 0.0)
	active.health = 38.0
	echo._physics_process(PHYSICS_STEP)
	_expect(
		echo.current_intent == &"heal"
		and echo.get_display_intent() == &"heal"
		and echo.get_intent_summary() == "Mend → Hero 2 · 38%",
		"heal summary shows the target and its health before the cast: %s" % echo.get_intent_summary()
	)
	echo._physics_process(PHYSICS_STEP)
	_expect(
		echo.current_intent != &"heal" and echo.get_display_intent() == &"heal",
		"heal intent stays displayed after its single tick"
	)
	_advance(echo, 0.3)
	_expect(echo.get_display_intent() != &"heal", "heal intent clears after the dwell")

	# A heal that lands while another intent is still dwelling is latched.
	var latched := _echo_with_job(HeroProgression.JOB_MENDER, active, root)
	latched.position = Vector2(50.0, 0.0)
	active.health = 100.0
	latched._physics_process(PHYSICS_STEP)
	active.health = 50.0
	latched.current_intent = &"idle"
	latched._display_intent = &"follow"
	latched._display_age = 0.0
	latched._physics_process(PHYSICS_STEP)
	_expect(
		latched.current_intent == &"heal" and latched.get_display_intent() == &"follow",
		"a dwelling intent defers a one-tick heal"
	)
	_advance(latched, 0.3)
	_expect(latched.get_display_intent() == &"heal", "the deferred heal still becomes visible")
	var state := latched._mcp_state()
	_expect(
		state["display_intent"] == "heal" and state["intent_summary"] is String,
		"echo _mcp_state exposes display intent and summary as plain values"
	)
	echo.free()
	latched.free()
	_clear_friendlies()
	_clear_transient_combat()


func _test_target_heal_feedback() -> void:
	_clear_transient_combat()
	var caster := _friendly_actor("Mender")
	caster.apply_job_loadout(HeroProgression.JOB_MENDER)
	var ally := _friendly_actor("Ally")
	ally.position = Vector2(80.0, 0.0)
	ally.health = 20.0
	_expect(caster.use_ability(), "Mend casts for the feedback check")
	var target_effects: Array[Node] = []
	for node in get_nodes_in_group(HeroActor.TRANSIENT_COMBAT_GROUP):
		if node.get_script() == HeroActor.HEAL_TARGET_EFFECT:
			target_effects.append(node)
	_expect(
		target_effects.size() == 1
		and target_effects[0].target == ally
		and target_effects[0].amount_text == "+60"
		and target_effects[0].global_position == ally.global_position,
		"Mend spawns a +60 heal effect on the target as well as the caster pulse"
	)
	_clear_transient_combat()
	caster.free()
	ally.free()


func _test_overlay_glyphs_are_distinct() -> void:
	var glyphs: Dictionary = {}
	for intent: StringName in EchoStatusOverlay.INTENT_STYLES:
		glyphs[EchoStatusOverlay.INTENT_STYLES[intent]["glyph"]] = true
	var intents := [
		&"attack", &"approach", &"retreat", &"hold", &"follow", &"regroup", &"heal", &"interrupt",
	]
	var covered := true
	for intent in intents:
		covered = covered and EchoStatusOverlay.INTENT_STYLES.has(intent)
	_expect(
		covered
		and glyphs.size() == intents.size()
		and not EchoStatusOverlay.INTENT_STYLES.has(&"idle"),
		"every non-idle intent has its own glyph shape and idle draws none"
	)


func _test_hud_text_and_state() -> void:
	root.size = Vector2i(1280, 720)
	var main := MainScene.instantiate()
	root.add_child(main)
	current_scene = main
	main.apply_scenario(&"mender", &"mender", 5, &"")
	await process_frame
	await process_frame
	main.player.attack_cooldowns[&"mace"] = 0.0
	for weapon_id: StringName in main.echo.attack_cooldowns:
		main.echo.attack_cooldowns[weapon_id] = 0.0
	main._process(0.0)
	var state: Dictionary = main._mcp_state()
	_expect(
		main.echo_intent_value.text.begins_with("Intent: ")
		and main.echo_cooldowns_value.text == "Cooldowns: Mace Ready · Sling Ready · Mend Ready"
		and main.dodge_value.text == "[Space] Dodge — Ready",
		"HUD rows show intent, echo cooldowns, and dodge: %s | %s | %s" % [
			main.echo_intent_value.text, main.echo_cooldowns_value.text, main.dodge_value.text,
		]
	)
	main.player.dodge_cooldown_left = 0.4
	main.player.attack_cooldowns[&"mace"] = WeaponCatalog.get_weapon(&"mace").cooldown
	main.player.ability_cooldown_left = 3.4
	main.echo.attack_cooldowns[&"mace"] = 0.2
	main.echo.ability_cooldown_left = 3.4
	main._process(0.0)
	_expect(
		main.dodge_value.text == "[Space] Dodge — 0.4s"
		and main.ability_value.text == "[E] Mend — 3.4s"
		and is_equal_approx(main.weapon_cooldown_bar.value, 0.0)
		and main.echo_cooldowns_value.text == "Cooldowns: Mace 0.2s · Sling Ready · Mend 3.4s",
		"HUD shows cooling weapon bar, dodge, ability, and echo cooldown text: %s" % main.echo_cooldowns_value.text
	)
	state = main._mcp_state()
	_expect(
		state["dodge_hud_text"] == main.dodge_value.text
		and state["echo_intent_hud_text"] == main.echo_intent_value.text
		and state["echo_cooldowns_hud_text"] == main.echo_cooldowns_value.text,
		"Main _mcp_state exposes the new HUD rows as strings"
	)
	current_scene = null
	main.free()
	_clear_friendlies()
	paused = false


func _advance(echo: EchoActor, seconds: float) -> void:
	var steps := int(round(seconds / PHYSICS_STEP))
	for step in steps:
		echo._physics_process(PHYSICS_STEP)


func _enemy(parent: Node, enemy_position: Vector2) -> EnemyActor:
	var enemy := EnemyScene.instantiate() as EnemyActor
	enemy.set_physics_process(false)
	enemy.position = enemy_position
	parent.add_child(enemy)
	enemy.max_health = 100000.0
	enemy.health = enemy.max_health
	return enemy


func _echo_with_job(job_id: StringName, active: Node2D, parent: Node) -> EchoActor:
	var progression := HeroProgression.new()
	progression.grant_experience(200)
	progression.apply_attribute_choice(2, HeroProgression.ATTRIBUTE_MIGHT)
	progression.apply_job_choice(3, job_id)
	var echo := EchoScene.instantiate() as EchoActor
	echo.set_physics_process(false)
	parent.add_child(echo)
	if active.get_parent() == null:
		parent.add_child(active)
	echo.configure(HeroRecord.capture("feedback-test", "Feedback Test", progression), active)
	echo.grant_shared_experience(200)
	return echo


func _friendly_actor(actor_name: String) -> HeroActor:
	var actor := HeroActor.new()
	actor.name = actor_name
	actor.set_physics_process(false)
	root.add_child(actor)
	actor.add_to_group(&"friendly_actors")
	return actor


func _clear_transient_combat() -> void:
	for node in get_nodes_in_group(HeroActor.TRANSIENT_COMBAT_GROUP):
		node.free()


func _clear_friendlies() -> void:
	for actor in get_nodes_in_group(&"friendly_actors"):
		actor.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
