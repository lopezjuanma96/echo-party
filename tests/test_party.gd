extends SceneTree


const MainScene := preload("res://src/main/main.tscn")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_run_tests")


func _run_tests() -> void:
	_test_address_cycling_and_clamping()
	_test_all_hold_semantics()
	_test_spawn_order_identity_and_offsets()
	_test_focus_addressing_and_snap_back()
	_test_all_focus_and_regroup()
	_test_full_experience_sharing()
	_test_per_slot_defeat_and_experience()
	_test_roster_coverage_order()
	_test_multi_echo_trial_report()
	_test_addressed_hold_toggles()
	_test_report_keeps_real_slot()
	_test_default_candidate_placement()
	_test_mcp_state_is_plain()
	await _test_two_row_hud_layout()

	if _failures.is_empty():
		print("Multi-echo party, command, XP, coverage, and HUD tests passed (14 cases).")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_address_cycling_and_clamping() -> void:
	var commander := PartyCommander.new()
	commander.cycle_address(1, 2)
	_expect(commander.address == 0, "wheel forward addresses Echo 1 first")
	commander.cycle_address(1, 2)
	_expect(commander.address == 1, "wheel forward addresses Echo 2 second")
	commander.cycle_address(1, 2)
	_expect(commander.address == PartyCommander.ADDRESS_ALL, "wheel forward returns to All")
	commander.cycle_address(-1, 2)
	_expect(commander.address == 1, "wheel backward wraps from All to Echo 2")
	commander.on_echoes_changed(1)
	_expect(commander.address == PartyCommander.ADDRESS_ALL, "removing the addressed slot clamps to All")
	commander.cycle_address(1, 0)
	_expect(commander.address == PartyCommander.ADDRESS_ALL, "an empty party only supports All")


func _test_all_hold_semantics() -> void:
	var commander := PartyCommander.new()
	var echoes: Array[EchoActor] = [EchoActor.new(), EchoActor.new()]
	echoes[0].slot_index = 0
	echoes[1].slot_index = 1
	echoes[0].is_holding_position = true
	_expect(
		commander.toggle_hold(echoes)
		and echoes[0].is_holding_position
		and echoes[1].is_holding_position,
		"All with mixed stances holds every echo"
	)
	_expect(
		not commander.toggle_hold(echoes)
		and not echoes[0].is_holding_position
		and not echoes[1].is_holding_position,
		"All with every echo holding releases every echo"
	)
	_expect(
		commander.address == PartyCommander.ADDRESS_ALL
		and commander.last_command.get("verb") == "hold"
		and commander.last_command.get("address") == PartyCommander.ADDRESS_ALL
		and commander.last_command.get("target") == ""
		and commander.last_command.get("tick") is int,
		"hold snaps back and records a plain last-command dictionary"
	)
	for echo in echoes:
		echo.free()


func _test_spawn_order_identity_and_offsets() -> void:
	var main := _two_echo_main(5, &"")
	_expect(
		main.echoes.size() == 2
		and main.echo == main.echoes[0]
		and main.latest_echo_record == main.roster.party[0]
		and main.echoes[0].slot_index == 0
		and main.echoes[1].slot_index == 1
		and main.echoes[0].job_id == HeroProgression.JOB_MENDER
		and main.echoes[1].job_id == HeroProgression.JOB_ARCANIST
		and main.echoes[0].progression.level == 5
		and main.echoes[1].progression.level == 5,
		"two records spawn in slot order with their jobs and levels; compatibility aliases remain valid"
	)
	_expect(
		main.echoes[0].position == Vector2(92.0, 0.0)
		and main.echoes[1].position == Vector2(-92.0, 0.0)
		and main.echoes[0].position.distance_to(main.echoes[1].position) >= 40.0,
		"fixed per-slot follow anchors keep idle echoes at least 40 px apart"
	)
	_expect(
		(main.echoes[0].get_node("EchoLabel") as Label).text == "ECHO 1 · Lv 5"
		and (main.echoes[1].get_node("EchoLabel") as Label).text == "ECHO 2 · Lv 5"
		and (main.echoes[1].get_node("EchoLabel") as Label).offset_top
			< (main.echoes[0].get_node("EchoLabel") as Label).offset_top - 20.0
		and main.focus_markers[0].slot_index == 0
		and main.focus_markers[1].slot_index == 1,
		"world labels and focus markers identify slots without relying on colour"
	)
	main.party_commander.cycle_address(1, 2)
	main._update_run_hud()
	_expect(
		main.echo_value.text.begins_with("▶ Echo 1: Mender")
		and main.echo_2_value.text.begins_with("Echo 2: Arcanist"),
		"the HUD prefixes only the addressed echo with an arrow"
	)
	main.free()


