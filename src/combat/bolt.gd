extends Area2D


@export var move_speed := 560.0
@export var max_distance := 650.0
@export var damage := 25.0

var travel_direction := Vector2.RIGHT
var distance_traveled := 0.0
var interrupts := false
var splash_radius := 0.0
var splash_fraction := 0.6

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
	color: Color,
	attack_interrupts: bool = false,
	area_radius: float = 0.0,
	area_fraction: float = 0.6
) -> void:
	global_position = spawn_position
	travel_direction = direction.normalized()
	rotation = travel_direction.angle()
	damage = attack_damage
	move_speed = travel_speed
	max_distance = travel_distance
	body.color = color
	interrupts = attack_interrupts
	splash_radius = area_radius
	splash_fraction = area_fraction


func _on_body_entered(other: Node2D) -> void:
	if is_queued_for_deletion():
		return
	if other.has_method(&"take_damage"):
		other.take_damage(damage, interrupts)
		if other.is_in_group(&"enemies"):
			_splash_damage(other)
	queue_free()


func _splash_damage(hit_enemy: Node2D) -> void:
	if splash_radius <= 0.0:
		return
	for enemy_node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := enemy_node as Node2D
		if (
			enemy == null
			or enemy == hit_enemy
			or enemy.is_queued_for_deletion()
			or hit_enemy.global_position.distance_to(enemy.global_position) > splash_radius
		):
			continue
		enemy.take_damage(damage * splash_fraction, interrupts)
