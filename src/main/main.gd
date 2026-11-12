extends Node2D


const ECHO_SCENE := preload("res://src/echo/echo.tscn")
const FOCUS_MARKER_SCRIPT := preload("res://src/combat/focus_target_marker.gd")
const FOCUS_CLICK_RADIUS := 96.0
## Weapon bar fill once ready; matches the echo overlay's ready colour so amber
## always means "cooling down".
const WEAPON_READY_FILL_COLOR := Color(0.72, 0.78, 0.88, 1.0)
const TRIAL_REPORT_SECONDS := 10.0
const CHOICE_PROMPT_HERO := "Combat is paused. Choose one permanent build step."
const CHOICE_PROMPT_ECHO := "Combat is paused. This extends the echo's saved history."
const RUN_NOTICE_SECONDS := 6.0
const DEFAULT_SAVE_PATH := "user://echo_party_save.json"
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
	&"weapon_previous": [],
	&"weapon_next": [],
	&"address_previous": [MOUSE_BUTTON_WHEEL_UP],
	&"address_next": [MOUSE_BUTTON_WHEEL_DOWN],
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
@onready var echo_2_value: Label = $HUD/RunStatus/Content/Echo2Value
@onready var echo_2_command_value: Label = $HUD/RunStatus/Content/Echo2CommandValue
@onready var echo_2_intent_value: Label = $HUD/RunStatus/Content/Echo2IntentValue
@onready var echo_2_cooldowns_value: Label = $HUD/RunStatus/Content/Echo2CooldownsValue
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
@onready var run_notice: Control = $HUD/RunNotice
@onready var run_notice_text: Label = $HUD/RunNotice/Margin/Text
@onready var resolution_screen: ResolutionScreen = $HUD/ResolutionScreen
@onready var choice_modal: Control = $HUD/ChoiceModal
@onready var choice_title: Label = $HUD/ChoiceModal/Center/Panel/Margin/Content/Title
@onready var choice_prompt: Label = $HUD/ChoiceModal/Center/Panel/Margin/Content/Prompt
@onready var choice_one_button: Button = $HUD/ChoiceModal/Center/Panel/Margin/Content/ChoiceOne
@onready var choice_two_button: Button = $HUD/ChoiceModal/Center/Panel/Margin/Content/ChoiceTwo
@onready var choice_three_button: Button = $HUD/ChoiceModal/Center/Panel/Margin/Content/ChoiceThree

var progression := HeroProgression.new()
var run_number := 1
var save_path := DEFAULT_SAVE_PATH
var document := SaveDocument.new_default()
var roster_store := SaveStore.new()
var save_status := "new"
var roster := Roster.new(RosterCapacity.BASE_PARTY_SLOTS, RosterCapacity.BASE_MEMORIAL_SLOTS)
var party_slots := RosterCapacity.BASE_PARTY_SLOTS
var run_anchors := 0
var unlocks: Array[StringName] = []
var trial_clears: Dictionary = {}
var party_commander := PartyCommander.new()
var echoes: Array[EchoActor] = []
var focus_markers: Array[FocusTargetMarker] = []
var latest_echo_record: HeroRecord:
	get:
		return roster.party[0] if not roster.party.is_empty() else null
var echo: EchoActor:
	get:
		if echoes.is_empty() or not is_instance_valid(echoes[0]):
			return null
		return echoes[0]
var focus_marker: Node2D:
	get:
		return focus_markers[0] if not focus_markers.is_empty() else null
var _defeat_transition_pending := false
var _clear_rewarded_this_run := false
## The subject the open choice modal is asking about: {} when closed, otherwise
## {"kind": &"hero"|&"echo", "slot": int (-1 for the hero), "level": int}.
var _choice_subject := {}
var _defeated_echo_slots := {}
var _ability_feedback_time_left := 0.0
var _weapon_cooling_fill: StyleBox
var _weapon_ready_fill: StyleBoxFlat
var _weapon_bar_shows_ready := false
var _trial_report_time_left := 0.0
var _run_notice_time_left := 0.0
var _trial_chip_panels: Array[PanelContainer] = []
var _trial_chip_labels: Array[Label] = []
var _trial_chip_covered_style: StyleBoxFlat
var _trial_chip_uncovered_style: StyleBoxFlat
var _party_cache_key := ""
var _party_cache_echo_jobs: Array[StringName] = []


