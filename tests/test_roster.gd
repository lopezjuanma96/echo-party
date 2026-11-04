extends SceneTree


var _failures: Array[String] = []


func _init() -> void:
	_test_candidate_to_empty_party()
	_test_candidate_to_empty_memorial()
	_test_candidate_replaces_party_and_stores_displaced()
	_test_candidate_replaces_party_and_loses_displaced()
	_test_candidate_replaces_memorial()
	_test_party_memorial_swaps()
	_test_party_party_swap()
	_test_cross_zone_moves_to_empty_slots()
	_test_noop_and_unknown_moves()
	_test_preview_does_not_mutate()
	_test_discard_candidate()
	_test_offer_candidate()
	_test_capacity_shrink_guard()
	_test_replace_record()
	_test_extended_with()
	_test_duplicate_id_rejection()
	_test_slot_order_and_dictionary_round_trip()

	if _failures.is_empty():
		print("Roster and record extension tests passed (17 cases).")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_candidate_to_empty_party() -> void:
	var roster := Roster.new(1, 1)
	var offered := _record(2, &"mender")
	roster.offer_candidate(offered)
	var result := roster.move(_at(Roster.ZONE_CANDIDATE), _at(Roster.ZONE_PARTY))
	_expect(result["ok"] and result["lost_id"].is_empty(), "candidate joins an empty party slot")
	_expect(roster.candidate == null and _ids(roster.party) == ["hero-2"], "candidate leaves the pending row")


func _test_candidate_to_empty_memorial() -> void:
	var roster := Roster.new(1, 1)
	roster.offer_candidate(_record(2, &"mender"))
	var result := roster.move(_at(Roster.ZONE_CANDIDATE), _at(Roster.ZONE_MEMORIAL, 4))
	_expect(result["ok"], "an at-or-past-end empty memorial index appends")
	_expect(_ids(roster.memorial) == ["hero-2"] and roster.candidate == null, "candidate is stored in memorial")


func _test_candidate_replaces_party_and_stores_displaced() -> void:
	var roster := Roster.new(1, 1)
	roster.party.append(_record(1))
	roster.offer_candidate(_record(2, &"mender"))
	var result := roster.move(_at(Roster.ZONE_CANDIDATE), _at(Roster.ZONE_PARTY))
	_expect(result["ok"] and result["lost_id"].is_empty(), "displaced party hero is not lost with memorial space")
	_expect(_ids(roster.party) == ["hero-2"] and _ids(roster.memorial) == ["hero-1"], "displaced party hero takes the first free memorial slot")


func _test_candidate_replaces_party_and_loses_displaced() -> void:
	var roster := Roster.new(1, 1)
	roster.party.append(_record(1))
	roster.memorial.append(_record(3, &"arcanist"))
	roster.offer_candidate(_record(2, &"mender"))
	var before := roster.to_dict()
	var result := roster.move(_at(Roster.ZONE_CANDIDATE), _at(Roster.ZONE_PARTY))
	_expect(result["ok"] and result["lost_id"] == "hero-1", "displaced party hero is lost when memorial is full")
	_expect(_ids(roster.party) == ["hero-2"] and _ids(roster.memorial) == ["hero-3"], "full memorial remains unchanged")
	_expect(before["candidate"]["runtime_id"] == "hero-2", "test setup retains the original candidate snapshot")


func _test_candidate_replaces_memorial() -> void:
	var roster := Roster.new(1, 1)
	roster.memorial.append(_record(1))
	roster.offer_candidate(_record(2, &"mender"))
	var result := roster.move(_at(Roster.ZONE_CANDIDATE), _at(Roster.ZONE_MEMORIAL))
	_expect(result["ok"] and result["lost_id"] == "hero-1", "candidate replacing memorial reports the lost hero")
	_expect(_ids(roster.memorial) == ["hero-2"] and roster.candidate == null, "candidate takes the memorial slot")


func _test_party_memorial_swaps() -> void:
	var roster := Roster.new(1, 1)
	roster.party.append(_record(1))
	roster.memorial.append(_record(2, &"mender"))
	var first := roster.move(_at(Roster.ZONE_PARTY), _at(Roster.ZONE_MEMORIAL))
	_expect(first["ok"] and _ids(roster.party) == ["hero-2"] and _ids(roster.memorial) == ["hero-1"], "party and memorial occupants swap")
	var second := roster.move(_at(Roster.ZONE_MEMORIAL), _at(Roster.ZONE_PARTY))
	_expect(second["ok"] and _ids(roster.party) == ["hero-1"] and _ids(roster.memorial) == ["hero-2"], "memorial and party swap in the reverse direction")


