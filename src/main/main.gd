extends Node2D


const ECHO_SCENE := preload("res://src/echo/echo.tscn")
const FOCUS_MARKER_SCRIPT := preload("res://src/combat/focus_target_marker.gd")
const FOCUS_CLICK_RADIUS := 96.0
## Weapon bar fill once ready; matches the echo overlay's ready colour so amber
## always means "cooling down".
const WEAPON_READY_FILL_COLOR := Color(0.72, 0.78, 0.88, 1.0)
const TRIAL_REPORT_SECONDS := 10.0
const TRIAL_CHIP_COVERED_TEXT := Color(0.72, 0.95, 0.8, 1.0)
const TRIAL_CHIP_UNCOVERED_TEXT := Color(1.0, 0.72, 0.72, 1.0)
const DEFAULT_KEY_BINDINGS := {
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"move_up": [KEY_W, KEY_UP],
	&"move_down": [KEY_S, KEY_DOWN],
	&"dodge": [KEY_SPACE],
	&"ability_1": [KEY_E],
	&"weapon_slot_1": [KEY_1],
	&"weapon_slot_2": [KEY_2],
	&"echo_regroup": [KEY_R],
	&"echo_hold": [KEY_Q],
}
const DEFAULT_MOUSE_BINDINGS := {
	&"basic_attack": [MOUSE_BUTTON_LEFT],
	&"weapon_previous": [MOUSE_BUTTON_WHEEL_UP],
	&"weapon_next": [MOUSE_BUTTON_WHEEL_DOWN],
	&"echo_focus": [MOUSE_BUTTON_RIGHT],
}

@onready var player: CharacterBody2D = $Player
@onready var health_bar: ProgressBar = $HUD/Health/Content/HealthBar
@onready var health_value: Label = $HUD/Health/Content/HealthValue
@onready var weapon_value: Label = $HUD/Weapon/Content/WeaponValue
@onready var weapon_cooldown_value: Label = $HUD/Weapon/Content/WeaponCooldownValue
@onready var weapon_cooldown_bar: ProgressBar = $HUD/Weapon/Content/WeaponCooldownBar
@onready var ability_value: Label = $HUD/Weapon/Content/AbilityValue
@onready var dodge_value: Label = $HUD/Weapon/Content/DodgeValue
@onready var level_value: Label = $HUD/Progression/Content/LevelValue
@onready var job_value: Label = $HUD/Progression/Content/JobValue
@onready var experience_value: Label = $HUD/Progression/Content/ExperienceValue
@onready var run_value: Label = $HUD/RunStatus/Content/RunValue
@onready var echo_value: Label = $HUD/RunStatus/Content/EchoValue
@onready var echo_command_value: Label = $HUD/RunStatus/Content/EchoCommandValue
@onready var echo_intent_value: Label = $HUD/RunStatus/Content/EchoIntentValue
@onready var echo_cooldowns_value: Label = $HUD/RunStatus/Content/EchoCooldownsValue
@onready var encounter_director: EncounterDirector = $EncounterDirector
@onready var trial_panel: Control = $HUD/Trial
@onready var trial_title: Label = $HUD/Trial/Margin/Content/Title
@onready var trial_chips: HBoxContainer = $HUD/Trial/Margin/Content/Chips
@onready var trial_status: Label = $HUD/Trial/Margin/Content/Status
@onready var trial_banner: Control = $HUD/TrialBanner
@onready var trial_banner_title: Label = $HUD/TrialBanner/Margin/Content/Title
@onready var trial_banner_needs: Label = $HUD/TrialBanner/Margin/Content/Needs
@onready var trial_banner_countdown: Label = $HUD/TrialBanner/Margin/Content/Countdown
@onready var trial_report: Control = $HUD/TrialReport
@onready var trial_report_title: Label = $HUD/TrialReport/Margin/Content/Title
@onready var trial_report_body: Label = $HUD/TrialReport/Margin/Content/Body
@onready var choice_modal: Control = $HUD/ChoiceModal
@onready var choice_title: Label = $HUD/ChoiceModal/Center/Panel/Margin/Content/Title
@onready var choice_one_button: Button = $HUD/ChoiceModal/Center/Panel/Margin/Content/ChoiceOne
@onready var choice_two_button: Button = $HUD/ChoiceModal/Center/Panel/Margin/Content/ChoiceTwo
@onready var choice_three_button: Button = $HUD/ChoiceModal/Center/Panel/Margin/Content/ChoiceThree

