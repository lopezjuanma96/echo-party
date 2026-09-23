extends Node2D


const LIFETIME := 0.14
const ARC_RADIUS := 72.0
const ARC_HALF_ANGLE := deg_to_rad(10.0)

var time_left := LIFETIME


func _ready() -> void:
	z_index = 1


func _process(delta: float) -> void:
	time_left -= delta
	modulate.a = maxf(time_left / LIFETIME, 0.0)
	if time_left <= 0.0:
		queue_free()


func _draw() -> void:
	draw_arc(
		Vector2.ZERO,
		ARC_RADIUS,
		-ARC_HALF_ANGLE,
		ARC_HALF_ANGLE,
		12,
		Color("78e6a3"),
		8.0,
		true
	)
