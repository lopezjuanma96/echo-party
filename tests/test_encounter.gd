extends SceneTree


const EchoScene := preload("res://src/echo/echo.tscn")
const MainScene := preload("res://src/main/main.tscn")
const MainScript := preload("res://src/main/main.gd")
const PHYSICS_STEP := 1.0 / 60.0

var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_run_tests")


func _run_tests() -> void:
	_test_party_needs_coverage()
	_test_catalog_data()
	_test_trigger_conditions()
	_test_warning_phase_pauses_spawner()
	_test_wave_timeline()
	_test_clear_resumes_spawner()
	_test_spawn_order_and_determinism()
	_test_counter_attribution()
	_test_reset_and_failure_report()
	_test_modal_annotations()
	_test_trial_hud_and_report()
	_test_scenario_hook_and_main_trigger()

	if _failures.is_empty():
		print("Encounter director, party needs, and Trial HUD tests passed (12 cases).")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_party_needs_coverage() -> void:
	var needs := EncounterCatalog.get_needs(&"bell_court")
	var vanguard_mender := PartyNeeds.evaluate([&"vanguard", &"mender"], needs)
	_expect(
		vanguard_mender["uncovered"].is_empty()
		and vanguard_mender["covered"][&"interrupt"] == &"vanguard"
		and vanguard_mender["covered"][&"area"] == &"vanguard"
		and vanguard_mender["covered"][&"sustain"] == &"mender",
		"Vanguard + Mender covers interrupt, area, and sustain"
	)
	_expect(
		PartyNeeds.uncovered([&"vanguard", &"arcanist"], needs) == [&"sustain"]
		and PartyNeeds.covered([&"vanguard", &"arcanist"], needs)[&"area"] == &"vanguard",
		"Vanguard + Arcanist misses sustain; the first provider covers a shared need"
	)
	var arcanist_mender := PartyNeeds.evaluate([&"arcanist", &"mender"], needs)
	_expect(
		arcanist_mender["uncovered"] == [&"interrupt"]
		and arcanist_mender["covered"][&"area"] == &"arcanist"
		and arcanist_mender["covered"][&"sustain"] == &"mender",
		"Arcanist + Mender misses interrupt"
	)
	_expect(
		PartyNeeds.uncovered([&"vanguard", &"vanguard"], needs) == [&"sustain"],
		"Vanguard + Vanguard misses sustain"
	)
	_expect(
		PartyNeeds.uncovered([&"novice", &"novice"], needs) == [&"interrupt", &"area", &"sustain"]
		and PartyNeeds.uncovered([], needs) == [&"interrupt", &"area", &"sustain"]
		and PartyNeeds.uncovered([&"", &"novice"], needs).size() == 3,
		"Novice, empty, and no-echo parties cover nothing"
	)
	_expect(
		PartyNeeds.uncovered([&"vanguard"], needs) == [&"sustain"]
		and PartyNeeds.covered([&"vanguard"], needs).size() == 2,
		"A solo Vanguard covers interrupt and area only"
	)
	_expect(
		PartyNeeds.providers(&"sustain") == [&"mender"]
		and PartyNeeds.providers(&"area") == [&"vanguard", &"arcanist"]
		and PartyNeeds.providers(&"interrupt") == [&"vanguard"],
		"providers lists choosable jobs in choice order"
	)
	_expect(
		PartyNeeds.fill_annotation(&"mender", [&"sustain"]) == "Fills Trial need: SUSTAIN ★"
		and PartyNeeds.fill_annotation(&"vanguard", [&"sustain"]).is_empty()
		and PartyNeeds.fill_annotation(&"vanguard", [&"interrupt", &"area", &"sustain"])
			== "Fills Trial need: INTERRUPT · AREA ★",
		"fill_annotation names the uncovered needs a job fills"
	)
	_expect(
		PartyNeeds.missing_line(&"sustain") == "Missing: SUSTAIN → Mender provides SUSTAIN"
		and PartyNeeds.missing_line(&"area") == "Missing: AREA → Vanguard or Arcanist provides AREA",
		"missing_line names the providing job"
	)