var progression := HeroProgression.new()
var run_number := 1
var latest_echo_record: HeroRecord
var echo: EchoActor
var focus_marker: Node2D
var _defeat_transition_pending := false
var _echo_was_defeated := false
var _ability_feedback_time_left := 0.0
var _weapon_cooling_fill: StyleBox
var _weapon_ready_fill: StyleBoxFlat
var _weapon_bar_shows_ready := false
var _trial_report_time_left := 0.0
var _trial_chip_panels: Array[PanelContainer] = []
var _trial_chip_labels: Array[Label] = []
var _trial_chip_covered_style: StyleBoxFlat
var _trial_chip_uncovered_style: StyleBoxFlat
var _party_cache_record: HeroRecord
var _party_cache_echo_job: StringName = &""


func _ready() -> void:
	_weapon_cooling_fill = weapon_cooldown_bar.get_theme_stylebox(&"fill")
	_weapon_ready_fill = _weapon_cooling_fill.duplicate() as StyleBoxFlat
	_weapon_ready_fill.bg_color = WEAPON_READY_FILL_COLOR
	_setup_default_bindings()
	_setup_choice_shortcuts()
	_trial_chip_covered_style = _make_trial_chip_style(Color(0.1, 0.28, 0.18, 0.9), Color(0.36, 0.85, 0.54, 1.0))
	_trial_chip_uncovered_style = _make_trial_chip_style(Color(0.3, 0.1, 0.12, 0.9), Color(0.9, 0.35, 0.35, 1.0))
	player.apply_progression(progression, true)
	_on_player_health_changed(player.health, player.max_health)
	_on_player_weapon_changed(player.get_selected_weapon_id())
	_update_progression_hud()
	_update_run_hud()
	_update_ability_hud()
	_update_trial_hud()
	focus_marker = FOCUS_MARKER_SCRIPT.new() as Node2D
	focus_marker.visible = false
	focus_marker.z_index = 5
	add_child(focus_marker)


func _process(delta: float) -> void:
	_ability_feedback_time_left = maxf(_ability_feedback_time_left - delta, 0.0)
	_update_weapon_cooldown_hud()
	_update_ability_hud()
	_update_run_hud()
	_update_encounter(delta)
	if is_instance_valid(echo):
		focus_marker.set("target", echo.focused_target)
	else:
		focus_marker.set("target", null)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"echo_focus"):
		command_echo_focus_at(player.get_global_mouse_position())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"echo_regroup") and is_instance_valid(echo):
		echo.command_regroup()
		_update_run_hud()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"echo_hold") and is_instance_valid(echo):
		echo.toggle_hold_position()
		_update_run_hud()
		get_viewport().set_input_as_handled()


func command_echo_focus_at(world_position: Vector2) -> bool:
	if not is_instance_valid(echo):
		return false
	var best: Node2D
	var best_distance_squared := FOCUS_CLICK_RADIUS * FOCUS_CLICK_RADIUS
	var best_order := 9223372036854775807
	for candidate_node in get_tree().get_nodes_in_group(&"enemies"):
		var candidate := candidate_node as Node2D
		if candidate == null or candidate.is_queued_for_deletion():
			continue
		var distance_squared := world_position.distance_squared_to(candidate.global_position)
		var order := int(candidate.get("stable_spawn_order"))
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
	return best != null and echo.command_focus(best)


func _update_weapon_cooldown_hud() -> void:
	var cooldown := float(player.attack_cooldowns.get(player.selected_weapon_id, 0.0))
	weapon_cooldown_value.text = "Ready" if cooldown <= 0.0 else "Cooldown %.1fs" % cooldown
	weapon_cooldown_bar.value = 1.0 - player.get_weapon_cooldown_fraction()
	var weapon_ready := cooldown <= 0.0
	if weapon_ready != _weapon_bar_shows_ready:
		_weapon_bar_shows_ready = weapon_ready
		weapon_cooldown_bar.add_theme_stylebox_override(
			&"fill",
			_weapon_ready_fill if weapon_ready else _weapon_cooling_fill
		)
	dodge_value.text = "[Space] Dodge — %s" % HeroActor.format_cooldown(player.dodge_cooldown_left)


