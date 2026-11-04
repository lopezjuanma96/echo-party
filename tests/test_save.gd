extends SceneTree


var _failures: Array[String] = []


func _init() -> void:
	_test_valid_round_trip()
	_test_float_integer_normalisation()
	_test_top_level_rejections()
	_test_unlock_validation_and_canonical_order()
	_test_trial_clear_validation()
	_test_capacity_and_record_validation()
	_test_pending_validation()
	_test_duplicate_and_hero_counter_validation()
	_test_capacity_tables()
	_test_migration_chain()
	_test_golden_fixture()
	_test_store_new_write_read_and_replace()
	_test_rename_absolute_overwrites()
	_test_corrupt_file_backup()
	_test_wrong_version_preserves_source()
	_test_too_new_is_read_only()
	_test_memory_only_store()
	_test_integer_overflow_rejected()
	_test_blocked_backup_keeps_original()
	_test_failed_write_keeps_original()

	if _failures.is_empty():
		print("Save schema, migration, capacity, and store tests passed (20 cases).")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_valid_round_trip() -> void:
	var data := _valid_dict()
	var document := SaveDocument.from_dict(data)
	_expect(document != null, "valid v1 document is accepted")
	if document != null:
		_expect(document.to_dict() == data, "valid document round-trips losslessly")
		_expect(document.roster.party_job_ids() == [&"vanguard"], "save restores roster records in slot order")


func _test_float_integer_normalisation() -> void:
	var parsed: Variant = JSON.parse_string(JSON.stringify(_valid_dict()))
	var document := SaveDocument.from_dict(parsed)
	_expect(document != null, "JSON whole floats are accepted")
	if document != null:
		var normalized := document.to_dict()
		_expect(normalized["version"] is int and normalized["next_hero_number"] is int, "document integers are normalised to int")
		_expect(normalized["trial_clears"]["bell_court"] is int and normalized["pending"]["anchors"] is int, "nested save integers are normalised to int")
		_expect(normalized == _valid_dict(), "float normalisation preserves all values")


func _test_top_level_rejections() -> void:
	_expect(SaveDocument.from_dict(null) == null, "non-dictionary root is rejected")
	var missing := _valid_dict()
	missing.erase("pending")
	_expect(SaveDocument.from_dict(missing) == null, "missing top-level key is rejected")
	var extra := _valid_dict()
	extra["settings"] = {}
	_expect(SaveDocument.from_dict(extra) == null, "extra top-level key is rejected")
	for version: Variant in [0, 2, 1.5, "1"]:
		var wrong := _valid_dict()
		wrong["version"] = version
		_expect(SaveDocument.from_dict(wrong) == null, "invalid current version %s is rejected" % version)
	for counter: Variant in [0, -1, 1.5, "5"]:
		var wrong := _valid_dict()
		wrong["next_hero_number"] = counter
		_expect(SaveDocument.from_dict(wrong) == null, "invalid hero counter %s is rejected" % counter)


func _test_unlock_validation_and_canonical_order() -> void:
	for unlocks: Variant in [["party_slot_2", "party_slot_2"], ["unknown"], [&"party_slot_2"], "party_slot_2"]:
		var wrong := _valid_dict()
		wrong["unlocks"] = unlocks
		_expect(SaveDocument.from_dict(wrong) == null, "invalid unlock list %s is rejected" % str(unlocks))
	var ordered := _valid_dict()
	ordered["unlocks"] = ["memorial_slot_2", "party_slot_2"]
	ordered["memorial"].append(_record(1, &"mender").to_dict())
	var document := SaveDocument.from_dict(ordered)
	_expect(document != null and document.unlocks == [&"party_slot_2", &"memorial_slot_2"], "unlocks canonicalise to table order")


func _test_trial_clear_validation() -> void:
	for clears: Variant in [{"unknown": 1}, {"bell_court": -1}, {"bell_court": 1.5}, {&"bell_court": 1}, []]:
		var wrong := _valid_dict()
		wrong["trial_clears"] = clears
		_expect(SaveDocument.from_dict(wrong) == null, "invalid trial clear data %s is rejected" % str(clears))


