extends SceneTree


const BruteScene := preload("res://src/enemy/brute.tscn")
const SkitterScene := preload("res://src/enemy/skitter.tscn")
const EnemyScene := preload("res://src/enemy/enemy.tscn")
const EnemySpawnerScript := preload("res://src/enemy/enemy_spawner.gd")
const PlayerScript := preload("res://src/player/player.gd")
const PHYSICS_STEP := 1.0 / 60.0

var _failures: Array[String] = []


class InterruptProbe:
	extends EnemyActor

	var received_interrupts := false

	func _on_damaged(_amount: float, interrupts: bool) -> void:
		received_interrupts = interrupts


func _init() -> void:
	call_deferred(&"_run_tests")


func _run_tests() -> void:
	_test_brute_windup_and_slam_radius()
	_test_dodge_roll_avoids_slam()
	_test_skitter_target_choice_and_tie_break()
	_test_staff_splash_and_wall_hit()
	_test_lance_interrupt_flag_reaches_melee_damage()
	_test_spawner_types_positions_and_pack()
	_test_single_argument_take_damage()
	_test_set_population_trims_pending_respawns()
	_test_debug_scenario_routes_experience()

	if _failures.is_empty():
		print("Enemy variant, weapon flag, and spawner tests passed (9 cases).")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_brute_windup_and_slam_radius() -> void:
	var inside := _friendly_actor("Inside", Vector2(60.0, 0.0))
	var outside := _friendly_actor("Outside", Vector2(100.0, 0.0))
	var brute := BruteScene.instantiate() as EnemyActor
	brute.set_physics_process(false)
	root.add_child(brute)
	brute._physics_process(PHYSICS_STEP)
	_expect(brute.state == &"windup", "Brute enters windup within 70 pixels")
	var windup_frames := 0
	while brute.state == &"windup" and windup_frames < 56:
		windup_frames += 1
		brute._physics_process(PHYSICS_STEP)
	_expect(absi(windup_frames - 54) <= 1, "Brute windup lasts 0.9 seconds within one physics frame")
	_expect(
		is_equal_approx(inside.health, 50.0),
		"Brute slam deals 50 damage inside radius 88"
	)
	_expect(is_equal_approx(outside.health, 100.0), "Brute slam deals no damage outside radius 88")
	_expect(brute.state == &"recover" and is_equal_approx(brute.state_time_left, 0.7), "Brute recovers after the slam")
	brute.free()
	inside.free()
	outside.free()


func _test_dodge_roll_avoids_slam() -> void:
	var player := _player_actor("DodgingHero", Vector2(50.0, 0.0))
	player.dodge_time_left = 0.1
	var brute := BruteScene.instantiate() as EnemyActor
	brute.set_physics_process(false)
	root.add_child(brute)
	brute._slam()
	_expect(is_equal_approx(player.health, player.max_health), "Dodge-rolling hero takes zero Brute slam damage")
	brute.free()
	player.free()


func _test_skitter_target_choice_and_tie_break() -> void:
	var skitter := SkitterScene.instantiate() as EnemyActor
	skitter.spawn_grace = 0.0
	skitter.set_physics_process(false)
	root.add_child(skitter)
	var alpha := _friendly_actor("Alpha", Vector2(-100.0, 0.0))
	var bravo := _friendly_actor("Bravo", Vector2(140.0, 0.0))
	skitter._physics_process(0.0)
	_expect(skitter.target == alpha and skitter.velocity.x < 0.0, "Skitter chases the nearest friendly")
	bravo.position = Vector2(100.0, 0.0)
	skitter._physics_process(0.0)
	_expect(skitter.target == alpha, "Equal-distance Skitter targets use natural node-name order")
	alpha.is_defeated = true
	skitter._physics_process(0.0)
	_expect(skitter.target == bravo, "Skitter skips defeated friendlies")
	skitter.free()
	alpha.free()
	bravo.free()


func _test_staff_splash_and_wall_hit() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var attacker := HeroActor.new()
	arena.add_child(attacker)
	attacker.attack_damage = 25.0
	attacker.set_aim_direction(Vector2.RIGHT)
	var target := _arena_enemy(arena, Vector2(300.0, 0.0))
	var neighbour := _arena_enemy(arena, Vector2(350.0, 0.0))
	var distant := _arena_enemy(arena, Vector2(450.0, 0.0))
	attacker._fire_projectile(WeaponCatalog.get_weapon(&"staff"))
	var bolt := arena.get_child(arena.get_child_count() - 1) as Area2D
	bolt.set_physics_process(false)
	bolt._on_body_entered(target)
	_expect(is_equal_approx(target.health, 25.0), "Staff bolt deals 25 damage to its target")
	_expect(is_equal_approx(neighbour.health, 35.0), "Staff splash deals 15 damage to neighbours")
	_expect(is_equal_approx(distant.health, 50.0), "Staff splash does not reach beyond 80 pixels")
	var wall := StaticBody2D.new()
	arena.add_child(wall)
	attacker._fire_projectile(WeaponCatalog.get_weapon(&"staff"))
	var wall_bolt := arena.get_child(arena.get_child_count() - 1) as Area2D
	wall_bolt.set_physics_process(false)
	wall_bolt._on_body_entered(wall)
	_expect(is_equal_approx(neighbour.health, 35.0), "Wall hits do not cause Staff splash")
	current_scene = null
	arena.free()


