class_name EnemySpawner
extends Node2D


signal enemy_defeated(experience_reward: int)

const DEFAULT_ENEMY_SCENE := preload("res://src/enemy/enemy.tscn")
const SKITTER_PACK_SIZE := 4
const SKITTER_CLUSTER_RADIUS := 40.0
const TYPE_TABLE := [
	{"max_level": 2, "weights": [[&"drifter", 100.0]]},
	{
		"max_level": 3,
		"weights": [[&"drifter", 55.0], [&"skitter", 25.0], [&"slinger", 20.0]],
	},
	{
		"max_level": 9223372036854775807,
		"weights": [
			[&"drifter", 40.0],
			[&"skitter", 20.0],
			[&"slinger", 15.0],
			[&"brute", 15.0],
			[&"hexcaller", 10.0],
		],
	},
]

@export var enemy_scene: PackedScene = DEFAULT_ENEMY_SCENE
@export var target_population := 7
@export var respawn_delay := 1.25
@export var simulation_seed := 424242
@export var spawn_bounds := Rect2(-820.0, -470.0, 1640.0, 940.0)
@export var minimum_player_distance := 260.0
@export var preferred_enemy_distance := 140.0
@export var player_path: NodePath = NodePath("../Player")

var threat_level := 1
var random := RandomNumberGenerator.new()
var type_random := RandomNumberGenerator.new()
var _pending_respawns: Array[float] = []
var _spawn_sequence := 0

@onready var player: Node2D = get_node_or_null(player_path)


func _ready() -> void:
	random.seed = simulation_seed
	type_random.seed = simulation_seed ^ 0x5eed
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
			if _get_alive_enemy_count() < target_population:
				_spawn_enemy()


func set_population(population: int) -> void:
	target_population = maxi(population, 0)
	var living_enemies: Array[Node] = []
	for child in get_children():
		if not child.is_queued_for_deletion():
			living_enemies.append(child)
	for index in range(target_population, living_enemies.size()):
		living_enemies[index].queue_free()
	var maximum_pending := maxi(target_population - _get_alive_enemy_count(), 0)
	while _pending_respawns.size() > maximum_pending:
		_pending_respawns.pop_back()


func _spawn_enemy() -> Node2D:
	var enemy_id := _choose_enemy_id()
	var pack_size := SKITTER_PACK_SIZE if enemy_id == &"skitter" else 1
	var cluster_center := choose_spawn_position()
	var first_enemy: Node2D
	for index in pack_size:
		var spawn_position := cluster_center
		if index > 0:
			var angle := type_random.randf_range(0.0, TAU)
			var distance := sqrt(type_random.randf()) * SKITTER_CLUSTER_RADIUS
			spawn_position += Vector2.RIGHT.rotated(angle) * distance
			spawn_position.x = clampf(spawn_position.x, spawn_bounds.position.x, spawn_bounds.end.x)
			spawn_position.y = clampf(spawn_position.y, spawn_bounds.position.y, spawn_bounds.end.y)
		var enemy := _spawn_enemy_of_type(enemy_id, spawn_position)
		if index == 0:
			first_enemy = enemy
	return first_enemy


func _choose_enemy_id() -> StringName:
	var weights: Array = TYPE_TABLE.back()["weights"]
	for entry: Dictionary in TYPE_TABLE:
		if threat_level <= int(entry["max_level"]):
			weights = entry["weights"]
			break
	var total_weight := 0.0
	for weighted_id: Array in weights:
		total_weight += float(weighted_id[1])
	var roll := type_random.randf_range(0.0, total_weight)
	for weighted_id: Array in weights:
		roll -= float(weighted_id[1])
		if roll <= 0.0:
			return weighted_id[0] as StringName
	return &"drifter"


func _spawn_enemy_of_type(enemy_id: StringName, spawn_position: Vector2) -> EnemyActor:
	var scene := enemy_scene if enemy_id == &"drifter" else EnemyCatalog.get_scene(enemy_id)
	if scene == null:
		return null
	var enemy := scene.instantiate() as EnemyActor
	if enemy == null:
		return null
	_spawn_sequence += 1
	enemy.name = "Enemy%d" % _spawn_sequence
	enemy.stable_spawn_order = _spawn_sequence
	enemy.position = spawn_position
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
	if _get_alive_enemy_count() - 1 + _pending_respawns.size() < target_population:
		_pending_respawns.append(respawn_delay)
	enemy_defeated.emit(experience_reward)