func _test_catalog_data() -> void:
	var data := EncounterCatalog.get_encounter(&"bell_court")
	_expect(
		EncounterCatalog.has_encounter(&"bell_court")
		and not EncounterCatalog.has_encounter(&"nope")
		and EncounterCatalog.get_encounter(&"nope").is_empty()
		and EncounterCatalog.get_display_name(&"bell_court") == "Bell Court"
		and EncounterCatalog.get_trigger_level(&"bell_court") == 5
		and EncounterCatalog.get_needs(&"bell_court") == [&"interrupt", &"area", &"sustain"]
		and is_equal_approx(float(data["warning_duration"]), 3.0)
		and is_equal_approx(float(data["spawn_grace"]), 1.0)
		and int(data["seed"]) == 7117
		and EncounterCatalog.get_total_enemy_count(&"bell_court") == 11,
		"bell_court catalog entry matches the design"
	)
	var times: Array[float] = []
	for wave: Dictionary in data["waves"]:
		times.append(float(wave["time"]))
	_expect(times == [0.0, 4.0, 12.0], "bell_court waves run at 0, 4, and 12 seconds")
	for need: StringName in EncounterCatalog.get_needs(&"bell_court"):
		_expect(
			not PartyNeeds.providers(need).is_empty(),
			"every bell_court need has a choosable provider job: %s" % need
		)


func _test_trigger_conditions() -> void:
	var court := _make_court()
	var director: EncounterDirector = court[2]
	_expect(
		director.state == EncounterDirector.STATE_IDLE and director.armed,
		"director starts idle and armed"
	)
	_expect(not director.try_trigger(4, false, [&"vanguard"]), "level 4 does not trigger")
	_expect(not director.try_trigger(5, true, [&"vanguard"]), "a pending level choice blocks the trigger")
	_expect(director.state == EncounterDirector.STATE_IDLE, "blocked triggers leave the director idle")
	_expect(director.try_trigger(5, false, [&"vanguard"]), "level 5 with no pending choice triggers")
	_expect(
		director.state == EncounterDirector.STATE_WARNING and not director.armed,
		"triggering enters WARNING and disarms"
	)
	_expect(not director.try_trigger(9, false, [&"vanguard"]), "a running encounter does not re-trigger")
	_step_until(director, EncounterDirector.STATE_ACTIVE)
	_expect(not director.try_trigger(9, false, [&"vanguard"]), "an active encounter does not re-trigger")
	_clear_court(director)
	_expect(director.state == EncounterDirector.STATE_CLEARED, "setup: court cleared after waves")
	_expect(
		not director.try_trigger(9, false, [&"vanguard"]),
		"once cleared, the encounter does not trigger again in the same run"
	)
	director.reset_for_new_run()
	_expect(
		director.armed and director.try_trigger(5, false, [&"vanguard"]),
		"reset_for_new_run re-arms the trigger"
	)
	_free_court(court)


func _test_warning_phase_pauses_spawner() -> void:
	var court := _make_court()
	var spawner: EnemySpawner = court[1]
	var director: EncounterDirector = court[2]
	_make_hero(court[0], Vector2.ZERO)
	var xp := [0]
	spawner.enemy_defeated.connect(func(reward: int) -> void: xp[0] += reward)
	director.enemy_defeated.connect(func(reward: int) -> void: xp[0] += reward)
	var drifters := spawner.get_children()
	_expect(drifters.size() == 7, "setup: the arena spawner holds 7 drifters")
	director.start_encounter([&"vanguard"])
	var remaining := 0
	for child in spawner.get_children():
		if not child.is_queued_for_deletion():
			remaining += 1
	_expect(
		director.state == EncounterDirector.STATE_WARNING
		and is_equal_approx(director.state_time_left, 3.0)
		and spawner.target_population == 0
		and remaining == 0
		and xp[0] == 0
		and spawner.get_pending_respawn_count() == 0,
		"WARNING pauses the spawner and silently removes drifters with no XP"
	)
	for _frame in 170:
		director._physics_process(PHYSICS_STEP)
	_expect(
		director.state == EncounterDirector.STATE_WARNING
		and director.get_child_count() == 0
		and spawner.target_population == 0,
		"nothing spawns during the 3 second warning"
	)
	_step_until(director, EncounterDirector.STATE_ACTIVE)
	_expect(
		director.state == EncounterDirector.STATE_ACTIVE
		and director.get_child_count() == 3
		and spawner.target_population == 0,
		"ACTIVE spawns wave 0 while the spawner stays paused"
	)
	_free_court(court)


