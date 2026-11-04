extends SceneTree


const EchoScene := preload("res://src/echo/echo.tscn")
const EnemyScene := preload("res://src/enemy/enemy.tscn")
const EnemyShotScene := preload("res://src/enemy/enemy_shot.tscn")
const HexcallerScene := preload("res://src/enemy/hexcaller.tscn")
const SlingerScene := preload("res://src/enemy/slinger.tscn")
const PlayerScript := preload("res://src/player/player.gd")
const PHYSICS_STEP := 1.0 / 60.0

var _failures: Array[String] = []
var _dealt_events: Array[Array] = []


func _init() -> void:
	call_deferred(&"_run_tests")


func _run_tests() -> void:
	_test_interrupt_rules()
	_test_cast_timing_cooldown_and_first_cast()
	_test_circle_stays_at_locked_position()
	_test_circle_damages_only_friendlies_inside()
	_test_slinger_target_choice()
	_test_slinger_windup_aim_freeze_and_dart()
	_test_dart_hits_first_friendly_and_dodge_roll_avoids_it()
	_test_echo_prefers_casters_but_focus_wins()
	_test_echo_lance_and_interrupt_intent()
	_test_scenarios_and_spawner_table()

	if _failures.is_empty():
		print("Hexcaller, Slinger, and echo interrupt tests passed (10 cases).")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_interrupt_rules() -> void:
	var lance_hexcaller := _casting_hexcaller()
	_expect(lance_hexcaller.is_casting(), "Hexcaller reports is_casting while casting")
	lance_hexcaller.take_damage(25.0, true)
	_expect(
		not lance_hexcaller.is_casting()
		and lance_hexcaller.state == &"stunned"
		and is_equal_approx(lance_hexcaller.state_time_left, 1.5)
		and lance_hexcaller.interrupt_label.visible
		and lance_hexcaller.interrupt_label.text == "INTERRUPTED",
		"One interrupting hit breaks the cast, stuns for 1.5 s, and shows INTERRUPTED"
	)
	var label_frames := 0
	while lance_hexcaller.interrupt_label.visible and label_frames < 60:
		label_frames += 1
		lance_hexcaller._physics_process(PHYSICS_STEP)
	_expect(absi(label_frames - 48) <= 1, "INTERRUPTED shows for 0.8 seconds")
	var stun_frames := label_frames
	while lance_hexcaller.state == &"stunned" and stun_frames < 120:
		stun_frames += 1
		lance_hexcaller._physics_process(PHYSICS_STEP)
	_expect(absi(stun_frames - 90) <= 1, "Interrupt stun lasts 1.5 seconds")
	lance_hexcaller.free()

	# Three Mender-sized hits reach 60 cumulative damage without lethal damage.
	var mender_hexcaller := _casting_hexcaller()
	mender_hexcaller.take_damage(20.0)
	mender_hexcaller.take_damage(20.0)
	_expect(mender_hexcaller.is_casting(), "Two non-interrupting 20-damage hits do not break the cast")
	mender_hexcaller.take_damage(20.0)
	_expect(mender_hexcaller.state == &"stunned", "Three 20-damage hits break the cast at 60 cumulative damage")
	mender_hexcaller.free()

	# Extra health isolates the cumulative-damage rule from the death rule.
	var sturdy_hexcaller := _casting_hexcaller()
	sturdy_hexcaller.max_health = 200.0
	sturdy_hexcaller.health = 200.0
	sturdy_hexcaller.take_damage(25.0)
	sturdy_hexcaller.take_damage(25.0)
	_expect(sturdy_hexcaller.is_casting(), "Two non-interrupting 25-damage hits (50) do not break the cast")
	sturdy_hexcaller.take_damage(25.0)
	_expect(sturdy_hexcaller.state == &"stunned", "Three 25-damage hits (75) break the cast")
	sturdy_hexcaller.free()

	var idle_hexcaller := HexcallerScene.instantiate() as EnemyActor
	idle_hexcaller.set_physics_process(false)
	root.add_child(idle_hexcaller)
	idle_hexcaller.take_damage(25.0, true)
	_expect(idle_hexcaller.state == &"kite", "An interrupting hit outside a cast does not stun")
	idle_hexcaller.free()
	_clear_friendlies()