func _ready() -> void:
	_weapon_cooling_fill = weapon_cooldown_bar.get_theme_stylebox(&"fill")
	_weapon_ready_fill = _weapon_cooling_fill.duplicate() as StyleBoxFlat
	_weapon_ready_fill.bg_color = WEAPON_READY_FILL_COLOR
	_setup_default_bindings()
	_setup_choice_shortcuts()
	_trial_chip_covered_style = _make_trial_chip_style(Color(0.1, 0.28, 0.18, 0.9), Color(0.36, 0.85, 0.54, 1.0))
	_trial_chip_uncovered_style = _make_trial_chip_style(Color(0.3, 0.1, 0.12, 0.9), Color(0.9, 0.35, 0.35, 1.0))
	resolution_screen.resolved.connect(_on_resolution_resolved)
	_load_progress()
	_apply_trial_rotation()
	player.apply_progression(progression, true)
	_on_player_health_changed(player.health, player.max_health)
	_on_player_weapon_changed(player.get_selected_weapon_id())
	_update_progression_hud()
	_update_run_hud()
	_update_ability_hud()
	_update_trial_hud()
	if document.pending:
		_restore_pending_resolution()
	else:
		_spawn_party()


func _load_progress() -> void:
	if save_path == DEFAULT_SAVE_PATH and DisplayServer.get_name() == "headless":
		save_path = ""
	roster_store = SaveStore.new(save_path)
	var loaded := roster_store.load_document()
	document = loaded["document"] as SaveDocument
	save_status = String(loaded["status"])
	unlocks = document.unlocks.duplicate()
	trial_clears = document.trial_clears.duplicate(true)
	run_number = document.next_hero_number
	run_anchors = document.pending_anchors if document.pending else 0
	roster = document.roster
	var loaded_party_slots := RosterCapacity.party_slots(unlocks)
	# A new memory/scenario document may carry a pre-ready fixture capacity.
	party_slots = maxi(party_slots, loaded_party_slots) if save_status == "new" else loaded_party_slots
	roster.set_capacity(party_slots, RosterCapacity.memorial_slots(unlocks))
	if save_status == "corrupt" and roster_store.read_only:
		_show_run_notice("Save unreadable and could not be backed up — progress this session will not be saved")
	elif save_status == "corrupt":
		_show_run_notice("Save unreadable — backed up to %s.corrupt" % save_path)
	elif save_status == "too_new":
		_show_run_notice("Save is from a newer version — progress this session will not be saved")


func _restore_pending_resolution() -> void:
	_defeat_transition_pending = true
	resolution_screen.present(roster, {
		"title": "ROSTER RESOLUTION RESTORED",
		"summary": "The saved resolution is unchanged. Place or discard the candidate before starting.",
		"anchors": run_anchors,
		"encounter_id": encounter_director.encounter_id,
		"unlocks": unlocks,
		"trial_clears": _total_trial_clears(),
	})
	_update_trial_hud()
	get_tree().paused = true


func _save_progress(pending: bool) -> bool:
	document.next_hero_number = run_number
	document.unlocks = unlocks.duplicate()
	document.trial_clears = trial_clears.duplicate(true)
	document.roster = roster
	document.pending = pending
	document.pending_anchors = run_anchors if pending else 0
	var saved := roster_store.save_document(document)
	if not saved:
		_show_run_notice("Save failed — progress this session may not be saved")
	return saved


## Names this run's Trial from the active hero's persisted number (odd → Bell
## Court, even → Slinger Gallery). Runs before the Trial panel, job annotations,
## coverage, and the roster screen's "Next Trial" line read the director.
func _apply_trial_rotation() -> void:
	encounter_director.encounter_id = EncounterCatalog.trial_for_hero(run_number)


func _total_trial_clears() -> int:
	var total := 0
	for count: Variant in trial_clears.values():
		total += int(count)
	return total