func _test_wave_timeline() -> void:
	var court := _make_court()
	var director: EncounterDirector = court[2]
	_make_hero(court[0], Vector2.ZERO)
	var data := EncounterCatalog.get_encounter(&"bell_court")
	var waves: Array = data["waves"]
	director.start_encounter([&"vanguard", &"mender"])
	_step_until(director, EncounterDirector.STATE_ACTIVE)
	var ids: Array[String] = []
	var positions: Array[Vector2] = []
	for enemy: EnemyActor in director.get_children():
		ids.append(String(enemy.enemy_id))
		positions.append(enemy.position)
	var expected_ids: Array[String] = []
	var expected_positions: Array[Vector2] = []
	for spawn: Dictionary in waves[0]["spawns"]:
		for _index in int(spawn["count"]):
			expected_ids.append(String(spawn["enemy_id"]))
			expected_positions.append(spawn["position"])
	_expect(
		ids == expected_ids and positions == expected_positions,
		"t=0 spawns two Brutes and a Hexcaller at the catalog positions"
	)
	var grace_ok := true
	for enemy: EnemyActor in director.get_children():
		grace_ok = grace_ok and is_equal_approx(enemy.spawn_grace, float(data["spawn_grace"]))
	_expect(grace_ok and director.waves_spawned == 1, "court enemies spawn with catalog spawn grace")
	var pack_a_time := float(waves[1]["time"])
	_step(director, _frames_until(director, pack_a_time) - 1)
	_expect(
		director.get_child_count() == 3 and director.waves_spawned == 1,
		"no skitters before t=%.0f s (elapsed %.3f)" % [pack_a_time, director.elapsed]
	)
	_step(director, 1)
	var pack_a := _skitters(director)
	var pack_a_center: Vector2 = waves[1]["spawns"][0]["position"]
	_expect(
		director.get_child_count() == 7
		and pack_a.size() == 4
		and director.waves_spawned == 2
		and pack_a[0].position == pack_a_center
		and _all_within(pack_a, pack_a_center, float(data["pack_jitter_radius"])),
		"t=%.0f s spawns skitter pack A (4) around the catalog position" % pack_a_time
	)
	var pack_b_time := float(waves[2]["time"])
	_step(director, _frames_until(director, pack_b_time) - 1)
	_expect(director.get_child_count() == 7, "no second pack before t=%.0f s" % pack_b_time)
	_step(director, 1)
	var skitters := _skitters(director)
	var pack_b := skitters.slice(4)
	var pack_b_center: Vector2 = waves[2]["spawns"][0]["position"]
	_expect(
		director.get_child_count() == 11
		and skitters.size() == 8
		and director.waves_spawned == 3
		and pack_b[0].position == pack_b_center
		and _all_within(pack_b, pack_b_center, float(data["pack_jitter_radius"])),
		"t=%.0f s spawns skitter pack B (4) around the catalog position" % pack_b_time
	)
	_free_court(court)