func _test_cast_timing_cooldown_and_first_cast() -> void:
	var target := _friendly_actor("Target", Vector2(300.0, 0.0))
	var hexcaller := HexcallerScene.instantiate() as EnemyActor
	hexcaller.spawn_grace = 0.5
	hexcaller.set_physics_process(false)
	root.add_child(hexcaller)
	var frames := 0
	while not hexcaller.is_casting() and frames < 200:
		frames += 1
		hexcaller._physics_process(PHYSICS_STEP)
	_expect(absi(frames - 90) <= 2, "First cast starts 1.0 s after the 0.5 s spawn grace")
	_expect(
		hexcaller.telegraph.top_level and hexcaller.telegraph.z_index == 0,
		"Locked circle telegraph is world-locked and drawn at z 0 above the arena floor"
	)
	var cast_frames := 0
	while hexcaller.is_casting() and cast_frames < 200:
		cast_frames += 1
		hexcaller._physics_process(PHYSICS_STEP)
	_expect(absi(cast_frames - 120) <= 1, "Hexcaller cast resolves after 2.0 seconds")
	_expect(
		is_equal_approx(hexcaller.cast_cooldown_left, 2.0) and hexcaller.state == &"kite",
		"Hexcaller starts a 2.0 s cast cooldown after resolving"
	)
	var state := hexcaller._mcp_state()
	_expect(
		state["enemy_id"] is String
		and state["target"] is String
		and state["state"] is String
		and state["is_casting"] is bool
		and state.has("circle_x")
		and state.has("cast_progress"),
		"Hexcaller _mcp_state exposes plain values"
	)
	hexcaller.free()
	target.free()


func _test_circle_stays_at_locked_position() -> void:
	var target := _friendly_actor("Target", Vector2(300.0, 0.0))
	var hexcaller := _casting_hexcaller()
	var locked: Vector2 = hexcaller.circle_center
	_expect(locked == Vector2(300.0, 0.0), "Circle locks on the nearest friendly's position at cast start")
	target.position = Vector2(-300.0, 0.0)
	for step in 60:
		hexcaller._physics_process(PHYSICS_STEP)
	_expect(
		hexcaller.circle_center == locked and hexcaller.telegraph.global_position == locked,
		"Circle stays at the locked position when the target moves"
	)
	_expect(
		hexcaller.get_cast_progress() > 0.4 and hexcaller.get_cast_progress() < 0.6,
		"Cast progress tracks elapsed cast time"
	)
	var frames := 0
	while hexcaller.is_casting() and frames < 100:
		frames += 1
		hexcaller._physics_process(PHYSICS_STEP)
	_expect(is_equal_approx(target.health, 100.0), "A target that left the locked circle takes no damage")
	hexcaller.free()
	_clear_friendlies()


