extends Node2D


const ARENA_SIZE := Vector2(1800.0, 1100.0)
const TILE_SIZE := 64.0
const FLOOR_COLOR := Color("f7f7f4")
const GRID_COLOR := Color("deded9")
const BORDER_COLOR := Color("12151a")
const BORDER_WIDTH := 24.0


func _draw() -> void:
	var arena_rect := Rect2(-ARENA_SIZE / 2.0, ARENA_SIZE)
	draw_rect(arena_rect, FLOOR_COLOR)

	var x := arena_rect.position.x + TILE_SIZE
	while x < arena_rect.end.x:
		draw_line(Vector2(x, arena_rect.position.y), Vector2(x, arena_rect.end.y), GRID_COLOR)
		x += TILE_SIZE

	var y := arena_rect.position.y + TILE_SIZE
	while y < arena_rect.end.y:
		draw_line(Vector2(arena_rect.position.x, y), Vector2(arena_rect.end.x, y), GRID_COLOR)
		y += TILE_SIZE

	draw_rect(arena_rect, BORDER_COLOR, false, BORDER_WIDTH)