func _test_clear_resumes_spawner() -> void:
	var court := _make_court()
	var spawner: EnemySpawner = court[1]
	var director: EncounterDirector = court[2]
	_make_hero(court[0], Vector2.ZERO)
	var xp := [0]
	var reports: Array[Dictionary] = []
	var waves: Array = EncounterCatalog.get_encounter(&"bell_court")["waves"]
	director.enemy_defeated.connect(func(reward: int) -> void: xp[0] += reward)
	director.report_ready.connect(func(report: Dictionary) -> void: reports.append(report))
	director.start_encounter([&"vanguard", &"mender"])
	_step_until(director, EncounterDirector.STATE_ACTIVE)
	_defeat_all(director)
	_step(director, 5)
	_expect(
		director.state == EncounterDirector.STATE_ACTIVE and xp[0] == 220,
		"killing wave 0 does not clear while skitter waves remain (xp %d)" % xp[0]
	)
	_step(director, _frames_until(director, float(waves[1]["time"])))
	_defeat_all(director)
	_step(director, _frames_until(director, float(waves[2]["time"])))
	_expect(
		director.state == EncounterDirector.STATE_ACTIVE and director.waves_spawned == 3,
		"all waves spawned but the last pack is still alive"
	)
	_defeat_all(director)
	_expect(
		director.state == EncounterDirector.STATE_ACTIVE,
		"CLEARED waits for the next director tick"
	)
	_step(director, 1)
	_expect(
		director.state == EncounterDirector.STATE_CLEARED
		and director.outcome == &"cleared"
		and spawner.target_population == 7
		and xp[0] == 300
		and reports.size() == 1
		and reports[0]["outcome"] == "cleared"
		and is_equal_approx(float(reports[0]["time"]), director.elapsed),
		"clearing every wave resumes the spawner, awards ~300 XP, and emits one report"
	)
	_step(director, 30)
	_expect(reports.size() == 1, "a cleared court reports exactly once")
	_free_court(court)


func _test_spawn_order_and_determinism() -> void:
	var first := _positions_and_seeds()
	var second := _positions_and_seeds()
	_expect(
		first["orders"] == [1000001, 1000002, 1000003]
		and first["names"] == ["Court1", "Court2", "Court3"]
		and first["all_orders"].size() == 11
		and first["all_orders"][10] == 1000011,
		"court enemies number from 1_000_001 in spawn order"
	)
	_expect(
		first["positions"] == second["positions"] and first["seeds"] == second["seeds"],
		"the director's seeded RNG gives identical pack jitter and enemy seeds"
	)


func _positions_and_seeds() -> Dictionary:
	var court := _make_court()
	var director: EncounterDirector = court[2]
	_make_hero(court[0], Vector2.ZERO)
	director.start_encounter([&"vanguard"])
	_step_until(director, EncounterDirector.STATE_ACTIVE)
	var orders: Array[int] = []
	var names: Array[String] = []
	for enemy: EnemyActor in director.get_children():
		orders.append(enemy.stable_spawn_order)
		names.append(String(enemy.name))
	_step(director, 1440)
	var all_orders: Array[int] = []
	var positions: Array[Vector2] = []
	var seeds: Array[int] = []
	for enemy: EnemyActor in director.get_children():
		all_orders.append(enemy.stable_spawn_order)
		positions.append(enemy.position)
		seeds.append(enemy.simulation_seed)
	_free_court(court)
	return {
		"orders": orders,
		"names": names,
		"all_orders": all_orders,
		"positions": positions,
		"seeds": seeds,
	}


