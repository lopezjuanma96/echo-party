extends EnemyActor


var target: Node2D


func _physics_process(delta: float) -> void:
	if _advance_spawn_grace(delta):
		velocity = Vector2.ZERO
		return
	target = EnemyTargeting.nearest_friendly(self)
	velocity = Vector2.ZERO
	if is_instance_valid(target):
		var to_target := target.global_position - global_position
		if not to_target.is_zero_approx():
			velocity = to_target.normalized() * move_speed
	move_and_slide()
	_damage_contact(delta)


func _mcp_state() -> Dictionary:
	return {
		"enemy_id": String(enemy_id),
		"pos_x": global_position.x,
		"pos_y": global_position.y,
		"health": health,
		"max_health": max_health,
		"state": "spawn_grace" if spawn_grace > 0.0 else ("defeated" if is_defeated else "chase"),
		"state_time_left": spawn_grace,
		"target": String(target.name) if is_instance_valid(target) else "",
		"stable_spawn_order": stable_spawn_order,
	}
