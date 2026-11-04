extends EnemyActor


const WINDUP_DURATION := 0.9
const RECOVER_DURATION := 0.7
const COOLDOWN_DURATION := 0.8
const WINDUP_RANGE := 70.0
const SLAM_RADIUS := 88.0
const SLAM_DAMAGE := 50.0

@onready var telegraph: Telegraph = $Telegraph

var state := &"chase"
var state_time_left := 0.0
var target: Node2D


func _physics_process(delta: float) -> void:
	if _advance_spawn_grace(delta):
		velocity = Vector2.ZERO
		return
	match state:
		&"windup":
			_tick_windup(delta)
		&"recover":
			_tick_recover(delta)
		&"cooldown":
			_tick_cooldown(delta)
		_:
			_tick_chase()
	move_and_slide()


func _tick_chase() -> void:
	target = EnemyTargeting.nearest_friendly(self)
	if is_instance_valid(target) and global_position.distance_to(target.global_position) <= WINDUP_RANGE:
		_start_windup()
		return
	_chase_target()


func _start_windup() -> void:
	state = &"windup"
	state_time_left = WINDUP_DURATION
	velocity = Vector2.ZERO
	telegraph.show_area(SLAM_RADIUS, Color("db1a21"))


func _tick_windup(delta: float) -> void:
	velocity = Vector2.ZERO
	state_time_left = maxf(state_time_left - delta, 0.0)
	telegraph.set_progress(
		1.0 - state_time_left / WINDUP_DURATION,
		state_time_left <= 0.1
	)
	if state_time_left > 0.0:
		return
	_slam()
	telegraph.clear()
	state = &"recover"
	state_time_left = RECOVER_DURATION
	body.color = _base_body_color.lerp(Color(0.45, 0.45, 0.45), 0.65)


func _tick_recover(delta: float) -> void:
	velocity = Vector2.ZERO
	state_time_left = maxf(state_time_left - delta, 0.0)
	if state_time_left <= 0.0:
		state = &"cooldown"
		state_time_left = COOLDOWN_DURATION
		body.color = _base_body_color


func _tick_cooldown(delta: float) -> void:
	state_time_left = maxf(state_time_left - delta, 0.0)
	_chase_target()
	if state_time_left <= 0.0:
		state = &"chase"


func _chase_target() -> void:
	target = EnemyTargeting.nearest_friendly(self)
	velocity = Vector2.ZERO
	if not is_instance_valid(target):
		return
	var to_target := target.global_position - global_position
	if not to_target.is_zero_approx():
		velocity = to_target.normalized() * move_speed


func _slam() -> void:
	for actor_node in get_tree().get_nodes_in_group(&"friendly_actors"):
		var actor := actor_node as Node2D
		if (
			actor == null
			or actor.is_queued_for_deletion()
			or bool(actor.get("is_defeated"))
			or global_position.distance_to(actor.global_position) > SLAM_RADIUS
		):
			continue
		_deal_damage(actor, SLAM_DAMAGE)


func _mcp_state() -> Dictionary:
	return {
		"enemy_id": String(enemy_id),
		"pos_x": global_position.x,
		"pos_y": global_position.y,
		"health": health,
		"max_health": max_health,
		"state": "spawn_grace" if spawn_grace > 0.0 else ("defeated" if is_defeated else String(state)),
		"state_time_left": spawn_grace if spawn_grace > 0.0 else state_time_left,
		"target": String(target.name) if is_instance_valid(target) else "",
		"stable_spawn_order": stable_spawn_order,
	}