func _test_capacity_and_record_validation() -> void:
	var over_party := _valid_dict()
	over_party["roster"].append(_record(1, &"mender").to_dict())
	over_party["unlocks"] = []
	over_party["next_hero_number"] = 6
	_expect(SaveDocument.from_dict(over_party) == null, "party larger than unlocked capacity is rejected")
	var over_memorial := _valid_dict()
	over_memorial["memorial"].append(_record(1, &"mender").to_dict())
	over_memorial["next_hero_number"] = 6
	_expect(SaveDocument.from_dict(over_memorial) == null, "memorial larger than unlocked capacity is rejected")
	var novice := _valid_dict()
	novice["roster"] = [_record(3, &"novice", 2).to_dict()]
	_expect(SaveDocument.from_dict(novice) == null, "novice-only roster record is rejected")
	var malformed := _valid_dict()
	malformed["roster"][0]["extra"] = true
	_expect(SaveDocument.from_dict(malformed) == null, "malformed hero record is rejected")


func _test_pending_validation() -> void:
	for pending: Variant in [{}, {"candidate": null}, {"candidate": null, "anchors": 2}, {"candidate": null, "anchors": -1}, {"candidate": null, "anchors": 0.5}, {"candidate": null, "anchors": 0, "extra": true}, []]:
		var wrong := _valid_dict()
		wrong["pending"] = pending
		_expect(SaveDocument.from_dict(wrong) == null, "invalid pending data %s is rejected" % str(pending))
	var novice := _valid_dict()
	novice["pending"]["candidate"] = _record(4, &"novice", 2).to_dict()
	_expect(SaveDocument.from_dict(novice) == null, "novice pending candidate is rejected")
	var empty_pending := _valid_dict()
	empty_pending["pending"] = {"candidate": null, "anchors": 0}
	var document := SaveDocument.from_dict(empty_pending)
	_expect(document != null and document.pending and document.to_dict() == empty_pending, "empty pending resolution remains distinct from null")


func _test_duplicate_and_hero_counter_validation() -> void:
	for zone: String in ["roster", "memorial", "pending"]:
		var duplicate := _valid_dict()
		var copy: Dictionary = duplicate["roster"][0].duplicate(true)
		if zone == "pending":
			duplicate["pending"]["candidate"] = copy
		else:
			duplicate[zone].append(copy)
		_expect(SaveDocument.from_dict(duplicate) == null, "duplicate ID across %s is rejected" % zone)
	for counter: int in [3, 4]:
		var wrong := _valid_dict()
		wrong["next_hero_number"] = counter
		_expect(SaveDocument.from_dict(wrong) == null, "hero counter must exceed every hero-N ID")


func _test_capacity_tables() -> void:
	_expect(RosterCapacity.party_slots([]) == 1 and RosterCapacity.memorial_slots([]) == 1, "base capacities are one party and one memorial slot")
	_expect(RosterCapacity.party_slots([&"party_slot_2"]) == 2 and RosterCapacity.memorial_slots([&"party_slot_2"]) == 1, "party unlock adds exactly one party slot")
	_expect(RosterCapacity.party_slots([&"party_slot_2", &"memorial_slot_2"]) == 2 and RosterCapacity.memorial_slots([&"memorial_slot_2"]) == 2, "M3 capacity caps at two slots per zone")
	_expect(RosterCapacity.newly_earned([], 0).is_empty(), "no unlock is earned without a clear")
	_expect(RosterCapacity.newly_earned([], 1) == [&"party_slot_2"], "first clear earns party slot two")
	_expect(RosterCapacity.newly_earned([&"party_slot_2"], 3) == [&"memorial_slot_2"], "third total clear earns only the missing memorial slot")
	_expect(RosterCapacity.next_unlock([], 0)["id"] == &"party_slot_2", "next unlock follows table order")
	_expect(RosterCapacity.next_unlock(RosterCapacity.UNLOCK_IDS, 3).is_empty(), "next unlock is empty when all are earned")
	_expect(RosterCapacity.hint_text([], 0) == "Next unlock: Party slot 2 — clear a Trial (0/1)", "unlock hint reports progress")


