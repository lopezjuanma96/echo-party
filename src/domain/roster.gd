class_name Roster
extends RefCounted


const ZONE_CANDIDATE := &"candidate"
const ZONE_PARTY := &"party"
const ZONE_MEMORIAL := &"memorial"

var party: Array[HeroRecord] = []
var memorial: Array[HeroRecord] = []
var candidate: HeroRecord
var _party_slots := 0
var _memorial_slots := 0


func _init(party_slots: int, memorial_slots: int) -> void:
	_party_slots = maxi(party_slots, 0)
	_memorial_slots = maxi(memorial_slots, 0)


func set_capacity(party_slots: int, memorial_slots: int) -> void:
	_party_slots = maxi(party_slots, party.size())
	_memorial_slots = maxi(memorial_slots, memorial.size())


func get_party_slots() -> int:
	return _party_slots


func get_memorial_slots() -> int:
	return _memorial_slots


func move(source: Dictionary, dest: Dictionary) -> Dictionary:
	if not _valid_location(source) or not _valid_location(dest):
		return _move_failure("Invalid source or destination.")
	var source_zone := StringName(source["zone"])
	var dest_zone := StringName(dest["zone"])
	var source_index := int(source["index"])
	var dest_index := int(dest["index"])
	if dest_zone == ZONE_CANDIDATE:
		return _move_failure("The candidate row is not a destination.")
	if source_zone != ZONE_CANDIDATE and source_zone != ZONE_PARTY and source_zone != ZONE_MEMORIAL:
		return _move_failure("Unknown source zone.")
	if dest_zone != ZONE_PARTY and dest_zone != ZONE_MEMORIAL:
		return _move_failure("Unknown destination zone.")

	if source_zone == ZONE_CANDIDATE:
		if candidate == null:
			return _move_failure("No candidate is available.")
		return _move_candidate(dest_zone, dest_index)

	var source_records := _records_for_zone(source_zone)
	if source_index >= source_records.size():
		return _move_failure("Unknown source slot.")
	if source_zone == dest_zone:
		if source_index == dest_index:
			return _move_failure("Source and destination are the same slot.")
		if source_zone == ZONE_MEMORIAL or dest_index >= source_records.size():
			return _move_failure("Only two occupied party slots can be swapped.")
		var party_record := party[source_index]
		party[source_index] = party[dest_index]
		party[dest_index] = party_record
		return _move_success()

	var dest_records := _records_for_zone(dest_zone)
	var dest_capacity := _capacity_for_zone(dest_zone)
	var moving_record: HeroRecord = source_records[source_index]
	if dest_index < dest_records.size():
		source_records[source_index] = dest_records[dest_index]
		dest_records[dest_index] = moving_record
		return _move_success()
	if dest_records.size() >= dest_capacity:
		return _move_failure("The destination is full.")
	source_records.remove_at(source_index)
	dest_records.append(moving_record)
	return _move_success()


func preview(source: Dictionary, dest: Dictionary) -> Dictionary:
	var copy := Roster.from_dict(to_dict(), _party_slots, _memorial_slots)
	if copy == null:
		return _move_failure("The roster could not be copied.")
	return copy.move(source, dest)


func discard_candidate(anchors: int) -> Dictionary:
	if candidate == null:
		return {"ok": false, "reason": "No candidate is available.", "anchors_left": maxi(anchors, 0)}
	if anchors <= 0:
		return {"ok": false, "reason": "An Echo Anchor is required.", "anchors_left": 0}
	candidate = null
	return {"ok": true, "reason": "", "anchors_left": anchors - 1}


func offer_candidate(record: HeroRecord) -> bool:
	if candidate != null or not _qualified(record) or _has_runtime_id(record.runtime_id):
		return false
	candidate = record
	return true


func replace_record(runtime_id: String, record: HeroRecord) -> bool:
	if not _qualified(record) or record.runtime_id != runtime_id:
		return false
	for index in party.size():
		if party[index].runtime_id == runtime_id:
			party[index] = record
			return true
	for index in memorial.size():
		if memorial[index].runtime_id == runtime_id:
			memorial[index] = record
			return true
	if candidate != null and candidate.runtime_id == runtime_id:
		candidate = record
		return true
	return false


