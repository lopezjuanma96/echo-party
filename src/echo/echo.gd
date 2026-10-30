class_name EchoActor
extends HeroActor


signal progression_changed

const DISPLAY_INTENT_DWELL := 0.25
const INTENT_LABELS := {
	&"attack": "Attack",
	&"approach": "Approach",
	&"retreat": "Retreat",
	&"hold": "Hold",
	&"follow": "Follow",
	&"regroup": "Regroup",
	&"heal": "Heal",
	&"interrupt": "Interrupt",
	&"idle": "Idle",
}

@export var move_speed := 220.0
@export var target_leash := 620.0
@export var follow_distance := 105.0
@export var ranged_retreat_distance := 180.0
@export var mend_threshold := 0.6
@export var support_retreat_distance := 140.0
@export var support_hero_distance := 70.0
@export var support_leash := 260.0
@export var interrupt_target_range := 450.0

var active_hero: Node2D
var hero_record: HeroRecord
var progression := HeroProgression.new()
var current_target: Node2D
var intent_target: Node2D
var current_intent := &"idle"
var focused_target: Node2D
var is_regrouping := false
var is_holding_position := false
## Label for the active hero in intent summaries; Main sets it to "Hero N".
var active_hero_label := "Hero"
var _recorded_choices: Array[Dictionary] = []
var _replay_level_limit := 1
var _hold_is_cooldown := false
var _heal_fraction_before := 0.0
var _display_intent := &"idle"
var _display_target: Node2D
var _display_heal_fraction := 0.0
var _has_pending_heal := false
var _pending_heal_target: Node2D
var _pending_heal_fraction := 0.0
var _display_age := DISPLAY_INTENT_DWELL


func configure(record: HeroRecord, new_active_hero: Node2D) -> bool:
	if record == null or new_active_hero == null:
		return false
	var recorded_progression := record.replay_progression()
	if recorded_progression == null:
		return false
	hero_record = record
	active_hero = new_active_hero
	_recorded_choices = recorded_progression.get_choices()
	_replay_level_limit = mini(recorded_progression.level, _recorded_choices.size() + 1)
	progression = HeroProgression.new()
	job_id = HeroProgression.JOB_NOVICE
	if not apply_progression(progression, true):
		return false
	reset_actor(position, true)
	_update_label()
	return true


func grant_shared_experience(amount: int) -> int:
	if amount <= 0 or progression.level >= _replay_level_limit:
		return 0
	var maximum_experience := (_replay_level_limit - 1) * HeroProgression.XP_PER_LEVEL
	var granted_amount := mini(amount, maximum_experience - progression.experience)
	var levels_gained := progression.grant_experience(granted_amount)
	for choice_level in progression.get_pending_choice_levels():
		var choice_index := choice_level - 2
		if choice_index < 0 or choice_index >= _recorded_choices.size():
			push_error("Missing recorded choice at level %d" % choice_level)
			break
		var choice := _recorded_choices[choice_index]
		var applied := false
		if choice.has("job_id"):
			applied = progression.apply_job_choice(choice_level, StringName(choice["job_id"]))
		elif choice.has("attribute_id"):
			applied = progression.apply_attribute_choice(
				choice_level,
				StringName(choice["attribute_id"])
			)
		if not applied:
			push_error("Failed to replay recorded choice at level %d" % choice_level)
			break
	if levels_gained > 0:
		job_id = progression.get_job_id()
		apply_progression(progression)
		_update_label()
		progression_changed.emit()
	return levels_gained


func get_replay_level_limit() -> int:
	return _replay_level_limit


func command_focus(target: Node2D) -> bool:
	if not _is_valid_focus_target(target):
		return false
	focused_target = target
	is_regrouping = false
	return true


func command_regroup() -> void:
	focused_target = null
	current_target = null
	is_holding_position = false
	is_regrouping = true
	current_intent = &"regroup"


func toggle_hold_position() -> bool:
	is_holding_position = not is_holding_position
	is_regrouping = false
	current_intent = &"hold" if is_holding_position else &"idle"
	return is_holding_position


func get_command_status() -> StringName:
	if is_regrouping:
		return &"regroup"
	if is_holding_position:
		return &"hold"
	if _is_valid_focus_target(focused_target):
		return &"focus"
	return &"follow"