func _test_focus_addressing_and_snap_back() -> void:
	var main := _two_echo_main(5, &"")
	var target := main.get_node("Enemies").get_child(0) as Node2D
	target.position = Vector2(200.0, 0.0)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	main._unhandled_input(wheel)
	_expect(main.party_commander.address == 0, "the wheel input action selects Echo 1")
	var accepted: int = main.command_echo_focus_at(target.global_position)
	_expect(
		accepted == 1
		and main.echoes[0].focused_target == target
		and main.echoes[1].focused_target == null
		and main.party_commander.address == PartyCommander.ADDRESS_ALL,
		"addressed focus affects only Echo 1 and snaps back to All"
	)
	_expect(
		main.party_commander.last_command.get("address") == 0
		and main.party_commander.last_command.get("verb") == "focus"
		and main.party_commander.last_command.get("target") == str(target.stable_spawn_order),
		"focus logs its original address and stable target order as a string"
	)
	main._process(0.0)
	_expect(
		main.focus_marker.target == target and main.focus_markers[1].target == null,
		"only the addressed echo's marker follows the target"
	)
	_expect(
		InputMap.action_get_events(&"weapon_previous").is_empty()
		and InputMap.action_get_events(&"weapon_next").is_empty()
		and not InputMap.action_get_events(&"weapon_slot_1").is_empty()
		and not InputMap.action_get_events(&"weapon_slot_2").is_empty(),
		"the wheel leaves weapon cycling while number-key weapon slots remain bound"
	)
	main.free()


func _test_all_focus_and_regroup() -> void:
	var main := _two_echo_main(5, &"")
	var target := main.get_node("Enemies").get_child(0) as Node2D
	target.position = Vector2(200.0, 0.0)
	_expect(
		main.command_echo_focus_at(target.global_position) == 2
		and main.echoes[0].focused_target == target
		and main.echoes[1].focused_target == target,
		"All focus commands both echoes"
	)
	_expect(
		main.party_commander.regroup(main.echoes) == 2
		and main.echoes[0].is_regrouping
		and main.echoes[1].is_regrouping
		and main.echoes[0].focused_target == null
		and main.echoes[1].focused_target == null,
		"All regroup clears focus and regroups both echoes"
	)
	main.free()


func _test_full_experience_sharing() -> void:
	var main := _unreplayed_two_echo_main()
	main._on_enemy_defeated(400)
	_expect(
		main.progression.experience == 400
		and main.echoes[0].progression.experience == 400
		and main.echoes[1].progression.experience == 400,
		"one kill grants its full reward once to the hero and both echoes"
	)
	main.free()
	paused = false


func _test_per_slot_defeat_and_experience() -> void:
	var main := _unreplayed_two_echo_main()
	main.party_commander.address = 0
	main.echoes[0].invulnerability_time_left = 0.0
	main.echoes[0].take_damage(10000.0)
	_expect(
		main.echo == null
		and main.echoes.size() == 2
		and is_instance_valid(main.echoes[1])
		and main.echoes[1].slot_index == 1
		and main.party_commander.address == PartyCommander.ADDRESS_ALL
		and main.echo_value.text == "Echo 1: Defeated"
		and main.echo_2_value.text.begins_with("Echo 2:"),
		"defeating Echo 1 preserves Echo 2's slot and resets its address"
	)
	main._on_enemy_defeated(400)
	_expect(
		main.progression.experience == 400
		and main.echoes[1].progression.experience == 400,
		"a defeated echo stops receiving XP while the hero and living echo continue"
	)
	main.free()
	paused = false


