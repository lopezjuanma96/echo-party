class_name EchoActor
extends HeroActor


@export var move_speed := 220.0
@export var target_leash := 620.0
@export var follow_distance := 105.0
@export var ranged_retreat_distance := 180.0

var active_hero: Node2D
var hero_record: HeroRecord
var job_id := HeroProgression.JOB_NOVICE
var current_target: Node2D
var current_intent := &"idle"


func configure(record: HeroRecord, new_active_hero: Node2D) -> bool:
	if record == null or new_active_hero == null:
		return false
	var replayed := record.replay_progression()
	if replayed == null:
		return false
	hero_record = record
	active_hero = new_active_hero
	job_id = replayed.get_job_id()
	if not apply_progression(replayed, true):
		return false
	reset_actor(position, true)
	var label := get_node_or_null("EchoLabel") as Label
	if label != null:
		label.text = "ECHO · %s · Lv %d" % [record.display_name, replayed.level]
	return true


func _physics_process(delta: float) -> void:
	tick_combat(delta)
	current_target = choose_target(get_tree().get_nodes_in_group(&"enemies"))
	velocity = Vector2.ZERO
	if current_target == null:
		_follow_active_hero()
	else:
		_fight_target()
	move_and_slide()


func choose_target(candidates: Array[Node]) -> Node2D:
	if not is_instance_valid(active_hero):
		return null
	var best: Node2D
	var best_distance_squared := INF
	var best_order := 9223372036854775807
	for candidate_node in candidates:
		var candidate := candidate_node as Node2D
		if candidate == null or candidate.is_queued_for_deletion():
			continue
		if candidate.global_position.distance_to(active_hero.global_position) > target_leash:
			continue
		var distance_squared := global_position.distance_squared_to(candidate.global_position)
		var order := _target_order(candidate)
		if (
			distance_squared < best_distance_squared
			or (is_equal_approx(distance_squared, best_distance_squared) and order < best_order)
			or (
				is_equal_approx(distance_squared, best_distance_squared)
				and order == best_order
				and (best == null or candidate.name.naturalnocasecmp_to(best.name) < 0)
			)
		):
			best = candidate
			best_distance_squared = distance_squared
			best_order = order
	return best


func choose_weapon_for_distance(distance: float) -> StringName:
	if weapon_loadout.is_empty():
		return &""
	var choice := weapon_loadout[-1]
	for weapon_id in weapon_loadout:
		var weapon := WeaponCatalog.get_weapon(weapon_id)
		if weapon != null and distance <= weapon.attack_range:
			choice = weapon_id
			break
	select_weapon(choice)
	return choice


func _follow_active_hero() -> void:
	current_intent = &"idle"
	if not is_instance_valid(active_hero):
		return
	var to_hero := active_hero.global_position - global_position
	if to_hero.length() > follow_distance:
		current_intent = &"follow"
		velocity = to_hero.normalized() * move_speed


func _fight_target() -> void:
	var to_target := current_target.global_position - global_position
	var distance := to_target.length()
	if distance <= 0.0:
		return
	set_aim_direction(to_target)
	var weapon_id := choose_weapon_for_distance(distance)
	var weapon := WeaponCatalog.get_weapon(weapon_id)
	if weapon == null:
		current_intent = &"idle"
		return
	if job_id == HeroProgression.JOB_ARCANIST and distance < ranged_retreat_distance:
		current_intent = &"retreat"
		velocity = -to_target.normalized() * move_speed
	elif distance > weapon.attack_range * 0.9:
		current_intent = &"approach"
		velocity = to_target.normalized() * move_speed
	else:
		current_intent = &"attack" if can_attack() else &"hold"
	if distance <= weapon.attack_range:
		attack_selected_weapon()


func _target_order(target: Node2D) -> int:
	var value: Variant = target.get("stable_spawn_order")
	return int(value) if value != null else 9223372036854775807


func get_current_target() -> Node2D:
	return current_target


func get_current_intent() -> StringName:
	return current_intent
