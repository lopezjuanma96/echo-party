extends SceneTree
## Balance tool, not a pass/fail test. Loads every `*_5_court.tscn` (Bell Court)
## and then every `*_5_gallery.tscn` (Slinger Gallery) scenario as the real
## current scene, steps physics frames, and prints one table per Trial with one
## row per scenario.
## The default deterministic bot drives only the harness player. `--idle`
## reproduces the original idle-player matrix. Neither mode replaces playtesting.
##
##   godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd
##   godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --idle
##
## `--fixed-fps 60` only makes the run fast (one 1/60 s step per frame, no
## real-time wait); without it the table is identical but takes minutes.
## `--hero-ability` remains available with `--idle` for the old ability-only mode.
## Level-up and echo-extension modals are resolved with a fixed rule (always the
## first option: Might) so XP from the fight can never stall a row. Pass
## `--leave-choices` to leave them unanswered, which reproduces the M2 tables.
## `--echo-level=N` replaces every echo's recorded level before scenario setup;
## echo HP is listed by party slot and losses include the earliest loss time.


const SCENARIO_DIR := "res://tests/scenarios"
## One table per Trial, in print order: scenario suffix and table title.
const TRIAL_TABLES := [
	{"suffix": "_5_court.tscn", "title": "Bell Court"},
	{"suffix": "_5_gallery.tscn", "title": "Slinger Gallery"},
]
## Active-fight seconds allowed after the 3 s warning before a row is "timeout".
const MAX_ACTIVE_SECONDS := 60.0
const SETUP_FRAME_LIMIT := 60
const PHYSICS_STEP := 1.0 / 60.0
const MEND_THRESHOLD := 0.6
const COLUMN_WIDTHS := [29, 9, 9, 14, 8, 9, 14, 10, 8, 5]

var _idle := false
var _hero_uses_ability := false
var _leave_choices := false
var _echo_level_override := 0


class PlayerBot:
	extends RefCounted

	var player: HeroActor
	var policy: EchoActor


	func _init(hero: HeroActor, parent: Node) -> void:
		player = hero
		policy = EchoActor.new()
		policy.set_physics_process(false)
		parent.add_child(policy)
		policy.active_hero = player
		policy.job_id = player.job_id
		policy.weapon_loadout = player.weapon_loadout


	func step() -> void:
		player.velocity = Vector2.ZERO
		if player.can_use_ability() and player.get_ability_target(MEND_THRESHOLD) != null:
			player.use_ability()
			return

		policy.global_position = player.global_position
		var target := policy.choose_target(player.get_tree().get_nodes_in_group(&"enemies"))
		if target == null:
			return
		var to_target := target.global_position - player.global_position
		var distance := to_target.length()
		if distance <= 0.0:
			return
		player.set_aim_direction(to_target)
		var weapon_id := policy.choose_weapon_for_target(target, distance)
		player.select_weapon(weapon_id)
		var weapon := WeaponCatalog.get_weapon(weapon_id)
		if weapon == null:
			return

		var move_speed := float(player.get("move_speed"))
		var posture := JobCatalog.get_posture(player.job_id)
		if posture == &"support" and distance < policy.support_retreat_distance:
			player.velocity = -to_target.normalized() * move_speed
		elif posture == &"ranged" and distance < policy.ranged_retreat_distance:
			player.velocity = -to_target.normalized() * move_speed
		elif distance > weapon.attack_range * 0.9:
			player.velocity = to_target.normalized() * move_speed
		if distance <= weapon.attack_range:
			player.attack_selected_weapon()


func _init() -> void:
	call_deferred(&"_run_matrix")