func _test_circle_damages_only_friendlies_inside() -> void:
	var inside := _friendly_actor("Inside", Vector2(300.0, 0.0))
	var edge := _friendly_actor("Edge", Vector2(400.0, 0.0))
	var outside := _friendly_actor("Outside", Vector2(300.0, 150.0))
	var defeated := _friendly_actor("Defeated", Vector2(300.0, 10.0))
	defeated.is_defeated = true
	var dodging := _player_actor("Dodging", Vector2(310.0, 0.0))
	dodging.dodge_time_left = 5.0
	var hexcaller := _casting_hexcaller()
	_dealt_events.clear()
	hexcaller.dealt_damage.connect(_record_dealt_damage)
	var frames := 0
	while hexcaller.is_casting() and frames < 130:
		frames += 1
		hexcaller._physics_process(PHYSICS_STEP)
	_expect(is_equal_approx(inside.health, 45.0), "Circle deals 55 damage to a friendly inside it")
	_expect(is_equal_approx(edge.health, 45.0), "Circle includes friendlies up to radius 110")
	_expect(is_equal_approx(outside.health, 100.0), "Circle deals no damage outside radius 110")
	_expect(is_equal_approx(defeated.health, 100.0), "Circle skips defeated friendlies")
	_expect(is_equal_approx(dodging.health, 100.0), "A dodge-rolling hero takes no circle damage")
	var inside_event_found := false
	for event in _dealt_events:
		if event[0] == &"hexcaller" and event[1] == inside and is_equal_approx(event[2], 55.0):
			inside_event_found = true
	_expect(inside_event_found, "Circle damage emits dealt_damage with the applied amount")
	hexcaller.free()
	_clear_friendlies()


func _test_slinger_target_choice() -> void:
	var slinger := SlingerScene.instantiate() as EnemyActor
	slinger.set_physics_process(false)
	root.add_child(slinger)
	var wounded := _friendly_actor("Wounded", Vector2(-300.0, 0.0))
	wounded.health = 40.0
	var healthy := _friendly_actor("Healthy", Vector2(100.0, 0.0))
	slinger.fire_cooldown_left = 0.0
	slinger._physics_process(PHYSICS_STEP)
	_expect(
		slinger.state == &"windup" and slinger.target == wounded,
		"Slinger targets the 0.4 health fraction friendly over the nearer 1.0 one"
	)
	var far := _friendly_actor("Far", Vector2(0.0, -700.0))
	far.health = 10.0
	slinger.state = &"kite"
	slinger.fire_cooldown_left = 0.0
	slinger._physics_process(PHYSICS_STEP)
	_expect(slinger.target == wounded, "Slinger ignores wounded friendlies beyond 600 pixels")
	wounded.health = 100.0
	healthy.free()
	var tie_near := _friendly_actor("TieNear", Vector2(0.0, 200.0))
	var tie_far := _friendly_actor("AATieFar", Vector2(400.0, 0.0))
	slinger.state = &"kite"
	slinger.fire_cooldown_left = 0.0
	slinger._physics_process(PHYSICS_STEP)
	_expect(
		slinger.target == tie_near and tie_far != null,
		"Slinger breaks equal health fractions by distance"
	)
	slinger.free()
	_clear_friendlies()


func _test_slinger_windup_aim_freeze_and_dart() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var target := _friendly_actor("Target", Vector2(300.0, 0.0))
	var slinger := SlingerScene.instantiate() as EnemyActor
	slinger.set_physics_process(false)
	arena.add_child(slinger)
	slinger.fire_cooldown_left = 0.0
	_dealt_events.clear()
	slinger.dealt_damage.connect(_record_dealt_damage)
	slinger._physics_process(PHYSICS_STEP)
	var frames := 1
	for step in 19:
		frames += 1
		slinger._physics_process(PHYSICS_STEP)
	target.position = Vector2(0.0, 300.0)
	slinger._physics_process(PHYSICS_STEP)
	frames += 1
	_expect(slinger.aim_direction.y > 0.95, "Aim line tracks the target during the first 0.45 seconds")
	while frames < 33:
		frames += 1
		slinger._physics_process(PHYSICS_STEP)
	var frozen: Vector2 = slinger.aim_direction
	target.position = Vector2(-300.0, 0.0)
	frames += 1
	slinger._physics_process(PHYSICS_STEP)
	_expect(slinger.aim_direction == frozen, "Aim line freezes for the last 0.15 seconds")
	while slinger.state == &"windup" and frames < 80:
		frames += 1
		slinger._physics_process(PHYSICS_STEP)
	_expect(absi(frames - 36) <= 1, "Slinger windup lasts 0.6 seconds")
	var shot: EnemyShot
	for child in arena.get_children():
		if child is EnemyShot:
			shot = child
	_expect(
		shot != null
		and shot.travel_direction.is_equal_approx(frozen)
		and is_equal_approx(shot.damage, 14.0)
		and is_equal_approx(shot.move_speed, 420.0)
		and is_equal_approx(shot.max_distance, 640.0)
		and shot.collision_mask == 3,
		"Slinger fires a 14-damage dart along the frozen aim at speed 420 with walls and friendlies masked"
	)
	_expect(is_equal_approx(slinger.fire_cooldown_left, 2.4 - 0.6), "Slinger fires every 2.4 seconds")
	target.position = Vector2(-300.0, 0.0)
	shot._on_body_entered(target)
	_expect(
		is_equal_approx(target.health, 86.0)
		and _dealt_events.size() == 1
		and _dealt_events[0][0] == &"slinger"
		and is_equal_approx(_dealt_events[0][2], 14.0),
		"Dart hits report through the Slinger's dealt_damage signal"
	)
	var state := slinger._mcp_state()
	_expect(
		state["state"] is String and state["target"] is String and state["is_casting"] is bool,
		"Slinger _mcp_state exposes plain values"
	)
	current_scene = null
	arena.free()
	_clear_friendlies()