func _process(delta: float) -> void:
	_ability_feedback_time_left = maxf(_ability_feedback_time_left - delta, 0.0)
	_update_weapon_cooldown_hud()
	_update_ability_hud()
	_update_run_hud()
	_update_encounter(delta)
	_update_run_notice(delta)
	for slot in focus_markers.size():
		var marker := focus_markers[slot]
		var current_echo := echoes[slot] if slot < echoes.size() else null
		marker.target = current_echo.focused_target if is_instance_valid(current_echo) else null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"address_previous"):
		party_commander.cycle_address(-1, roster.party.size())
		_update_run_hud()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"address_next"):
		party_commander.cycle_address(1, roster.party.size())
		_update_run_hud()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"echo_focus"):
		command_echo_focus_at(player.get_global_mouse_position())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"echo_regroup"):
		party_commander.regroup(echoes)
		_update_run_hud()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"echo_hold"):
		party_commander.toggle_hold(echoes)
		_update_run_hud()
		get_viewport().set_input_as_handled()


func command_echo_focus_at(world_position: Vector2) -> int:
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
	var accepted := party_commander.focus(echoes, best)
	_update_run_hud()
	return accepted


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
	_choice_subject = {}
	choice_modal.hide()
	get_tree().paused = false
	call_deferred(&"_start_next_run")


## Death handler. Offers the fallen hero to the roster (only heroes who chose a
## job qualify), tears the run down, then either opens the resolution screen or
## begins the next run straight away.
func _start_next_run() -> void:
	if resolution_screen.visible:
		return
	_choice_subject = {}
	choice_modal.hide()
	get_tree().paused = false
	var fallen_number := run_number
	var offered := roster.offer_candidate(HeroRecord.capture(
		"hero-%d" % fallen_number,
		"Hero %d" % fallen_number,
		progression.chosen_only()
	))
	var fallen_summary := _fallen_summary(fallen_number, offered)
	_clear_transient_combat()
	trial_report.hide()
	# Before the party is freed, so a failed court still reports whether it lived.
	encounter_director.reset_for_new_run()
	_clear_party()
	run_number += 1
	_apply_trial_rotation()
	if roster.candidate == null and roster.memorial.is_empty():
		_show_run_notice(fallen_summary)
		_save_progress(false)
		_begin_run()
		return
	_save_progress(true)
	resolution_screen.present(roster, {
		"title": "HERO %d HAS FALLEN" % fallen_number,
		"summary": fallen_summary,
		"anchors": run_anchors,
		"encounter_id": encounter_director.encounter_id,
		"unlocks": unlocks,
		"trial_clears": _total_trial_clears(),
	})
	_update_trial_hud()
	get_tree().paused = true


func _fallen_summary(fallen_number: int, offered: bool) -> String:
	if offered:
		return "Hero %d fell as a %s at Level %d. Place them in the roster." % [
			fallen_number,
			_job_display_name(progression.get_job_id()),
			progression.level,
		]
	return "Hero %d fell at Level %d without choosing a job, so they leave no echo." % [
		fallen_number,
		progression.level,
	]


func _on_resolution_resolved(anchors_left: int) -> void:
	run_anchors = anchors_left
	get_tree().paused = false
	_save_progress(false)
	_begin_run()


## Test and scenario shortcut: places any candidate with
## `RosterResolution.default_choice` and starts the run.
func resolve_default() -> bool:
	if not resolution_screen.visible:
		return false
	if roster.candidate != null:
		var result := roster.move(
			{"zone": Roster.ZONE_CANDIDATE, "index": 0},
			RosterResolution.default_choice(roster)
		)
		if not bool(result["ok"]):
			return false
	return resolution_screen.start()


func _begin_run() -> void:
	# Unspent Anchors do not carry into the next run.
	run_anchors = 0
	_clear_rewarded_this_run = false
	progression = HeroProgression.new()
	_defeated_echo_slots.clear()
	party_commander.address = PartyCommander.ADDRESS_ALL
	player.reset_for_new_run(Vector2.ZERO)
	player.suppress_combat_input_until_released()
	_spawn_party()
	_on_player_health_changed(player.health, player.max_health)
	_on_player_weapon_changed(player.get_selected_weapon_id())
	_update_progression_hud()
	_update_run_hud()
	_update_trial_hud()
	_defeat_transition_pending = false


func _show_run_notice(text: String) -> void:
	run_notice_text.text = text
	run_notice.show()
	_run_notice_time_left = RUN_NOTICE_SECONDS


