extends Node


const MAIN_SCENE := preload("res://src/main/main.tscn")
## Scenario-only action so MCP playtesters can save the rendered frame to disk
## without screenshot transport or arbitrary code execution.
const CAPTURE_ACTION := &"playtest_capture"
const CAPTURE_DIR := "user://playtest_captures"

@export var player_job: StringName
@export var echo_job: StringName
@export var echo_jobs: Array[StringName] = []
@export var echo_levels: Array[int] = []
## Live level each echo starts the scenario at (empty = replayed to its record).
## Set below `echo_levels` so the echo is still inside its record when XP arrives.
@export var echo_start_levels: Array[int] = []
@export var party_slots := 1
@export var level := 1
@export var encounter_id: StringName
## Starting health as a fraction of max health, so playtests can check
## healing without steering actors into enemies first.
@export_range(0.05, 1.0) var player_health_fraction := 1.0
@export_range(0.05, 1.0) var echo_health_fraction := 1.0
## Arena enemy population; -1 keeps the spawner default. Use 0 for isolated
## checks so incidental kills cannot open the level-up modal mid-test.
@export var enemy_population := -1
@export var debug_enemies: Array[StringName] = []
## Experience granted through `Main._on_enemy_defeated` after setup (hero and
## every living echo), so level-up and extension modals open immediately.
@export var bonus_experience := 0
## Playtest hook for a mouse-less tester: after debug enemies spawn, address
## this slot (-1 = All, 0/1 = echo slot) and focus the first debug enemy through
## the same PartyCommander path as right-click. -2 does nothing.
@export var debug_focus_address := -2
## Opens the roster resolution screen instead of a run: `fallen_job` at
## `fallen_level` is the hero who just died; `echo_jobs`/`echo_levels`/
## `party_slots` build the party, `memorial_jobs` the memorial (all at `level`).
## An empty `fallen_job` is a Novice (keep `fallen_level` at 2 or below).
@export var start_at_resolution := false
@export var fallen_job: StringName
@export var fallen_level := 4
@export var memorial_jobs: Array[StringName] = []
@export var memorial_slots := 1
@export var anchors := 0
## Empty uses memory-only; a named slot is isolated under user://playtest_saves.
@export var save_slot := ""
@export var reset_save := true
## Runs the director's real clear path after scenario setup.
@export var court_instant_clear := false


var _capture_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_capture_action()
	if not save_slot.is_empty() and save_slot != save_slot.validate_filename():
		push_error("Invalid scenario save slot")
		return
	var main := MAIN_SCENE.instantiate()
	main.party_slots = party_slots
	main.save_path = "" if save_slot.is_empty() else "user://playtest_saves/%s.json" % save_slot
	if reset_save and not save_slot.is_empty():
		_reset_save(main.save_path)
	add_child(main)
	if start_at_resolution:
		if not main.apply_resolution_scenario(
			fallen_job, fallen_level, echo_jobs, echo_levels, memorial_jobs, memorial_slots, anchors, level
		):
			push_error("Resolution scenario setup failed")
			return
	elif _has_scenario_overrides() and not main.apply_scenario(
		player_job, echo_job, level, encounter_id, echo_jobs, echo_levels, echo_start_levels
	):
		push_error("Scenario setup failed")
		return
	_set_health_fraction(main.get_node("Player") as HeroActor, player_health_fraction)
	for echo in main.echoes:
		_set_health_fraction(echo as HeroActor, echo_health_fraction)
	var spawner := main.get_node("Enemies") as EnemySpawner
	if enemy_population >= 0:
		_set_enemy_population(spawner, enemy_population)
	var first_enemy := _spawn_debug_enemies(spawner)
	if debug_focus_address != -2 and first_enemy != null:
		main.party_commander.address = debug_focus_address
		main.party_commander.focus(main.echoes, first_enemy)
	if bonus_experience > 0 and not start_at_resolution:
		main._on_enemy_defeated(bonus_experience)
	if court_instant_clear and not start_at_resolution:
		main.debug_clear_encounter()


func _has_scenario_overrides() -> bool:
	return (
		not player_job.is_empty()
		or not echo_job.is_empty()
		or not echo_jobs.is_empty()
		or not echo_levels.is_empty()
		or not echo_start_levels.is_empty()
		or party_slots != 1
		or level != 1
		or not encounter_id.is_empty()
		or not is_equal_approx(player_health_fraction, 1.0)
		or not is_equal_approx(echo_health_fraction, 1.0)
		or enemy_population >= 0
		or not debug_enemies.is_empty()
		or bonus_experience != 0
		or debug_focus_address != -2
	)


func _reset_save(path: String) -> void:
	for suffix: String in ["", ".tmp", ".corrupt"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)


func _set_health_fraction(actor: HeroActor, fraction: float) -> void:
	if actor == null or is_equal_approx(fraction, 1.0):
		return
	actor.health = actor.max_health * fraction
	actor.health_changed.emit(actor.health, actor.max_health)


func _set_enemy_population(spawner: EnemySpawner, population: int) -> void:
	spawner.set_population(population)


func _spawn_debug_enemies(spawner: EnemySpawner) -> Node2D:
	var first_enemy: Node2D
	for index in debug_enemies.size():
		var enemy := EnemyCatalog.instantiate(debug_enemies[index])
		if enemy == null:
			push_error("Unknown debug enemy ID: %s" % debug_enemies[index])
			continue
		enemy.name = "Debug%s%d" % [String(debug_enemies[index]).capitalize(), index + 1]
		enemy.stable_spawn_order = 10000 + index
		var angle := TAU * float(index) / float(debug_enemies.size())
		enemy.position = Vector2.RIGHT.rotated(angle) * 320.0
		enemy.defeated.connect(spawner._on_enemy_defeated)
		spawner.add_child(enemy)
		if first_enemy == null:
			first_enemy = enemy
	return first_enemy


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(CAPTURE_ACTION):
		capture_frame()


func capture_frame() -> String:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	_capture_count += 1
	var path := "%s/%s_%02d.png" % [CAPTURE_DIR, name.to_snake_case(), _capture_count]
	var absolute_path := ProjectSettings.globalize_path(path)
	if get_viewport().get_texture().get_image().save_png(path) != OK:
		push_error("Playtest capture failed: %s" % absolute_path)
		return ""
	print("Playtest capture saved: %s" % absolute_path)
	return absolute_path


func _ensure_capture_action() -> void:
	if InputMap.has_action(CAPTURE_ACTION):
		return
	InputMap.add_action(CAPTURE_ACTION)
	var key_event := InputEventKey.new()
	key_event.physical_keycode = KEY_F12
	InputMap.action_add_event(CAPTURE_ACTION, key_event)