func party_job_ids() -> Array[StringName]:
	var job_ids: Array[StringName] = []
	for record: HeroRecord in party:
		job_ids.append(record.replay_progression().get_job_id())
	return job_ids


func to_dict() -> Dictionary:
	var party_data: Array = []
	for record: HeroRecord in party:
		party_data.append(record.to_dict())
	var memorial_data: Array = []
	for record: HeroRecord in memorial:
		memorial_data.append(record.to_dict())
	return {
		"party": party_data,
		"memorial": memorial_data,
		"candidate": null if candidate == null else candidate.to_dict(),
	}


static func from_dict(data: Variant, party_slots: int, memorial_slots: int) -> Roster:
	if not data is Dictionary:
		return null
	var dictionary: Dictionary = data
	if dictionary.size() != 3 or not dictionary.has("party") or not dictionary.has("memorial") or not dictionary.has("candidate"):
		return null
	if not dictionary["party"] is Array or not dictionary["memorial"] is Array:
		return null
	if party_slots < 0 or memorial_slots < 0:
		return null
	if dictionary["party"].size() > party_slots or dictionary["memorial"].size() > memorial_slots:
		return null
	var result := Roster.new(party_slots, memorial_slots)
	var runtime_ids: Dictionary = {}
	for zone: StringName in [ZONE_PARTY, ZONE_MEMORIAL]:
		var values: Array = dictionary["party" if zone == ZONE_PARTY else "memorial"]
		for value: Variant in values:
			var record := HeroRecord.from_dict(value)
			if not result._qualified(record) or runtime_ids.has(record.runtime_id):
				return null
			runtime_ids[record.runtime_id] = true
			result._records_for_zone(zone).append(record)
	if dictionary["candidate"] != null:
		var offered := HeroRecord.from_dict(dictionary["candidate"])
		if not result._qualified(offered) or runtime_ids.has(offered.runtime_id):
			return null
		result.candidate = offered
	return result


func _move_candidate(dest_zone: StringName, dest_index: int) -> Dictionary:
	var dest_records := _records_for_zone(dest_zone)
	var dest_capacity := _capacity_for_zone(dest_zone)
	if dest_index >= dest_records.size():
		if dest_records.size() >= dest_capacity:
			return _move_failure("The destination is full.")
		dest_records.append(candidate)
		candidate = null
		return _move_success()
	var displaced: HeroRecord = dest_records[dest_index]
	dest_records[dest_index] = candidate
	candidate = null
	if dest_zone == ZONE_PARTY and memorial.size() < _memorial_slots:
		memorial.append(displaced)
		return _move_success()
	return {"ok": true, "reason": "", "lost_id": displaced.runtime_id}


func _records_for_zone(zone: StringName) -> Array[HeroRecord]:
	return party if zone == ZONE_PARTY else memorial


func _capacity_for_zone(zone: StringName) -> int:
	return _party_slots if zone == ZONE_PARTY else _memorial_slots


func _has_runtime_id(runtime_id: String) -> bool:
	for record: HeroRecord in party:
		if record.runtime_id == runtime_id:
			return true
	for record: HeroRecord in memorial:
		if record.runtime_id == runtime_id:
			return true
	return candidate != null and candidate.runtime_id == runtime_id


func _qualified(record: HeroRecord) -> bool:
	if record == null:
		return false
	var progression := record.replay_progression()
	return progression != null and progression.get_job_id() != HeroProgression.JOB_NOVICE


func _valid_location(location: Dictionary) -> bool:
	if not location.has("zone") or not location.has("index"):
		return false
	var zone: Variant = location["zone"]
	if not zone is String and not zone is StringName:
		return false
	var index: Variant = location["index"]
	return index is int and index >= 0


func _move_success() -> Dictionary:
	return {"ok": true, "reason": "", "lost_id": ""}


func _move_failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "lost_id": ""}