func _test_counter_attribution() -> void:
	var court := _make_court()
	var director: EncounterDirector = court[2]
	var hero := _make_hero(court[0], Vector2(0.0, -200.0))
	var echo := _make_echo(court[0], hero, Vector2(40.0, -200.0))
	director.start_encounter([&"vanguard", &"mender"])
	_expect(director.had_echo and director.echo_survived, "the director notes the echo at trigger")
	_step_until(director, EncounterDirector.STATE_ACTIVE)
	var hexcaller: EnemyActor
	var brute: EnemyActor
	for enemy: EnemyActor in director.get_children():
		if enemy.enemy_id == &"hexcaller":
			hexcaller = enemy
		elif brute == null:
			brute = enemy
		enemy.spawn_grace = 0.0

	_begin_cast(hexcaller)
	_expect(hexcaller.is_casting(), "setup: the court Hexcaller starts a cast")
	hexcaller.take_damage(25.0, true)
	_expect(
		director.casts_broken == 1 and director.casts_landed == 0,
		"an interrupted cast counts as broken"
	)
	hexcaller.state = &"kite"
	hexcaller.state_time_left = 0.0
	_begin_cast(hexcaller)
	hexcaller.state_time_left = 0.0
	hexcaller._physics_process(PHYSICS_STEP)
	_expect(
		director.casts_landed == 1 and director.casts_broken == 1,
		"a resolved cast counts as landed"
	)
	var hexcaller_damage: Dictionary = director.damage_taken.get("hexcaller", {})
	_expect(
		is_equal_approx(float(hexcaller_damage.get("hero", 0.0)), 55.0)
		and is_equal_approx(float(hexcaller_damage.get("echo", 0.0)), 55.0),
		"the circle's damage is split hero and echo under the Hexcaller: %s" % [hexcaller_damage]
	)
	brute.dealt_damage.emit(&"brute", echo, 30.0)
	brute.dealt_damage.emit(&"brute", hero, 12.0)
	brute.dealt_damage.emit(&"brute", hero, 0.0)
	brute.dealt_damage.emit(&"brute", echo, 8.0)
	var brute_damage: Dictionary = director.damage_taken.get("brute", {})
	_expect(
		is_equal_approx(float(brute_damage.get("hero", 0.0)), 12.0)
		and is_equal_approx(float(brute_damage.get("echo", 0.0)), 38.0),
		"damage accumulates per enemy id and target side: %s" % [brute_damage]
	)

	hero.total_healing_done += 25.0
	echo.total_healing_done += 15.0
	_step(director, 1)
	_expect(is_equal_approx(director.healing_done, 40.0), "healing sums both actors' totals")
	echo.is_defeated = true
	echo.total_healing_done = 0.0
	hero.total_healing_done += 10.0
	_step(director, 1)
	_expect(
		is_equal_approx(director.healing_done, 50.0) and not director.echo_survived,
		"healing never decreases when an actor resets, and a defeated echo is noted"
	)
	var report := director.build_report()
	_expect(
		report["casts_landed"] == 1
		and report["casts_broken"] == 1
		and report["had_echo"]
		and not report["echo_survived"]
		and is_equal_approx(float(report["healing_done"]), 50.0)
		and report["damage_taken"]["brute"]["echo"] == 38.0
		and report["uncovered"].is_empty()
		and report["party_jobs"] == ["vanguard", "mender"],
		"build_report snapshots the counters as plain data"
	)
	_free_court(court)


func _test_reset_and_failure_report() -> void:
	var court := _make_court()
	var spawner: EnemySpawner = court[1]
	var director: EncounterDirector = court[2]
	var hero := _make_hero(court[0], Vector2.ZERO)
	var echo := _make_echo(court[0], hero, Vector2(40.0, 0.0))
	var reports: Array[Dictionary] = []
	director.report_ready.connect(func(report: Dictionary) -> void: reports.append(report))
	director.reset_for_new_run()
	_expect(reports.is_empty() and director.armed, "resetting an idle director reports nothing")
	director.start_encounter([&"vanguard", &"arcanist"])
	_step_until(director, EncounterDirector.STATE_ACTIVE)
	_step(director, 120)
	_expect(director.get_child_count() == 3 and spawner.target_population == 0, "setup: court is active")
	director.reset_for_new_run()
	_expect(
		director.get_child_count() == 0
		and director.state == EncounterDirector.STATE_IDLE
		and director.armed
		and spawner.target_population == 7
		and director.waves_spawned == 0
		and is_zero_approx(director.elapsed)
		and director.casts_landed == 0
		and director.damage_taken.is_empty(),
		"reset_for_new_run frees the director's enemies, resumes spawning, re-arms, and clears counters"
	)
	_expect(
		reports.size() == 1
		and reports[0]["outcome"] == "failed"
		and reports[0]["echo_survived"]
		and reports[0]["uncovered"] == ["sustain"]
		and director.last_report["outcome"] == "failed",
		"a reset mid-court emits a failed report that survives the reset"
	)
	_expect(director.try_trigger(5, false, [&"vanguard"]), "the re-armed director can trigger again")
	director.reset_for_new_run()
	_expect(
		reports.size() == 2 and spawner.target_population == 7,
		"a reset during WARNING also fails and restores the spawner"
	)
	echo.free()
	_free_court(court)