func _update_run_notice(delta: float) -> void:
	if not run_notice.visible:
		return
	_run_notice_time_left -= delta
	if _run_notice_time_left <= 0.0:
		run_notice.hide()


func _spawn_party() -> void:
	_clear_party()
	echoes.resize(roster.party.size())
	focus_markers.resize(roster.party.size())
	for slot in roster.party.size():
		var current_echo := ECHO_SCENE.instantiate() as EchoActor
		if current_echo == null:
			continue
		current_echo.name = "Echo%d" % (slot + 1)
		current_echo.slot_index = slot
		current_echo.position = player.position + EchoActor.FOLLOW_ANCHOR_OFFSETS[slot]
		current_echo.active_hero_label = "Hero %d" % run_number
		add_child(current_echo)
		if not current_echo.configure(roster.party[slot], player):
			current_echo.free()
			continue
		echoes[slot] = current_echo
		current_echo.defeated.connect(_on_echo_defeated.bind(slot))
		current_echo.progression_changed.connect(_update_run_hud)
		var marker := FOCUS_MARKER_SCRIPT.new() as FocusTargetMarker
		marker.slot_index = slot
		marker.visible = false
		marker.z_index = 5
		add_child(marker)
		focus_markers[slot] = marker


func _clear_party() -> void:
	for current_echo in echoes:
		if is_instance_valid(current_echo):
			current_echo.free()
	for marker in focus_markers:
		if is_instance_valid(marker):
			marker.free()
	echoes.clear()
	focus_markers.clear()


func _on_echo_defeated(slot_index: int = 0) -> void:
	_defeated_echo_slots[slot_index] = true
	if slot_index < 0 or slot_index >= echoes.size():
		return
	var defeated_echo := echoes[slot_index]
	echoes[slot_index] = null
	if is_instance_valid(defeated_echo):
		defeated_echo.queue_free()
	if slot_index < focus_markers.size() and is_instance_valid(focus_markers[slot_index]):
		focus_markers[slot_index].target = null
	if party_commander.address == slot_index:
		party_commander.address = PartyCommander.ADDRESS_ALL
	party_commander.on_echoes_changed(roster.party.size())
	_update_run_hud()
	if choice_modal.visible:
		# A defeated echo keeps only the levels it already chose; its pending ones are dropped.
		_show_next_choice_if_needed()


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
	for current_echo in echoes:
		if is_instance_valid(current_echo) and not current_echo.is_defeated:
			current_echo.grant_shared_experience(experience_reward)
	_update_progression_hud()
	_update_run_hud()
	_show_next_choice_if_needed()


## Pending choices in the order they are asked: the hero first, then each living
## echo in slot order. Each entry is {"kind", "slot", "level"} for that subject's
## next unchosen level.
func _pending_choice_subjects() -> Array[Dictionary]:
	var subjects: Array[Dictionary] = []
	var hero_levels: Array[int] = progression.get_pending_choice_levels()
	if not hero_levels.is_empty():
		subjects.append({"kind": &"hero", "slot": -1, "level": hero_levels[0]})
	for slot in echoes.size():
		var current_echo := echoes[slot]
		if not is_instance_valid(current_echo) or current_echo.is_defeated:
			continue
		var echo_levels := current_echo.get_pending_extension_levels()
		if not echo_levels.is_empty():
			subjects.append({"kind": &"echo", "slot": slot, "level": echo_levels[0]})
	return subjects


func _show_next_choice_if_needed() -> void:
	var subjects := _pending_choice_subjects()
	if subjects.is_empty():
		_choice_subject = {}
		choice_modal.hide()
		get_tree().paused = false
		return
	_choice_subject = subjects[0]
	var choice_level: int = _choice_subject["level"]
	var is_echo_choice: bool = _choice_subject["kind"] == &"echo"
	choice_prompt.text = CHOICE_PROMPT_ECHO if is_echo_choice else CHOICE_PROMPT_HERO
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
		if is_echo_choice:
			choice_title.text = "%s · %s" % [_echo_choice_subject_text(int(_choice_subject["slot"])), choice_title.text]
		choice_one_button.text = "[1] MIGHT\n+5 attack damage"
		choice_two_button.text = "[2] VITALITY\n+20 max health and current health"
	choice_modal.show()
	get_tree().paused = true


