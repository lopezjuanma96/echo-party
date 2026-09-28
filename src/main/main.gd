extends Node2D


const DEFAULT_KEY_BINDINGS := {
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"move_up": [KEY_W, KEY_UP],
	&"move_down": [KEY_S, KEY_DOWN],
	&"dodge": [KEY_SPACE],
	&"weapon_slot_1": [KEY_1],
	&"weapon_slot_2": [KEY_2],
}
const DEFAULT_MOUSE_BINDINGS := {
	&"basic_attack": [MOUSE_BUTTON_LEFT],
	&"weapon_previous": [MOUSE_BUTTON_WHEEL_UP],
	&"weapon_next": [MOUSE_BUTTON_WHEEL_DOWN],
}

@onready var player: CharacterBody2D = $Player
@onready var health_bar: ProgressBar = $HUD/Health/Content/HealthBar
@onready var health_value: Label = $HUD/Health/Content/HealthValue
@onready var weapon_value: Label = $HUD/Weapon/Content/WeaponValue
@onready var level_value: Label = $HUD/Progression/Content/LevelValue
@onready var job_value: Label = $HUD/Progression/Content/JobValue
@onready var experience_value: Label = $HUD/Progression/Content/ExperienceValue
@onready var choice_modal: Control = $HUD/ChoiceModal
@onready var choice_title: Label = $HUD/ChoiceModal/Center/Panel/Margin/Content/Title
@onready var choice_one_button: Button = $HUD/ChoiceModal/Center/Panel/Margin/Content/ChoiceOne
@onready var choice_two_button: Button = $HUD/ChoiceModal/Center/Panel/Margin/Content/ChoiceTwo

var progression := HeroProgression.new()


func _ready() -> void:
	_setup_default_bindings()
	_setup_choice_shortcuts()
	player.apply_job_loadout(progression.get_job_id())
	player.apply_progression_stats(progression.get_max_health(), progression.get_attack_damage())
	_on_player_health_changed(player.health, player.max_health)
	_on_player_weapon_changed(player.get_selected_weapon_id())
	_update_progression_hud()


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


func _on_player_health_changed(current_health: float, maximum_health: float) -> void:
	health_bar.max_value = maximum_health
	health_bar.value = current_health
	health_value.text = "%d / %d" % [current_health, maximum_health]


func _on_player_defeated() -> void:
	player.reset_at(Vector2.ZERO)


func _on_player_weapon_changed(weapon_id: StringName) -> void:
	weapon_value.text = WeaponCatalog.get_display_name(weapon_id)


func _setup_choice_shortcuts() -> void:
	_set_button_shortcut(choice_one_button, KEY_1)
	_set_button_shortcut(choice_two_button, KEY_2)


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
	var choice_level := pending_levels[0]
	if choice_level == HeroProgression.ADVANCEMENT_LEVEL:
		choice_title.text = "LEVEL %d — CHOOSE A JOB" % choice_level
		choice_one_button.text = "[1] VANGUARD\nSword and Lance — medium arc or long thrust"
		choice_two_button.text = "[2] ARCANIST\nWand and Staff — quick short or slow long bolts"
	else:
		choice_title.text = "LEVEL %d — CHOOSE AN ATTRIBUTE" % choice_level
		choice_one_button.text = "[1] MIGHT\n+5 attack damage"
		choice_two_button.text = "[2] VITALITY\n+20 max health and current health"
	choice_modal.show()
	get_tree().paused = true


func _on_choice_one_pressed() -> void:
	_apply_pending_choice(0)


func _on_choice_two_pressed() -> void:
	_apply_pending_choice(1)


func _apply_pending_choice(option_index: int) -> void:
	var pending_levels: Array[int] = progression.get_pending_choice_levels()
	if pending_levels.is_empty():
		return
	var choice_level := pending_levels[0]
	var applied := false
	if choice_level == HeroProgression.ADVANCEMENT_LEVEL:
		var job_id := (
			HeroProgression.JOB_VANGUARD
			if option_index == 0
			else HeroProgression.JOB_ARCANIST
		)
		applied = progression.apply_job_choice(choice_level, job_id)
		if applied:
			player.apply_job_loadout(job_id)
	else:
		var attribute_id := (
			HeroProgression.ATTRIBUTE_MIGHT
			if option_index == 0
			else HeroProgression.ATTRIBUTE_VITALITY
		)
		applied = progression.apply_attribute_choice(choice_level, attribute_id)
	if not applied:
		return
	player.suppress_combat_input_until_released()
	player.apply_progression_stats(progression.get_max_health(), progression.get_attack_damage())
	_update_progression_hud()
	_show_next_choice_if_needed()


func _update_progression_hud() -> void:
	level_value.text = "Level %d" % progression.level
	job_value.text = _job_display_name(progression.get_job_id())
	experience_value.text = "XP %d / %d" % [
		progression.get_experience_into_level(),
		HeroProgression.XP_PER_LEVEL,
	]


func _job_display_name(job_id: StringName) -> String:
	match job_id:
		HeroProgression.JOB_VANGUARD:
			return "Vanguard"
		HeroProgression.JOB_ARCANIST:
			return "Arcanist"
		_:
			return "Novice"
