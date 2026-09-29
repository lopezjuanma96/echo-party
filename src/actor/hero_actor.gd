class_name HeroActor
extends CharacterBody2D


signal health_changed(current_health: float, maximum_health: float)
signal defeated
signal weapon_changed(weapon_id: StringName)

const BOLT_SCENE := preload("res://src/combat/bolt.tscn")
const SLASH_EFFECT := preload("res://src/combat/slash_effect.gd")
const TRANSIENT_COMBAT_GROUP := &"transient_combat"

@export var max_health := 100.0
@export var damage_invulnerability := 0.35
@export var spawn_invulnerability := 1.0

var health := max_health
var attack_damage := 25.0
var invulnerability_time_left := 0.0
var aim_direction := Vector2.RIGHT
var weapon_loadout: Array[StringName] = [&"knife"]
var selected_weapon_id := &"knife"
var attack_cooldowns: Dictionary = {}
var is_defeated := false


func _ready() -> void:
	health = max_health
	attack_cooldowns[selected_weapon_id] = 0.0
	_update_aim_marker()


func tick_combat(delta: float) -> void:
	invulnerability_time_left = maxf(invulnerability_time_left - delta, 0.0)
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


func apply_job_loadout(job_id: StringName) -> bool:
	var new_loadout := WeaponCatalog.get_loadout(job_id)
	if new_loadout.is_empty():
		return false
	weapon_loadout = new_loadout
	selected_weapon_id = weapon_loadout[0]
	for weapon_id in weapon_loadout:
		if not attack_cooldowns.has(weapon_id):
			attack_cooldowns[weapon_id] = 0.0
	weapon_changed.emit(selected_weapon_id)
	return true


func get_selected_weapon_id() -> StringName:
	return selected_weapon_id


func get_weapon_loadout() -> Array[StringName]:
	return weapon_loadout.duplicate()


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
			enemy.take_damage(attack_damage)


func _fire_projectile(weapon: WeaponDefinition) -> void:
	var bolt := BOLT_SCENE.instantiate()
	get_tree().current_scene.add_child(bolt)
	bolt.add_to_group(TRANSIENT_COMBAT_GROUP)
	bolt.launch(
		global_position + aim_direction * 34.0,
		aim_direction,
		attack_damage,
		weapon.projectile_speed,
		weapon.attack_range,
		weapon.projectile_color
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
	for weapon_id: StringName in attack_cooldowns:
		attack_cooldowns[weapon_id] = 0.0
	health_changed.emit(health, max_health)
