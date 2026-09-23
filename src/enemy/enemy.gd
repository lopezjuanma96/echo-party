extends CharacterBody2D


@export var move_speed := 90.0
@export var contact_damage := 10.0
@export var contact_interval := 0.5
@export var min_direction_time := 0.7
@export var max_direction_time := 2.0
@export var max_health := 50.0

@onready var contact_area: Area2D = $ContactArea
@onready var body: Polygon2D = $Body

var move_direction := Vector2.ZERO
var direction_time_left := 0.0
var contact_time_left := 0.0
var contact_target: Node = null
var random := RandomNumberGenerator.new()
var health := max_health


func _ready() -> void:
	health = max_health
	random.randomize()
	contact_area.body_entered.connect(_on_contact_area_body_entered)
	contact_area.body_exited.connect(_on_contact_area_body_exited)
	_choose_direction()


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
	if not is_instance_valid(contact_target):
		contact_target = null
		return

	contact_time_left -= delta
	if contact_time_left <= 0.0:
		contact_target.take_damage(contact_damage)
		contact_time_left = contact_interval


func _on_contact_area_body_entered(body: Node2D) -> void:
	if body.has_method(&"take_damage"):
		contact_target = body
		contact_time_left = 0.0


func _on_contact_area_body_exited(body: Node2D) -> void:
	if body == contact_target:
		contact_target = null


func take_damage(amount: float) -> void:
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		queue_free()
		return

	body.color = Color("78e6a3")
	var hit_tween := create_tween()
	hit_tween.tween_property(body, "color", Color("db1a21"), 0.12)