func _test_dart_hits_first_friendly_and_dodge_roll_avoids_it() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var front := _friendly_actor("Front", Vector2(100.0, 0.0))
	var back := _friendly_actor("Back", Vector2(200.0, 0.0))
	var shot := EnemyShotScene.instantiate() as EnemyShot
	shot.set_physics_process(false)
	arena.add_child(shot)
	shot._on_body_entered(front)
	shot._on_body_entered(back)
	_expect(
		is_equal_approx(front.health, 86.0)
		and is_equal_approx(back.health, 100.0)
		and shot.is_queued_for_deletion(),
		"Dart hits only the first friendly it reaches"
	)
	var wall_shot := EnemyShotScene.instantiate() as EnemyShot
	wall_shot.set_physics_process(false)
	arena.add_child(wall_shot)
	var wall := StaticBody2D.new()
	arena.add_child(wall)
	wall_shot._on_body_entered(wall)
	_expect(wall_shot.is_queued_for_deletion(), "Dart is absorbed by walls")
	var player := _player_actor("Dodger", Vector2(300.0, 0.0))
	player.dodge_time_left = 0.1
	var dodged_shot := EnemyShotScene.instantiate() as EnemyShot
	dodged_shot.set_physics_process(false)
	arena.add_child(dodged_shot)
	dodged_shot._on_body_entered(player)
	_expect(is_equal_approx(player.health, player.max_health), "A dodge-rolling player takes zero dart damage")
	var rolled_out := _player_actor("Grounded", Vector2(400.0, 0.0))
	var grounded_shot := EnemyShotScene.instantiate() as EnemyShot
	grounded_shot.set_physics_process(false)
	arena.add_child(grounded_shot)
	grounded_shot._on_body_entered(rolled_out)
	_expect(is_equal_approx(rolled_out.health, 86.0), "A player not dodge-rolling takes 14 dart damage")
	arena.free()
	_clear_friendlies()