func _is_valid_focus_target(target: Node2D) -> bool:
	return (
		is_instance_valid(target)
		and not target.is_queued_for_deletion()
		and target.is_in_group(&"enemies")
		and is_instance_valid(active_hero)
		and target.global_position.distance_to(active_hero.global_position) <= target_leash
	)


func _update_label() -> void:
	var label := get_node_or_null("EchoLabel") as Label
	if label != null:
		label.text = "ECHO · %s · Lv %d\n%d / %d HP · %s" % [
			hero_record.display_name,
			progression.level,
			health,
			max_health,
			String(get_command_status()).to_upper(),
		]


func _physics_process(delta: float) -> void:
	tick_combat(delta)
	velocity = Vector2.ZERO
	intent_target = null
	_hold_is_cooldown = false
	if not _try_mend():
		if is_regrouping:
			current_target = null
			_regroup_with_active_hero()
		else:
			if focused_target != null and not _is_valid_focus_target(focused_target):
				focused_target = null
			current_target = choose_target(get_tree().get_nodes_in_group(&"enemies"))
			if current_target == null:
				if is_holding_position:
					current_intent = &"hold"
				else:
					_follow_active_hero()
			else:
				_fight_target()
	move_and_slide()
	_update_display_intent(delta)
	_update_label()


func _try_mend() -> bool:
	if not can_use_ability():
		return false
	var target := get_ability_target(mend_threshold)
	if target == null:
		return false
	_heal_fraction_before = target.health / maxf(target.max_health, 1.0)
	if not use_ability():
		return false
	current_intent = &"heal"
	intent_target = target
	return true


func _ability_active_hero() -> HeroActor:
	return active_hero as HeroActor


func _regroup_with_active_hero() -> void:
	current_intent = &"regroup"
	if not is_instance_valid(active_hero):
		is_regrouping = false
		return
	var to_hero := active_hero.global_position - global_position
	if to_hero.length() <= follow_distance * 0.8:
		is_regrouping = false
		current_intent = &"idle"
		return
	velocity = to_hero.normalized() * move_speed


func choose_target(candidates: Array[Node]) -> Node2D:
	if _is_valid_focus_target(focused_target):
		return focused_target
	focused_target = null
	if not is_instance_valid(active_hero):
		return null
	var pool: Array[Node2D] = []
	for candidate_node in candidates:
		var candidate := candidate_node as Node2D
		if candidate == null or candidate.is_queued_for_deletion():
			continue
		if candidate.global_position.distance_to(active_hero.global_position) > target_leash:
			continue
		pool.append(candidate)
	if get_interrupt_weapon_id() != &"":
		var casters: Array[Node2D] = []
		for candidate in pool:
			if (
				_is_casting(candidate)
				and global_position.distance_to(candidate.global_position) <= interrupt_target_range
			):
				casters.append(candidate)
		if not casters.is_empty():
			pool = casters
	return _nearest_candidate(pool)


func _nearest_candidate(pool: Array[Node2D]) -> Node2D:
	var best: Node2D
	var best_distance_squared := INF
	var best_order := 9223372036854775807
	for candidate in pool:
		var distance_squared := global_position.distance_squared_to(candidate.global_position)
		var order := _target_order(candidate)
		if (
			distance_squared < best_distance_squared
			or (is_equal_approx(distance_squared, best_distance_squared) and order < best_order)
			or (
				is_equal_approx(distance_squared, best_distance_squared)
				and order == best_order
				and (best == null or candidate.name.naturalnocasecmp_to(best.name) < 0)
			)
		):
			best = candidate
			best_distance_squared = distance_squared
			best_order = order
	return best


func get_interrupt_weapon_id() -> StringName:
	for weapon_id in weapon_loadout:
		var weapon := WeaponCatalog.get_weapon(weapon_id)
		if weapon != null and weapon.interrupts:
			return weapon_id
	return &""


func _is_casting(target: Node2D) -> bool:
	return (
		is_instance_valid(target)
		and target.has_method(&"is_casting")
		and bool(target.call(&"is_casting"))
	)


