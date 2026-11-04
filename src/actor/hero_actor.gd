class_name HeroActor
extends CharacterBody2D


signal health_changed(current_health: float, maximum_health: float)
signal defeated
signal weapon_changed(weapon_id: StringName)
signal ability_feedback(message: String)

const BOLT_SCENE := preload("res://src/combat/bolt.tscn")
const SLASH_EFFECT := preload("res://src/combat/slash_effect.gd")
const HEAL_PULSE_EFFECT := preload("res://src/combat/heal_pulse_effect.gd")
const HEAL_TARGET_EFFECT := preload("res://src/combat/heal_target_effect.gd")
const TRANSIENT_COMBAT_GROUP := &"transient_combat"

@export var max_health := 100.0
@export var damage_invulnerability := 0.35
@export var spawn_invulnerability := 1.0

var health := max_health
var attack_damage := 25.0
var invulnerability_time_left := 0.0
var aim_direction := Vector2.RIGHT
var job_id := HeroProgression.JOB_NOVICE
var weapon_loadout: Array[StringName] = [&"knife"]
var selected_weapon_id := &"knife"
var attack_cooldowns: Dictionary = {}
var ability_id := &""
var ability_cooldown_left := 0.0
var total_healing_done := 0.0
var is_defeated := false


func _ready() -> void:
	health = max_health
	attack_cooldowns[selected_weapon_id] = 0.0
	_update_aim_marker()


func tick_combat(delta: float) -> void:
	invulnerability_time_left = maxf(invulnerability_time_left - delta, 0.0)
	ability_cooldown_left = maxf(ability_cooldown_left - delta, 0.0)
	for weapon_id: StringName in attack_cooldowns:
		attack_cooldowns[weapon_id] = maxf(float(attack_cooldowns[weapon_id]) - delta, 0.0)


func set_aim_direction(direction: Vector2) -> void:
	if direction.is_zero_approx():
		return
	aim_direction = direction.normalized()
	_update_aim_marker()


func _update_aim_marker() -> void:
	var marker := get_node_or_null("AimMarker") as Node2D
	if marker == null:
		return
	marker.position = aim_direction * 34.0
	marker.rotation = aim_direction.angle() + PI / 2.0


func select_weapon_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= weapon_loadout.size():
		return false
	return select_weapon(weapon_loadout[slot_index])


func cycle_weapon(direction: int) -> bool:
	if weapon_loadout.size() < 2 or direction == 0:
		return false
	var current_index := weapon_loadout.find(selected_weapon_id)
	var next_index := posmod(current_index + direction, weapon_loadout.size())
	return select_weapon(weapon_loadout[next_index])


func select_weapon(weapon_id: StringName) -> bool:
	if not weapon_loadout.has(weapon_id) or selected_weapon_id == weapon_id:
		return false
	selected_weapon_id = weapon_id
	if not attack_cooldowns.has(weapon_id):
		attack_cooldowns[weapon_id] = 0.0
	weapon_changed.emit(selected_weapon_id)
	return true


func apply_job_loadout(new_job_id: StringName) -> bool:
	var new_loadout := WeaponCatalog.get_loadout(new_job_id)
	if new_loadout.is_empty():
		return false
	job_id = new_job_id
	weapon_loadout = new_loadout
	selected_weapon_id = weapon_loadout[0]
	ability_id = JobCatalog.get_ability_id(new_job_id)
	ability_cooldown_left = 0.0
	for weapon_id in weapon_loadout:
		if not attack_cooldowns.has(weapon_id):
			attack_cooldowns[weapon_id] = 0.0
	weapon_changed.emit(selected_weapon_id)
	return true


func get_selected_weapon_id() -> StringName:
	return selected_weapon_id


func get_weapon_loadout() -> Array[StringName]:
	return weapon_loadout.duplicate()


## Remaining weapon cooldown as a 0..1 fraction: 0 when ready, 1 right after use.
func get_weapon_cooldown_fraction(weapon_id: StringName = &"") -> float:
	var id := selected_weapon_id if weapon_id == &"" else weapon_id
	var weapon := WeaponCatalog.get_weapon(id)
	if weapon == null or weapon.cooldown <= 0.0:
		return 0.0
	return clampf(float(attack_cooldowns.get(id, 0.0)) / weapon.cooldown, 0.0, 1.0)


## Remaining ability cooldown as a 0..1 fraction; 0 with no ability.
func get_ability_cooldown_fraction() -> float:
	var ability := AbilityCatalog.get_ability(ability_id)
	if ability == null or ability.cooldown <= 0.0:
		return 0.0
	return clampf(ability_cooldown_left / ability.cooldown, 0.0, 1.0)


static func format_cooldown(seconds: float) -> String:
	return "Ready" if seconds <= 0.0 else "%.1fs" % seconds


func can_use_ability() -> bool:
	return (
		not is_defeated
		and ability_cooldown_left <= 0.0
		and AbilityCatalog.get_ability(ability_id) != null
	)


func get_ability_target(max_health_fraction: float = 1.0) -> HeroActor:
	var ability := AbilityCatalog.get_ability(ability_id)
	if ability == null or not is_inside_tree():
		return null
	var best: HeroActor
	var best_fraction := INF
	for actor_node in get_tree().get_nodes_in_group(&"friendly_actors"):
		var actor := actor_node as HeroActor
		if (
			actor == null
			or actor.is_queued_for_deletion()
			or actor.is_defeated
			or actor.health >= actor.max_health
			or actor.max_health <= 0.0
			or global_position.distance_to(actor.global_position) > ability.radius
		):
			continue
		var health_fraction := actor.health / actor.max_health
		if health_fraction > max_health_fraction:
			continue
		if (
			best == null
			or health_fraction < best_fraction
			or (
				is_equal_approx(health_fraction, best_fraction)
				and _ability_target_wins_tie(actor, best)
			)
		):
			best = actor
			best_fraction = health_fraction
	return best


