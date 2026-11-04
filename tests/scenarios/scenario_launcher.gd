extends Node


const MAIN_SCENE := preload("res://src/main/main.tscn")
## Scenario-only action so MCP playtesters can save the rendered frame to disk
## without screenshot transport or arbitrary code execution.
const CAPTURE_ACTION := &"playtest_capture"
const CAPTURE_DIR := "user://playtest_captures"

@export var player_job: StringName
@export var echo_job: StringName
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


var _capture_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_capture_action()
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	if not main.apply_scenario(player_job, echo_job, level, encounter_id):
		push_error("Scenario setup failed")
		return
	_set_health_fraction(main.get_node("Player") as HeroActor, player_health_fraction)
	_set_health_fraction(main.echo as HeroActor, echo_health_fraction)
	var spawner := main.get_node("Enemies") as EnemySpawner
	if enemy_population >= 0:
		_set_enemy_population(spawner, enemy_population)
	_spawn_debug_enemies(spawner)


func _set_health_fraction(actor: HeroActor, fraction: float) -> void:
	if actor == null or is_equal_approx(fraction, 1.0):
		return
	actor.health = actor.max_health * fraction
	actor.health_changed.emit(actor.health, actor.max_health)


func _set_enemy_population(spawner: EnemySpawner, population: int) -> void:
	spawner.set_population(population)


func _spawn_debug_enemies(spawner: EnemySpawner) -> void:
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
