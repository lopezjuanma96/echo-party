class_name Telegraph
extends Node2D
## Ground telegraph. Keep it as the first child of its enemy at z 0 so it draws
## above the arena floor and below the enemy body.


## White means "interruptible" elsewhere, and white vanishes on the light floor,
## so the last-moment flash is a dark, saturated crimson.
const FINAL_OUTLINE_COLOR := Color("40040c")
const FINAL_OUTLINE_WIDTH := 4.0

var radius := 88.0
var fill_color := Color("db1a21")
var progress := 0.0
var outline_active := false
var active := false


func _process(_delta: float) -> void:
	if active:
		queue_redraw()


func show_area(area_radius: float, color: Color) -> void:
	radius = area_radius
	fill_color = color
	progress = 0.0
	outline_active = false
	active = true
	visible = true
	queue_redraw()


func set_progress(value: float, show_outline: bool = false) -> void:
	progress = clampf(value, 0.0, 1.0)
	outline_active = show_outline
	active = true
	queue_redraw()


func clear() -> void:
	active = false
	visible = false
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	var alpha := lerpf(0.15, 0.55, progress)
	draw_circle(Vector2.ZERO, radius, Color(fill_color, alpha))
	if outline_active:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, FINAL_OUTLINE_COLOR, FINAL_OUTLINE_WIDTH, true)
