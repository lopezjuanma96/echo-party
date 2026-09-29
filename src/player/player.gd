extends HeroActor


@export var move_speed := 260.0
@export var dodge_speed := 720.0
@export var dodge_duration := 0.18
@export var dodge_cooldown := 0.55
@onready var body: Polygon2D = $Body
@onready var facing_marker: Polygon2D = $FacingMarker

var facing := Vector2.DOWN
var dodge_direction := Vector2.ZERO
var dodge_time_left := 0.0
var dodge_cooldown_left := 0.0
var suppress_combat_input := false


func _ready() -> void:
	super()


func _physics_process(delta: float) -> void:
	tick_combat(delta)
	dodge_cooldown_left = maxf(dodge_cooldown_left - delta, 0.0)
	_update_aim()
	if suppress_combat_input:
		if not _is_combat_input_pressed():
			suppress_combat_input = false
	else:
		_update_weapon_selection()

	if dodge_time_left > 0.0:
		dodge_time_left -= delta
		velocity = dodge_direction * dodge_speed
		body.color = Color("65a0ff")
	else:
		body.color = Color("1a61f2")
		var input_direction := Input.get_vector(
			&"move_left", &"move_right", &"move_up", &"move_down"
		)
		if not input_direction.is_zero_approx():
			facing = input_direction.normalized()
			facing_marker.rotation = facing.angle() + PI / 2.0

		if Input.is_action_just_pressed(&"dodge") and dodge_cooldown_left <= 0.0:
			_start_dodge(input_direction)
		else:
			velocity = input_direction * move_speed

	move_and_slide()

	if (
		not suppress_combat_input
		and Input.is_action_just_pressed(&"basic_attack")
		and dodge_time_left <= 0.0
	):
		attack_selected_weapon()


func _start_dodge(input_direction: Vector2) -> void:
	dodge_direction = facing if input_direction.is_zero_approx() else input_direction.normalized()
	dodge_time_left = dodge_duration
	dodge_cooldown_left = dodge_cooldown
	velocity = dodge_direction * dodge_speed


func _update_aim() -> void:
	set_aim_direction(get_global_mouse_position() - global_position)


func _update_weapon_selection() -> void:
	if Input.is_action_just_pressed(&"weapon_slot_1"):
		select_weapon_slot(0)
	elif Input.is_action_just_pressed(&"weapon_slot_2"):
		select_weapon_slot(1)
	elif Input.is_action_just_pressed(&"weapon_previous"):
		cycle_weapon(-1)
	elif Input.is_action_just_pressed(&"weapon_next"):
		cycle_weapon(1)


func suppress_combat_input_until_released() -> void:
	suppress_combat_input = true


func _is_combat_input_pressed() -> bool:
	return (
		Input.is_action_pressed(&"basic_attack")
		or Input.is_action_pressed(&"weapon_slot_1")
		or Input.is_action_pressed(&"weapon_slot_2")
		or Input.is_action_pressed(&"weapon_previous")
		or Input.is_action_pressed(&"weapon_next")
	)


func take_damage(amount: float) -> void:
	if dodge_time_left > 0.0:
		return
	super(amount)


func reset_for_new_run(spawn_position: Vector2) -> void:
	max_health = HeroProgression.BASE_MAX_HEALTH
	attack_damage = HeroProgression.BASE_ATTACK_DAMAGE
	weapon_loadout = WeaponCatalog.get_loadout(HeroProgression.JOB_NOVICE)
	selected_weapon_id = weapon_loadout[0]
	attack_cooldowns.clear()
	attack_cooldowns[selected_weapon_id] = 0.0
	facing = Vector2.DOWN
	dodge_direction = Vector2.ZERO
	dodge_time_left = 0.0
	dodge_cooldown_left = 0.0
	suppress_combat_input = false
	set_aim_direction(Vector2.RIGHT)
	reset_actor(spawn_position, true)
	weapon_changed.emit(selected_weapon_id)
