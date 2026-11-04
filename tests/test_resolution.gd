extends SceneTree


const MainScene := preload("res://src/main/main.tscn")

var _failures: Array[String] = []
var _case_count := 0


func _init() -> void:
	call_deferred(&"_run_tests")


func _run_tests() -> void:
	_test_qualification_threshold()
	_test_swap_only_screen_and_pause()
	_test_candidate_placement_rows()
	_test_loss_confirmation()
	_test_party_memorial_moves()
	_test_rejections_and_reselection()
	_test_anchor_discard()
	_test_start_gating_and_resolved_signal()
	_test_coverage_updates_after_moves()
	_test_party_spawns_after_start()
	_test_keyboard_flow()
	_test_mcp_state_is_plain()
	_test_clear_unlock_applies_at_next_resolution()
	await _test_screen_layout()

	if _failures.is_empty():
		print("Roster resolution screen tests passed (14 cases, %d checks)." % _case_count)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_qualification_threshold() -> void:
	var main := MainScene.instantiate()
	root.add_child(main)
	var novice: HeroProgression = main._build_scenario_progression(&"", 2)
	_expect(novice != null and novice.level == 2 and novice.get_job_id() == HeroProgression.JOB_NOVICE, "level-2 novice fixture builds")
	main.progression = novice
	main._start_next_run()
	_expect(
		not main.resolution_screen.visible
		and main.roster.candidate == null
		and main.roster.party.is_empty()
		and main.run_notice.visible
		and main.run_notice_text.text.contains("Hero 1")
		and main.run_notice_text.text.contains("without choosing a job"),
		"a level-2 death with an empty memorial starts the next run with a notice and no screen"
	)
	_expect(
		not paused and main.run_number == 2 and main.progression.level == 1 and not main._defeat_transition_pending,
		"the notice path begins the next run immediately"
	)
	var unchosen := HeroProgression.new()
	unchosen.grant_experience(2 * HeroProgression.XP_PER_LEVEL)
	_expect(unchosen.level == 3 and unchosen.get_job_id() == HeroProgression.JOB_NOVICE, "level 3 with the job choice pending is still a Novice")
	main.progression = unchosen
	main._start_next_run()
	_expect(
		not main.resolution_screen.visible and main.roster.candidate == null and main.run_number == 3,
		"reaching level 3 without choosing a job does not qualify"
	)
	main.progression = main._build_scenario_progression(&"mender", 3)
	main._start_next_run()
	_expect(
		main.resolution_screen.visible
		and main.roster.candidate != null
		and main.roster.candidate.runtime_id == "hero-3"
		and main.roster.candidate.display_name == "Hero 3"
		and main.run_number == 4,
		"a level-3 death after choosing a job opens the screen with that hero as candidate"
	)
	_expect(paused and main.echoes.is_empty(), "the open screen pauses the tree and no run is spawned yet")
	main.free()
	paused = false


func _test_swap_only_screen_and_pause() -> void:
	var main := _resolution_main(&"", 2, [&"vanguard"], 1, [&"arcanist"], 1, 0)
	var screen: ResolutionScreen = main.resolution_screen
	_expect(
		screen.visible
		and paused
		and main.roster.candidate == null
		and screen.can_start()
		and screen.get_row_text(0) == "[1] CANDIDATE · — none —"
		and screen.get_row_text(1) == "[2] PARTY 1 · Hero 1 · Vanguard · Lv 5"
		and screen.get_row_text(2) == "[3] MEMORIAL 1 · Hero 2 · Arcanist · Lv 5",
		"a Novice death with a non-empty memorial opens a swap-only screen with labelled rows"
	)
	_expect(
		screen.get_text().contains("without choosing a job"),
		"the swap-only screen explains why there is no candidate"
	)
	_expect(screen.start() and not paused and not screen.visible, "Start unpauses the tree and hides the screen")
	_expect(not main.resolve_default(), "resolve_default does nothing when no screen is open")
	main.free()
	paused = false


