class_name EnemyShot
extends Area2D
## Slinger dart. Unlike Bolt it only hurts friendlies, so enemy fire cannot
## touch other enemies.


signal hit_friendly(target: Node, applied: float)

@export var move_speed := 420.0
@export var max_distance := 640.0
@export var damage := 14.0

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


func launch(
	spawn_position: Vector2,
	direction: Vector2,
	attack_damage: float,
	travel_speed: float,
	travel_distance: float
) -> void:
	global_position = spawn_position
	travel_direction = direction.normalized()
	rotation = travel_direction.angle()
	damage = attack_damage
	move_speed = travel_speed
	max_distance = travel_distance


func _on_body_entered(other: Node2D) -> void:
	if is_queued_for_deletion():
		return
	if other.has_method(&"take_damage"):
		if bool(other.get("is_defeated")):
			return
		var health_before := float(other.get("health"))
		other.take_damage(damage)
		hit_friendly.emit(other, health_before - float(other.get("health")))
	queue_free()
