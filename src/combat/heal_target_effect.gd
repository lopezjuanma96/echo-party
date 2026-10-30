extends Node2D


const LIFETIME := 0.7
const FLASH_RADIUS := 26.0
const RING_GROWTH := 12.0
const TEXT_OFFSET := Vector2(26.0, -10.0)
const TEXT_RISE := 36.0
const FONT_SIZE := 18
const OUTLINE_COLOR := Color(0.03, 0.08, 0.05, 0.9)

var target: Node2D
var amount_text := ""
var flash_color := Color("5bd98a")
var time_left := LIFETIME


func _ready() -> void:
	z_index = 3
	queue_redraw()


func configure(new_target: Node2D, amount: float, color: Color) -> void:
	target = new_target
	amount_text = "+%d" % roundi(amount)
	flash_color = color
	if is_instance_valid(target) and target.is_inside_tree():
		global_position = target.global_position
	queue_redraw()


func _process(delta: float) -> void:
	time_left -= delta
	if is_instance_valid(target) and target.is_inside_tree():
		global_position = target.global_position
	if time_left <= 0.0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var progress := 1.0 - maxf(time_left / LIFETIME, 0.0)
	var fade := 1.0 - progress
	draw_circle(Vector2.ZERO, FLASH_RADIUS, Color(flash_color, 0.35 * fade))
	draw_arc(
		Vector2.ZERO,
		FLASH_RADIUS + RING_GROWTH * progress,
		0.0,
		TAU,
		40,
		Color(flash_color, fade),
		3.0,
		true
	)
	var font := ThemeDB.fallback_font
	var text_position := TEXT_OFFSET + Vector2(0.0, -TEXT_RISE * progress)
	var text_alpha := minf(fade * 2.0, 1.0)
	draw_string_outline(
		font, text_position, amount_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, 5,
		Color(OUTLINE_COLOR, OUTLINE_COLOR.a * text_alpha)
	)
	draw_string(
		font, text_position, amount_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE,
		Color(flash_color, text_alpha)
	)
