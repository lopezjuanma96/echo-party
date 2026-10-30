extends CharacterBody2D


signal defeated(experience_reward: int)


@export var move_speed := 90.0
@export var contact_damage := 10.0
@export var contact_interval := 0.5
@export var min_direction_time := 0.7
@export var max_direction_time := 2.0
@export var max_health := 50.0
@export var experience_reward := 50

@onready var contact_area: Area2D = $ContactArea
@onready var body: Polygon2D = $Body

var move_direction := Vector2.ZERO
var direction_time_left := 0.0
var contact_time_left := 0.0
var contact_target: Node = null
var random := RandomNumberGenerator.new()
var simulation_seed := 1
var stable_spawn_order := 0
var health := max_health
var is_defeated := false


func _ready() -> void:
	health = max_health
	random.seed = simulation_seed
	_choose_direction()


func set_simulation_seed(value: int) -> void:
	simulation_seed = value
	random.seed = simulation_seed


func _physics_process(delta: float) -> void:
	direction_time_left -= delta
	if direction_time_left <= 0.0:
		_choose_direction()

	velocity = move_direction * move_speed
	move_and_slide()

	if get_slide_collision_count() > 0:
		move_direction = move_direction.bounce(get_slide_collision(0).get_normal()).normalized()
		direction_time_left = random.randf_range(min_direction_time, max_direction_time)

	_damage_contact(delta)


func _choose_direction() -> void:
	move_direction = Vector2.RIGHT.rotated(random.randf_range(0.0, TAU))
	direction_time_left = random.randf_range(min_direction_time, max_direction_time)


func _damage_contact(delta: float) -> void:
	var next_target := _choose_contact_target()
	if next_target == null and next_target != contact_target:
		contact_time_left = 0.0
	contact_target = next_target
	if not is_instance_valid(contact_target):
		contact_target = null
		return

	contact_time_left -= delta
	if contact_time_left <= 0.0:
		contact_target.take_damage(contact_damage)
		contact_time_left = contact_interval


func _choose_contact_target() -> Node2D:
	var best: Node2D
	var best_distance_squared := INF
	for body_node in contact_area.get_overlapping_bodies():
		var candidate := body_node as Node2D
		if candidate == null or not candidate.has_method(&"take_damage"):
			continue
		var distance_squared := global_position.distance_squared_to(candidate.global_position)
		if (
			distance_squared < best_distance_squared
			or (
				is_equal_approx(distance_squared, best_distance_squared)
				and (best == null or candidate.name.naturalnocasecmp_to(best.name) < 0)
			)
		):
			best = candidate
			best_distance_squared = distance_squared
	return best


func take_damage(amount: float) -> void:
	if is_defeated:
		return
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		is_defeated = true
		defeated.emit(experience_reward)
		queue_free()
		return

	body.color = Color("78e6a3")
	var hit_tween := create_tween()
	hit_tween.tween_property(body, "color", Color("db1a21"), 0.12)
