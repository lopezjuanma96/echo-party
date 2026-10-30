class_name EnemySpawner
extends Node2D


signal enemy_defeated(experience_reward: int)

const DEFAULT_ENEMY_SCENE := preload("res://src/enemy/enemy.tscn")

@export var enemy_scene: PackedScene = DEFAULT_ENEMY_SCENE
@export var target_population := 7
@export var respawn_delay := 1.25
@export var simulation_seed := 424242
@export var spawn_bounds := Rect2(-820.0, -470.0, 1640.0, 940.0)
@export var minimum_player_distance := 260.0
@export var preferred_enemy_distance := 140.0
@export var player_path: NodePath = NodePath("../Player")

var random := RandomNumberGenerator.new()
var _pending_respawns: Array[float] = []
var _spawn_sequence := 0

@onready var player: Node2D = get_node_or_null(player_path)


func _ready() -> void:
	random.seed = simulation_seed
	while get_child_count() < target_population:
		_spawn_enemy()


func _process(delta: float) -> void:
	var alive_count := _get_alive_enemy_count()
	while alive_count + _pending_respawns.size() < target_population:
		_pending_respawns.append(respawn_delay)

	for index in range(_pending_respawns.size() - 1, -1, -1):
		_pending_respawns[index] -= delta
		if _pending_respawns[index] <= 0.0:
			_pending_respawns.remove_at(index)
			_spawn_enemy()


func _spawn_enemy() -> Node2D:
	var enemy := enemy_scene.instantiate() as Node2D
	if enemy == null:
		return null
	_spawn_sequence += 1
	enemy.name = "Enemy%d" % _spawn_sequence
	enemy.set("stable_spawn_order", _spawn_sequence)
	enemy.position = choose_spawn_position()
	if enemy.has_method(&"set_simulation_seed"):
		enemy.set_simulation_seed(random.randi())
	enemy.defeated.connect(_on_enemy_defeated)
	add_child(enemy)
	return enemy


func choose_spawn_position() -> Vector2:
	var best_position := _safest_fallback_position()
	var best_enemy_distance := -1.0
	for attempt in 24:
		var candidate := Vector2(
			random.randf_range(spawn_bounds.position.x, spawn_bounds.end.x),
			random.randf_range(spawn_bounds.position.y, spawn_bounds.end.y)
		)
		if player != null and candidate.distance_to(player.position) < minimum_player_distance:
			continue
		var enemy_distance := _distance_to_nearest_enemy(candidate)
		if enemy_distance >= preferred_enemy_distance:
			return candidate
		if enemy_distance > best_enemy_distance:
			best_position = candidate
			best_enemy_distance = enemy_distance
	return best_position


func _safest_fallback_position() -> Vector2:
	if player == null:
		return spawn_bounds.get_center()
	var corners: Array[Vector2] = [
		spawn_bounds.position,
		Vector2(spawn_bounds.end.x, spawn_bounds.position.y),
		spawn_bounds.end,
		Vector2(spawn_bounds.position.x, spawn_bounds.end.y),
	]
	var safest := corners[0]
	for corner in corners:
		if corner.distance_squared_to(player.position) > safest.distance_squared_to(player.position):
			safest = corner
	return safest


func get_pending_respawn_count() -> int:
	return _pending_respawns.size()


func _get_alive_enemy_count() -> int:
	var count := 0
	for child in get_children():
		if not child.is_queued_for_deletion():
			count += 1
	return count


func _distance_to_nearest_enemy(candidate: Vector2) -> float:
	var nearest := INF
	for child in get_children():
		if child is Node2D and not child.is_queued_for_deletion():
			nearest = minf(nearest, candidate.distance_to(child.position))
	return nearest


func _on_enemy_defeated(experience_reward: int) -> void:
	_pending_respawns.append(respawn_delay)
	enemy_defeated.emit(experience_reward)