func _test_candidate_placement_rows() -> void:
	var main := _resolution_main(&"mender", 5, [], 1, [], 1, 0)
	var screen: ResolutionScreen = main.resolution_screen
	_expect(
		screen.get_row_text(0) == "[1] CANDIDATE · Hero 1 · Mender · Lv 5"
		and screen.get_row_text(1) == "[2] PARTY 1 · — empty —"
		and screen.get_row_text(2) == "[3] MEMORIAL 1 · — empty —",
		"rows show the candidate and empty slots"
	)
	_expect(
		screen.select_row(Roster.ZONE_CANDIDATE, 0) == ResolutionScreen.RESULT_SELECTED
		and screen.select_row(Roster.ZONE_PARTY, 0) == ResolutionScreen.RESULT_COMMITTED
		and _ids(main.roster.party) == ["hero-1"]
		and main.roster.candidate == null,
		"candidate to an empty party slot joins the party in two presses"
	)
	main.free()
	paused = false

	main = _resolution_main(&"mender", 5, [], 1, [], 1, 0)
	screen = main.resolution_screen
	screen.select_row(Roster.ZONE_CANDIDATE, 0)
	_expect(
		screen.select_row(Roster.ZONE_MEMORIAL, 0) == ResolutionScreen.RESULT_COMMITTED
		and _ids(main.roster.memorial) == ["hero-1"]
		and main.roster.party.is_empty(),
		"candidate to an empty memorial slot stores the hero"
	)
	main.free()
	paused = false

	main = _resolution_main(&"mender", 5, [&"vanguard"], 1, [], 1, 0)
	screen = main.resolution_screen
	screen.select_row(Roster.ZONE_CANDIDATE, 0)
	var status := screen.select_row(Roster.ZONE_PARTY, 0)
	_expect(
		status == ResolutionScreen.RESULT_COMMITTED
		and _ids(main.roster.party) == ["hero-2"]
		and _ids(main.roster.memorial) == ["hero-1"]
		and screen.get_outcome_text().contains("Hero 1 → Memorial 1"),
		"candidate to an occupied party slot stores the displaced hero without confirmation: %s" % screen.get_outcome_text()
	)
	main.free()
	paused = false


func _test_loss_confirmation() -> void:
	var main := _resolution_main(&"mender", 5, [&"vanguard"], 1, [&"arcanist"], 1, 1)
	var screen: ResolutionScreen = main.resolution_screen
	screen.select_row(Roster.ZONE_CANDIDATE, 0)
	var first := screen.select_row(Roster.ZONE_PARTY, 0)
	var state := screen._mcp_state()
	_expect(
		first == ResolutionScreen.RESULT_PENDING
		and _ids(main.roster.party) == ["hero-1"]
		and _ids(main.roster.memorial) == ["hero-2"]
		and main.roster.candidate != null
		and state["pending_lost_name"] == "Hero 1"
		and screen.get_outcome_text().contains("Hero 1 → LOST")
		and screen.get_outcome_text().contains("Hero 1 will be lost"),
		"candidate to an occupied party slot with a full memorial names the lost hero and waits: %s" % screen.get_outcome_text()
	)
	_expect(
		screen.get_row_text(1).begins_with("✖ [2] PARTY 1"),
		"the loss destination row is marked with text, not colour alone"
	)
	var second := screen.select_row(Roster.ZONE_PARTY, 0)
	_expect(
		second == ResolutionScreen.RESULT_COMMITTED
		and _ids(main.roster.party) == ["hero-3"]
		and _ids(main.roster.memorial) == ["hero-2"]
		and main.roster.candidate == null,
		"the second press on the same row commits and the displaced hero is gone"
	)
	main.free()
	paused = false

	main = _resolution_main(&"mender", 5, [&"vanguard"], 1, [&"arcanist"], 1, 0)
	screen = main.resolution_screen
	screen.select_row(Roster.ZONE_CANDIDATE, 0)
	screen.select_row(Roster.ZONE_PARTY, 0)
	_expect(
		screen.select_row(Roster.ZONE_MEMORIAL, 0) == ResolutionScreen.RESULT_PENDING
		and screen._mcp_state()["pending_lost_name"] == "Hero 2"
		and _ids(main.roster.party) == ["hero-1"],
		"pressing a different row replaces the pending move and names that row's hero"
	)
	_expect(screen.cancel() and screen._mcp_state()["pending_kind"] == "" and main.roster.candidate != null, "cancel clears a pending loss without changing the roster")
	screen.select_row(Roster.ZONE_CANDIDATE, 0)
	screen.select_row(Roster.ZONE_MEMORIAL, 0)
	_expect(
		screen.confirm() == ResolutionScreen.RESULT_COMMITTED
		and _ids(main.roster.memorial) == ["hero-3"]
		and _ids(main.roster.party) == ["hero-1"],
		"confirm() commits a candidate replacing an occupied memorial slot"
	)
	main.free()
	paused = false