func choose_weapon_for_distance(distance: float) -> StringName:
	if weapon_loadout.is_empty():
		return &""
	var choice := weapon_loadout[-1]
	for weapon_id in weapon_loadout:
		var weapon := WeaponCatalog.get_weapon(weapon_id)
		if weapon != null and distance <= weapon.attack_range:
			choice = weapon_id
			break
	select_weapon(choice)
	return choice


func choose_weapon_for_target(target: Node2D, distance: float) -> StringName:
	var interrupt_id := get_interrupt_weapon_id()
	if interrupt_id != &"" and _is_casting(target):
		var weapon := WeaponCatalog.get_weapon(interrupt_id)
		if distance <= weapon.attack_range:
			select_weapon(interrupt_id)
			return interrupt_id
	return choose_weapon_for_distance(distance)


func _follow_active_hero() -> void:
	current_intent = &"idle"
	if not is_instance_valid(active_hero):
		return
	var to_hero := active_hero.global_position - global_position
	if to_hero.length() > follow_distance:
		current_intent = &"follow"
		velocity = to_hero.normalized() * move_speed


func _fight_target() -> void:
	var to_target := current_target.global_position - global_position
	var distance := to_target.length()
	if distance <= 0.0:
		return
	set_aim_direction(to_target)
	var weapon_id := choose_weapon_for_target(current_target, distance)
	var weapon := WeaponCatalog.get_weapon(weapon_id)
	if weapon == null:
		current_intent = &"idle"
		return
	if is_holding_position:
		current_intent = &"hold"
		if distance <= weapon.attack_range:
			current_intent = &"attack" if can_attack() else &"hold"
			_mark_interrupt_intent(weapon)
			_assign_intent_target()
			attack_selected_weapon()
		return
	var posture := JobCatalog.get_posture(job_id)
	if posture == &"support" and distance < support_retreat_distance:
		current_intent = &"retreat"
		var to_hero := active_hero.global_position - global_position
		if to_hero.length() > support_hero_distance:
			velocity = to_hero.normalized() * move_speed
		else:
			velocity = -to_target.normalized() * move_speed
	elif posture == &"ranged" and distance < ranged_retreat_distance:
		current_intent = &"retreat"
		velocity = -to_target.normalized() * move_speed
	elif (
		distance > weapon.attack_range * 0.9
		and (
			posture != &"support"
			or global_position.distance_to(active_hero.global_position) <= support_leash
		)
	):
		current_intent = &"approach"
		velocity = to_target.normalized() * move_speed
	else:
		current_intent = &"attack" if can_attack() else &"hold"
		_hold_is_cooldown = current_intent == &"hold"
	_mark_interrupt_intent(weapon)
	_assign_intent_target()
	if distance <= weapon.attack_range:
		attack_selected_weapon()


func _mark_interrupt_intent(weapon: WeaponDefinition) -> void:
	if (
		weapon.interrupts
		and current_intent in [&"approach", &"attack"]
		and _is_casting(current_target)
	):
		current_intent = &"interrupt"
		intent_target = current_target


func _assign_intent_target() -> void:
	if current_intent in [&"attack", &"approach", &"retreat", &"interrupt"]:
		intent_target = current_target


func _target_order(target: Node2D) -> int:
	var value: Variant = target.get("stable_spawn_order")
	return int(value) if value != null else 9223372036854775807


## The intent shown to the player. It follows `current_intent` but dwells at
## least DISPLAY_INTENT_DWELL seconds per value, shows a fight-time wait for
## weapon cooldown as attack (or interrupt), and keeps one-tick intents such
## as heal visible. The hold stance still shows as hold.
func get_display_intent() -> StringName:
	return _display_intent


func get_display_target() -> Node2D:
	return _display_target if is_instance_valid(_display_target) else null


func get_intent_summary() -> String:
	var label: String = INTENT_LABELS.get(_display_intent, String(_display_intent).capitalize())
	if _display_intent == &"heal":
		var ability := AbilityCatalog.get_ability(ability_id)
		if ability != null:
			label = ability.display_name
	var target := get_display_target()
	if target == null:
		return label
	var detail := ""
	if _display_intent == &"heal":
		detail = "%d%%" % roundi(_display_heal_fraction * 100.0)
	else:
		detail = "%d px" % roundi(global_position.distance_to(target.global_position))
	return "%s → %s · %s" % [label, _describe_target(target), detail]