func _test_party_party_swap() -> void:
	var roster := Roster.new(2, 1)
	roster.party.append(_record(1))
	roster.party.append(_record(2, &"mender"))
	var result := roster.move(_at(Roster.ZONE_PARTY, 0), _at(Roster.ZONE_PARTY, 1))
	_expect(result["ok"] and _ids(roster.party) == ["hero-2", "hero-1"], "party slots swap deterministically")
	_expect(roster.party_job_ids() == [&"mender", &"vanguard"], "party job IDs follow swapped slot order")


func _test_cross_zone_moves_to_empty_slots() -> void:
	var roster := Roster.new(1, 1)
	roster.party.append(_record(1))
	var to_memorial := roster.move(_at(Roster.ZONE_PARTY), _at(Roster.ZONE_MEMORIAL, 8))
	_expect(to_memorial["ok"] and roster.party.is_empty() and _ids(roster.memorial) == ["hero-1"], "party hero moves to an empty memorial slot")
	var to_party := roster.move(_at(Roster.ZONE_MEMORIAL), _at(Roster.ZONE_PARTY, 8))
	_expect(to_party["ok"] and roster.memorial.is_empty() and _ids(roster.party) == ["hero-1"], "memorial hero moves to an empty party slot")


func _test_noop_and_unknown_moves() -> void:
	var roster := Roster.new(2, 2)
	roster.party.append(_record(1))
	roster.memorial.append(_record(2, &"mender"))
	roster.memorial.append(_record(3, &"arcanist"))
	var before := roster.to_dict()
	_expect(not roster.move(_at(Roster.ZONE_PARTY), _at(Roster.ZONE_PARTY))["ok"], "same-slot party move is rejected")
	_expect(not roster.move(_at(Roster.ZONE_MEMORIAL, 0), _at(Roster.ZONE_MEMORIAL, 1))["ok"], "memorial-to-memorial move is rejected")
	_expect(not roster.move(_at(Roster.ZONE_PARTY, 9), _at(Roster.ZONE_MEMORIAL))["ok"], "unknown source index is rejected")
	_expect(not roster.move(_at(Roster.ZONE_PARTY), _at(Roster.ZONE_CANDIDATE))["ok"], "candidate cannot be a destination")
	_expect(not roster.move(_at(Roster.ZONE_PARTY), _at(Roster.ZONE_PARTY, 1))["ok"], "party hero cannot move to an empty same-zone slot")
	_expect(roster.to_dict() == before, "every failed move leaves the roster untouched")


func _test_preview_does_not_mutate() -> void:
	var roster := Roster.new(1, 1)
	roster.party.append(_record(1))
	roster.memorial.append(_record(3, &"arcanist"))
	roster.offer_candidate(_record(2, &"mender"))
	var before := roster.to_dict()
	var result := roster.preview(_at(Roster.ZONE_CANDIDATE), _at(Roster.ZONE_PARTY))
	_expect(result["ok"] and result["lost_id"] == "hero-1", "preview reports the same loss as commit")
	_expect(roster.to_dict() == before, "preview runs on a copy")


func _test_discard_candidate() -> void:
	var roster := Roster.new(1, 1)
	var before := roster.to_dict()
	_expect(not roster.discard_candidate(0)["ok"], "discard without a candidate fails")
	roster.offer_candidate(_record(2, &"mender"))
	var without_anchor := roster.discard_candidate(0)
	_expect(not without_anchor["ok"] and without_anchor["anchors_left"] == 0, "discard fails with zero Anchors")
	_expect(roster.candidate != null and roster.party == before["party"], "failed Anchor discard preserves the candidate")
	var with_anchor := roster.discard_candidate(2)
	_expect(with_anchor["ok"] and with_anchor["anchors_left"] == 1 and roster.candidate == null, "discard spends exactly one Anchor")


func _test_offer_candidate() -> void:
	var roster := Roster.new(1, 1)
	_expect(not roster.offer_candidate(_record(1, &"novice", 2)), "novice-only candidate is rejected")
	_expect(roster.offer_candidate(_record(2, &"mender")), "job-bearing candidate is accepted")
	_expect(not roster.offer_candidate(_record(3, &"arcanist")), "a second unresolved candidate is rejected")


