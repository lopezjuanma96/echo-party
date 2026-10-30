class_name FocusTargetMarker
extends Node2D


const MARKER_COLOR := Color("9b5de5")
const MARKER_RADIUS := 34.0

var target: Node2D


func _process(_delta: float) -> void:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		visible = false
		return
	visible = true
	global_position = target.global_position


func _draw() -> void:
	draw_arc(Vector2.ZERO, MARKER_RADIUS, 0.0, TAU, 48, MARKER_COLOR, 2.0, true)
	for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
		draw_line(
			direction * (MARKER_RADIUS - 6.0),
			direction * (MARKER_RADIUS + 6.0),
			MARKER_COLOR,
			2.0,
			true
		)