func _test_party_memorial_moves() -> void:
	var main := _resolution_main(&"", 2, [&"vanguard"], 1, [&"arcanist"], 1, 0)
	var screen: ResolutionScreen = main.resolution_screen
	screen.select_row(Roster.ZONE_PARTY, 0)
	_expect(
		screen.select_row(Roster.ZONE_MEMORIAL, 0) == ResolutionScreen.RESULT_COMMITTED
		and _ids(main.roster.party) == ["hero-2"]
		and _ids(main.roster.memorial) == ["hero-1"]
		and screen.get_outcome_text().contains("Hero 1 → Memorial 1 · Hero 2 → Party 1"),
		"party and memorial heroes swap without a candidate: %s" % screen.get_outcome_text()
	)
	main.free()
	paused = false

	main = _resolution_main(&"", 2, [&"vanguard", &"arcanist"], 2, [&"mender"], 2, 0)
	screen = main.resolution_screen
	screen.select_row(Roster.ZONE_PARTY, 0)
	_expect(
		screen.select_row(Roster.ZONE_PARTY, 1) == ResolutionScreen.RESULT_COMMITTED
		and _ids(main.roster.party) == ["hero-2", "hero-1"],
		"two party slots swap, changing slot order"
	)
	screen.select_row(Roster.ZONE_PARTY, 0)
	_expect(
		screen.select_row(Roster.ZONE_MEMORIAL, 1) == ResolutionScreen.RESULT_COMMITTED
		and _ids(main.roster.party) == ["hero-1"]
		and _ids(main.roster.memorial) == ["hero-3", "hero-2"],
		"a party hero moves into an empty memorial slot"
	)
	screen.select_row(Roster.ZONE_MEMORIAL, 0)
	_expect(
		screen.select_row(Roster.ZONE_PARTY, 1) == ResolutionScreen.RESULT_COMMITTED
		and _ids(main.roster.party) == ["hero-1", "hero-3"]
		and _ids(main.roster.memorial) == ["hero-2"],
		"a memorial hero moves into an empty party slot"
	)
	main.free()
	paused = false


func _test_rejections_and_reselection() -> void:
	var main := _resolution_main(&"", 2, [&"vanguard"], 2, [&"arcanist"], 1, 0)
	var screen: ResolutionScreen = main.resolution_screen
	_expect(
		screen.select_row(Roster.ZONE_PARTY, 1) == ResolutionScreen.RESULT_REJECTED
		and screen.get_outcome_text().contains("empty"),
		"an empty slot cannot be picked as a source"
	)
	screen.select_row(Roster.ZONE_PARTY, 0)
	_expect(
		screen.select_row(Roster.ZONE_CANDIDATE, 0) == ResolutionScreen.RESULT_REJECTED
		and screen._mcp_state()["selected"] == "party:0",
		"with no candidate the candidate row is rejected and the selection stays"
	)
	_expect(
		screen.select_row(Roster.ZONE_PARTY, 0) == ResolutionScreen.RESULT_DESELECTED
		and screen._mcp_state()["selected"] == "",
		"picking the selected row again deselects it"
	)
	_expect(screen.select_row(Roster.ZONE_MEMORIAL, 5) == ResolutionScreen.RESULT_IGNORED, "an unknown row is ignored")
	main.free()
	paused = false

	main = _resolution_main(&"mender", 5, [&"vanguard"], 1, [], 1, 0)
	screen = main.resolution_screen
	screen.select_row(Roster.ZONE_PARTY, 0)
	_expect(
		screen.select_row(Roster.ZONE_CANDIDATE, 0) == ResolutionScreen.RESULT_SELECTED
		and screen._mcp_state()["selected"] == "candidate:0",
		"picking the candidate row while another hero is selected switches the source to the candidate"
	)
	_expect(screen.cancel() and screen._mcp_state()["selected"] == "", "cancel drops the selection")
	main.free()
	paused = false


