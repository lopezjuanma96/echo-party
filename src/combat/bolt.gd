extends Area2D


@export var move_speed := 560.0
@export var max_distance := 650.0
@export var damage := 25.0

var travel_direction := Vector2.RIGHT
var distance_traveled := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	var movement := travel_direction * move_speed * delta
	position += movement
	distance_traveled += movement.length()
	if distance_traveled >= max_distance:
		queue_free()


func launch(spawn_position: Vector2, direction: Vector2) -> void:
	global_position = spawn_position
	travel_direction = direction.normalized()
	rotation = travel_direction.angle()


func _on_body_entered(body: Node2D) -> void:
	if is_queued_for_deletion():
		return
	if body.has_method(&"take_damage"):
		body.take_damage(damage)
	queue_free()