func _test_roster_coverage_order() -> void:
	var main := MainScene.instantiate()
	main.party_slots = 2
	root.add_child(main)
	var jobs: Array[StringName] = [&"mender", &"vanguard"]
	var levels: Array[int] = [5, 5]
	_expect(
		main.apply_scenario(&"", &"", 1, &"", jobs, levels),
		"a scenario can pair a level-1 Novice hero with recorded job echoes"
	)
	_expect(
		main._party_job_ids() == [&"mender", &"vanguard", &"novice"]
		and PartyNeeds.uncovered(main._party_job_ids(), EncounterCatalog.get_needs(&"bell_court")).is_empty()
		and main._trial_chip_labels[0].text == "✓ INTERRUPT\nVanguard"
		and main._trial_chip_labels[1].text == "✓ AREA\nVanguard"
		and main._trial_chip_labels[2].text == "✓ SUSTAIN\nMender",
		"coverage uses recorded echo jobs in slot order, then the hero, and covers all Court needs"
	)
	main.free()


func _test_multi_echo_trial_report() -> void:
	var main := _two_echo_main(5, &"bell_court")
	var director := main.encounter_director as EncounterDirector
	main.echoes[0].invulnerability_time_left = 0.0
	main.echoes[0].take_damage(10000.0)
	director._track_party()
	var report := director.build_report()
	_expect(
		report["had_echo"]
		and not report["echo_survived"]
		and report["echoes"] == [
			{"slot": 1, "job_id": "mender", "survived": false},
			{"slot": 2, "job_id": "arcanist", "survived": true},
		],
		"the director records each echo's slot, recorded job, and survival"
	)
	var body: String = main.format_trial_report_body(report)
	_expect(
		body.contains("Echo 1 Mender: defeated")
		and body.contains("Echo 2 Arcanist: survived"),
		"the Trial report names both echoes and their outcomes"
	)
	main.free()


func _test_default_candidate_placement() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	main.progression = main._build_scenario_progression(&"mender", 3)
	main._start_next_run()
	main.resolve_default()
	_expect(
		main.roster.party.size() == 1
		and main.roster.memorial.is_empty()
		and main.roster.party[0].replay_progression().get_job_id() == HeroProgression.JOB_MENDER
		and main.echo.progression.level == 1
		and main.echo.job_id == HeroProgression.JOB_NOVICE,
		"the first qualified fallen hero takes the party slot and starts replaying at level 1"
	)
	main.progression = main._build_scenario_progression(&"vanguard", 3)
	main._start_next_run()
	main.resolve_default()
	_expect(
		main.roster.party.size() == 1
		and main.roster.party[0].replay_progression().get_job_id() == HeroProgression.JOB_MENDER
		and main.roster.memorial.size() == 1
		and main.roster.memorial[0].replay_progression().get_job_id() == HeroProgression.JOB_VANGUARD,
		"the next candidate takes the first empty memorial slot"
	)
	main.progression = main._build_scenario_progression(&"arcanist", 3)
	main._start_next_run()
	main.resolve_default()
	_expect(
		main.roster.party[0].replay_progression().get_job_id() == HeroProgression.JOB_ARCANIST
		and main.roster.memorial[0].replay_progression().get_job_id() == HeroProgression.JOB_VANGUARD,
		"a full in-memory roster replaces party slot 1 by default"
	)
	main.free()


func _test_mcp_state_is_plain() -> void:
	var main := _two_echo_main(5, &"")
	main.party_commander.cycle_address(1, 2)
	var selected_state: Dictionary = main._mcp_state()
	_expect(
		selected_state["address"] == 0
		and selected_state["address_label"] == "Echo 1 · Mender",
		"MCP state exposes the selected slot and readable address label"
	)
	var target := main.get_node("Enemies").get_child(0) as Node2D
	target.position = Vector2(200.0, 0.0)
	main.command_echo_focus_at(target.global_position)
	var state: Dictionary = main._mcp_state()
	_expect(
		state["echo_count"] == 2
		and state["echoes"].size() == 2
		and state["echoes"][0]["slot"] == 1
		and state["echoes"][1]["slot"] == 2
		and state["party_slots"] == 2
		and state["roster_party"] == [
			{"id": "scenario-echo-1", "name": "Hero 1", "job_id": "mender", "level": 5},
			{"id": "scenario-echo-2", "name": "Hero 2", "job_id": "arcanist", "level": 5},
		]
		and state["last_command"]["verb"] == "focus",
		"MCP state exposes live echoes, roster records, party capacity, and the last command"
	)
	_expect(_is_plain(state), "Main and nested echo/director MCP state contains only plain serialized types")
	main.echoes[0].current_target = target
	target.free()
	var freed_target_state: Dictionary = main._mcp_state()
	_expect(
		not freed_target_state["echoes"][0]["target_is_casting"]
		and freed_target_state["echoes"][0]["current_target"] == "",
		"MCP serialization ignores a target freed before the state snapshot"
	)
	main.free()