func _test_anchor_discard() -> void:
	var main := _resolution_main(&"mender", 5, [&"vanguard"], 1, [&"arcanist"], 1, 0)
	var screen: ResolutionScreen = main.resolution_screen
	_expect(
		screen.discard() == ResolutionScreen.RESULT_REJECTED
		and main.roster.candidate != null
		and screen.anchors == 0
		and not screen._mcp_state()["discard_enabled"]
		and screen.get_outcome_text().contains("Echo Anchor"),
		"discarding with no Echo Anchor is rejected and keeps the candidate"
	)
	main.free()
	paused = false

	main = _resolution_main(&"mender", 5, [&"vanguard"], 1, [&"arcanist"], 1, 1)
	screen = main.resolution_screen
	var resolved_with: Array[int] = []
	screen.resolved.connect(func(anchors_left: int) -> void: resolved_with.append(anchors_left))
	_expect(
		screen._mcp_state()["discard_enabled"]
		and screen.discard() == ResolutionScreen.RESULT_PENDING
		and screen.anchors == 1
		and main.roster.candidate != null
		and screen._mcp_state()["pending_kind"] == "discard",
		"the first discard press asks for confirmation and spends nothing"
	)
	_expect(
		screen.discard() == ResolutionScreen.RESULT_COMMITTED
		and screen.anchors == 0
		and main.roster.candidate == null
		and _ids(main.roster.party) == ["hero-1"]
		and _ids(main.roster.memorial) == ["hero-2"],
		"the second discard press spends exactly one Anchor and leaves party and memorial untouched"
	)
	_expect(screen.start() and resolved_with == [0], "Start reports the remaining Anchor count (0)")
	main.free()
	paused = false


func _test_start_gating_and_resolved_signal() -> void:
	var main := _resolution_main(&"mender", 5, [&"vanguard"], 1, [&"arcanist"], 2, 1)
	var screen: ResolutionScreen = main.resolution_screen
	var resolved_with: Array[int] = []
	screen.resolved.connect(func(anchors_left: int) -> void: resolved_with.append(anchors_left))
	_expect(
		not screen.can_start()
		and not screen.start()
		and resolved_with.is_empty()
		and screen.visible
		and paused
		and screen.get_outcome_text().contains("Place or discard"),
		"Start stays disabled while the candidate is unresolved"
	)
	screen.select_row(Roster.ZONE_CANDIDATE, 0)
	screen.select_row(Roster.ZONE_MEMORIAL, 1)
	_expect(screen.can_start() and not screen.start_button.disabled, "placing the candidate enables Start")
	_expect(
		screen.start()
		and resolved_with == [1]
		and not paused
		and not screen.visible
		and main.run_anchors == 0,
		"Start reports the unspent Anchor and Main drops it when the run begins"
	)
	main.free()
	paused = false


func _test_coverage_updates_after_moves() -> void:
	var main := _resolution_main(&"mender", 5, [&"vanguard"], 1, [], 1, 0)
	var screen: ResolutionScreen = main.resolution_screen
	_expect(
		screen.get_coverage_text() == "Roster covers: INTERRUPT ✓ Vanguard · AREA ✓ Vanguard · SUSTAIN ✗"
		and screen.next_hero_label.text == "Your next hero should fill: SUSTAIN → Mender provides SUSTAIN",
		"coverage names the covering jobs and the missing need: %s | %s" % [screen.get_coverage_text(), screen.next_hero_label.text]
	)
	screen.select_row(Roster.ZONE_CANDIDATE, 0)
	screen.select_row(Roster.ZONE_PARTY, 0)
	_expect(
		screen.get_coverage_text() == "Roster covers: INTERRUPT ✗ · AREA ✗ · SUSTAIN ✓ Mender"
		and screen.next_hero_label.text.contains("INTERRUPT")
		and screen.next_hero_label.text.contains("AREA"),
		"coverage updates after the Mender takes the party slot: %s" % screen.get_coverage_text()
	)
	_expect(
		screen.trial_label.text.contains("Bell Court")
		and screen.capacity_label.text.begins_with("Next unlock: Party slot 2")
		and screen.anchors_label.text == "Echo Anchors: 0",
		"the screen shows the next Trial, unlock hint, and Anchor count"
	)
	main.free()
	paused = false