func _update_ability_hud() -> void:
	var ability := AbilityCatalog.get_ability(player.ability_id) as AbilityDefinition
	ability_value.visible = ability != null
	if ability == null or _ability_feedback_time_left > 0.0:
		return
	var status := "Ready"
	if player.ability_cooldown_left > 0.0:
		status = "%.1fs" % player.ability_cooldown_left
	ability_value.text = "[E] %s — %s" % [ability.display_name, status]


func _on_player_ability_feedback(message: String) -> void:
	ability_value.text = message
	_ability_feedback_time_left = 1.5


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
	if _defeat_transition_pending:
		return
	_defeat_transition_pending = true
	choice_modal.hide()
	get_tree().paused = false
	call_deferred(&"_start_next_run")


func _start_next_run() -> void:
	choice_modal.hide()
	get_tree().paused = false
	latest_echo_record = HeroRecord.capture(
		"hero-%d" % run_number,
		"Hero %d" % run_number,
		progression
	)
	_clear_transient_combat()
	trial_report.hide()
	# Before the echo is freed, so a failed court still reports whether it lived.
	encounter_director.reset_for_new_run()
	if is_instance_valid(echo):
		echo.free()
		echo = null

	run_number += 1
	progression = HeroProgression.new()
	_echo_was_defeated = false
	player.reset_for_new_run(Vector2.ZERO)
	_spawn_latest_echo()
	_on_player_health_changed(player.health, player.max_health)
	_on_player_weapon_changed(player.get_selected_weapon_id())
	_update_progression_hud()
	_update_run_hud()
	_update_trial_hud()
	_defeat_transition_pending = false


func _spawn_latest_echo() -> void:
	if latest_echo_record == null:
		return
	echo = ECHO_SCENE.instantiate() as EchoActor
	if echo == null:
		return
	echo.position = player.position + Vector2(92.0, 0.0)
	echo.active_hero_label = "Hero %d" % run_number
	add_child(echo)
	if not echo.configure(latest_echo_record, player):
		echo.queue_free()
		echo = null
		return
	echo.defeated.connect(_on_echo_defeated)
	echo.progression_changed.connect(_update_run_hud)


func _on_echo_defeated() -> void:
	_echo_was_defeated = true
	if is_instance_valid(echo):
		echo.queue_free()
	echo = null
	_update_run_hud()


func _clear_transient_combat() -> void:
	for transient in get_tree().get_nodes_in_group(HeroActor.TRANSIENT_COMBAT_GROUP):
		transient.queue_free()


func _on_player_weapon_changed(weapon_id: StringName) -> void:
	weapon_value.text = WeaponCatalog.get_display_name(weapon_id)


func _setup_choice_shortcuts() -> void:
	_set_button_shortcut(choice_one_button, KEY_1)
	_set_button_shortcut(choice_two_button, KEY_2)
	_set_button_shortcut(choice_three_button, KEY_3)