## "ECHO 1 · Hero 2 (Mender)": the echo's slot, record name, and recorded job.
func _echo_choice_subject_text(slot: int) -> String:
	var current_echo := echoes[slot]
	return "ECHO %d · %s (%s)" % [
		slot + 1,
		current_echo.hero_record.display_name,
		_job_display_name(current_echo.job_id),
	]


func _on_choice_one_pressed() -> void:
	_apply_pending_choice(0)


func _on_choice_two_pressed() -> void:
	_apply_pending_choice(1)


func _on_choice_three_pressed() -> void:
	_apply_pending_choice(2)


func _apply_pending_choice(option_index: int) -> void:
	var subjects := _pending_choice_subjects()
	if subjects.is_empty() or option_index < 0:
		return
	var subject := subjects[0]
	var choice_level: int = subject["level"]
	var applied := false
	if subject["kind"] == &"echo":
		if option_index >= HeroProgression.ATTRIBUTE_IDS.size():
			return
		applied = _apply_echo_extension(
			int(subject["slot"]),
			choice_level,
			HeroProgression.ATTRIBUTE_IDS[option_index]
		)
	elif choice_level == HeroProgression.ADVANCEMENT_LEVEL:
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
	if subject["kind"] == &"hero":
		player.apply_progression_stats(progression.get_max_health(), progression.get_attack_damage())
	_update_progression_hud()
	_update_run_hud()
	_update_ability_hud()
	_show_next_choice_if_needed()


## Applies one extension choice and commits it to the roster at once (in memory):
## the extended record replaces the old one, which is left untouched.
func _apply_echo_extension(slot: int, choice_level: int, attribute_id: StringName) -> bool:
	if slot < 0 or slot >= echoes.size() or not is_instance_valid(echoes[slot]):
		return false
	var current_echo := echoes[slot]
	if not current_echo.apply_extension_choice(choice_level, attribute_id):
		return false
	var extended := current_echo.extension_record()
	if extended != null and roster.replace_record(extended.runtime_id, extended):
		current_echo.hero_record = extended
	return true


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
	_update_echo_slot(0, echo_value, echo_command_value, echo_intent_value, echo_cooldowns_value)
	_update_echo_slot(1, echo_2_value, echo_2_command_value, echo_2_intent_value, echo_2_cooldowns_value)


func _update_echo_slot(
	slot: int,
	value_label: Label,
	command_label: Label,
	intent_label: Label,
	cooldowns_label: Label
) -> void:
	var unlocked := slot < party_slots
	value_label.visible = unlocked
	command_label.visible = unlocked
	intent_label.visible = unlocked
	cooldowns_label.visible = unlocked
	if not unlocked:
		return
	var prefix := "▶ " if party_commander.address == slot else ""
	command_label.text = "Command: —"
	intent_label.text = "Intent: —"
	cooldowns_label.text = "Cooldowns: —"
	if slot >= roster.party.size():
		value_label.text = "%sEcho %d: empty slot" % [prefix, slot + 1]
		return
	if _defeated_echo_slots.has(slot):
		value_label.text = "Echo %d: Defeated" % (slot + 1)
		return
	if slot >= echoes.size() or not is_instance_valid(echoes[slot]):
		value_label.text = "%sEcho %d: Unavailable" % [prefix, slot + 1]
		return
	var current_echo := echoes[slot]
	value_label.text = "%sEcho %d: %s · Level %d · %d/%d HP" % [
		prefix,
		slot + 1,
		_job_display_name(current_echo.job_id),
		current_echo.progression.level,
		current_echo.health,
		current_echo.max_health,
	]
	command_label.text = "Command: %s" % String(current_echo.get_command_status()).capitalize()
	intent_label.text = "Intent: %s" % current_echo.get_intent_summary()
	cooldowns_label.text = "Cooldowns: %s" % current_echo.get_cooldown_summary()