func _test_party_spawns_after_start() -> void:
	var main := _resolution_main(&"mender", 6, [&"vanguard", &"arcanist"], 2, [&"mender", &"vanguard"], 2, 1)
	var screen: ResolutionScreen = main.resolution_screen
	_expect(main.echoes.is_empty(), "no echoes exist while the screen is open")
	screen.select_row(Roster.ZONE_CANDIDATE, 0)
	screen.select_row(Roster.ZONE_PARTY, 0)
	_expect(
		screen.select_row(Roster.ZONE_PARTY, 0) == ResolutionScreen.RESULT_COMMITTED
		and _ids(main.roster.party) == ["hero-5", "hero-2"],
		"candidate replaces party slot 1 after confirmation"
	)
	_expect(screen.start(), "Start closes the placed screen")
	var spawned: Array[EchoActor] = []
	for child in main.get_children():
		if child is EchoActor:
			spawned.append(child)
	_expect(
		main.echoes.size() == 2
		and spawned.size() == 2
		and main.echoes[0].hero_record.runtime_id == "hero-5"
		and main.echoes[1].hero_record.runtime_id == "hero-2"
		and main.echoes[0].slot_index == 0
		and main.echoes[1].slot_index == 1,
		"the next run spawns exactly the final party in slot order"
	)
	_expect(
		_ids(main.roster.memorial) == ["hero-3", "hero-4"] and not _spawned_ids(spawned).has("hero-3"),
		"memorial heroes never spawn"
	)
	_expect(
		main.run_number == 6
		and main.progression.level == 1
		and main.player.job_id == HeroProgression.JOB_NOVICE
		and not main._defeat_transition_pending
		and not paused,
		"the new run starts the next hero as a fresh Novice and unpauses"
	)
	main.free()
	paused = false


func _test_keyboard_flow() -> void:
	var main := _resolution_main(&"mender", 5, [&"vanguard"], 1, [&"arcanist"], 1, 1)
	var screen: ResolutionScreen = main.resolution_screen
	_key(screen, KEY_1)
	_expect(screen._mcp_state()["selected"] == "candidate:0", "key 1 picks the candidate row")
	_key(screen, KEY_BACKSPACE)
	_expect(screen._mcp_state()["selected"] == "", "Backspace cancels a selection")
	_key(screen, KEY_1)
	_key(screen, KEY_ESCAPE)
	_expect(screen._mcp_state()["selected"] == "", "Esc cancels a selection")
	_key(screen, KEY_5)
	_expect(screen._mcp_state()["selected"] == "", "a key past the visible rows is ignored")
	_key(screen, KEY_1)
	_key(screen, KEY_2)
	_expect(screen._mcp_state()["pending_kind"] == "move", "keys 1 then 2 preview the candidate into party slot 1")
	_key(screen, KEY_2)
	_expect(
		_ids(main.roster.party) == ["hero-3"] and main.roster.candidate == null,
		"pressing the destination key again commits the loss"
	)
	_key(screen, KEY_X)
	_expect(screen.anchors == 1, "X with no candidate spends nothing")
	_key(screen, KEY_ENTER)
	_expect(not screen.visible and not paused, "Enter starts the run once the candidate is placed")
	main.free()
	paused = false

	main = _resolution_main(&"mender", 5, [&"vanguard"], 1, [&"arcanist"], 1, 1)
	screen = main.resolution_screen
	_key(screen, KEY_X)
	_expect(screen._mcp_state()["pending_kind"] == "discard", "X arms a discard")
	_key(screen, KEY_ENTER)
	_expect(
		main.roster.candidate == null and screen.anchors == 0 and screen.visible,
		"Enter confirms a pending discard instead of starting"
	)
	_key(screen, KEY_ENTER)
	_expect(not screen.visible, "a second Enter starts the run")
	main.free()
	paused = false


func _test_mcp_state_is_plain() -> void:
	var main := _resolution_main(&"mender", 5, [&"vanguard"], 1, [&"arcanist"], 1, 1)
	main.resolution_screen.select_row(Roster.ZONE_CANDIDATE, 0)
	var state: Dictionary = main._mcp_state()
	var resolution: Dictionary = state["resolution"]
	_expect(
		resolution["visible"]
		and resolution["candidate"] == {"id": "hero-3", "name": "Hero 3", "job_id": "mender", "level": 5}
		and resolution["party"] == [{"id": "hero-1", "name": "Hero 1", "job_id": "vanguard", "level": 5}]
		and resolution["memorial"] == [{"id": "hero-2", "name": "Hero 2", "job_id": "arcanist", "level": 5}]
		and resolution["anchors"] == 1
		and not resolution["can_start"]
		and resolution["selected"] == "candidate:0"
		and resolution["coverage_text"] is String
		and resolution["outcome_text"] is String
		and resolution["rows"].size() == 3
		and state["run_anchors"] == 1
		and state["paused"],
		"resolution MCP block exposes visible, candidate, party, memorial, anchors, can_start, and texts"
	)
	_expect(_is_plain(state), "Main MCP state with the resolution block contains only plain serialized types")
	main.free()
	paused = false


