extends CharacterBody2D


signal health_changed(current_health: float, maximum_health: float)
signal defeated
signal weapon_changed(weapon_name: String)


enum Weapon { SWORD, BOLT }

const BOLT_SCENE := preload("res://src/combat/bolt.tscn")
const SLASH_EFFECT := preload("res://src/combat/slash_effect.gd")

@export var move_speed := 260.0
@export var dodge_speed := 720.0
@export var dodge_duration := 0.18
@export var dodge_cooldown := 0.55
@export var max_health := 100.0
@export var damage_invulnerability := 0.35
@export var spawn_invulnerability := 1.0
@export var sword_range := 82.0
@export var sword_arc_degrees := 20.0
@export var sword_cooldown := 0.42
@export var bolt_cooldown := 0.62

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
var selected_weapon := Weapon.SWORD
var attack_cooldowns := {
	Weapon.SWORD: 0.0,
	Weapon.BOLT: 0.0,
}
var suppress_combat_input := false


func _ready() -> void:
	health = max_health
	aim_marker.position = aim_direction * 34.0
	aim_marker.rotation = aim_direction.angle() + PI / 2.0


func _physics_process(delta: float) -> void:
	dodge_cooldown_left = maxf(dodge_cooldown_left - delta, 0.0)
	invulnerability_time_left = maxf(invulnerability_time_left - delta, 0.0)
	for weapon: Weapon in attack_cooldowns:
		attack_cooldowns[weapon] = maxf(attack_cooldowns[weapon] - delta, 0.0)
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
		and attack_cooldowns[selected_weapon] <= 0.0
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
	if Input.is_action_just_pressed(&"weapon_sword"):
		_select_weapon(Weapon.SWORD)
	elif Input.is_action_just_pressed(&"weapon_bolt"):
		_select_weapon(Weapon.BOLT)
	elif Input.is_action_just_pressed(&"weapon_previous"):
		_select_weapon(Weapon.BOLT if selected_weapon == Weapon.SWORD else Weapon.SWORD)
	elif Input.is_action_just_pressed(&"weapon_next"):
		_select_weapon(Weapon.BOLT if selected_weapon == Weapon.SWORD else Weapon.SWORD)


func _select_weapon(weapon: Weapon) -> void:
	if selected_weapon == weapon:
		return
	selected_weapon = weapon
	weapon_changed.emit(get_selected_weapon_name())


func get_selected_weapon_name() -> String:
	return "Sword" if selected_weapon == Weapon.SWORD else "Bolt"


func _attack() -> void:
	if selected_weapon == Weapon.SWORD:
		_swing_sword()
		attack_cooldowns[Weapon.SWORD] = sword_cooldown
	else:
		_fire_bolt()
		attack_cooldowns[Weapon.BOLT] = bolt_cooldown


func _swing_sword() -> void:
	var slash := SLASH_EFFECT.new()
	get_tree().current_scene.add_child(slash)
	slash.global_position = global_position
	slash.rotation = aim_direction.angle()

	var half_arc := deg_to_rad(sword_arc_degrees / 2.0)
	for enemy: Node2D in get_tree().get_nodes_in_group(&"enemies"):
		var to_enemy := enemy.global_position - global_position
		if (
			to_enemy.length() <= sword_range
			and absf(aim_direction.angle_to(to_enemy.normalized())) <= half_arc
		):
			enemy.take_damage(attack_damage)


func _fire_bolt() -> void:
	var bolt := BOLT_SCENE.instantiate()
	get_tree().current_scene.add_child(bolt)
	bolt.launch(global_position + aim_direction * 34.0, aim_direction, attack_damage)


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
		or Input.is_action_pressed(&"weapon_sword")
		or Input.is_action_pressed(&"weapon_bolt")
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
