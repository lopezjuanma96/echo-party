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
@onready var level_value: Label = $HUD/Progression/Content/LevelValue
@onready var experience_value: Label = $HUD/Progression/Content/ExperienceValue
@onready var choice_modal: Control = $HUD/ChoiceModal
@onready var choice_title: Label = $HUD/ChoiceModal/Center/Panel/Margin/Content/Title
@onready var might_button: Button = $HUD/ChoiceModal/Center/Panel/Margin/Content/Might
@onready var vitality_button: Button = $HUD/ChoiceModal/Center/Panel/Margin/Content/Vitality

var random := RandomNumberGenerator.new()
var progression := HeroProgression.new()


func _ready() -> void:
	_setup_default_bindings()
	_setup_choice_shortcuts()
	player.apply_progression_stats(progression.get_max_health(), progression.get_attack_damage())
	_on_player_health_changed(player.health, player.max_health)
	_on_player_weapon_changed(player.get_selected_weapon_name())
	_update_progression_hud()
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
		enemy.defeated.connect(_on_enemy_defeated)
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


func _setup_choice_shortcuts() -> void:
	_set_button_shortcut(might_button, KEY_1)
	_set_button_shortcut(vitality_button, KEY_2)


func _set_button_shortcut(button: Button, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	var shortcut := Shortcut.new()
	shortcut.events = [event]
	button.shortcut = shortcut


func _on_enemy_defeated(experience_reward: int) -> void:
	progression.grant_experience(experience_reward)
	_update_progression_hud()
	_show_next_choice_if_needed()


func _show_next_choice_if_needed() -> void:
	var pending_levels: Array[int] = progression.get_pending_choice_levels()
	if pending_levels.is_empty():
		choice_modal.hide()
		get_tree().paused = false
		return
	choice_title.text = "LEVEL %d — CHOOSE AN ATTRIBUTE" % pending_levels[0]
	choice_modal.show()
	get_tree().paused = true


func _on_might_pressed() -> void:
	_apply_pending_choice(HeroProgression.ATTRIBUTE_MIGHT)


func _on_vitality_pressed() -> void:
	_apply_pending_choice(HeroProgression.ATTRIBUTE_VITALITY)


func _apply_pending_choice(attribute_id: StringName) -> void:
	var pending_levels: Array[int] = progression.get_pending_choice_levels()
	if pending_levels.is_empty():
		return
	if not progression.apply_attribute_choice(pending_levels[0], attribute_id):
		return
	player.suppress_combat_input_until_released()
	player.apply_progression_stats(progression.get_max_health(), progression.get_attack_damage())
	_update_progression_hud()
	_show_next_choice_if_needed()


func _update_progression_hud() -> void:
	level_value.text = "Level %d" % progression.level
	experience_value.text = "XP %d / %d" % [
		progression.get_experience_into_level(),
		HeroProgression.XP_PER_LEVEL,
	]