func _test_echo_prefers_casters_but_focus_wins() -> void:
	var active := Node2D.new()
	root.add_child(active)
	var echo := _echo_with_job(HeroProgression.JOB_VANGUARD, active)
	var drifter := EnemyScene.instantiate() as EnemyActor
	drifter.name = "Drifter"
	drifter.position = Vector2(100.0, 0.0)
	drifter.set_physics_process(false)
	root.add_child(drifter)
	var hexcaller := _casting_hexcaller()
	hexcaller.position = Vector2(-300.0, 0.0)
	var candidates: Array[Node] = [drifter, hexcaller]
	_expect(echo.get_interrupt_weapon_id() == &"lance", "Vanguard echo identifies the lance as its interrupting weapon")
	_expect(
		echo.choose_target(candidates) == hexcaller,
		"Vanguard echo prefers a casting Hexcaller within 450 over a nearer Drifter"
	)
	hexcaller.position = Vector2(-500.0, 0.0)
	_expect(echo.choose_target(candidates) == drifter, "Vanguard echo ignores casters beyond 450")
	hexcaller.position = Vector2(-300.0, 0.0)
	hexcaller.state = &"kite"
	_expect(echo.choose_target(candidates) == drifter, "Vanguard echo ignores a Hexcaller that is not casting")
	hexcaller.state = &"cast"
	_expect(echo.command_focus(drifter), "Echo accepts focus on the Drifter")
	_expect(echo.choose_target(candidates) == drifter, "Manual focus still wins over a casting enemy")

	var arcanist_echo := _echo_with_job(HeroProgression.JOB_ARCANIST, active)
	_expect(
		arcanist_echo.get_interrupt_weapon_id() == &"" and arcanist_echo.choose_target(candidates) == drifter,
		"Arcanist echo has no interrupting weapon and keeps nearest-target choice"
	)
	arcanist_echo.free()
	echo.free()
	drifter.free()
	hexcaller.free()
	active.free()
	_clear_friendlies()


func _test_echo_lance_and_interrupt_intent() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var active := Node2D.new()
	arena.add_child(active)
	var echo := _echo_with_job(HeroProgression.JOB_VANGUARD, active)
	var hexcaller := _casting_hexcaller(arena)
	hexcaller.position = Vector2(60.0, 0.0)
	var drifter := EnemyScene.instantiate() as EnemyActor
	drifter.position = Vector2(0.0, 60.0)
	drifter.set_physics_process(false)
	arena.add_child(drifter)
	_expect(echo.choose_weapon_for_target(hexcaller, 60.0) == &"lance", "Echo selects the lance against a casting target in range")
	_expect(echo.choose_weapon_for_target(drifter, 60.0) == &"sword", "Echo keeps the sword against a non-casting target in sword range")
	_expect(echo.choose_weapon_for_target(hexcaller, 200.0) == &"lance", "Echo still uses the lance when only it reaches")

	hexcaller.position = Vector2(300.0, 0.0)
	echo.current_target = hexcaller
	echo._fight_target()
	_expect(
		echo.current_intent == &"interrupt"
		and echo.intent_target == hexcaller
		and echo.velocity.x > 0.0,
		"Echo approaching a casting target shows the interrupt intent"
	)
	var state := echo._mcp_state()
	_expect(
		state["current_intent"] == "interrupt"
		and state["intent_target"] == String(hexcaller.name)
		and state["interrupt_weapon_id"] == "lance"
		and state["target_is_casting"] == true,
		"Echo _mcp_state exposes the interrupt intent as plain values"
	)

	hexcaller.position = Vector2(100.0, 0.0)
	echo.intent_target = null
	echo.current_target = hexcaller
	echo._fight_target()
	_expect(
		echo.current_intent == &"interrupt"
		and echo.selected_weapon_id == &"lance"
		and hexcaller.state == &"stunned",
		"Echo attacking a casting target with the lance interrupts it"
	)
	echo.intent_target = null
	echo.current_target = drifter
	echo.attack_cooldowns[&"sword"] = 0.0
	echo._fight_target()
	_expect(
		echo.current_intent == &"attack" and echo.intent_target == drifter,
		"Echo attacking a non-casting target keeps the attack intent"
	)
	current_scene = null
	arena.free()
	_clear_friendlies()