func _test_clear_unlock_applies_at_next_resolution() -> void:
	var main := MainScene.instantiate()
	main.save_path = ""
	root.add_child(main)
	main._on_trial_report_ready({"encounter_id": "bell_court", "outcome": "cleared"})
	_expect(
		main.party_slots == 2
		and main.roster.get_party_slots() == 2
		and main.echoes.is_empty(),
		"a clear changes capacity without spawning an echo into the current run"
	)
	main.progression = main._build_scenario_progression(&"mender", 3)
	main._start_next_run()
	_expect(
		main.resolution_screen.visible
		and main.resolution_screen.get_row_text(2) == "[3] PARTY 2 · — empty —",
		"the next resolution offers the unlocked second party slot"
	)
	main.free()
	paused = false


func _test_screen_layout() -> void:
	root.size = Vector2i(1280, 720)
	var main := _resolution_main(&"mender", 6, [&"vanguard", &"arcanist"], 2, [&"mender", &"vanguard"], 2, 1)
	current_scene = main
	await process_frame
	await process_frame
	var screen: ResolutionScreen = main.resolution_screen
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(root.size))
	var panel_rect := screen.panel.get_global_rect()
	_expect(viewport_rect.encloses(panel_rect), "the five-row panel fits inside 1280x720: %s" % panel_rect)
	var previous_end := -1.0
	var rows_ok := true
	for index in 5:
		var rect := screen.row_buttons[index].get_global_rect()
		rows_ok = rows_ok and screen.row_buttons[index].visible and rect.position.y >= previous_end and panel_rect.encloses(rect)
		previous_end = rect.end.y
	_expect(rows_ok, "the five rows stack without overlap inside the panel")
	var info_ok := true
	previous_end = -1.0
	for label: Label in [screen.trial_label, screen.coverage_label, screen.next_hero_label, screen.anchors_label, screen.capacity_label]:
		var rect := label.get_global_rect()
		info_ok = info_ok and rect.position.y >= previous_end and panel_rect.encloses(rect)
		previous_end = rect.end.y
	_expect(info_ok, "the info column labels stack without overlap inside the panel")
	var rows_right := screen.row_buttons[0].get_global_rect().end.x
	_expect(
		screen.trial_label.get_global_rect().position.x >= rows_right,
		"the info column sits to the right of the rows"
	)
	var buttons := [screen.discard_button, screen.confirm_button, screen.cancel_button, screen.start_button]
	var buttons_ok := true
	var previous_right := -1.0
	for button: Button in buttons:
		if not button.visible:
			continue
		var rect := button.get_global_rect()
		buttons_ok = buttons_ok and rect.position.x >= previous_right and panel_rect.encloses(rect)
		previous_right = rect.end.x
	_expect(buttons_ok, "the action buttons sit side by side inside the panel")
	_expect(
		screen.outcome_label.get_global_rect().end.y <= screen.discard_button.get_global_rect().position.y
		and panel_rect.encloses(screen.outcome_label.get_global_rect()),
		"the outcome line sits above the buttons"
	)
	screen.select_row(Roster.ZONE_CANDIDATE, 0)
	screen.select_row(Roster.ZONE_PARTY, 0)
	await process_frame
	await process_frame
	panel_rect = screen.panel.get_global_rect()
	_expect(
		viewport_rect.encloses(panel_rect) and screen.confirm_button.visible and panel_rect.encloses(screen.confirm_button.get_global_rect()),
		"the panel still fits with a pending loss and the Confirm button: %s" % panel_rect
	)
	current_scene = null
	main.free()
	paused = false


func _resolution_main(
	fallen_job: StringName,
	fallen_level: int,
	party_jobs: Array[StringName],
	party_slot_count: int,
	memorial_jobs: Array[StringName],
	memorial_slot_count: int,
	anchor_count: int
) -> Node:
	var main := MainScene.instantiate()
	main.party_slots = party_slot_count
	root.add_child(main)
	var party_levels: Array[int] = []
	var applied: bool = main.apply_resolution_scenario(
		fallen_job, fallen_level, party_jobs, party_levels, memorial_jobs, memorial_slot_count, anchor_count, 5
	)
	_expect(applied, "resolution scenario builds")
	return main


func _key(screen: ResolutionScreen, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	screen._unhandled_input(event)


func _ids(records: Array[HeroRecord]) -> Array[String]:
	var ids: Array[String] = []
	for record in records:
		ids.append(record.runtime_id)
	return ids


func _spawned_ids(spawned: Array[EchoActor]) -> Array[String]:
	var ids: Array[String] = []
	for echo in spawned:
		ids.append(echo.hero_record.runtime_id)
	return ids


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
	_case_count += 1
	if not condition:
		_failures.append(message)