func _test_capacity_shrink_guard() -> void:
	var roster := Roster.new(2, 2)
	roster.party.append(_record(1))
	roster.party.append(_record(2, &"mender"))
	roster.memorial.append(_record(3, &"arcanist"))
	roster.set_capacity(0, 0)
	_expect(roster.party.size() == 2 and roster.memorial.size() == 1, "capacity shrink never removes contents")
	roster.offer_candidate(_record(4, &"mender"))
	_expect(not roster.move(_at(Roster.ZONE_CANDIDATE), _at(Roster.ZONE_PARTY, 2))["ok"], "shrunk capacity still prevents exceeding retained contents")


func _test_replace_record() -> void:
	var roster := Roster.new(1, 1)
	var original := _record(1)
	roster.party.append(original)
	var extended := _record(1, &"vanguard", 4)
	_expect(roster.replace_record("hero-1", extended), "party record replacement succeeds")
	_expect(roster.party[0] == extended and original.replay_progression().level == 3, "replacement is immediate and the old record is unchanged")
	_expect(not roster.replace_record("hero-1", _record(2, &"mender")), "replacement cannot change runtime ID")
	_expect(not roster.replace_record("missing", _record(3, &"mender")), "unknown runtime ID is not replaced")


func _test_extended_with() -> void:
	var original := _record(1)
	var progression := original.replay_progression()
	_expect(original.extended_with(progression) == null, "unchanged progression is not an extension")
	progression.grant_experience(100)
	_expect(original.extended_with(progression) == null, "a level without a new choice is not an extension")
	progression.apply_attribute_choice(4, HeroProgression.ATTRIBUTE_VITALITY)
	var extended := original.extended_with(progression)
	_expect(extended != null and extended.runtime_id == original.runtime_id and extended.display_name == original.display_name, "extension preserves identity")
	_expect(extended.replay_progression().level == 4 and original.replay_progression().level == 3, "extension returns a new record and leaves the original immutable")
	var divergent := HeroProgression.new()
	divergent.grant_experience(300)
	divergent.apply_attribute_choice(2, HeroProgression.ATTRIBUTE_VITALITY)
	divergent.apply_job_choice(3, HeroProgression.JOB_VANGUARD)
	divergent.apply_attribute_choice(4, HeroProgression.ATTRIBUTE_MIGHT)
	_expect(original.extended_with(divergent) == null, "divergent choice prefix is rejected")


func _test_duplicate_id_rejection() -> void:
	var roster := Roster.new(2, 2)
	roster.party.append(_record(1))
	_expect(not roster.offer_candidate(_record(1, &"mender")), "candidate cannot duplicate a party ID")
	var duplicate_party := {
		"party": [_record(1).to_dict(), _record(1).to_dict()],
		"memorial": [],
		"candidate": null,
	}
	_expect(Roster.from_dict(duplicate_party, 2, 1) == null, "serialized duplicate IDs are rejected")


func _test_slot_order_and_dictionary_round_trip() -> void:
	var roster := Roster.new(2, 1)
	roster.party.append(_record(1))
	roster.party.append(_record(2, &"mender"))
	roster.memorial.append(_record(3, &"arcanist"))
	roster.offer_candidate(_record(4, &"mender"))
	var copy := Roster.from_dict(roster.to_dict(), 2, 1)
	_expect(copy != null and copy.to_dict() == roster.to_dict(), "roster dictionary round-trip is lossless")
	_expect(copy.party_job_ids() == [&"vanguard", &"mender"], "final recorded jobs serialize in slot order")


func _record(number: int, job_id: StringName = &"vanguard", level: int = 3) -> HeroRecord:
	var progression := HeroProgression.new()
	progression.grant_experience((level - 1) * HeroProgression.XP_PER_LEVEL)
	for choice_level in range(2, level + 1):
		if choice_level == HeroProgression.ADVANCEMENT_LEVEL:
			progression.apply_job_choice(choice_level, job_id)
		else:
			progression.apply_attribute_choice(choice_level, HeroProgression.ATTRIBUTE_MIGHT)
	return HeroRecord.capture("hero-%d" % number, "Hero %d" % number, progression)


func _at(zone: StringName, index: int = 0) -> Dictionary:
	return {"zone": zone, "index": index}


func _ids(records: Array[HeroRecord]) -> Array[String]:
	var ids: Array[String] = []
	for record: HeroRecord in records:
		ids.append(record.runtime_id)
	return ids


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