func _test_modal_annotations() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	main.apply_scenario(&"vanguard", &"mender", 3, &"")
	main.progression = _level_three_progression()
	main._show_next_choice_if_needed()
	_expect(
		main.choice_modal.visible
		and main.choice_one_button.text.ends_with("\nFills Trial need: INTERRUPT · AREA ★")
		and main.choice_two_button.text.ends_with("\nFills Trial need: AREA ★")
		and not main.choice_three_button.text.contains("★"),
		"Mender echo: Vanguard and Arcanist get ★, Mender does not: %s | %s | %s" % [
			main.choice_one_button.text.replace("\n", " / "),
			main.choice_two_button.text.replace("\n", " / "),
			main.choice_three_button.text.replace("\n", " / "),
		]
	)
	main.apply_scenario(&"vanguard", &"vanguard", 3, &"")
	main.progression = _level_three_progression()
	main._show_next_choice_if_needed()
	_expect(
		not main.choice_one_button.text.contains("★")
		and not main.choice_two_button.text.contains("★")
		and main.choice_three_button.text.ends_with("\nFills Trial need: SUSTAIN ★"),
		"Vanguard echo: only Mender is starred"
	)
	main.apply_scenario(&"vanguard", &"", 3, &"")
	main.progression = _level_three_progression()
	main._show_next_choice_if_needed()
	_expect(
		main.choice_one_button.text.contains("INTERRUPT · AREA ★")
		and main.choice_two_button.text.contains("AREA ★")
		and main.choice_three_button.text.contains("SUSTAIN ★")
		and main.choice_one_button.text.begins_with("[1] VANGUARD\nSword and Lance"),
		"no echo: every option is starred for the needs it covers"
	)
	main.free()
	paused = false


func _test_trial_hud_and_report() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	main._update_trial_hud()
	_expect(
		main.trial_panel.visible
		and main.trial_title.text == "TRIAL · Bell Court · Lv 5"
		and main._trial_chip_labels.size() == 3
		and main._trial_chip_labels[0].text == "✗ INTERRUPT\nMissing"
		and main._trial_chip_labels[1].text == "✗ AREA\nMissing"
		and main._trial_chip_labels[2].text == "✗ SUSTAIN\nMissing",
		"run 1 with no echo shows every need uncovered from run start"
	)
	main.apply_scenario(&"vanguard", &"mender", 5, &"")
	main._update_trial_hud()
	_expect(
		main._trial_chip_labels[0].text == "✓ INTERRUPT\nVanguard"
		and main._trial_chip_labels[1].text == "✓ AREA\nVanguard"
		and main._trial_chip_labels[2].text == "✓ SUSTAIN\nMender",
		"echo job plus active hero job cover all three needs"
	)
	main.progression = HeroProgression.new()
	main._update_trial_hud()
	_expect(
		main._trial_chip_labels[0].text.begins_with("✗")
		and main._trial_chip_labels[1].text.begins_with("✗")
		and main._trial_chip_labels[2].text == "✓ SUSTAIN\nMender",
		"before the active hero chooses a job only the echo's job counts"
	)

	var report := {
		"display_name": "Bell Court",
		"outcome": "failed",
		"time": 14.6,
		"casts_landed": 2,
		"casts_broken": 1,
		"damage_taken": {
			"hexcaller": {"hero": 45.0, "echo": 45.0},
			"brute": {"hero": 40.0, "echo": 0.0},
		},
		"healing_done": 0.0,
		"had_echo": true,
		"echo_survived": false,
		"uncovered": ["sustain"],
	}
	main._on_trial_report_ready(report)
	_expect(
		main.trial_report.visible
		and main.trial_report_title.text == "BELL COURT — FAILED · 14 s"
		and main.trial_report_body.text == "\n".join([
			"Casts: 2 landed · 1 broken",
			"Damage taken:",
			"  Brute — Hero 40 · Echo 0",
			"  Hexcaller — Hero 45 · Echo 45",
			"Healing done: 0",
			"Echo: defeated",
			"Missing: SUSTAIN → Mender provides SUSTAIN",
		]),
		"the report lists casts, per-enemy damage, healing, echo fate, and Missing lines:\n%s" % [
			main.trial_report_body.text
		]
	)
	var mcp: Dictionary = main._mcp_state()
	_expect(
		mcp["trial_report_visible"]
		and String(mcp["trial_report_text"]).contains("Missing: SUSTAIN → Mender provides SUSTAIN")
		and String(mcp["trial_panel_text"]).contains("TRIAL · Bell Court · Lv 5")
		and not mcp["trial_banner_visible"],
		"_mcp_state exposes the Trial panel, banner, and report"
	)
	main._update_encounter(9.0)
	_expect(main.trial_report.visible, "the report is still visible after 9 seconds")
	main._update_encounter(1.5)
	_expect(not main.trial_report.visible, "the report hides after 10 seconds")

	var clean := report.duplicate(true)
	clean["outcome"] = "cleared"
	clean["uncovered"] = []
	clean["had_echo"] = false
	clean["damage_taken"] = {}
	var body: String = MainScript.format_trial_report_body(clean)
	_expect(
		body.contains("Damage taken: none")
		and body.contains("Echo: none")
		and body.contains("All needs covered ✓")
		and not body.contains("Missing"),
		"a clean solo report omits Missing lines"
	)
	main.free()
	paused = false


