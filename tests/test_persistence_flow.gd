extends SceneTree


const MainScene := preload("res://src/main/main.tscn")
const TEST_ROOT := "user://test_saves/"

var _failures: Array[String] = []
var _checks := 0


func _init() -> void:
	call_deferred(&"_run_tests")


func _run_tests() -> void:
	_test_new_launch_and_headless_guard()
	_test_death_resolve_relaunch_and_hero_counter()
	_test_pending_recovery_and_anchor_discard()
	_test_clear_rewards_and_capacity()
	_test_corrupt_and_read_only_sessions()
	_test_midrun_quit_abandons_run()
	_test_scenario_slots()
	_test_mcp_persistence_state()

	paused = false
	if _failures.is_empty():
		print("Persistence flow tests passed (8 cases, %d checks)." % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_new_launch_and_headless_guard() -> void:
	var path := TEST_ROOT + "flow_new.json"
	_cleanup(path)
	var main := _main(path)
	_expect(
		main.save_status == "new"
		and main.party_slots == 1
		and main.roster.get_party_slots() == 1
		and main.roster.get_memorial_slots() == 1
		and main.run_number == 1
		and not FileAccess.file_exists(path),
		"a new launch uses base capacities and writes nothing before a save point"
	)
	_free_main(main)

	var guarded := MainScene.instantiate()
	root.add_child(guarded)
	_expect(
		guarded.save_path.is_empty()
		and guarded.roster_store.path.is_empty()
		and guarded.save_status == "new",
		"the headless guard turns the default real-save path into memory-only storage"
	)
	_free_main(guarded)
	_cleanup(path)


func _test_death_resolve_relaunch_and_hero_counter() -> void:
	var path := TEST_ROOT + "flow_cycle.json"
	_cleanup(path)
	var main := _main(path)
	main.progression = main._build_scenario_progression(&"vanguard", 4)
	main.run_anchors = 1
	main._start_next_run()
	_expect(
		main.resolution_screen.visible
		and main.roster.candidate != null
		and main.roster.candidate.runtime_id == "hero-1"
		and main.document.next_hero_number == 2
		and main.document.pending
		and main.document.pending_anchors == 1
		and main.encounter_director.encounter_id == &"slinger_gallery"
		and main.trial_title.text == "TRIAL · Slinger Gallery · Lv 5"
		and main.resolution_screen.trial_label.text == "Next Trial: Slinger Gallery\nNeeds: INTERRUPT · AREA · RANGE",
		"death saves the next counter and a pending candidate with its Anchor"
	)
	var saved := _load_document(path)
	_expect(
		saved != null
		and saved.pending
		and saved.pending_anchors == 1
		and saved.roster.candidate != null
		and saved.roster.candidate.runtime_id == "hero-1",
		"the on-disk death snapshot contains the same candidate and Anchor"
	)
	_expect(main.resolve_default(), "the first death resolves through the normal screen")
	saved = _load_document(path)
	_expect(
		saved != null
		and not saved.pending
		and saved.pending_anchors == 0
		and saved.next_hero_number == 2
		and saved.roster.party.size() == 1
		and saved.roster.party[0].runtime_id == "hero-1",
		"confirming resolution clears pending and persists the final roster"
	)
	_free_main(main)

	main = _main(path)
	_expect(
		main.save_status == "ok"
		and main.run_number == 2
		and main.document.next_hero_number == 2
		and main.roster.party.size() == 1
		and main.roster.party[0].runtime_id == "hero-1"
		and main.echo != null
		and main.echo.hero_record.runtime_id == "hero-1"
		and main.encounter_director.encounter_id == &"slinger_gallery"
		and main.trial_title.text == "TRIAL · Slinger Gallery · Lv 5",
		"relaunch restores the roster, counter, and active party"
	)
	main.progression = main._build_scenario_progression(&"mender", 3)
	main._start_next_run()
	_expect(
		main.roster.candidate != null
		and main.roster.candidate.runtime_id == "hero-2"
		and main.run_number == 3
		and main.encounter_director.encounter_id == &"bell_court"
		and main.resolution_screen.trial_label.text == "Next Trial: Bell Court\nNeeds: INTERRUPT · AREA · SUSTAIN",
		"the next fallen hero uses the persisted counter instead of reusing hero-1"
	)
	_expect(main.resolve_default(), "the second candidate resolves into the empty memorial")
	_free_main(main)

	main = _main(path)
	_expect(
		main.run_number == 3
		and main.roster.party[0].runtime_id == "hero-1"
		and main.roster.memorial.size() == 1
		and main.roster.memorial[0].runtime_id == "hero-2",
		"a second relaunch keeps both zones and the advanced hero counter"
	)
	_free_main(main)
	_cleanup(path)


func _test_pending_recovery_and_anchor_discard() -> void:
	var path := TEST_ROOT + "flow_pending.json"
	_cleanup(path)
	var main := _main(path)
	main.progression = main._build_scenario_progression(&"arcanist", 4)
	main.run_anchors = 1
	main._start_next_run()
	var expected_candidate: Dictionary = main.roster.candidate.to_dict()
	_free_main(main)

	main = _main(path)
	_expect(
		main.resolution_screen.visible
		and paused
		and main.roster.candidate != null
		and main.roster.candidate.to_dict() == expected_candidate
		and main.run_anchors == 1
		and main.resolution_screen.anchors == 1
		and main.document.pending
		and main.encounter_director.encounter_id == &"slinger_gallery"
		and main.resolution_screen.trial_label.text.contains("Slinger Gallery"),
		"launching with pending reopens the same resolution before the first run"
	)
	_expect(
		main.resolution_screen.discard() == ResolutionScreen.RESULT_PENDING
		and main.resolution_screen.discard() == ResolutionScreen.RESULT_COMMITTED
		and main.resolution_screen.anchors == 0,
		"the recovered Anchor can still pay for exactly one discard"
	)
	_expect(main.resolution_screen.start(), "the recovered resolution confirms normally")
	var saved := _load_document(path)
	_expect(
		saved != null
		and not saved.pending
		and saved.pending_anchors == 0
		and saved.roster.candidate == null
		and main.run_anchors == 0,
		"resolving the recovered screen clears the saved Anchor and pending entry"
	)
	_free_main(main)
	_cleanup(path)


func _test_clear_rewards_and_capacity() -> void:
	var path := TEST_ROOT + "flow_clears.json"
	_cleanup(path)
	var main := _main(path)
	main._on_trial_report_ready(_report("failed"))
	_expect(
		main.trial_clears.is_empty()
		and main.unlocks.is_empty()
		and main.run_anchors == 0
		and not FileAccess.file_exists(path),
		"a failed Trial grants no clear, unlock, Anchor, or save"
	)
	main._on_trial_report_ready(_report("cleared"))
	_expect(
		main.trial_clears == {"bell_court": 1}
		and main.unlocks == [&"party_slot_2"]
		and main.party_slots == 2
		and main.roster.get_party_slots() == 2
		and main.run_anchors == 1
		and main.run_notice_text.text == "Unlocked: Party slot 2 · Echo Anchor found",
		"the first clear unlocks party slot two and grants one Anchor with a toast"
	)
	main._on_trial_report_ready(_report("cleared"))
	_expect(
		main.trial_clears == {"bell_court": 1} and main.run_anchors == 1,
		"a duplicate clear report in the same run awards nothing twice"
	)
	var saved := _load_document(path)
	_expect(
		saved != null
		and saved.trial_clears == {"bell_court": 1}
		and saved.unlocks == [&"party_slot_2"]
		and not saved.pending
		and saved.pending_anchors == 0,
		"the clear is durable while its run-only Anchor stays out of the save"
	)

	main._begin_run()
	main._on_trial_report_ready(_report("cleared", "slinger_gallery"))
	_expect(
		main.trial_clears == {"bell_court": 1, "slinger_gallery": 1}
		and main.unlocks == [&"party_slot_2"]
		and main.run_anchors == 1
		and main.run_notice_text.text == "Echo Anchor found",
		"a later clear grants another run Anchor but no duplicate unlock"
	)
	saved = _load_document(path)
	_expect(
		saved != null and saved.trial_clears == {"bell_court": 1, "slinger_gallery": 1},
		"Gallery clears persist under their stable ID beside Bell Court clears"
	)
	main._begin_run()
	main._on_trial_report_ready(_report("cleared"))
	_expect(
		main.trial_clears == {"bell_court": 2, "slinger_gallery": 1}
		and main.unlocks == [&"party_slot_2", &"memorial_slot_2"]
		and main.roster.get_memorial_slots() == 2
		and main.run_notice_text.text.contains("Unlocked: Memorial slot 2"),
		"the third total clear unlocks memorial slot two"
	)
	main.progression = main._build_scenario_progression(&"vanguard", 3)
	main._start_next_run()
	_expect(
		main.resolution_screen.visible
		and main.resolution_screen._row_locations.size() == 5
		and main.resolution_screen.get_row_text(2).contains("PARTY 2")
		and main.resolution_screen.get_row_text(4).contains("MEMORIAL 2")
		and main.document.pending_anchors == 1,
		"the next resolution exposes both newly unlocked slots and preserves the Anchor"
	)
	_free_main(main)
	_cleanup(path)


func _test_corrupt_and_read_only_sessions() -> void:
	var corrupt_path := TEST_ROOT + "flow_corrupt.json"
	_cleanup(corrupt_path)
	_write_text(corrupt_path, "{not json")
	var main := _main(corrupt_path)
	_expect(
		main.save_status == "corrupt"
		and main.document.next_hero_number == 1
		and main.run_notice_text.text.contains("Save unreadable")
		and FileAccess.get_file_as_string(corrupt_path + ".corrupt") == "{not json"
		and FileAccess.get_file_as_string(corrupt_path) == "{not json",
		"a corrupt save is backed up and replaced by defaults without overwriting the source"
	)
	_free_main(main)
	_cleanup(corrupt_path)

	var future_path := TEST_ROOT + "flow_future.json"
	_cleanup(future_path)
	_write_text(future_path, JSON.stringify({"version": 999}))
	main = _main(future_path)
	_expect(
		main.save_status == "too_new"
		and main.roster_store.read_only
		and main.run_notice_text.text.contains("newer version"),
		"a newer save opens a read-only default session with a notice"
	)
	main.progression = main._build_scenario_progression(&"mender", 3)
	main._start_next_run()
	_expect(
		main.resolution_screen.visible
		and main.run_notice_text.text.contains("Save failed")
		and FileAccess.get_file_as_string(future_path) == JSON.stringify({"version": 999}),
		"a failed save does not block resolution or overwrite the newer file"
	)
	_expect(main.resolve_default() and not paused, "play continues after the read-only save failure")
	_free_main(main)
	_cleanup(future_path)


func _test_midrun_quit_abandons_run() -> void:
	var path := TEST_ROOT + "flow_abandon.json"
	_cleanup(path)
	var main := _main(path)
	main.progression = main._build_scenario_progression(&"", 2)
	main._start_next_run()
	_expect(not main.resolution_screen.visible and main.run_number == 2, "an unqualified death saves the next run directly")
	main.progression.grant_experience(200)
	_free_main(main)
	main = _main(path)
	_expect(
		main.run_number == 2
		and main.progression.level == 1
		and not main.document.pending
		and main.roster.candidate == null,
		"quitting mid-run restores the last save point and abandons unsaved run progress"
	)
	_free_main(main)
	_cleanup(path)


func _test_scenario_slots() -> void:
	var pw1 := "user://playtest_saves/pw1.json"
	var pw2 := "user://playtest_saves/pw2.json"
	_cleanup(pw1)
	_cleanup(pw2)
	var scene := (load("res://tests/scenarios/persist_new_slot.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var main := scene.get_node("Main")
	_expect(
		main.save_path == pw1
		and main.progression.level == 3
		and main.progression.get_job_id() == HeroProgression.JOB_VANGUARD
		and not FileAccess.file_exists(pw1),
		"persist_new_slot uses its isolated slot without writing at launch"
	)
	main._start_next_run()
	_expect(main.resolve_default() and FileAccess.file_exists(pw1), "the new-slot scenario reaches a real resolution save point")
	_free_main(scene)

	scene = (load("res://tests/scenarios/persist_reload_slot.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	main = scene.get_node("Main")
	_expect(
		main.save_path == pw1
		and main.save_status == "ok"
		and main.run_number == 2
		and main.roster.party.size() == 1
		and main.roster.party[0].runtime_id == "hero-1",
		"persist_reload_slot performs no scenario reset and round-trips the saved roster"
	)
	_free_main(scene)

	scene = (load("res://tests/scenarios/vanguard_mender_5_court_clear_slot.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	main = scene.get_node("Main")
	_expect(
		main.save_path == pw2
		and main.trial_clears == {"bell_court": 1}
		and main.unlocks == [&"party_slot_2"]
		and main.run_anchors == 1,
		"the Court slot scenario reaches its deterministic clear and save through Main.debug_clear_encounter"
	)
	var saved := _load_document(pw2)
	_expect(saved != null and saved.unlocks == [&"party_slot_2"], "the Court scenario writes its unlock to the isolated slot")
	_free_main(scene)
	_cleanup(pw1)
	_cleanup(pw2)


func _test_mcp_persistence_state() -> void:
	var main := _main("")
	main._on_trial_report_ready(_report("cleared"))
	var state: Dictionary = main._mcp_state()
	_expect(
		state["save_path"] == ""
		and state["save_status"] == "new"
		and state["save_read_only"] == false
		and state["unlocks"] == ["party_slot_2"]
		and state["trial_clears"] == {"bell_court": 1}
		and state["next_hero_number"] == 1
		and state["pending_saved"] == false
		and _is_plain(state),
		"Main exposes every persistence field with plain MCP serialization types"
	)
	main.progression = main._build_scenario_progression(&"mender", 3)
	main._start_next_run()
	state = main._mcp_state()
	_expect(
		state["next_hero_number"] == 2 and state["pending_saved"] == true and _is_plain(state),
		"MCP state reports the advanced counter and saved pending resolution"
	)
	_free_main(main)


func _main(path: String) -> Node:
	var main := MainScene.instantiate()
	main.save_path = path
	root.add_child(main)
	return main


func _report(outcome: String, encounter_id: String = "bell_court") -> Dictionary:
	return {
		"encounter_id": encounter_id,
		"display_name": EncounterCatalog.get_display_name(StringName(encounter_id)),
		"outcome": outcome,
		"time": 1.0,
	}


func _load_document(path: String) -> SaveDocument:
	var loaded := SaveStore.new(path).load_document()
	return loaded["document"] as SaveDocument if loaded["status"] == &"ok" else null


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _cleanup(path: String) -> void:
	for suffix: String in ["", ".tmp", ".corrupt"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)


func _free_main(main: Node) -> void:
	paused = false
	main.free()


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
	_checks += 1
	if not condition:
		_failures.append(message)