func _party_job_ids() -> Array[StringName]:
	# Runtime IDs identify the records; extension only appends attributes, so a
	# record replaced under the same ID keeps its job.
	var cache_key := "party:"
	for record: HeroRecord in roster.party:
		cache_key += record.runtime_id + "|"
	if cache_key != _party_cache_key:
		_party_cache_key = cache_key
		_party_cache_echo_jobs = roster.party_job_ids()
	var jobs := _party_cache_echo_jobs.duplicate()
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
	# During resolution the next hero is still unchosen; the fallen job must
	# not cover the next Trial's needs on the panel behind the roster screen.
	var jobs: Array[StringName] = roster.party_job_ids() if resolution_screen.visible else _party_job_ids()
	var coverage := PartyNeeds.evaluate(jobs, needs)
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
			return "Trial begins in %.1f s" % encounter_director.state_time_left
		EncounterDirector.STATE_ACTIVE:
			return "Trial in progress · %d s" % int(encounter_director.elapsed)
		EncounterDirector.STATE_CLEARED:
			return "Trial cleared in %d s" % int(encounter_director.elapsed)
	if not encounter_director.armed:
		return "Trial inactive"
	return "Reach Lv %d to face the Trial" % EncounterCatalog.get_trigger_level(
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
	if StringName(report.get("outcome", "")) != EncounterDirector.OUTCOME_CLEARED or _clear_rewarded_this_run:
		return
	var encounter_id := StringName(report.get("encounter_id", encounter_director.encounter_id))
	if not EncounterCatalog.has_encounter(encounter_id):
		return
	_clear_rewarded_this_run = true
	var clear_key := String(encounter_id)
	trial_clears[clear_key] = int(trial_clears.get(clear_key, 0)) + 1
	var earned := RosterCapacity.newly_earned(unlocks, _total_trial_clears())
	for unlock_id: StringName in earned:
		unlocks.append(unlock_id)
	party_slots = RosterCapacity.party_slots(unlocks)
	roster.set_capacity(party_slots, RosterCapacity.memorial_slots(unlocks))
	run_anchors = mini(run_anchors + 1, 1)
	var toast_parts: Array[String] = []
	for unlock_id: StringName in earned:
		toast_parts.append("Unlocked: %s" % _unlock_label(unlock_id))
	toast_parts.append("Echo Anchor found")
	_show_run_notice(" · ".join(toast_parts))
	_update_run_hud()
	_save_progress(false)


func _unlock_label(unlock_id: StringName) -> String:
	return "Party slot 2" if unlock_id == &"party_slot_2" else "Memorial slot 2"


func debug_clear_encounter() -> bool:
	if encounter_director.state == EncounterDirector.STATE_CLEARED:
		return false
	encounter_director._clear()
	return encounter_director.state == EncounterDirector.STATE_CLEARED


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
	var echo_entries: Array = report.get("echoes", [])
	if not echo_entries.is_empty():
		for echo_entry: Dictionary in echo_entries:
			lines.append("Echo %d %s: %s" % [
				int(echo_entry["slot"]),
				JobCatalog.get_display_name(StringName(echo_entry["job_id"])),
				"survived" if bool(echo_entry["survived"]) else "defeated",
			])
	elif not had_echo:
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
	encounter_id: StringName,
	echo_jobs: Array[StringName] = [],
	echo_levels: Array[int] = [],
	echo_start_levels: Array[int] = []
) -> bool:
	if not encounter_id.is_empty() and not EncounterCatalog.has_encounter(encounter_id):
		return false
	var jobs: Array[StringName] = echo_jobs.duplicate()
	if jobs.is_empty() and not echo_job.is_empty():
		jobs.append(echo_job)
	if (
		jobs.size() > party_slots
		or jobs.size() > EchoActor.FOLLOW_ANCHOR_OFFSETS.size()
		or (not echo_levels.is_empty() and echo_levels.size() != jobs.size())
		or (not echo_start_levels.is_empty() and echo_start_levels.size() != jobs.size())
	):
		return false
	var player_progression := _build_scenario_progression(player_job, level)
	if player_progression == null:
		return false
	var echo_progressions: Array[HeroProgression] = []
	for index in jobs.size():
		var echo_level := echo_levels[index] if not echo_levels.is_empty() else level
		var echo_progression := _build_scenario_progression(jobs[index], echo_level)
		if echo_progression == null:
			return false
		echo_progressions.append(echo_progression)

	_choice_subject = {}
	choice_modal.hide()
	get_tree().paused = false
	encounter_director.reset_for_new_run()
	trial_report.hide()
	_clear_party()
	progression = player_progression
	run_number = document.next_hero_number
	run_anchors = 0
	document.pending = false
	document.pending_anchors = 0
	_clear_rewarded_this_run = false
	_defeat_transition_pending = false
	_defeated_echo_slots.clear()
	_ability_feedback_time_left = 0.0
	party_commander.address = PartyCommander.ADDRESS_ALL
	party_commander.last_command = {}
	_party_cache_key = ""
	roster = Roster.new(party_slots, RosterCapacity.BASE_MEMORIAL_SLOTS)
	player.reset_for_new_run(Vector2.ZERO)
	player.apply_progression(progression, true)
	for index in echo_progressions.size():
		roster.party.append(HeroRecord.capture(
			"scenario-echo-%d" % (index + 1),
			"Hero %d" % (index + 1),
			echo_progressions[index]
		))
	_spawn_party()
	for index in echoes.size():
		if not is_instance_valid(echoes[index]):
			continue
		# Echoes start replayed to their record unless the scenario starts them lower,
		# so a record can sit above the live level and leave room to extend.
		var start_experience := echo_progressions[index].experience
		if not echo_start_levels.is_empty():
			start_experience = maxi(echo_start_levels[index] - 1, 0) * HeroProgression.XP_PER_LEVEL
		echoes[index].grant_shared_experience(start_experience)
	_on_player_health_changed(player.health, player.max_health)
	_on_player_weapon_changed(player.get_selected_weapon_id())
	_update_progression_hud()
	_update_run_hud()
	_update_ability_hud()
	# Scenarios are isolated: an un-armed director keeps level-5 scenarios from
	# starting the court on their own.
	if encounter_id.is_empty():
		_apply_trial_rotation()
		encounter_director.disarm()
	elif not encounter_director.start_encounter(_party_job_ids(), encounter_id):
		return false
	_update_trial_hud()
	return true


