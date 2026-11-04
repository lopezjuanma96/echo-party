class_name FocusTargetMarker
extends Node2D


const MARKER_COLOR := Color("9b5de5")
const MARKER_RADIUS := 34.0
const DIGIT_FONT_SIZE := 18
const DIGIT_SLOT_SPACING := 14.0
const DIGIT_OUTLINE_COLOR := Color(0.08, 0.06, 0.12, 1.0)

var target: Node2D
var slot_index := 0


func _process(_delta: float) -> void:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		visible = false
		return
	visible = true
	global_position = target.global_position


func _draw() -> void:
	draw_arc(Vector2.ZERO, MARKER_RADIUS, 0.0, TAU, 48, MARKER_COLOR, 2.0, true)
	# The digit sits outside the ring's upper right with a dark outline, so it
	# stays legible over any enemy body instead of being drawn on top of it.
	# Each slot gets its own digit column, so two echoes focusing one enemy read "1 2".
	var digit_position := Vector2(MARKER_RADIUS * 0.72 + DIGIT_SLOT_SPACING * slot_index, -MARKER_RADIUS * 0.72)
	draw_string_outline(
		ThemeDB.fallback_font,
		digit_position,
		str(slot_index + 1),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		DIGIT_FONT_SIZE,
		4,
		DIGIT_OUTLINE_COLOR
	)
	draw_string(
		ThemeDB.fallback_font,
		digit_position,
		str(slot_index + 1),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		DIGIT_FONT_SIZE,
		MARKER_COLOR
	)
	for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
		draw_line(
			direction * (MARKER_RADIUS - 6.0),
			direction * (MARKER_RADIUS + 6.0),
			MARKER_COLOR,
			2.0,
			true
		)