func _test_scenario_hook_and_main_trigger() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	var director: EncounterDirector = main.encounter_director
	_expect(
		not main.apply_scenario(&"vanguard", &"", 5, &"no_such_court")
		and director.state == EncounterDirector.STATE_IDLE,
		"an unknown encounter id fails the scenario without side effects"
	)
	_expect(
		main.apply_scenario(&"vanguard", &"", 5, &"")
		and not director.armed
		and not director.try_trigger(5, false, [&"vanguard"]),
		"setup: an empty encounter id disarms the director"
	)
	main._update_encounter(0.0)
	_expect(
		director.state == EncounterDirector.STATE_IDLE,
		"a level-5 scenario with no encounter id never starts the court by itself"
	)
	director.reset_for_new_run()

	var spawner := main.get_node("Enemies") as EnemySpawner
	_expect(
		main.apply_scenario(&"vanguard", &"", 5, &"bell_court")
		and director.state == EncounterDirector.STATE_WARNING
		and is_equal_approx(director.state_time_left, 3.0)
		and spawner.target_population == 0
		and not director.had_echo
		and director.party_jobs == [&"vanguard"],
		"a bell_court scenario skips the level trigger but still goes through WARNING, with no echo"
	)
	main._update_trial_hud()
	var mcp: Dictionary = main._mcp_state()
	_expect(
		mcp["director_state"] == "warning"
		and mcp["trial_banner_visible"]
		and String(mcp["trial_banner_text"]).begins_with("THE BELL COURT\nNeeds: Interrupt · Area · Sustain")
		and String(mcp["trial_banner_text"]).ends_with("Begins in 3.0 s")
		and mcp["director"]["state"] == "warning"
		and mcp["director"]["alive_enemies"] == 0,
		"the WARNING banner and director state appear in _mcp_state: %s" % [mcp["trial_banner_text"]]
	)
	_step(director, 181)
	main._update_trial_hud()
	_expect(
		director.state == EncounterDirector.STATE_ACTIVE
		and not main.trial_banner.visible
		and main.trial_status.text.begins_with("Court in progress")
		and director.get_child_count() == 3,
		"the banner hides once the court is ACTIVE"
	)
	# A court enemy's defeat flows through the same XP handler as arena enemies.
	var xp_before: int = main.progression.experience
	for enemy: EnemyActor in director.get_children():
		enemy.spawn_grace = 0.0
		enemy.take_damage(1000.0)
	_expect(main.progression.experience > xp_before, "court kills grant XP through Main")
	main.free()
	paused = false

	main = MainScene.instantiate()
	root.add_child(main)
	director = main.encounter_director
	main.progression = HeroProgression.new()
	main.progression.grant_experience(400)
	main._update_encounter(0.0)
	_expect(
		director.state == EncounterDirector.STATE_IDLE,
		"level 5 with every level choice still pending does not trigger"
	)
	main.progression = main._build_scenario_progression(&"vanguard", 4)
	main._update_encounter(0.0)
	_expect(director.state == EncounterDirector.STATE_IDLE, "level 4 does not trigger")
	main.progression = main._build_scenario_progression(&"vanguard", 5)
	main._update_encounter(0.0)
	_expect(
		director.state == EncounterDirector.STATE_WARNING
		and main.trial_banner.visible
		and director.party_jobs == [&"vanguard"],
		"level 5 with the choices applied triggers the court from Main"
	)
	main._update_encounter(0.0)
	_expect(director.state == EncounterDirector.STATE_WARNING, "Main does not re-trigger a running court")
	# Failure path: the active hero dies mid-court and the next run shows the report.
	main._start_next_run()
	_expect(
		director.state == EncounterDirector.STATE_IDLE
		and director.armed
		and main.trial_report.visible
		and main.trial_report_title.text.contains("FAILED")
		and main.trial_report_body.text.contains("Missing: SUSTAIN → Mender provides SUSTAIN")
		and main.trial_report_body.text.contains("Echo: none"),
		"dying mid-court resets the director and shows the failure report at the next run start"
	)
	main.free()
	paused = false