func apply_resolution_scenario(
	fallen_job: StringName,
	fallen_level: int,
	party_jobs: Array[StringName],
	party_levels: Array[int],
	memorial_jobs: Array[StringName],
	memorial_slot_count: int,
	anchor_count: int,
	roster_level: int
) -> bool:
	if (
		party_jobs.size() > party_slots
		or party_jobs.size() > EchoActor.FOLLOW_ANCHOR_OFFSETS.size()
		or memorial_jobs.size() > memorial_slot_count
		or (not party_levels.is_empty() and party_levels.size() != party_jobs.size())
		or memorial_slot_count < 0
		or anchor_count < 0
	):
		return false
	var fallen_progression := _build_scenario_progression(fallen_job, fallen_level)
	if fallen_progression == null:
		return false
	var scenario_roster := Roster.new(party_slots, memorial_slot_count)
	for index in party_jobs.size():
		var party_level := party_levels[index] if not party_levels.is_empty() else roster_level
		var party_progression := _build_scenario_progression(party_jobs[index], party_level)
		var party_record := HeroRecord.capture(
			"hero-%d" % (index + 1),
			"Hero %d" % (index + 1),
			party_progression
		) if party_progression != null else null
		if party_record == null:
			return false
		scenario_roster.party.append(party_record)
	for index in memorial_jobs.size():
		var memorial_progression := _build_scenario_progression(memorial_jobs[index], roster_level)
		var memorial_record := HeroRecord.capture(
			"hero-%d" % (party_jobs.size() + index + 1),
			"Hero %d" % (party_jobs.size() + index + 1),
			memorial_progression
		) if memorial_progression != null else null
		if memorial_record == null:
			return false
		scenario_roster.memorial.append(memorial_record)

	choice_modal.hide()
	resolution_screen.hide()
	encounter_director.reset_for_new_run()
	trial_report.hide()
	_clear_party()
	roster = scenario_roster
	progression = fallen_progression
	# Stored heroes are Hero 1..N, so the fallen hero is the next number.
	run_number = maxi(document.next_hero_number, party_jobs.size() + memorial_jobs.size() + 1)
	run_anchors = anchor_count
	_clear_rewarded_this_run = false
	_sync_unlocks_to_capacity(memorial_slot_count)
	_defeat_transition_pending = true
	_party_cache_key = ""
	party_commander.address = PartyCommander.ADDRESS_ALL
	party_commander.last_command = {}
	_start_next_run()
	return true