func get_cooldown_summary() -> String:
	var parts: PackedStringArray = []
	for weapon_id in weapon_loadout:
		parts.append("%s %s" % [
			WeaponCatalog.get_display_name(weapon_id),
			format_cooldown(float(attack_cooldowns.get(weapon_id, 0.0))),
		])
	var ability := AbilityCatalog.get_ability(ability_id)
	if ability != null:
		parts.append("%s %s" % [ability.display_name, format_cooldown(ability_cooldown_left)])
	return " · ".join(parts)


func _describe_target(target: Node2D) -> String:
	if target == self:
		return "Self"
	if target == active_hero:
		return active_hero_label
	var enemy_id: Variant = target.get("enemy_id")
	if enemy_id != null:
		return String(enemy_id).capitalize()
	return String(target.name)


func _resolve_display_intent() -> StringName:
	if current_intent == &"hold" and _hold_is_cooldown:
		var weapon := WeaponCatalog.get_weapon(selected_weapon_id)
		if weapon != null and weapon.interrupts and _is_casting(current_target):
			return &"interrupt"
		return &"attack"
	return current_intent


func _resolve_display_target(intent: StringName) -> Node2D:
	if is_instance_valid(intent_target):
		return intent_target
	if intent in [&"attack", &"interrupt"] and is_instance_valid(current_target):
		return current_target
	if intent in [&"follow", &"regroup"] and is_instance_valid(active_hero):
		return active_hero
	return null


func _update_display_intent(delta: float) -> void:
	_display_age += delta
	var candidate := _resolve_display_intent()
	if candidate == &"heal" and _display_intent != &"heal":
		# Heal lasts a single tick; latch it so a dwelling intent cannot swallow it.
		_pending_heal_target = intent_target
		_pending_heal_fraction = _heal_fraction_before
		_has_pending_heal = true
	if _has_pending_heal:
		if _display_age >= DISPLAY_INTENT_DWELL:
			_display_intent = &"heal"
			_display_age = 0.0
			_display_target = _pending_heal_target if is_instance_valid(_pending_heal_target) else null
			_display_heal_fraction = _pending_heal_fraction
			_has_pending_heal = false
			_pending_heal_target = null
		return
	if candidate != _display_intent:
		if _display_age < DISPLAY_INTENT_DWELL:
			return
		_display_intent = candidate
		_display_age = 0.0
		_display_target = _resolve_display_target(candidate)
		return
	var live_target := _resolve_display_target(candidate)
	if live_target != null:
		_display_target = live_target


func get_current_target() -> Node2D:
	return current_target


func get_current_intent() -> StringName:
	return current_intent


func _mcp_state() -> Dictionary:
	return {
		"pos_x": global_position.x,
		"pos_y": global_position.y,
		"health": health,
		"max_health": max_health,
		"job_id": String(job_id),
		"weapon_id": String(selected_weapon_id),
		"weapon_loadout": Array(weapon_loadout).map(func(id: StringName) -> String: return String(id)),
		"weapon_cooldown_left": float(attack_cooldowns.get(selected_weapon_id, 0.0)),
		"ability_id": String(ability_id),
		"ability_cooldown_left": ability_cooldown_left,
		"total_healing_done": total_healing_done,
		"level": progression.level,
		"current_intent": String(current_intent),
		"display_intent": String(_display_intent),
		"intent_summary": get_intent_summary(),
		"cooldown_summary": get_cooldown_summary(),
		"weapon_cooldown_fraction": get_weapon_cooldown_fraction(),
		"ability_cooldown_fraction": get_ability_cooldown_fraction(),
		"intent_target": String(intent_target.name) if is_instance_valid(intent_target) else "",
		"current_target": String(current_target.name) if is_instance_valid(current_target) else "",
		"command_status": String(get_command_status()),
		"focused_target": String(focused_target.name) if is_instance_valid(focused_target) else "",
		"interrupt_weapon_id": String(get_interrupt_weapon_id()),
		"target_is_casting": _is_casting(current_target),
		"mend_threshold": mend_threshold,
		"support_leash": support_leash,
		"is_defeated": is_defeated,
	}