func _make_court() -> Array:
	var arena := Node2D.new()
	root.add_child(arena)
	var spawner := EnemySpawner.new()
	spawner.name = "Enemies"
	arena.add_child(spawner)
	var director := EncounterDirector.new()
	director.name = "EncounterDirector"
	director.set_physics_process(false)
	arena.add_child(director)
	return [arena, spawner, director]


func _free_court(court: Array) -> void:
	(court[0] as Node).free()


func _make_hero(arena: Node, hero_position: Vector2) -> HeroActor:
	var hero := HeroActor.new()
	hero.name = "Hero"
	hero.position = hero_position
	hero.set_physics_process(false)
	arena.add_child(hero)
	hero.add_to_group(&"friendly_actors")
	return hero


func _make_echo(arena: Node, active: Node2D, echo_position: Vector2) -> EchoActor:
	var progression := HeroProgression.new()
	progression.grant_experience(200)
	progression.apply_attribute_choice(2, HeroProgression.ATTRIBUTE_MIGHT)
	progression.apply_job_choice(3, HeroProgression.JOB_MENDER)
	var echo := EchoScene.instantiate() as EchoActor
	echo.set_physics_process(false)
	echo.position = echo_position
	arena.add_child(echo)
	echo.configure(HeroRecord.capture("court-test", "Court Test", progression), active)
	echo.grant_shared_experience(200)
	echo.invulnerability_time_left = 0.0
	return echo


func _step(director: EncounterDirector, frames: int) -> void:
	for _frame in frames:
		director._physics_process(PHYSICS_STEP)


func _frames_until(director: EncounterDirector, time: float) -> int:
	return maxi(int(roundi((time - director.elapsed) / PHYSICS_STEP)), 0)


func _step_until(director: EncounterDirector, target_state: StringName) -> void:
	var guard := 0
	while director.state != target_state and guard < 600:
		director._physics_process(PHYSICS_STEP)
		guard += 1


## Defeats every living court enemy through the real damage path.
func _defeat_all(director: EncounterDirector) -> void:
	for enemy: EnemyActor in director.get_children():
		if enemy.is_queued_for_deletion():
			continue
		enemy.spawn_grace = 0.0
		enemy.take_damage(1000.0)


## Steps and kills until every wave has spawned and the director clears.
func _clear_court(director: EncounterDirector) -> void:
	var guard := 0
	while director.state == EncounterDirector.STATE_ACTIVE and guard < 3000:
		_defeat_all(director)
		director._physics_process(PHYSICS_STEP)
		guard += 1


func _skitters(director: EncounterDirector) -> Array[EnemyActor]:
	var result: Array[EnemyActor] = []
	for enemy: EnemyActor in director.get_children():
		if enemy.enemy_id == &"skitter":
			result.append(enemy)
	return result


func _all_within(enemies: Array, center: Vector2, radius: float) -> bool:
	for enemy: EnemyActor in enemies:
		if enemy.position.distance_to(center) > radius + 0.001:
			return false
	return true


func _begin_cast(hexcaller: EnemyActor) -> void:
	hexcaller.spawn_grace = 0.0
	hexcaller.cast_cooldown_left = 0.0
	hexcaller.state = &"kite"
	hexcaller._physics_process(PHYSICS_STEP)


func _level_three_progression() -> HeroProgression:
	var progression := HeroProgression.new()
	progression.grant_experience(200)
	progression.apply_attribute_choice(2, HeroProgression.ATTRIBUTE_MIGHT)
	return progression


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
