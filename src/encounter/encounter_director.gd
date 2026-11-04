class_name EncounterDirector
extends Node2D
## Runs one scripted encounter per run: IDLE → WARNING → ACTIVE → CLEARED.
## The director owns the enemies it spawns (they are its children); the arena
## spawner owns open-arena population and is paused while the encounter runs.


signal state_changed(new_state: StringName)
signal enemy_defeated(experience_reward: int)
## Emitted once per finished encounter, with a plain-data report dictionary.
signal report_ready(report: Dictionary)

const STATE_IDLE := &"idle"
const STATE_WARNING := &"warning"
const STATE_ACTIVE := &"active"
const STATE_CLEARED := &"cleared"
const OUTCOME_CLEARED := &"cleared"
const OUTCOME_FAILED := &"failed"
const STABLE_ORDER_BASE := 1_000_000
## Guards wave times against float drift from accumulating many physics deltas.
const TIME_EPSILON := 0.000001

@export var encounter_id: StringName = &"bell_court"
@export var spawner_path := NodePath("../Enemies")

var spawner: EnemySpawner
var armed := true
var state := STATE_IDLE
var state_time_left := 0.0
var elapsed := 0.0
var waves_spawned := 0
var outcome := &""
var casts_landed := 0
var casts_broken := 0
## enemy_id (String) -> {"hero": float, "echo": float}
var damage_taken := {}
var healing_done := 0.0
var had_echo := false
var echo_survived := true
var party_jobs: Array[StringName] = []
var last_report := {}
var random := RandomNumberGenerator.new()
var _spawn_count := 0
var _saved_population := 0
var _population_paused := false
var _healing_baselines := {}
var _echo: EchoActor


func _ready() -> void:
	if spawner == null:
		spawner = get_node_or_null(spawner_path) as EnemySpawner


func disarm() -> void:
	armed = false


## Fires the encounter when it is armed and idle, the active hero has reached
## the trigger level, and no level choice is pending.
func try_trigger(hero_level: int, has_pending_choice: bool, new_party_jobs: Array) -> bool:
	if not can_trigger(hero_level, has_pending_choice):
		return false
	return start_encounter(new_party_jobs)


func can_trigger(hero_level: int, has_pending_choice: bool) -> bool:
	return (
		armed
		and state == STATE_IDLE
		and not has_pending_choice
		and hero_level >= EncounterCatalog.get_trigger_level(encounter_id)
	)


## Skips the level trigger (scenarios); the encounter still goes through WARNING.
func start_encounter(new_party_jobs: Array, new_encounter_id: StringName = &"") -> bool:
	if state != STATE_IDLE or not is_inside_tree():
		return false
	if not new_encounter_id.is_empty():
		encounter_id = new_encounter_id
	var data := EncounterCatalog.get_encounter(encounter_id)
	if data.is_empty():
		return false
	armed = false
	_clear_counters()
	party_jobs.clear()
	for job_value: Variant in new_party_jobs:
		if not StringName(job_value).is_empty():
			party_jobs.append(StringName(job_value))
	random.seed = int(data["seed"])
	_find_echo()
	_track_party()
	if spawner != null:
		_saved_population = spawner.target_population
		_population_paused = true
		spawner.set_population(0)
	state_time_left = float(data["warning_duration"])
	_set_state(STATE_WARNING)
	return true


func reset_for_new_run() -> void:
	if state == STATE_WARNING or state == STATE_ACTIVE:
		_finish(OUTCOME_FAILED)
	for child in get_children():
		child.free()
	_resume_spawner()
	_clear_counters()
	armed = true
	_set_state(STATE_IDLE)


func get_alive_enemy_count() -> int:
	var count := 0
	for child in get_children():
		var enemy := child as EnemyActor
		if enemy != null and not enemy.is_queued_for_deletion() and not enemy.is_defeated:
			count += 1
	return count


func _physics_process(delta: float) -> void:
	match state:
		STATE_WARNING:
			state_time_left = maxf(state_time_left - delta, 0.0)
			_track_party()
			if state_time_left <= 0.0:
				_begin_active()
		STATE_ACTIVE:
			elapsed += delta
			_spawn_due_waves()
			_track_party()
			if (
				waves_spawned >= EncounterCatalog.get_encounter(encounter_id)["waves"].size()
				and get_alive_enemy_count() == 0
			):
				_clear()


func _begin_active() -> void:
	elapsed = 0.0
	waves_spawned = 0
	state_time_left = 0.0
	_set_state(STATE_ACTIVE)
	_spawn_due_waves()


func _spawn_due_waves() -> void:
	var waves: Array = EncounterCatalog.get_encounter(encounter_id)["waves"]
	while waves_spawned < waves.size():
		var wave: Dictionary = waves[waves_spawned]
		if elapsed + TIME_EPSILON < float(wave["time"]):
			break
		_spawn_wave(wave)
		waves_spawned += 1


func _spawn_wave(wave: Dictionary) -> void:
	var data := EncounterCatalog.get_encounter(encounter_id)
	var grace := float(data["spawn_grace"])
	var jitter_radius := float(data["pack_jitter_radius"])
	for spawn: Dictionary in wave["spawns"]:
		for index in int(spawn.get("count", 1)):
			var spawn_position: Vector2 = spawn["position"]
			if index > 0:
				var angle := random.randf_range(0.0, TAU)
				var distance := sqrt(random.randf()) * jitter_radius
				spawn_position += Vector2.RIGHT.rotated(angle) * distance
			_spawn_enemy(spawn["enemy_id"], spawn_position, grace)


