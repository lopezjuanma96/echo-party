extends CharacterBody2D


signal health_changed(current_health: float, maximum_health: float)
signal defeated
signal weapon_changed(weapon_id: StringName)

const BOLT_SCENE := preload("res://src/combat/bolt.tscn")
const SLASH_EFFECT := preload("res://src/combat/slash_effect.gd")

@export var move_speed := 260.0
@export var dodge_speed := 720.0
@export var dodge_duration := 0.18
@export var dodge_cooldown := 0.55
@export var max_health := 100.0
@export var damage_invulnerability := 0.35
@export var spawn_invulnerability := 1.0
@onready var body: Polygon2D = $Body
@onready var facing_marker: Polygon2D = $FacingMarker
@onready var aim_marker: Polygon2D = $AimMarker

var facing := Vector2.DOWN
var dodge_direction := Vector2.ZERO
var dodge_time_left := 0.0
var dodge_cooldown_left := 0.0
var health := max_health
var attack_damage := 25.0
var invulnerability_time_left := 0.0
var aim_direction := Vector2.RIGHT
var weapon_loadout: Array[StringName] = [&"knife"]
var selected_weapon_id := &"knife"
var attack_cooldowns: Dictionary = {}
var suppress_combat_input := false


func _ready() -> void:
	health = max_health
	attack_cooldowns[selected_weapon_id] = 0.0
	aim_marker.position = aim_direction * 34.0
	aim_marker.rotation = aim_direction.angle() + PI / 2.0


func _physics_process(delta: float) -> void:
	dodge_cooldown_left = maxf(dodge_cooldown_left - delta, 0.0)
	invulnerability_time_left = maxf(invulnerability_time_left - delta, 0.0)
	for weapon_id: StringName in attack_cooldowns:
		attack_cooldowns[weapon_id] = maxf(float(attack_cooldowns[weapon_id]) - delta, 0.0)
	_update_aim()
	if suppress_combat_input:
		if not _is_combat_input_pressed():
			suppress_combat_input = false
	else:
		_update_weapon_selection()

	if dodge_time_left > 0.0:
		dodge_time_left -= delta
		velocity = dodge_direction * dodge_speed
		body.color = Color("65a0ff")
	else:
		body.color = Color("1a61f2")
		var input_direction := Input.get_vector(
			&"move_left", &"move_right", &"move_up", &"move_down"
		)
		if not input_direction.is_zero_approx():
			facing = input_direction.normalized()
			facing_marker.rotation = facing.angle() + PI / 2.0

		if Input.is_action_just_pressed(&"dodge") and dodge_cooldown_left <= 0.0:
			_start_dodge(input_direction)
		else:
			velocity = input_direction * move_speed

	move_and_slide()

	if (
		not suppress_combat_input
		and Input.is_action_just_pressed(&"basic_attack")
		and float(attack_cooldowns.get(selected_weapon_id, 0.0)) <= 0.0
		and dodge_time_left <= 0.0
	):
		_attack()


func _start_dodge(input_direction: Vector2) -> void:
	dodge_direction = facing if input_direction.is_zero_approx() else input_direction.normalized()
	dodge_time_left = dodge_duration
	dodge_cooldown_left = dodge_cooldown
	velocity = dodge_direction * dodge_speed


func _update_aim() -> void:
	var mouse_direction := get_global_mouse_position() - global_position
	if not mouse_direction.is_zero_approx():
		aim_direction = mouse_direction.normalized()
		aim_marker.position = aim_direction * 34.0
		aim_marker.rotation = aim_direction.angle() + PI / 2.0


func _update_weapon_selection() -> void:
	if Input.is_action_just_pressed(&"weapon_slot_1"):
		select_weapon_slot(0)
	elif Input.is_action_just_pressed(&"weapon_slot_2"):
		select_weapon_slot(1)
	elif Input.is_action_just_pressed(&"weapon_previous"):
		cycle_weapon(-1)
	elif Input.is_action_just_pressed(&"weapon_next"):
		cycle_weapon(1)


func select_weapon_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= weapon_loadout.size():
		return false
	return _select_weapon(weapon_loadout[slot_index])


func cycle_weapon(direction: int) -> bool:
	if weapon_loadout.size() < 2 or direction == 0:
		return false
	var current_index := weapon_loadout.find(selected_weapon_id)
	var next_index := posmod(current_index + direction, weapon_loadout.size())
	return _select_weapon(weapon_loadout[next_index])


func _select_weapon(weapon_id: StringName) -> bool:
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


func _attack() -> void:
	var weapon := WeaponCatalog.get_weapon(selected_weapon_id)
	if weapon == null:
		push_error("Unknown selected weapon ID: %s" % selected_weapon_id)
		return
	if weapon.attack_kind == WeaponDefinition.AttackKind.MELEE:
		_swing_melee(weapon)
	else:
		_fire_projectile(weapon)
	attack_cooldowns[selected_weapon_id] = weapon.cooldown


func _swing_melee(weapon: WeaponDefinition) -> void:
	var slash := SLASH_EFFECT.new()
	get_tree().current_scene.add_child(slash)
	slash.global_position = global_position
	slash.rotation = aim_direction.angle()
	slash.configure(weapon.attack_range, weapon.arc_degrees)

	var half_arc := deg_to_rad(weapon.arc_degrees / 2.0)
	for enemy: Node2D in get_tree().get_nodes_in_group(&"enemies"):
		var to_enemy := enemy.global_position - global_position
		if (
			to_enemy.length() <= weapon.attack_range
			and absf(aim_direction.angle_to(to_enemy.normalized())) <= half_arc
		):
			enemy.take_damage(attack_damage)


func _fire_projectile(weapon: WeaponDefinition) -> void:
	var bolt := BOLT_SCENE.instantiate()
	get_tree().current_scene.add_child(bolt)
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


func suppress_combat_input_until_released() -> void:
	suppress_combat_input = true


func _is_combat_input_pressed() -> bool:
	return (
		Input.is_action_pressed(&"basic_attack")
		or Input.is_action_pressed(&"weapon_slot_1")
		or Input.is_action_pressed(&"weapon_slot_2")
		or Input.is_action_pressed(&"weapon_previous")
		or Input.is_action_pressed(&"weapon_next")
	)


func take_damage(amount: float) -> void:
	if invulnerability_time_left > 0.0 or dodge_time_left > 0.0:
		return

	health = maxf(health - amount, 0.0)
	invulnerability_time_left = damage_invulnerability
	health_changed.emit(health, max_health)
	if health <= 0.0:
		defeated.emit()


func reset_at(spawn_position: Vector2) -> void:
	position = spawn_position
	velocity = Vector2.ZERO
	dodge_time_left = 0.0
	health = max_health
	invulnerability_time_left = spawn_invulnerability
	health_changed.emit(health, max_health)