func _ability_target_wins_tie(candidate: HeroActor, current: HeroActor) -> bool:
	var active_hero := _ability_active_hero()
	if candidate == active_hero and current != active_hero:
		return true
	if current == active_hero:
		return false
	return candidate.name.naturalnocasecmp_to(current.name) < 0


func _ability_active_hero() -> HeroActor:
	return self


func use_ability() -> bool:
	if not can_use_ability():
		return false
	var ability := AbilityCatalog.get_ability(ability_id)
	var target := get_ability_target()
	if target == null:
		ability_feedback.emit("No one needs healing")
		return false
	var amount := ability.heal_amount
	if target == self:
		amount *= ability.self_heal_fraction
	var applied := target.heal(amount)
	total_healing_done += applied
	ability_cooldown_left = ability.cooldown

	var pulse := HEAL_PULSE_EFFECT.new()
	var effect_parent := get_tree().current_scene
	if effect_parent == null:
		effect_parent = get_tree().root
	effect_parent.add_child(pulse)
	pulse.add_to_group(TRANSIENT_COMBAT_GROUP)
	pulse.global_position = global_position
	pulse.configure(ability.radius, ability.color)

	var target_effect := HEAL_TARGET_EFFECT.new()
	effect_parent.add_child(target_effect)
	target_effect.add_to_group(TRANSIENT_COMBAT_GROUP)
	target_effect.configure(target, applied, ability.color)
	return true


func heal(amount: float) -> float:
	if is_defeated or amount <= 0.0 or health >= max_health:
		return 0.0
	var applied := minf(amount, max_health - health)
	health += applied
	health_changed.emit(health, max_health)
	return applied


func can_attack() -> bool:
	return not is_defeated and float(attack_cooldowns.get(selected_weapon_id, 0.0)) <= 0.0


func attack_selected_weapon() -> bool:
	if not can_attack():
		return false
	var weapon := WeaponCatalog.get_weapon(selected_weapon_id)
	if weapon == null:
		push_error("Unknown selected weapon ID: %s" % selected_weapon_id)
		return false
	if weapon.attack_kind == WeaponDefinition.AttackKind.MELEE:
		_swing_melee(weapon)
	else:
		_fire_projectile(weapon)
	attack_cooldowns[selected_weapon_id] = weapon.cooldown
	return true


func _swing_melee(weapon: WeaponDefinition) -> void:
	var slash := SLASH_EFFECT.new()
	get_tree().current_scene.add_child(slash)
	slash.add_to_group(TRANSIENT_COMBAT_GROUP)
	slash.global_position = global_position
	slash.rotation = aim_direction.angle()
	slash.configure(weapon.attack_range, weapon.arc_degrees)

	var half_arc := deg_to_rad(weapon.arc_degrees / 2.0)
	for enemy: Node2D in get_tree().get_nodes_in_group(&"enemies"):
		var to_enemy := enemy.global_position - global_position
		if (
			to_enemy.length() <= weapon.attack_range
			and not to_enemy.is_zero_approx()
			and absf(aim_direction.angle_to(to_enemy.normalized())) <= half_arc
		):
			enemy.take_damage(attack_damage * weapon.damage_multiplier, weapon.interrupts)


func _fire_projectile(weapon: WeaponDefinition) -> void:
	var bolt := BOLT_SCENE.instantiate()
	get_tree().current_scene.add_child(bolt)
	bolt.add_to_group(TRANSIENT_COMBAT_GROUP)
	bolt.launch(
		global_position + aim_direction * 34.0,
		aim_direction,
		attack_damage * weapon.damage_multiplier,
		weapon.projectile_speed,
		weapon.attack_range,
		weapon.projectile_color,
		weapon.interrupts,
		weapon.splash_radius,
		weapon.splash_fraction
	)


func apply_progression_stats(new_max_health: float, new_attack_damage: float) -> void:
	var health_increase := new_max_health - max_health
	max_health = new_max_health
	attack_damage = new_attack_damage
	if health_increase > 0.0:
		health = minf(health + health_increase, max_health)
	else:
		health = minf(health, max_health)
	health_changed.emit(health, max_health)


func apply_progression(progression: HeroProgression, full_heal: bool = false) -> bool:
	if progression == null or not apply_job_loadout(progression.get_job_id()):
		return false
	apply_progression_stats(progression.get_max_health(), progression.get_attack_damage())
	if full_heal:
		health = max_health
		health_changed.emit(health, max_health)
	return true


func take_damage(amount: float) -> void:
	if is_defeated or amount <= 0.0 or invulnerability_time_left > 0.0:
		return
	health = maxf(health - amount, 0.0)
	invulnerability_time_left = damage_invulnerability
	health_changed.emit(health, max_health)
	if health <= 0.0:
		is_defeated = true
		defeated.emit()


func reset_actor(spawn_position: Vector2, use_spawn_invulnerability: bool = true) -> void:
	position = spawn_position
	velocity = Vector2.ZERO
	health = max_health
	is_defeated = false
	invulnerability_time_left = spawn_invulnerability if use_spawn_invulnerability else 0.0
	ability_cooldown_left = 0.0
	total_healing_done = 0.0
	for weapon_id: StringName in attack_cooldowns:
		attack_cooldowns[weapon_id] = 0.0
	health_changed.emit(health, max_health)
