extends Node2D


const LIFETIME := 0.4
var time_left := LIFETIME
var radius := 240.0
var pulse_color := Color("5bd98a")


func _ready() -> void:
	z_index = 1
	queue_redraw()


func configure(effect_radius: float, color: Color) -> void:
	radius = effect_radius
	pulse_color = color
	queue_redraw()


func _process(delta: float) -> void:
	time_left -= delta
	modulate.a = maxf(time_left / LIFETIME, 0.0)
	queue_redraw()
	if time_left <= 0.0:
		queue_free()


func _draw() -> void:
	var progress := 1.0 - maxf(time_left / LIFETIME, 0.0)
	draw_arc(Vector2.ZERO, radius * progress, 0.0, TAU, 64, pulse_color, 5.0, true)
