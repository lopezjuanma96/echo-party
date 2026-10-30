extends EnemyActor


## Emitted when a cast finishes and its circle resolves, or when damage or an
## interrupting hit breaks it. Encounter counters listen; nothing else needs to.
signal cast_resolved
signal cast_interrupted

const CAST_DURATION := 2.0
const CAST_COOLDOWN := 2.0
const FIRST_CAST_DELAY := 1.0
const CIRCLE_RADIUS := 110.0
const CIRCLE_DAMAGE := 55.0
const BREAK_DAMAGE := 60.0
const STUN_DURATION := 1.5
const INTERRUPT_LABEL_DURATION := 0.8
const FLEE_DISTANCE := 240.0
const APPROACH_DISTANCE := 440.0
const BREAK_RING_RADIUS := 34.0
const CAST_BAR_SIZE := Vector2(44.0, 4.0)
const CAST_BAR_OFFSET := Vector2(-22.0, -46.0)
const CIRCLE_COLOR := Color("c2409a")

@onready var telegraph: Telegraph = $Telegraph
@onready var interrupt_label: Label = $InterruptLabel

var state := &"kite"
var state_time_left := 0.0
var cast_cooldown_left := FIRST_CAST_DELAY
var cast_damage_taken := 0.0
var circle_center := Vector2.ZERO
var target: Node2D
var _interrupt_label_time_left := 0.0


func _ready() -> void:
	super()
	telegraph.top_level = true
	interrupt_label.visible = false


func _physics_process(delta: float) -> void:
	if _advance_spawn_grace(delta):
		velocity = Vector2.ZERO
		return
	cast_cooldown_left = maxf(cast_cooldown_left - delta, 0.0)
	_tick_interrupt_label(delta)
	match state:
		&"cast":
			_tick_cast(delta)
		&"stunned":
			_tick_stunned(delta)
		_:
			_tick_kite()
	move_and_slide()


func is_casting() -> bool:
	return state == &"cast"


func _tick_kite() -> void:
	target = EnemyTargeting.nearest_friendly(self)
	state_time_left = cast_cooldown_left
	velocity = Vector2.ZERO
	if not is_instance_valid(target):
		return
	if cast_cooldown_left <= 0.0:
		_start_cast()
		return
	var to_target := target.global_position - global_position
	var distance := to_target.length()
	if to_target.is_zero_approx():
		return
	if distance < FLEE_DISTANCE:
		velocity = -to_target.normalized() * move_speed
	elif distance > APPROACH_DISTANCE:
		velocity = to_target.normalized() * move_speed


func _start_cast() -> void:
	state = &"cast"
	state_time_left = CAST_DURATION
	cast_damage_taken = 0.0
	velocity = Vector2.ZERO
	circle_center = target.global_position
	telegraph.global_position = circle_center
	telegraph.show_area(CIRCLE_RADIUS, CIRCLE_COLOR)
	queue_redraw()


func _tick_cast(delta: float) -> void:
	velocity = Vector2.ZERO
	state_time_left = maxf(state_time_left - delta, 0.0)
	telegraph.set_progress(get_cast_progress())
	queue_redraw()
	if state_time_left > 0.0:
		return
	_resolve_cast()


func _resolve_cast() -> void:
	for actor_node in get_tree().get_nodes_in_group(&"friendly_actors"):
		var actor := actor_node as Node2D
		if (
			actor == null
			or actor.is_queued_for_deletion()
			or bool(actor.get("is_defeated"))
			or circle_center.distance_to(actor.global_position) > CIRCLE_RADIUS
		):
			continue
		_deal_damage(actor, CIRCLE_DAMAGE)
	_end_cast()
	state = &"kite"
	cast_resolved.emit()


func _end_cast() -> void:
	telegraph.clear()
	cast_damage_taken = 0.0
	cast_cooldown_left = CAST_COOLDOWN
	state_time_left = 0.0
	queue_redraw()


func _tick_stunned(delta: float) -> void:
	velocity = Vector2.ZERO
	state_time_left = maxf(state_time_left - delta, 0.0)
	if state_time_left <= 0.0:
		state = &"kite"


func _on_damaged(amount: float, interrupts: bool) -> void:
	super(amount, interrupts)
	if state != &"cast":
		return
	cast_damage_taken += amount
	if interrupts or cast_damage_taken >= BREAK_DAMAGE:
		_interrupt()


func _interrupt() -> void:
	_end_cast()
	state = &"stunned"
	state_time_left = STUN_DURATION
	velocity = Vector2.ZERO
	_interrupt_label_time_left = INTERRUPT_LABEL_DURATION
	interrupt_label.text = "INTERRUPTED"
	interrupt_label.visible = true
	interrupt_label.modulate.a = 1.0
	cast_interrupted.emit()


func _tick_interrupt_label(delta: float) -> void:
	if _interrupt_label_time_left <= 0.0:
		return
	_interrupt_label_time_left = maxf(_interrupt_label_time_left - delta, 0.0)
	var remaining := _interrupt_label_time_left / INTERRUPT_LABEL_DURATION
	interrupt_label.modulate.a = remaining
	interrupt_label.position.y = -86.0 - (1.0 - remaining) * 14.0
	if _interrupt_label_time_left <= 0.0:
		interrupt_label.visible = false


func get_cast_progress() -> float:
	if state != &"cast":
		return 0.0
	return 1.0 - state_time_left / CAST_DURATION


func _draw() -> void:
	if state != &"cast":
		return
	draw_arc(Vector2.ZERO, BREAK_RING_RADIUS, 0.0, TAU, 48, Color.WHITE, 2.0, true)
	draw_rect(Rect2(CAST_BAR_OFFSET, CAST_BAR_SIZE), Color(0.0, 0.0, 0.0, 0.6))
	draw_rect(
		Rect2(CAST_BAR_OFFSET, Vector2(CAST_BAR_SIZE.x * get_cast_progress(), CAST_BAR_SIZE.y)),
		CIRCLE_COLOR.lightened(0.3)
	)


func _mcp_state() -> Dictionary:
	return {
		"enemy_id": String(enemy_id),
		"pos_x": global_position.x,
		"pos_y": global_position.y,
		"health": health,
		"max_health": max_health,
		"state": "spawn_grace" if spawn_grace > 0.0 else ("defeated" if is_defeated else String(state)),
		"state_time_left": spawn_grace if spawn_grace > 0.0 else state_time_left,
		"cast_progress": get_cast_progress(),
		"is_casting": is_casting(),
		"target": String(target.name) if is_instance_valid(target) else "",
		"circle_x": circle_center.x,
		"circle_y": circle_center.y,
		"stable_spawn_order": stable_spawn_order,
	}