func _test_migration_chain() -> void:
	var step := func(data: Dictionary) -> Dictionary:
		var migrated := data.duplicate(true)
		migrated["migrated_marker"] = "v2"
		return migrated
	var result := SaveMigrations.migrate_with({1: step}, 2, {"version": 1.0, "value": 7})
	_expect(result["status"] == &"migrated" and result["from_version"] == 1, "fake v1-to-v2 migration reports its origin")
	_expect(result["data"]["version"] == 2 and result["data"]["migrated_marker"] == "v2", "migration step runs and advances the version")
	_expect(SaveMigrations.migrate_with({}, 2, {"version": 1})["status"] == &"invalid", "missing migration step is invalid")
	_expect(SaveMigrations.migrate({"version": 1.0})["status"] == &"ok", "current whole-float version needs no migration")
	_expect(SaveMigrations.migrate({"version": 0})["status"] == &"invalid", "version zero is invalid")
	_expect(SaveMigrations.migrate({"version": 999})["status"] == &"too_new", "future version is too new")


func _test_golden_fixture() -> void:
	var path := "res://tests/fixtures/save_v1.json"
	var bytes := FileAccess.get_file_as_bytes(path)
	var text := bytes.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	var document := SaveDocument.from_dict(parsed)
	_expect(document != null, "golden v1 fixture loads")
	if document != null:
		var encoded := JSON.stringify(document.to_dict(), "\t", true)
		_expect(encoded.to_utf8_buffer() == bytes, "golden fixture round-trips byte-for-byte")
		_expect(not text.ends_with("\n"), "golden fixture has no trailing newline")


func _test_store_new_write_read_and_replace() -> void:
	var path := "user://test_saves/slice1_store.json"
	_cleanup(path)
	var store := SaveStore.new(path)
	_expect(store.load_document()["status"] == &"new", "missing file returns a new default document")
	var document := SaveDocument.from_dict(_valid_dict())
	_expect(store.save_document(document), "initial atomic save succeeds")
	_expect(not FileAccess.file_exists(path + ".tmp"), "successful save removes the temporary path")
	document.next_hero_number = 6
	_expect(store.save_document(document), "atomic replace of an existing save succeeds")
	var loaded := store.load_document()
	_expect(loaded["status"] == &"ok" and loaded["document"].next_hero_number == 6, "replaced save reads back the newest document")
	_cleanup(path)