func _run_matrix() -> void:
	var args := OS.get_cmdline_user_args()
	_idle = args.has("--idle")
	_hero_uses_ability = args.has("--hero-ability")
	_leave_choices = args.has("--leave-choices")
	for arg in args:
		if not arg.begins_with("--echo-level="):
			continue
		var level_text := arg.trim_prefix("--echo-level=")
		if not level_text.is_valid_int() or int(level_text) < 1:
			printerr("--echo-level requires a positive integer")
			quit(2)
			return
		_echo_level_override = int(level_text)
	var mode := (
		"idle player" + (" pressing its ability key" if _hero_uses_ability else "")
		if _idle else "deterministic player bot"
	)
	if _echo_level_override > 0:
		mode += ", echo level %d" % _echo_level_override
	var scenario_names: Array[String] = []
	for file_name in DirAccess.get_files_at(SCENARIO_DIR):
		scenario_names.append(file_name)
	scenario_names.sort()
	for table_index in TRIAL_TABLES.size():
		var table: Dictionary = TRIAL_TABLES[table_index]
		var suffix: String = table["suffix"]
		if table_index > 0:
			print("")
		print("%s matrix (%s, <= %d s of fight per scenario)" % [
			table["title"],
			mode,
			int(MAX_ACTIVE_SECONDS),
		])
		print(_format_row(
			["scenario", "bot side", "outcome", "time", "hero HP", "echo HP", "echoes lost", "casts L/B", "healing", "left"]
		))
		for file_name in scenario_names:
			if not file_name.ends_with(suffix):
				continue
			var row: Array = await _run_scenario("%s/%s" % [SCENARIO_DIR, file_name])
			row.push_front(file_name.trim_suffix(suffix))
			print(_format_row(row))
	quit(0)


## Returns the row cells after the scenario name.
func _run_scenario(path: String) -> Array:
	var bot_side := "idle" if _idle else "hero"
	var scene_error := ""
	if _echo_level_override > 0:
		scene_error = _change_scene_with_echo_level(path)
	elif change_scene_to_file(path) != OK:
		scene_error = "load-error"
	if not scene_error.is_empty():
		return [bot_side, "SKIPPED", scene_error, "-", "-", "-", "-", "-", "-"]
	var main: Node
	var frames := 0
	while main == null and frames < SETUP_FRAME_LIMIT:
		await physics_frame
		frames += 1
		if current_scene != null:
			main = current_scene.get_node_or_null("Main")
	if main == null:
		return [bot_side, "no-main", "-", "-", "-", "-", "-", "-", "-"]

	var player := main.get_node("Player") as HeroActor
	var encounter := main.get_node("EncounterDirector") as EncounterDirector
	var bot: PlayerBot
	if not _idle:
		player.set_physics_process(false)
		bot = PlayerBot.new(player, main)
	var hero_health := player.health
	var echo_health: Array[float] = []
	var echo_lost_at: Array[float] = []
	var initial_echoes: Array = main.get("echoes")
	for echo_value: Variant in initial_echoes:
		var echo := echo_value as HeroActor
		echo_health.append(echo.health if is_instance_valid(echo) else 0.0)
		echo_lost_at.append(-1.0)
	var alive := 0
	var state: Dictionary = main._mcp_state()
	var director: Dictionary = state["director"]
	var max_frames := int((MAX_ACTIVE_SECONDS + 4.0) / PHYSICS_STEP)
	for _frame in max_frames:
		await physics_frame
		_resolve_choice_modals(main)
		if bot != null:
			player.tick_combat(PHYSICS_STEP)
			bot.step()
			player.move_and_slide()
		elif _hero_uses_ability and player.can_use_ability():
			player.use_ability()
		# Snapshot before reading the outcome: a failed run resets the hero,
		# echoes, and director in the same frame it reports the failure.
		var previous_hero := hero_health
		var previous_echo: Array[float] = echo_health.duplicate()
		var previous_losses: Array[float] = echo_lost_at.duplicate()
		var previous_alive := alive
		hero_health = player.health
		_snapshot_echoes(main, encounter, echo_health, echo_lost_at)
		state = main._mcp_state()
		director = state["director"]
		alive = int(director["alive_enemies"])
		var failed := int(state["run_number"]) > 1
		if failed:
			hero_health = previous_hero
			echo_health = previous_echo
			echo_lost_at = previous_losses
			alive = previous_alive
		if (
			failed
			or StringName(director["state"]) == EncounterDirector.STATE_CLEARED
		):
			break

	var failed_run := int(state["run_number"]) > 1
	var cleared := StringName(director["state"]) == EncounterDirector.STATE_CLEARED
	var outcome := "CLEARED" if cleared else ("FAILED" if failed_run else "TIMEOUT")
	var report := _read_report(main, director, failed_run)
	return [
		bot_side,
		outcome,
		"%.1fs" % float(report["time"]),
		"%d" % int(roundf(hero_health)),
		_format_echo_health(echo_health, bool(report["had_echo"])),
		_format_echo_losses(echo_lost_at, bool(report["had_echo"])),
		"%d/%d" % [int(report["casts_landed"]), int(report["casts_broken"])],
		"%d" % int(roundf(float(report["healing_done"]))),
		"%d" % alive,
	]


