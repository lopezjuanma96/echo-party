class_name EchoActor
extends HeroActor


signal progression_changed

@export var move_speed := 220.0
@export var target_leash := 620.0
@export var follow_distance := 105.0
@export var ranged_retreat_distance := 180.0

var active_hero: Node2D
var hero_record: HeroRecord
var progression := HeroProgression.new()
var job_id := HeroProgression.JOB_NOVICE
var current_target: Node2D
var current_intent := &"idle"
var _recorded_choices: Array[Dictionary] = []
var _replay_level_limit := 1


func configure(record: HeroRecord, new_active_hero: Node2D) -> bool:
	if record == null or new_active_hero == null:
		return false
	var recorded_progression := record.replay_progression()
	if recorded_progression == null:
		return false
	hero_record = record
	active_hero = new_active_hero
	_recorded_choices = recorded_progression.get_choices()
	_replay_level_limit = mini(recorded_progression.level, _recorded_choices.size() + 1)
	progression = HeroProgression.new()
	job_id = HeroProgression.JOB_NOVICE
	if not apply_progression(progression, true):
		return false
	reset_actor(position, true)
	_update_label()
	return true


func grant_shared_experience(amount: int) -> int:
	if amount <= 0 or progression.level >= _replay_level_limit:
		return 0
	var maximum_experience := (_replay_level_limit - 1) * HeroProgression.XP_PER_LEVEL
	var granted_amount := mini(amount, maximum_experience - progression.experience)
	var levels_gained := progression.grant_experience(granted_amount)
	for choice_level in progression.get_pending_choice_levels():
		var choice_index := choice_level - 2
		if choice_index < 0 or choice_index >= _recorded_choices.size():
			push_error("Missing recorded choice at level %d" % choice_level)
			break
		var choice := _recorded_choices[choice_index]
		var applied := false
		if choice.has("job_id"):
			applied = progression.apply_job_choice(choice_level, StringName(choice["job_id"]))
		elif choice.has("attribute_id"):
			applied = progression.apply_attribute_choice(
				choice_level,
				StringName(choice["attribute_id"])
			)
		if not applied:
			push_error("Failed to replay recorded choice at level %d" % choice_level)
			break
	if levels_gained > 0:
		job_id = progression.get_job_id()
		apply_progression(progression)
		_update_label()
		progression_changed.emit()
	return levels_gained


func get_replay_level_limit() -> int:
	return _replay_level_limit


func _update_label() -> void:
	var label := get_node_or_null("EchoLabel") as Label
	if label != null:
		label.text = "ECHO · %s · Lv %d" % [
			hero_record.display_name,
			progression.level,
		]


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