func _test_scenarios_and_spawner_table() -> void:
	var hexcaller_scene := load("res://tests/scenarios/vanguard_vanguard_4_hexcaller.tscn") as PackedScene
	var slinger_scene := load("res://tests/scenarios/arcanist_vanguard_4_slinger.tscn") as PackedScene
	_expect(hexcaller_scene != null and slinger_scene != null, "Slice 3 scenario scenes load")
	var scenario := hexcaller_scene.instantiate()
	root.add_child(scenario)
	var spawner := scenario.get_child(0).get_node("Enemies") as EnemySpawner
	var ids: Array[StringName] = []
	for child in spawner.get_children():
		if not child.is_queued_for_deletion():
			ids.append((child as EnemyActor).enemy_id)
	_expect(ids == [&"hexcaller"], "Hexcaller scenario spawns only a Hexcaller")
	scenario.free()
	_clear_friendlies()

	var level_three := EnemySpawner.new()
	level_three.threat_level = 3
	level_three.target_population = 0
	root.add_child(level_three)
	var level_four := EnemySpawner.new()
	level_four.threat_level = 4
	level_four.target_population = 0
	root.add_child(level_four)
	var seen_three: Dictionary = {}
	var seen_four: Dictionary = {}
	for index in 600:
		seen_three[level_three._choose_enemy_id()] = true
		seen_four[level_four._choose_enemy_id()] = true
	_expect(
		seen_three.keys().size() == 3
		and seen_three.has(&"slinger")
		and not seen_three.has(&"brute")
		and not seen_three.has(&"hexcaller"),
		"Level three adds Slingers but no Brutes or Hexcallers"
	)
	_expect(
		seen_four.keys().size() == 5 and seen_four.has(&"hexcaller") and seen_four.has(&"brute"),
		"Level four includes all five variants"
	)
	level_three.free()
	level_four.free()


func _casting_hexcaller(parent: Node = root) -> EnemyActor:
	var hexcaller := HexcallerScene.instantiate() as EnemyActor
	hexcaller.set_physics_process(false)
	parent.add_child(hexcaller)
	if EnemyTargeting.nearest_friendly(hexcaller) == null:
		hexcaller.state = &"cast"
		hexcaller.state_time_left = hexcaller.CAST_DURATION
		return hexcaller
	hexcaller.cast_cooldown_left = 0.0
	hexcaller._physics_process(PHYSICS_STEP)
	return hexcaller


func _echo_with_job(job_id: StringName, active: Node2D) -> EchoActor:
	var progression := HeroProgression.new()
	progression.grant_experience(200)
	progression.apply_attribute_choice(2, HeroProgression.ATTRIBUTE_MIGHT)
	progression.apply_job_choice(3, job_id)
	var echo := EchoScene.instantiate() as EchoActor
	echo.set_physics_process(false)
	if active.get_parent() == null:
		root.add_child(active)
	var echo_parent: Node = active.get_parent()
	echo_parent.add_child(echo)
	echo.configure(HeroRecord.capture("caster-test", "Caster Test", progression), active)
	echo.grant_shared_experience(200)
	return echo


func _friendly_actor(actor_name: String, actor_position: Vector2) -> HeroActor:
	var actor := HeroActor.new()
	actor.name = actor_name
	actor.position = actor_position
	actor.set_physics_process(false)
	root.add_child(actor)
	actor.add_to_group(&"friendly_actors")
	return actor


func _player_actor(actor_name: String, actor_position: Vector2) -> HeroActor:
	var actor := PlayerScript.new()
	actor.name = actor_name
	actor.position = actor_position
	actor.set_physics_process(false)
	var body := Polygon2D.new()
	body.name = "Body"
	actor.add_child(body)
	var facing_marker := Polygon2D.new()
	facing_marker.name = "FacingMarker"
	actor.add_child(facing_marker)
	root.add_child(actor)
	actor.add_to_group(&"friendly_actors")
	return actor


func _clear_friendlies() -> void:
	for actor in get_nodes_in_group(&"friendly_actors"):
		actor.free()


func _record_dealt_damage(enemy_id: StringName, target: Node, applied: float) -> void:
	_dealt_events.append([enemy_id, target, applied])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
