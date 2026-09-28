extends Area2D


@export var move_speed := 560.0
@export var max_distance := 650.0
@export var damage := 25.0

var travel_direction := Vector2.RIGHT
var distance_traveled := 0.0

@onready var body: Polygon2D = $Body


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	var movement := travel_direction * move_speed * delta
	position += movement
	distance_traveled += movement.length()
	if distance_traveled >= max_distance:
		queue_free()


func launch(
	spawn_position: Vector2,
	direction: Vector2,
	attack_damage: float,
	travel_speed: float,
	travel_distance: float,
	color: Color
) -> void:
	global_position = spawn_position
	travel_direction = direction.normalized()
	rotation = travel_direction.angle()
	damage = attack_damage
	move_speed = travel_speed
	max_distance = travel_distance
	body.color = color


func _on_body_entered(other: Node2D) -> void:
	if is_queued_for_deletion():
		return
	if other.has_method(&"take_damage"):
		other.take_damage(damage)
	queue_free()
