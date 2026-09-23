extends Node2D


const ENEMY_SCENE := preload("res://src/enemy/enemy.tscn")
const DEFAULT_KEY_BINDINGS := {
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"move_up": [KEY_W, KEY_UP],
	&"move_down": [KEY_S, KEY_DOWN],
	&"dodge": [KEY_SPACE],
	&"weapon_sword": [KEY_1],
	&"weapon_bolt": [KEY_2],
}
const DEFAULT_MOUSE_BINDINGS := {
	&"basic_attack": [MOUSE_BUTTON_LEFT],
	&"weapon_previous": [MOUSE_BUTTON_WHEEL_UP],
	&"weapon_next": [MOUSE_BUTTON_WHEEL_DOWN],
}

@export var enemy_count := 7

@onready var player: CharacterBody2D = $Player
@onready var health_bar: ProgressBar = $HUD/Health/Content/HealthBar
@onready var health_value: Label = $HUD/Health/Content/HealthValue
@onready var weapon_value: Label = $HUD/Weapon/Content/WeaponValue

var random := RandomNumberGenerator.new()


func _ready() -> void:
	_setup_default_bindings()
	_on_player_health_changed(player.health, player.max_health)
	_on_player_weapon_changed(player.get_selected_weapon_name())
	random.randomize()
	_spawn_enemies()


func _setup_default_bindings() -> void:
	for action: StringName in DEFAULT_KEY_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if not InputMap.action_get_events(action).is_empty():
			continue

		for keycode: Key in DEFAULT_KEY_BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)

	for action: StringName in DEFAULT_MOUSE_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if not InputMap.action_get_events(action).is_empty():
			continue

		for button: MouseButton in DEFAULT_MOUSE_BINDINGS[action]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			InputMap.action_add_event(action, event)


func _spawn_enemies() -> void:
	for index in enemy_count:
		var enemy := ENEMY_SCENE.instantiate()
		enemy.name = "Enemy%d" % (index + 1)
		enemy.position = _random_spawn_position()
		$Enemies.add_child(enemy)


func _random_spawn_position() -> Vector2:
	var spawn_position := Vector2.ZERO
	while spawn_position.length() < 260.0:
		spawn_position = Vector2(
			random.randf_range(-820.0, 820.0),
			random.randf_range(-470.0, 470.0)
		)
	return spawn_position


func _on_player_health_changed(current_health: float, maximum_health: float) -> void:
	health_bar.max_value = maximum_health
	health_bar.value = current_health
	health_value.text = "%d / %d" % [current_health, maximum_health]


func _on_player_defeated() -> void:
	player.reset_at(Vector2.ZERO)


func _on_player_weapon_changed(weapon_name: String) -> void:
	weapon_value.text = weapon_name