func _test_two_row_hud_layout() -> void:
	root.size = Vector2i(1280, 720)
	var main := _two_echo_main(5, &"")
	current_scene = main
	await process_frame
	await process_frame
	var instructions := main.get_node("HUD/Instructions") as Control
	var run_status := main.get_node("HUD/RunStatus") as Control
	var progression := main.get_node("HUD/Progression") as Control
	_expect(
		instructions.get_rect().end.y + 12.0 <= run_status.get_rect().position.y
		and run_status.get_rect().end.y + 12.0 <= progression.get_rect().position.y
		and progression.get_rect().end.y <= root.size.y,
		"two echo rows retain 12 px gaps and keep the left HUD inside 720 px: %s / %s / %s" % [
			instructions.get_rect(), run_status.get_rect(), progression.get_rect(),
		]
	)
	_expect(
		run_status.get_rect().size.y >= run_status.get_combined_minimum_size().y
		and main.echo_2_value.visible
		and main.echo_2_command_value.visible
		and main.echo_2_intent_value.visible
		and main.echo_2_cooldowns_value.visible,
		"RunStatus fits both complete echo blocks and shows unlocked slot 2"
	)
	current_scene = null
	main.free()


func _two_echo_main(level: int, encounter_id: StringName) -> Node:
	var main := MainScene.instantiate()
	main.party_slots = 2
	root.add_child(main)
	var jobs: Array[StringName] = [&"mender", &"arcanist"]
	var levels: Array[int] = [level, level]
	main.apply_scenario(&"vanguard", &"", level, encounter_id, jobs, levels)
	return main


func _unreplayed_two_echo_main() -> Node:
	var main := MainScene.instantiate()
	main.party_slots = 2
	root.add_child(main)
	main.roster = Roster.new(2, RosterCapacity.BASE_MEMORIAL_SLOTS)
	var jobs: Array[StringName] = [&"mender", &"arcanist"]
	for index in jobs.size():
		var recorded: HeroProgression = main._build_scenario_progression(jobs[index], 5)
		main.roster.party.append(HeroRecord.capture(
			"party-test-%d" % (index + 1),
			"Hero %d" % (index + 1),
			recorded
		))
	main._spawn_party()
	return main


func _is_plain(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return true
		TYPE_ARRAY:
			for item: Variant in value:
				if not _is_plain(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not key is String or not _is_plain(value[key]):
					return false
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_addressed_hold_toggles() -> void:
	var commander := PartyCommander.new()
	var echoes: Array[EchoActor] = [EchoActor.new(), EchoActor.new()]
	echoes[0].slot_index = 0
	echoes[1].slot_index = 1
	commander.cycle_address(1, 2)
	commander.toggle_hold(echoes)
	commander.cycle_address(1, 2)
	var released := not commander.toggle_hold(echoes)
	_expect(
		released
		and not echoes[0].is_holding_position
		and not echoes[1].is_holding_position,
		"addressing one echo twice with hold holds it and then releases it"
	)
	for echo in echoes:
		echo.free()


func _test_report_keeps_real_slot() -> void:
	var main := _two_echo_main(5, &"")
	var director := main.encounter_director as EncounterDirector
	main.echoes[0].free()
	director.start_encounter(main._party_job_ids(), &"bell_court")
	var report := director.build_report()
	_expect(
		report["echoes"] == [{"slot": 2, "job_id": "arcanist", "survived": true}],
		"a Trial started after echo 1 fell still reports the survivor as Echo 2: %s" % str(report["echoes"])
	)
	main.free()