func _set_button_shortcut(button: Button, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	var shortcut := Shortcut.new()
	shortcut.events = [event]
	button.shortcut = shortcut


func _on_enemy_defeated(experience_reward: int) -> void:
	if _defeat_transition_pending:
		return
	progression.grant_experience(experience_reward)
	if is_instance_valid(echo):
		echo.grant_shared_experience(experience_reward)
	_update_progression_hud()
	_update_run_hud()
	_show_next_choice_if_needed()


func _show_next_choice_if_needed() -> void:
	var pending_levels: Array[int] = progression.get_pending_choice_levels()
	if pending_levels.is_empty():
		choice_modal.hide()
		get_tree().paused = false
		return
	var choice_level := pending_levels[0]
	choice_three_button.visible = choice_level == HeroProgression.ADVANCEMENT_LEVEL
	if choice_level == HeroProgression.ADVANCEMENT_LEVEL:
		choice_title.text = "LEVEL %d — CHOOSE A JOB" % choice_level
		var uncovered_needs := PartyNeeds.uncovered(
			_party_job_ids(),
			EncounterCatalog.get_needs(encounter_director.encounter_id)
		)
		choice_one_button.text = _annotate_job_choice(
			"[1] VANGUARD\nSword and Lance — medium arc or long thrust",
			HeroProgression.JOB_VANGUARD,
			uncovered_needs
		)
		choice_two_button.text = _annotate_job_choice(
			"[2] ARCANIST\nWand and Staff — quick short or slow long bolts",
			HeroProgression.JOB_ARCANIST,
			uncovered_needs
		)
		choice_three_button.text = _annotate_job_choice(
			"[3] MENDER\nMace and Sling — Mend a wounded ally",
			HeroProgression.JOB_MENDER,
			uncovered_needs
		)
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


func _on_choice_three_pressed() -> void:
	_apply_pending_choice(2)


func _apply_pending_choice(option_index: int) -> void:
	var pending_levels: Array[int] = progression.get_pending_choice_levels()
	if pending_levels.is_empty() or option_index < 0:
		return
	var choice_level := pending_levels[0]
	var applied := false
	if choice_level == HeroProgression.ADVANCEMENT_LEVEL:
		if option_index >= HeroProgression.JOB_IDS.size():
			return
		var job_id := HeroProgression.JOB_IDS[option_index]
		applied = progression.apply_job_choice(choice_level, job_id)
		if applied:
			player.apply_job_loadout(job_id)
	else:
		if option_index >= HeroProgression.ATTRIBUTE_IDS.size():
			return
		var attribute_id := HeroProgression.ATTRIBUTE_IDS[option_index]
		applied = progression.apply_attribute_choice(choice_level, attribute_id)
	if not applied:
		return
	player.suppress_combat_input_until_released()
	player.apply_progression_stats(progression.get_max_health(), progression.get_attack_damage())
	_update_progression_hud()
	_update_ability_hud()
	_show_next_choice_if_needed()


func _update_progression_hud() -> void:
	(get_node("Enemies") as EnemySpawner).threat_level = progression.level
	level_value.text = "Level %d" % progression.level
	job_value.text = _job_display_name(progression.get_job_id())
	experience_value.text = "XP %d / %d" % [
		progression.get_experience_into_level(),
		HeroProgression.XP_PER_LEVEL,
	]


func _update_run_hud() -> void:
	run_value.text = "Run %d" % run_number
	echo_command_value.text = "Command: —"
	echo_intent_value.text = "Intent: —"
	echo_cooldowns_value.text = "Cooldowns: —"
	if latest_echo_record == null:
		echo_value.text = "Echo: None"
		return
	if _echo_was_defeated:
		echo_value.text = "Echo: Defeated"
	elif is_instance_valid(echo):
		echo_value.text = "Echo: %s · Level %d" % [
			_job_display_name(echo.job_id),
			echo.progression.level,
		]
		echo_command_value.text = "Command: %s · %d/%d HP" % [
			String(echo.get_command_status()).capitalize(),
			echo.health,
			echo.max_health,
		]
		echo_intent_value.text = "Intent: %s" % echo.get_intent_summary()
		echo_cooldowns_value.text = "Cooldowns: %s" % echo.get_cooldown_summary()
	else:
		echo_value.text = "Echo: Unavailable"


func _party_job_ids() -> Array[StringName]:
	if latest_echo_record != _party_cache_record:
		_party_cache_record = latest_echo_record
		_party_cache_echo_job = &""
		if latest_echo_record != null:
			var recorded := latest_echo_record.replay_progression()
			if recorded != null:
				_party_cache_echo_job = recorded.get_job_id()
	var jobs: Array[StringName] = []
	if not _party_cache_echo_job.is_empty():
		jobs.append(_party_cache_echo_job)
	jobs.append(progression.get_job_id())
	return jobs


func _annotate_job_choice(base_text: String, job_id: StringName, uncovered_needs: Array) -> String:
	var annotation := PartyNeeds.fill_annotation(job_id, uncovered_needs)
	return base_text if annotation.is_empty() else "%s\n%s" % [base_text, annotation]


func _update_encounter(delta: float) -> void:
	if not _defeat_transition_pending and encounter_director.can_trigger(
		progression.level,
		progression.has_pending_choice()
	):
		encounter_director.try_trigger(
			progression.level,
			progression.has_pending_choice(),
			_party_job_ids()
		)
	if trial_report.visible:
		_trial_report_time_left -= delta
		if _trial_report_time_left <= 0.0:
			trial_report.hide()
	_update_trial_hud()


func _make_trial_chip_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style


func _ensure_trial_chips(count: int) -> void:
	while _trial_chip_panels.size() < count:
		var chip := PanelContainer.new()
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override(&"font_size", 13)
		chip.add_child(label)
		trial_chips.add_child(chip)
		_trial_chip_panels.append(chip)
		_trial_chip_labels.append(label)
	while _trial_chip_panels.size() > count:
		_trial_chip_panels.pop_back().queue_free()
		_trial_chip_labels.pop_back()


func _update_trial_hud() -> void:
	var encounter_id := encounter_director.encounter_id
	var needs := EncounterCatalog.get_needs(encounter_id)
	var coverage := PartyNeeds.evaluate(_party_job_ids(), needs)
	var covered: Dictionary = coverage["covered"]
	_ensure_trial_chips(needs.size())
	for index in needs.size():
		var need := StringName(needs[index])
		var label := _trial_chip_labels[index]
		var is_covered := covered.has(need)
		var chip_text := ""
		if is_covered:
			chip_text = "✓ %s\n%s" % [
				PartyNeeds.need_label(need),
				JobCatalog.get_display_name(covered[need]),
			]
		else:
			chip_text = "✗ %s\nMissing" % PartyNeeds.need_label(need)
		if label.text == chip_text:
			continue
		label.text = chip_text
		label.add_theme_color_override(
			&"font_color",
			TRIAL_CHIP_COVERED_TEXT if is_covered else TRIAL_CHIP_UNCOVERED_TEXT
		)
		_trial_chip_panels[index].add_theme_stylebox_override(
			&"panel",
			_trial_chip_covered_style if is_covered else _trial_chip_uncovered_style
		)
	trial_title.text = "TRIAL · %s · Lv %d" % [
		EncounterCatalog.get_display_name(encounter_id),
		EncounterCatalog.get_trigger_level(encounter_id),
	]
	trial_status.text = _trial_status_text()
	var warning := encounter_director.state == EncounterDirector.STATE_WARNING
	trial_banner.visible = warning
	if warning:
		var data := EncounterCatalog.get_encounter(encounter_id)
		var need_names: Array[String] = []
		for need: StringName in needs:
			need_names.append(String(need).capitalize())
		trial_banner_title.text = String(data.get("banner_title", ""))
		trial_banner_needs.text = "Needs: %s" % " · ".join(need_names)
		trial_banner_countdown.text = "Begins in %.1f s" % encounter_director.state_time_left


func _trial_status_text() -> String:
	match encounter_director.state:
		EncounterDirector.STATE_WARNING:
			return "Court begins in %.1f s" % encounter_director.state_time_left
		EncounterDirector.STATE_ACTIVE:
			return "Court in progress · %d s" % int(encounter_director.elapsed)
		EncounterDirector.STATE_CLEARED:
			return "Court cleared in %d s" % int(encounter_director.elapsed)
	if not encounter_director.armed:
		return "Court inactive"
	return "Reach Lv %d to face the Court" % EncounterCatalog.get_trigger_level(
		encounter_director.encounter_id
	)


func _trial_panel_text() -> String:
	var lines: Array[String] = [trial_title.text]
	for label in _trial_chip_labels:
		lines.append(label.text.replace("\n", " · "))
	lines.append(trial_status.text)
	return "\n".join(lines)


func _trial_banner_text() -> String:
	return "%s\n%s\n%s" % [
		trial_banner_title.text,
		trial_banner_needs.text,
		trial_banner_countdown.text,
	]


func _on_trial_report_ready(report: Dictionary) -> void:
	trial_report_title.text = format_trial_report_title(report)
	trial_report_body.text = format_trial_report_body(report)
	trial_report.show()
	_trial_report_time_left = TRIAL_REPORT_SECONDS


static func format_trial_report_title(report: Dictionary) -> String:
	return "%s — %s · %d s" % [
		String(report.get("display_name", "Trial")).to_upper(),
		String(report.get("outcome", "")).to_upper(),
		int(report.get("time", 0.0)),
	]


static func format_trial_report_body(report: Dictionary) -> String:
	var had_echo := bool(report.get("had_echo", false))
	var lines: Array[String] = [
		"Casts: %d landed · %d broken" % [
			int(report.get("casts_landed", 0)),
			int(report.get("casts_broken", 0)),
		],
	]
	var damage: Dictionary = report.get("damage_taken", {})
	if damage.is_empty():
		lines.append("Damage taken: none")
	else:
		lines.append("Damage taken:")
		var enemy_ids: Array = damage.keys()
		enemy_ids.sort()
		for enemy_id: String in enemy_ids:
			var entry: Dictionary = damage[enemy_id]
			var detail := "Hero %d" % roundi(float(entry["hero"]))
			if had_echo:
				detail += " · Echo %d" % roundi(float(entry["echo"]))
			lines.append("  %s — %s" % [enemy_id.capitalize(), detail])
	lines.append("Healing done: %d" % roundi(float(report.get("healing_done", 0.0))))
	if not had_echo:
		lines.append("Echo: none")
	else:
		lines.append("Echo: %s" % ("survived" if bool(report.get("echo_survived", false)) else "defeated"))
	var uncovered: Array = report.get("uncovered", [])
	if uncovered.is_empty():
		lines.append("All needs covered ✓")
	for need: String in uncovered:
		lines.append(PartyNeeds.missing_line(StringName(need)))
	return "\n".join(lines)


func _job_display_name(job_id: StringName) -> String:
	return JobCatalog.get_display_name(job_id)


func apply_scenario(
	player_job: StringName,
	echo_job: StringName,
	level: int,
	encounter_id: StringName
) -> bool:
	if not encounter_id.is_empty() and not EncounterCatalog.has_encounter(encounter_id):
		return false
	var player_progression := _build_scenario_progression(player_job, level)
	if player_progression == null:
		return false
	var echo_progression: HeroProgression
	if not echo_job.is_empty():
		echo_progression = _build_scenario_progression(echo_job, level)
		if echo_progression == null:
			return false

	choice_modal.hide()
	get_tree().paused = false
	encounter_director.reset_for_new_run()
	trial_report.hide()
	progression = player_progression
	run_number = 1
	_defeat_transition_pending = false
	_echo_was_defeated = false
	_ability_feedback_time_left = 0.0
	player.reset_for_new_run(Vector2.ZERO)
	player.apply_progression(progression, true)
	if is_instance_valid(echo):
		echo.free()
		echo = null
	latest_echo_record = null
	if echo_progression != null:
		latest_echo_record = HeroRecord.capture(
			"scenario-echo",
			"%s Echo" % JobCatalog.get_display_name(echo_job),
			echo_progression
		)
		_spawn_latest_echo()
		if is_instance_valid(echo):
			echo.grant_shared_experience(echo_progression.experience)
	_on_player_health_changed(player.health, player.max_health)
	_on_player_weapon_changed(player.get_selected_weapon_id())
	_update_progression_hud()
	_update_run_hud()
	_update_ability_hud()
	# Scenarios are isolated: an un-armed director keeps level-5 scenarios from
	# starting the court on their own.
	if encounter_id.is_empty():
		encounter_director.disarm()
	elif not encounter_director.start_encounter(_party_job_ids(), encounter_id):
		return false
	_update_trial_hud()
	return true


func _build_scenario_progression(job_id: StringName, level: int) -> HeroProgression:
	if level < 1:
		return null
	var scenario_progression := HeroProgression.new()
	scenario_progression.grant_experience((level - 1) * HeroProgression.XP_PER_LEVEL)
	for choice_level in range(2, level + 1):
		var applied := false
		if choice_level == HeroProgression.ADVANCEMENT_LEVEL:
			if not HeroProgression.JOB_IDS.has(job_id):
				return null
			applied = scenario_progression.apply_job_choice(choice_level, job_id)
		else:
			var attribute_id := (
				HeroProgression.ATTRIBUTE_MIGHT
				if choice_level % 2 == 0
				else HeroProgression.ATTRIBUTE_VITALITY
			)
			applied = scenario_progression.apply_attribute_choice(choice_level, attribute_id)
		if not applied:
			return null
	return scenario_progression


func _mcp_state() -> Dictionary:
	return {
		"run_number": run_number,
		"level": progression.level,
		"experience": progression.experience,
		"job_id": String(progression.get_job_id()),
		"pending_choice_levels": progression.get_pending_choice_levels(),
		"choice_modal_visible": choice_modal.visible,
		"choice_three_visible": choice_three_button.visible,
		"ability_hud_visible": ability_value.visible,
		"ability_hud_text": ability_value.text,
		"weapon_cooldown_hud_text": weapon_cooldown_value.text,
		"dodge_hud_text": dodge_value.text,
		"echo_intent_hud_text": echo_intent_value.text,
		"echo_cooldowns_hud_text": echo_cooldowns_value.text,
		"has_echo": is_instance_valid(echo),
		"paused": get_tree().paused,
		"director_state": String(encounter_director.state),
		"director": encounter_director._mcp_state(),
		"trial_panel_text": _trial_panel_text(),
		"trial_banner_visible": trial_banner.visible,
		"trial_banner_text": _trial_banner_text(),
		"trial_report_visible": trial_report.visible,
		"trial_report_text": "%s\n%s" % [trial_report_title.text, trial_report_body.text],
	}