func _test_lance_interrupt_flag_reaches_melee_damage() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var attacker := HeroActor.new()
	arena.add_child(attacker)
	attacker.set_aim_direction(Vector2.RIGHT)
	var probe := InterruptProbe.new()
	probe.position = Vector2(60.0, 0.0)
	var body := Polygon2D.new()
	body.name = "Body"
	probe.add_child(body)
	var contact_area := Area2D.new()
	contact_area.name = "ContactArea"
	probe.add_child(contact_area)
	arena.add_child(probe)
	probe.add_to_group(&"enemies")
	var lance := WeaponCatalog.get_weapon(&"lance")
	attacker._swing_melee(lance)
	_expect(lance.interrupts and probe.received_interrupts, "Lance melee passes its interrupt flag to take_damage")
	current_scene = null
	arena.free()


func _test_spawner_types_positions_and_pack() -> void:
	var first := _spawner(91827, 4, 16)
	var second := _spawner(91827, 4, 16)
	_expect(_enemy_ids(first) == _enemy_ids(second), "Fixed seed and threat level reproduce the enemy type sequence")
	_expect(_enemy_positions(first) == _enemy_positions(second), "Fixed seed and threat level reproduce spawn positions")
	_expect(_enemy_ids(first).has(&"skitter") and _enemy_ids(first).has(&"brute"), "Level-four mix includes Skitters and Brutes")
	first.free()
	second.free()

	var low_level := _spawner(77, 2, 12)
	_expect(not _enemy_ids(low_level).has(&"skitter") and not _enemy_ids(low_level).has(&"brute"), "Levels one and two spawn only Drifters")
	low_level.free()
	var level_three := _spawner(91827, 3, 0)
	for index in 24:
		_expect(
			level_three._choose_enemy_id() in [&"drifter", &"skitter", &"slinger"],
			"Level-three table contains only Drifter, Skitter, and Slinger"
		)
	level_three.free()

	var typed := _spawner(55221, 4, 0)
	var position_only := _spawner(55221, 4, 0)
	var typed_positions: Array[Vector2] = []
	var plain_positions: Array[Vector2] = []
	for index in 12:
		typed._choose_enemy_id()
		typed_positions.append(typed.choose_spawn_position())
		plain_positions.append(position_only.choose_spawn_position())
	_expect(typed_positions == plain_positions, "Type RNG draws leave the position RNG stream unchanged")
	typed.free()
	position_only.free()

	var pack_spawner := _spawner(424242, 4, 0)
	var pack_found := false
	for attempt in 24:
		if pack_found:
			break
		var previous_count := pack_spawner.get_child_count()
		var leader := pack_spawner._spawn_enemy()
		if leader.enemy_id != &"skitter":
			continue
		pack_found = true
		var spawned := pack_spawner.get_children().slice(previous_count)
		_expect(spawned.size() == 4, "A Skitter spawn creates one intact pack of four")
		var clustered := true
		for member: Node2D in spawned:
			clustered = clustered and member.position.distance_to(leader.position) <= 40.0
		_expect(clustered, "Every Skitter in a pack spawns within the 40-pixel cluster")
	_expect(pack_found, "The deterministic level-four sequence produces a Skitter pack")
	pack_spawner.free()


func _test_single_argument_take_damage() -> void:
	var enemy := EnemyScene.instantiate() as EnemyActor
	root.add_child(enemy)
	enemy.take_damage(12.0)
	_expect(is_equal_approx(enemy.health, 38.0), "Single-argument take_damage remains compatible")
	enemy.free()


func _test_set_population_trims_pending_respawns() -> void:
	var spawner := _spawner(77, 1, 3)
	spawner.get_child(0).take_damage(50.0)
	spawner.get_child(1).take_damage(50.0)
	_expect(spawner.get_pending_respawn_count() == 2, "Two defeats schedule two replacements")
	spawner.set_population(1)
	_expect(
		spawner.target_population == 1
		and spawner.get_pending_respawn_count() == 0
		and _living_enemy_count(spawner) == 1,
		"set_population trims living enemies and pending replacements"
	)
	spawner._process(2.0)
	_expect(_living_enemy_count(spawner) == 1, "Trimmed respawns do not spawn later")
	spawner.free()


func _test_debug_scenario_routes_experience() -> void:
	var scene := load("res://tests/scenarios/vanguard_vanguard_4_brute.tscn") as PackedScene
	var scenario := scene.instantiate()
	root.add_child(scenario)
	current_scene = scenario
	var main := scenario.get_child(0)
	var spawner := main.get_node("Enemies") as EnemySpawner
	_expect(
		spawner.target_population == 0
		and _living_enemy_count(spawner) == 1
		and _enemy_ids(spawner) == [&"brute"],
		"Debug scenario spawns only its requested Brute"
	)
	var brute := spawner.get_child(spawner.get_child_count() - 1) as EnemyActor
	brute.take_damage(brute.max_health)
	_expect(main.progression.experience == 370, "Debug enemy XP uses the normal Main reward handler")
	current_scene = null
	scenario.free()


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


func _arena_enemy(arena: Node2D, enemy_position: Vector2) -> EnemyActor:
	var enemy := EnemyScene.instantiate() as EnemyActor
	enemy.position = enemy_position
	enemy.set_physics_process(false)
	arena.add_child(enemy)
	return enemy


func _spawner(seed_value: int, level: int, population: int) -> EnemySpawner:
	var spawner := EnemySpawnerScript.new() as EnemySpawner
	spawner.simulation_seed = seed_value
	spawner.threat_level = level
	spawner.target_population = population
	root.add_child(spawner)
	return spawner


func _enemy_ids(spawner: EnemySpawner) -> Array[StringName]:
	var ids: Array[StringName] = []
	for child in spawner.get_children():
		if not child.is_queued_for_deletion():
			ids.append(child.enemy_id)
	return ids


func _enemy_positions(spawner: EnemySpawner) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for child in spawner.get_children():
		positions.append(child.position)
	return positions


func _living_enemy_count(spawner: EnemySpawner) -> int:
	var count := 0
	for child in spawner.get_children():
		if not child.is_queued_for_deletion():
			count += 1
	return count


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