func _change_scene_with_echo_level(path: String) -> String:
	var packed := ResourceLoader.load(path) as PackedScene
	if packed == null:
		return "load-error"
	var scenario := packed.instantiate()
	if scenario == null:
		return "instantiate-error"
	var jobs: Array[StringName] = []
	for job_value: Variant in scenario.get("echo_jobs"):
		jobs.append(StringName(job_value))
	if jobs.is_empty():
		var echo_job := StringName(scenario.get("echo_job"))
		if not echo_job.is_empty():
			jobs.append(echo_job)
	if jobs.is_empty():
		scenario.free()
		return "no echoes"
	if jobs.size() > int(scenario.get("party_slots")):
		scenario.free()
		return "party too small"
	var levels: Array[int] = []
	for _job in jobs:
		levels.append(_echo_level_override)
	scenario.set("echo_levels", levels)
	var configured := PackedScene.new()
	var pack_result := configured.pack(scenario)
	scenario.free()
	if pack_result != OK:
		return "override-error"
	if change_scene_to_packed(configured) != OK:
		return "load-error"
	return ""


func _snapshot_echoes(
	main: Node,
	encounter: EncounterDirector,
	health: Array[float],
	lost_at: Array[float]
) -> void:
	var echoes: Array = main.get("echoes")
	for index in health.size():
		var echo: HeroActor
		if index < echoes.size():
			echo = echoes[index] as HeroActor
		health[index] = (
			echo.health
			if is_instance_valid(echo) and not echo.is_defeated and not echo.is_queued_for_deletion()
			else 0.0
		)
	for index in mini(encounter.echo_survival.size(), lost_at.size()):
		if not encounter.echo_survival[index] and lost_at[index] < 0.0:
			lost_at[index] = encounter.elapsed


func _format_echo_health(health: Array[float], had_echo: bool) -> String:
	if not had_echo:
		return "-"
	var values: Array[String] = []
	for value in health:
		values.append("%d" % int(roundf(value)))
	return "/".join(values)


func _format_echo_losses(lost_at: Array[float], had_echo: bool) -> String:
	if not had_echo:
		return "-"
	var count := 0
	var earliest := -1.0
	for value in lost_at:
		if value < 0.0:
			continue
		count += 1
		if earliest < 0.0 or value < earliest:
			earliest = value
	if count == 0:
		return "0"
	return "%d @ %.1fs" % [count, earliest]


## Fixed rule for deterministic rows: take option 1 for every pending choice.
func _resolve_choice_modals(main: Node) -> void:
	if _leave_choices:
		return
	var guard := 0
	while bool(main.get("choice_modal").visible) and guard < 32:
		main._apply_pending_choice(0)
		guard += 1


## A failed run resets the live director counters, so read its saved report.
func _read_report(main: Node, director: Dictionary, failed: bool) -> Dictionary:
	if failed:
		var last_report: Dictionary = main.get_node("EncounterDirector").last_report
		if not last_report.is_empty():
			return last_report
	return {
		"time": director["elapsed"],
		"casts_landed": director["casts_landed"],
		"casts_broken": director["casts_broken"],
		"healing_done": director["healing_done"],
		"had_echo": director["had_echo"],
	}


func _format_row(cells: Array) -> String:
	var parts: Array[String] = []
	for index in cells.size():
		parts.append(String(cells[index]).rpad(COLUMN_WIDTHS[index]))
	return " ".join(parts).strip_edges(false, true)