func _sync_unlocks_to_capacity(memorial_slot_count: int) -> void:
	unlocks.clear()
	if party_slots > RosterCapacity.BASE_PARTY_SLOTS:
		unlocks.append(&"party_slot_2")
	if memorial_slot_count > RosterCapacity.BASE_MEMORIAL_SLOTS:
		unlocks.append(&"memorial_slot_2")
	trial_clears = {}


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


## Plain-typed view of the choice queue: {"subject": "hero"|"echo", "slot": int
## (0 for the hero, 1-based for echoes), "level": int, "pending": int}.
func _pending_choice_subject_states() -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	for subject in _pending_choice_subjects():
		var is_echo: bool = subject["kind"] == &"echo"
		var pending_count := (
			echoes[int(subject["slot"])].get_pending_extension_levels().size()
			if is_echo
			else progression.get_pending_choice_levels().size()
		)
		states.append({
			"subject": "echo" if is_echo else "hero",
			"slot": int(subject["slot"]) + 1 if is_echo else 0,
			"level": int(subject["level"]),
			"pending": pending_count,
		})
	return states


func _mcp_state() -> Dictionary:
	var echo_states: Array[Dictionary] = []
	for slot in echoes.size():
		if not is_instance_valid(echoes[slot]):
			continue
		var echo_state := echoes[slot]._mcp_state()
		echo_state["slot"] = slot + 1
		echo_states.append(echo_state)
	var roster_party: Array[Dictionary] = []
	for record in roster.party:
		var recorded := record.replay_progression()
		roster_party.append({
			"id": record.runtime_id,
			"name": record.display_name,
			"job_id": String(recorded.get_job_id()),
			"level": recorded.level,
		})
	var roster_memorial: Array[Dictionary] = []
	for record in roster.memorial:
		var memorial_recorded := record.replay_progression()
		roster_memorial.append({
			"id": record.runtime_id,
			"name": record.display_name,
			"job_id": String(memorial_recorded.get_job_id()),
			"level": memorial_recorded.level,
		})
	var unlock_values: Array[String] = []
	for unlock_id: StringName in unlocks:
		unlock_values.append(String(unlock_id))
	var clear_values: Dictionary = {}
	for encounter_id: Variant in trial_clears:
		clear_values[String(encounter_id)] = int(trial_clears[encounter_id])
	return {
		"run_number": run_number,
		"save_path": save_path,
		"save_status": save_status,
		"save_read_only": roster_store.read_only,
		"unlocks": unlock_values,
		"trial_clears": clear_values,
		"next_hero_number": document.next_hero_number,
		"pending_saved": document.pending,
		"level": progression.level,
		"experience": progression.experience,
		"job_id": String(progression.get_job_id()),
		"pending_choice_levels": progression.get_pending_choice_levels(),
		"pending_choice_subjects": _pending_choice_subject_states(),
		"choice_title_text": choice_title.text,
		"choice_modal_visible": choice_modal.visible,
		"choice_three_visible": choice_three_button.visible,
		"ability_hud_visible": ability_value.visible,
		"ability_hud_text": ability_value.text,
		"weapon_cooldown_hud_text": weapon_cooldown_value.text,
		"dodge_hud_text": dodge_value.text,
		"echo_intent_hud_text": echo_intent_value.text,
		"echo_cooldowns_hud_text": echo_cooldowns_value.text,
		"has_echo": is_instance_valid(echo),
		"echo_count": echo_states.size(),
		"echoes": echo_states,
		"address": party_commander.address,
		"address_label": party_commander.address_label(echoes),
		"last_command": party_commander.last_command.duplicate(true),
		"party_slots": party_slots,
		"roster_party": roster_party,
		"roster_memorial": roster_memorial,
		"run_anchors": run_anchors,
		"resolution": resolution_screen._mcp_state(),
		"run_notice_visible": run_notice.visible,
		"run_notice_text": run_notice_text.text,
		"paused": get_tree().paused,
		"director_state": String(encounter_director.state),
		"director": encounter_director._mcp_state(),
		"trial_panel_text": _trial_panel_text(),
		"trial_banner_visible": trial_banner.visible,
		"trial_banner_text": _trial_banner_text(),
		"trial_report_visible": trial_report.visible,
		"trial_report_text": "%s\n%s" % [trial_report_title.text, trial_report_body.text],
	}