func _test_rename_absolute_overwrites() -> void:
	var path := "user://test_saves/rename_probe.json"
	var temporary := path + ".tmp"
	_cleanup(path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_write_text(path, "old")
	_write_text(temporary, "new")
	var error := DirAccess.rename_absolute(temporary, path)
	_expect(error == OK and FileAccess.get_file_as_string(path) == "new", "DirAccess.rename_absolute overwrites an existing user:// target")
	_cleanup(path)


func _test_corrupt_file_backup() -> void:
	var path := "user://test_saves/corrupt.json"
	_cleanup(path)
	_write_text(path, "{not json")
	_write_text(path + ".corrupt", "old backup")
	var store := SaveStore.new(path)
	var loaded := store.load_document()
	_expect(loaded["status"] == &"corrupt" and loaded["document"].next_hero_number == 1, "corrupt JSON returns a fresh default")
	_expect(FileAccess.get_file_as_string(path + ".corrupt") == "{not json", "corrupt backup overwrites the earlier copy with exact source bytes")
	_expect(FileAccess.get_file_as_string(path) == "{not json", "corrupt source is not overwritten")
	_cleanup(path)


func _test_wrong_version_preserves_source() -> void:
	var path := "user://test_saves/wrong_version.json"
	_cleanup(path)
	var data := _valid_dict()
	data["version"] = 0
	var source := JSON.stringify(data, "\t", true)
	_write_text(path, source)
	var loaded := SaveStore.new(path).load_document()
	_expect(loaded["status"] == &"corrupt", "wrong old version produces corrupt status")
	_expect(FileAccess.get_file_as_string(path) == source, "wrong-version source remains untouched")
	_cleanup(path)


func _test_too_new_is_read_only() -> void:
	var path := "user://test_saves/too_new.json"
	_cleanup(path)
	var data := _valid_dict()
	data["version"] = 999
	var source := JSON.stringify(data, "\t", true)
	_write_text(path, source)
	var store := SaveStore.new(path)
	var loaded := store.load_document()
	_expect(loaded["status"] == &"too_new" and store.read_only, "future save loads default in read-only mode")
	_expect(not store.save_document(SaveDocument.new_default()), "read-only store refuses all saves")
	_expect(FileAccess.get_file_as_string(path) == source and not FileAccess.file_exists(path + ".tmp"), "future save is never overwritten")
	_cleanup(path)


func _test_memory_only_store() -> void:
	var store := SaveStore.new()
	var loaded := store.load_document()
	_expect(loaded["status"] == &"new" and loaded["document"].to_dict() == SaveDocument.new_default().to_dict(), "memory-only store returns defaults")
	_expect(store.save_document(SaveDocument.new_default()) and not store.read_only, "memory-only save succeeds without file I/O")


func _valid_dict() -> Dictionary:
	return {
		"version": 1,
		"next_hero_number": 5,
		"unlocks": ["party_slot_2"],
		"trial_clears": {"bell_court": 2},
		"roster": [_record(3, &"vanguard", 4).to_dict()],
		"memorial": [_record(2, &"mender", 3).to_dict()],
		"pending": {"candidate": _record(4, &"arcanist", 5).to_dict(), "anchors": 1},
	}


func _record(number: int, job_id: StringName = &"vanguard", level: int = 3) -> HeroRecord:
	var progression := HeroProgression.new()
	progression.grant_experience((level - 1) * HeroProgression.XP_PER_LEVEL)
	for choice_level in range(2, level + 1):
		if choice_level == HeroProgression.ADVANCEMENT_LEVEL:
			progression.apply_job_choice(choice_level, job_id)
		else:
			progression.apply_attribute_choice(choice_level, HeroProgression.ATTRIBUTE_MIGHT)
	return HeroRecord.capture("hero-%d" % number, "Hero %d" % number, progression)


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _cleanup(path: String) -> void:
	for suffix: String in ["", ".tmp", ".corrupt"]:
		var target := path + suffix
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_integer_overflow_rejected() -> void:
	var counter := _valid_dict()
	counter["next_hero_number"] = 1e30
	_expect(SaveDocument.from_dict(counter) == null, "a hero counter beyond 2^53 is rejected instead of overflowing")
	var anchors := _valid_dict()
	anchors["pending"]["anchors"] = 1e30
	_expect(SaveDocument.from_dict(anchors) == null, "a huge pending anchor count is rejected instead of overflowing")
	var version := _valid_dict()
	version["version"] = 1e30
	_expect(SaveMigrations.migrate(version)["status"] == &"invalid", "a huge save version is invalid rather than too new")


func _test_blocked_backup_keeps_original() -> void:
	var path := "user://test_saves/blocked_backup.json"
	_cleanup(path)
	DirAccess.remove_absolute(path + ".corrupt")
	_write_text(path, "{not json")
	DirAccess.make_dir_recursive_absolute(path + ".corrupt")
	var store := SaveStore.new(path)
	var loaded := store.load_document()
	_expect(
		loaded["status"] == &"corrupt" and not loaded["backed_up"] and store.read_only,
		"a corrupt save whose backup fails makes the store read-only"
	)
	_expect(not store.save_document(SaveDocument.new_default()), "a read-only store refuses to save")
	_expect(FileAccess.get_file_as_string(path) == "{not json", "the unbacked corrupt original is never overwritten")
	DirAccess.remove_absolute(path + ".corrupt")
	_cleanup(path)


func _test_failed_write_keeps_original() -> void:
	var path := "user://test_saves/failed_write.json"
	_cleanup(path)
	DirAccess.remove_absolute(path + ".tmp")
	var store := SaveStore.new(path)
	_expect(store.save_document(SaveDocument.new_default()), "baseline save succeeds")
	var original := FileAccess.get_file_as_string(path)
	DirAccess.make_dir_recursive_absolute(path + ".tmp")
	var document := SaveDocument.new_default()
	document.next_hero_number = 7
	_expect(not store.save_document(document), "a save whose temporary file cannot be written reports failure")
	_expect(FileAccess.get_file_as_string(path) == original, "a failed write leaves the existing save intact")
	DirAccess.remove_absolute(path + ".tmp")
	_cleanup(path)