func _spawn_enemy(enemy_id: StringName, spawn_position: Vector2, grace: float) -> EnemyActor:
	var enemy := EnemyCatalog.instantiate(enemy_id)
	if enemy == null:
		push_error("Unknown encounter enemy ID: %s" % enemy_id)
		return null
	_spawn_count += 1
	enemy.name = "Court%d" % _spawn_count
	enemy.stable_spawn_order = STABLE_ORDER_BASE + _spawn_count
	enemy.position = spawn_position
	enemy.spawn_grace = grace
	enemy.set_simulation_seed(random.randi())
	enemy.defeated.connect(_on_enemy_defeated)
	enemy.dealt_damage.connect(_on_enemy_dealt_damage)
	if enemy.has_signal(&"cast_resolved"):
		enemy.connect(&"cast_resolved", _on_cast_resolved)
		enemy.connect(&"cast_interrupted", _on_cast_interrupted)
	add_child(enemy)
	return enemy


func _clear() -> void:
	_resume_spawner()
	_set_state(STATE_CLEARED)
	_finish(OUTCOME_CLEARED)


func _finish(result: StringName) -> void:
	_track_party()
	outcome = result
	last_report = build_report()
	report_ready.emit(last_report)


func build_report() -> Dictionary:
	var needs := EncounterCatalog.get_needs(encounter_id)
	var party: Array[String] = []
	for job_id in party_jobs:
		party.append(String(job_id))
	var need_names: Array[String] = []
	for need: StringName in needs:
		need_names.append(String(need))
	var uncovered_names: Array[String] = []
	for need in PartyNeeds.uncovered(party_jobs, needs):
		uncovered_names.append(String(need))
	return {
		"encounter_id": String(encounter_id),
		"display_name": EncounterCatalog.get_display_name(encounter_id),
		"outcome": String(outcome),
		"time": elapsed,
		"casts_landed": casts_landed,
		"casts_broken": casts_broken,
		"damage_taken": damage_taken.duplicate(true),
		"healing_done": healing_done,
		"had_echo": had_echo,
		"echo_survived": echo_survived,
		"party_jobs": party,
		"needs": need_names,
		"uncovered": uncovered_names,
	}


func _resume_spawner() -> void:
	if _population_paused and spawner != null:
		spawner.set_population(_saved_population)
	_population_paused = false


func _clear_counters() -> void:
	state_time_left = 0.0
	elapsed = 0.0
	waves_spawned = 0
	outcome = &""
	casts_landed = 0
	casts_broken = 0
	damage_taken = {}
	healing_done = 0.0
	had_echo = false
	echo_survived = true
	_spawn_count = 0
	_healing_baselines = {}
	_echo = null


func _set_state(new_state: StringName) -> void:
	var changed := state != new_state
	state = new_state
	if changed:
		state_changed.emit(new_state)


func _find_echo() -> void:
	_echo = null
	for actor_node in get_tree().get_nodes_in_group(&"friendly_actors"):
		if actor_node is EchoActor:
			_echo = actor_node
			had_echo = true
			return


## Accumulates healing from per-actor `total_healing_done` deltas (so a defeated
## echo's healing is not lost) and notes whether the echo is still standing.
func _track_party() -> void:
	for actor_node in get_tree().get_nodes_in_group(&"friendly_actors"):
		var actor := actor_node as HeroActor
		if actor == null:
			continue
		var actor_id := actor.get_instance_id()
		var total := actor.total_healing_done
		if _healing_baselines.has(actor_id):
			healing_done += maxf(total - float(_healing_baselines[actor_id]), 0.0)
		_healing_baselines[actor_id] = total
	if had_echo and echo_survived:
		if (
			not is_instance_valid(_echo)
			or _echo.is_queued_for_deletion()
			or _echo.is_defeated
		):
			echo_survived = false


func _on_enemy_defeated(experience_reward: int) -> void:
	enemy_defeated.emit(experience_reward)


func _on_enemy_dealt_damage(enemy_id: StringName, target: Node, applied: float) -> void:
	if applied <= 0.0:
		return
	var key := String(enemy_id)
	if not damage_taken.has(key):
		damage_taken[key] = {"hero": 0.0, "echo": 0.0}
	var side := "echo" if target is EchoActor else "hero"
	damage_taken[key][side] = float(damage_taken[key][side]) + applied


func _on_cast_resolved() -> void:
	casts_landed += 1


func _on_cast_interrupted() -> void:
	casts_broken += 1


func _mcp_state() -> Dictionary:
	var hero_damage := 0.0
	var echo_damage := 0.0
	for key: String in damage_taken:
		hero_damage += float(damage_taken[key]["hero"])
		echo_damage += float(damage_taken[key]["echo"])
	return {
		"encounter_id": String(encounter_id),
		"state": String(state),
		"state_time_left": state_time_left,
		"elapsed": elapsed,
		"armed": armed,
		"waves_spawned": waves_spawned,
		"alive_enemies": get_alive_enemy_count(),
		"outcome": String(outcome),
		"casts_landed": casts_landed,
		"casts_broken": casts_broken,
		"damage_to_hero": hero_damage,
		"damage_to_echo": echo_damage,
		"healing_done": healing_done,
		"had_echo": had_echo,
		"echo_survived": echo_survived,
	}
