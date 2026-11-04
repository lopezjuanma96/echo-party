class_name EchoStatusOverlay
extends Node2D


## Glyph shape and colour per displayed intent. Shapes differ so intent does not
## depend on colour alone. `idle` draws nothing.
const INTENT_STYLES := {
	&"attack": {"glyph": &"cross", "color": Color("e5484d")},
	&"approach": {"glyph": &"chevron_toward", "color": Color("1bb6e0")},
	&"retreat": {"glyph": &"chevron_away", "color": Color("ff8a1f")},
	&"hold": {"glyph": &"bars", "color": Color("8a929e")},
	&"follow": {"glyph": &"dots", "color": Color("4d8bff")},
	&"regroup": {"glyph": &"ring_dot", "color": Color("4d8bff")},
	&"heal": {"glyph": &"plus", "color": Color("5bd98a")},
	&"interrupt": {"glyph": &"zigzag", "color": Color("ffd23f")},
}
## Intents that draw a line from the echo to its target.
const LINE_INTENTS: Array[StringName] = [&"attack", &"approach", &"retreat", &"interrupt", &"heal"]
const BAR_WIDTH := 48.0
const HEALTH_BAR_Y := 30.0
const HEALTH_BAR_HEIGHT := 6.0
const COOLDOWN_BAR_Y := 37.0
const COOLDOWN_BAR_HEIGHT := 3.0
const GLYPH_CENTER := Vector2(-35.0, 34.0)
const PIP_CENTER := Vector2(36.0, 34.0)
const PIP_RADIUS := 5.0
const BACKING_COLOR := Color(0.04, 0.06, 0.1, 0.85)
const TRACK_COLOR := Color(0.2, 0.23, 0.29, 1.0)
const COOLDOWN_COLOR := Color("f4a259")
const COOLDOWN_READY_COLOR := Color(0.72, 0.78, 0.88, 1.0)
const LINE_WIDTH := 2.0

var echo: EchoActor


func _ready() -> void:
	z_index = 2
	echo = get_parent() as EchoActor


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if echo == null:
		return
	_draw_intent_line()
	_draw_health_bar()
	_draw_cooldown_bar()
	_draw_ability_pip()
	_draw_intent_glyph()


static func health_color(fraction: float) -> Color:
	if fraction > 0.6:
		return Color("5bd98a")
	if fraction > 0.3:
		return Color("ffd23f")
	return Color("e5484d")


func _draw_bar(y: float, height: float, fraction: float, color: Color) -> void:
	var left := -BAR_WIDTH / 2.0
	draw_rect(Rect2(left - 1.0, y - 1.0, BAR_WIDTH + 2.0, height + 2.0), BACKING_COLOR)
	draw_rect(Rect2(left, y, BAR_WIDTH, height), TRACK_COLOR)
	var fill_width := roundf(BAR_WIDTH * clampf(fraction, 0.0, 1.0))
	if fill_width > 0.0:
		draw_rect(Rect2(left, y, fill_width, height), color)


func _draw_health_bar() -> void:
	var fraction := echo.health / maxf(echo.max_health, 1.0)
	_draw_bar(HEALTH_BAR_Y, HEALTH_BAR_HEIGHT, fraction, health_color(fraction))


func _draw_cooldown_bar() -> void:
	var remaining := echo.get_weapon_cooldown_fraction()
	var color := COOLDOWN_READY_COLOR if remaining <= 0.0 else COOLDOWN_COLOR
	_draw_bar(COOLDOWN_BAR_Y, COOLDOWN_BAR_HEIGHT, 1.0 - remaining, color)


func _draw_ability_pip() -> void:
	var ability := AbilityCatalog.get_ability(echo.ability_id)
	if ability == null:
		return
	var charge := 1.0 - echo.get_ability_cooldown_fraction()
	draw_circle(PIP_CENTER, PIP_RADIUS + 1.0, BACKING_COLOR)
	if charge >= 1.0:
		draw_circle(PIP_CENTER, PIP_RADIUS, ability.color)
		draw_arc(PIP_CENTER, PIP_RADIUS, 0.0, TAU, 20, Color.WHITE, 1.0)
		return
	draw_circle(PIP_CENTER, PIP_RADIUS, TRACK_COLOR)
	if charge > 0.02:
		var points := PackedVector2Array([PIP_CENTER])
		var steps := maxi(int(ceil(charge * 24.0)), 2)
		for step in range(steps + 1):
			var angle := -PI / 2.0 + TAU * charge * float(step) / float(steps)
			points.append(PIP_CENTER + Vector2.from_angle(angle) * PIP_RADIUS)
		draw_colored_polygon(points, ability.color)
	draw_arc(PIP_CENTER, PIP_RADIUS, 0.0, TAU, 20, ability.color, 1.0)


func _draw_intent_line() -> void:
	var intent := echo.get_display_intent()
	var target := echo.get_display_target()
	if target == null or not LINE_INTENTS.has(intent):
		return
	var end := to_local(target.global_position)
	if end.length() < 24.0:
		return
	var color: Color = INTENT_STYLES[intent]["color"]
	draw_line(Vector2.ZERO, end, Color(BACKING_COLOR, 0.4), LINE_WIDTH + 2.0)
	draw_line(Vector2.ZERO, end, Color(color, 0.9), LINE_WIDTH)
	draw_circle(end, 4.0, Color(color, 0.9))


func _draw_intent_glyph() -> void:
	var intent := echo.get_display_intent()
	if not INTENT_STYLES.has(intent):
		return
	var style: Dictionary = INTENT_STYLES[intent]
	var color: Color = style["color"]
	var center := GLYPH_CENTER
	draw_circle(center, 8.0, BACKING_COLOR)
	var toward := Vector2.RIGHT
	var target := echo.get_display_target()
	if target != null:
		toward = (target.global_position - echo.global_position).normalized()
	elif not echo.aim_direction.is_zero_approx():
		toward = echo.aim_direction
	match style["glyph"]:
		&"cross":
			draw_line(center + Vector2(-4, -4), center + Vector2(4, 4), color, 2.0)
			draw_line(center + Vector2(-4, 4), center + Vector2(4, -4), color, 2.0)
		&"chevron_toward":
			_draw_chevron(center, toward, color)
		&"chevron_away":
			_draw_chevron(center, -toward, color)
		&"bars":
			draw_line(center + Vector2(-2.5, -4), center + Vector2(-2.5, 4), color, 2.0)
			draw_line(center + Vector2(2.5, -4), center + Vector2(2.5, 4), color, 2.0)
		&"dots":
			for x in [-4.0, 0.0, 4.0]:
				draw_circle(center + Vector2(x, 0), 1.3, color)
		&"ring_dot":
			draw_arc(center, 4.5, 0.0, TAU, 16, color, 1.5)
			draw_circle(center, 1.3, color)
		&"plus":
			draw_line(center + Vector2(-4, 0), center + Vector2(4, 0), color, 2.0)
			draw_line(center + Vector2(0, -4), center + Vector2(0, 4), color, 2.0)
		&"zigzag":
			var zigzag := PackedVector2Array([
				center + Vector2(-5, 3), center + Vector2(-2, -3), center + Vector2(1, 3),
				center + Vector2(5, -3),
			])
			draw_polyline(zigzag, color, 2.0)


func _draw_chevron(center: Vector2, direction: Vector2, color: Color) -> void:
	var side := direction.orthogonal()
	var tip := center + direction * 4.0
	var points := PackedVector2Array([
		center - direction * 3.0 + side * 4.0,
		tip,
		center - direction * 3.0 - side * 4.0,
	])
	draw_polyline(points, color, 2.0)
