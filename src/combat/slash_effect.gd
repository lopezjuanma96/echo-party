extends Node2D


const LIFETIME := 0.14
var time_left := LIFETIME
var arc_radius := 72.0
var arc_half_angle := deg_to_rad(10.0)


func _ready() -> void:
	z_index = 1
	queue_redraw()


func configure(attack_range: float, arc_degrees: float) -> void:
	arc_radius = attack_range
	arc_half_angle = deg_to_rad(arc_degrees / 2.0)
	queue_redraw()


func _process(delta: float) -> void:
	time_left -= delta
	modulate.a = maxf(time_left / LIFETIME, 0.0)
	if time_left <= 0.0:
		queue_free()


func _draw() -> void:
	draw_arc(
		Vector2.ZERO,
		arc_radius,
		-arc_half_angle,
		arc_half_angle,
		12,
		Color("78e6a3"),
		8.0,
		true
	)
