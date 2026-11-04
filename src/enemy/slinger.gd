extends EnemyActor


const SHOT_SCENE := preload("res://src/enemy/enemy_shot.tscn")
const FIRE_INTERVAL := 2.4
const FIRST_SHOT_DELAY := 1.0
const WINDUP_DURATION := 0.6
const AIM_TRACK_DURATION := 0.45
const TARGET_RANGE := 600.0
const FLEE_DISTANCE := 260.0
const KEEP_DISTANCE := 380.0
const SHOT_SPEED := 420.0
const SHOT_DAMAGE := 14.0
const SHOT_MAX_DISTANCE := 640.0
const SHOT_SPAWN_OFFSET := 22.0
const AIM_LINE_COLOR := Color(0.9, 0.12, 0.12, 0.75)
const AIM_MARKER_RADIUS := 18.0

var state := &"kite"
var state_time_left := 0.0
var fire_cooldown_left := FIRST_SHOT_DELAY
var aim_direction := Vector2.RIGHT
## Distance to the target when the aim last tracked it; the line stops there.
var aim_length := TARGET_RANGE
var target: Node2D


func _physics_process(delta: float) -> void:
	if _advance_spawn_grace(delta):
		velocity = Vector2.ZERO
		return
	fire_cooldown_left = maxf(fire_cooldown_left - delta, 0.0)
	if state == &"windup":
		_tick_windup(delta)
	else:
		_tick_kite()
	move_and_slide()


func _tick_kite() -> void:
	state_time_left = fire_cooldown_left
	velocity = Vector2.ZERO
	var nearest := EnemyTargeting.nearest_friendly(self)
	if fire_cooldown_left <= 0.0:
		var victim := EnemyTargeting.weakest_friendly(self, TARGET_RANGE)
		if victim != null:
			_start_windup(victim)
			return
	if not is_instance_valid(nearest):
		return
	var to_nearest := nearest.global_position - global_position
	if to_nearest.is_zero_approx():
		return
	var distance := to_nearest.length()
	if distance < FLEE_DISTANCE:
		velocity = -to_nearest.normalized() * move_speed
	elif distance > KEEP_DISTANCE:
		velocity = to_nearest.normalized() * move_speed


func _start_windup(victim: Node2D) -> void:
	target = victim
	state = &"windup"
	state_time_left = WINDUP_DURATION
	fire_cooldown_left = FIRE_INTERVAL
	velocity = Vector2.ZERO
	_aim_at_target()
	queue_redraw()


func _tick_windup(delta: float) -> void:
	velocity = Vector2.ZERO
	state_time_left = maxf(state_time_left - delta, 0.0)
	if WINDUP_DURATION - state_time_left <= AIM_TRACK_DURATION:
		_aim_at_target()
	queue_redraw()
	if state_time_left > 0.0:
		return
	_fire()
	state = &"kite"
	queue_redraw()


func _aim_at_target() -> void:
	if not is_instance_valid(target):
		return
	var to_target := target.global_position - global_position
	if not to_target.is_zero_approx():
		aim_direction = to_target.normalized()
		aim_length = minf(to_target.length(), SHOT_MAX_DISTANCE)


func _fire() -> void:
	var shot := SHOT_SCENE.instantiate() as EnemyShot
	var shot_parent := get_tree().current_scene
	if shot_parent == null:
		shot_parent = get_tree().root
	shot_parent.add_child(shot)
	shot.add_to_group(HeroActor.TRANSIENT_COMBAT_GROUP)
	shot.launch(
		global_position + aim_direction * SHOT_SPAWN_OFFSET,
		aim_direction,
		SHOT_DAMAGE,
		SHOT_SPEED,
		SHOT_MAX_DISTANCE
	)
	shot.hit_friendly.connect(_on_shot_hit_friendly)


func _on_shot_hit_friendly(hit_target: Node, applied: float) -> void:
	dealt_damage.emit(enemy_id, hit_target, applied)


func get_windup_progress() -> float:
	if state != &"windup":
		return 0.0
	return 1.0 - state_time_left / WINDUP_DURATION


func _draw() -> void:
	if state != &"windup":
		return
	var aim_end := aim_direction * aim_length
	draw_line(Vector2.ZERO, aim_end, AIM_LINE_COLOR, 2.0)
	draw_arc(aim_end, AIM_MARKER_RADIUS, 0.0, TAU, 24, AIM_LINE_COLOR, 2.0, true)


func _mcp_state() -> Dictionary:
	return {
		"enemy_id": String(enemy_id),
		"pos_x": global_position.x,
		"pos_y": global_position.y,
		"health": health,
		"max_health": max_health,
		"state": "spawn_grace" if spawn_grace > 0.0 else ("defeated" if is_defeated else String(state)),
		"state_time_left": spawn_grace if spawn_grace > 0.0 else state_time_left,
		"cast_progress": get_windup_progress(),
		"is_casting": is_casting(),
		"target": String(target.name) if is_instance_valid(target) else "",
		"stable_spawn_order": stable_spawn_order,
	}
