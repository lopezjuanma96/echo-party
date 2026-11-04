extends SceneTree
## Balance tool, not a pass/fail test. Loads every `*_5_court.tscn` scenario as
## the real current scene, steps physics frames, and prints one row per scenario.
## The default deterministic bot drives only the harness player. `--idle`
## reproduces the original idle-player matrix. Neither mode replaces playtesting.
##
##   godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd
##   godot --headless --fixed-fps 60 --path . --script res://tests/court_matrix.gd -- --idle
##
## `--fixed-fps 60` only makes the run fast (one 1/60 s step per frame, no
## real-time wait); without it the table is identical but takes minutes.
## `--hero-ability` remains available with `--idle` for the old ability-only mode.


const SCENARIO_DIR := "res://tests/scenarios"
const SCENARIO_SUFFIX := "_5_court.tscn"
## Active-fight seconds allowed after the 3 s warning before a row is "timeout".
const MAX_ACTIVE_SECONDS := 60.0
const SETUP_FRAME_LIMIT := 60
const PHYSICS_STEP := 1.0 / 60.0
const MEND_THRESHOLD := 0.6
const COLUMN_WIDTHS := [24, 9, 9, 8, 8, 8, 10, 10, 8, 5]

var _idle := false
var _hero_uses_ability := false


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
	var scenario_files: Array[String] = []
	for file_name in DirAccess.get_files_at(SCENARIO_DIR):
		if file_name.ends_with(SCENARIO_SUFFIX):
			scenario_files.append(file_name)
	scenario_files.sort()

	print("Bell Court matrix (%s, <= %d s of fight per scenario)" % [
		"idle player" + (" pressing its ability key" if _hero_uses_ability else "") if _idle else "deterministic player bot",
		int(MAX_ACTIVE_SECONDS),
	])
	print(_format_row(
		["scenario", "bot side", "outcome", "time", "hero HP", "echo HP", "echo lost", "casts L/B", "healing", "left"]
	))
	for file_name in scenario_files:
		var row: Array = await _run_scenario("%s/%s" % [SCENARIO_DIR, file_name])
		row.push_front(file_name.trim_suffix(SCENARIO_SUFFIX))
		print(_format_row(row))
	quit(0)


## Returns the row cells after the scenario name.
func _run_scenario(path: String) -> Array:
	var bot_side := "idle" if _idle else "hero"
	if change_scene_to_file(path) != OK:
		return [bot_side, "load-error", "-", "-", "-", "-", "-", "-", "-"]
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
	var bot: PlayerBot
	if not _idle:
		player.set_physics_process(false)
		bot = PlayerBot.new(player, main)
	var hero_health := player.health
	var echo_health := -1.0
	var alive := 0
	var echo_lost_at := -1.0
	var state: Dictionary = main._mcp_state()
	var director: Dictionary = state["director"]
	var max_frames := int((MAX_ACTIVE_SECONDS + 4.0) / PHYSICS_STEP)
	for _frame in max_frames:
		await physics_frame
		if bot != null:
			player.tick_combat(PHYSICS_STEP)
			bot.step()
			player.move_and_slide()
		elif _hero_uses_ability and player.can_use_ability():
			player.use_ability()
		# Snapshot before reading the outcome: a failed run resets the hero,
		# echo, and director in the same frame it reports the failure.
		var previous_hero := hero_health
		var previous_echo := echo_health
		var previous_alive := alive
		hero_health = player.health
		var echo := main.get("echo") as HeroActor
		echo_health = echo.health if is_instance_valid(echo) else 0.0
		state = main._mcp_state()
		director = state["director"]
		alive = int(director["alive_enemies"])
		if (
			echo_lost_at < 0.0
			and bool(director["had_echo"])
			and not bool(director["echo_survived"])
		):
			echo_lost_at = float(director["elapsed"])
		var failed := int(state["run_number"]) > 1
		if failed:
			hero_health = previous_hero
			echo_health = previous_echo
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
		"%d" % int(roundf(echo_health)) if bool(report["had_echo"]) else "-",
		"%.1fs" % echo_lost_at if echo_lost_at >= 0.0 else "-",
		"%d/%d" % [int(report["casts_landed"]), int(report["casts_broken"])],
		"%d" % int(roundf(float(report["healing_done"]))),
		"%d" % alive,
	]


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
