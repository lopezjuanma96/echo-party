class_name SaveDocument
extends RefCounted


const CURRENT_VERSION := 1
const TOP_LEVEL_KEYS := [
	"version",
	"next_hero_number",
	"unlocks",
	"trial_clears",
	"roster",
	"memorial",
	"pending",
]

var next_hero_number := 1
var unlocks: Array[StringName] = []
var trial_clears: Dictionary = {}
var roster: Roster
var pending := false
var pending_anchors := 0


func _init() -> void:
	roster = Roster.new(RosterCapacity.BASE_PARTY_SLOTS, RosterCapacity.BASE_MEMORIAL_SLOTS)


static func new_default() -> SaveDocument:
	return SaveDocument.new()


func to_dict() -> Dictionary:
	var unlock_data: Array = []
	for unlock_id: StringName in unlocks:
		unlock_data.append(String(unlock_id))
	var roster_data := roster.to_dict()
	var pending_data: Variant = null
	if pending or roster.candidate != null or pending_anchors != 0:
		pending_data = {
			"candidate": roster_data["candidate"],
			"anchors": pending_anchors,
		}
	return {
		"version": CURRENT_VERSION,
		"next_hero_number": next_hero_number,
		"unlocks": unlock_data,
		"trial_clears": trial_clears.duplicate(true),
		"roster": roster_data["party"],
		"memorial": roster_data["memorial"],
		"pending": pending_data,
	}


static func from_dict(data: Variant) -> SaveDocument:
	if not data is Dictionary:
		return null
	var dictionary: Dictionary = data
	if dictionary.size() != TOP_LEVEL_KEYS.size():
		return null
	for key: String in TOP_LEVEL_KEYS:
		if not dictionary.has(key):
			return null
	if not _is_positive_integer(dictionary["version"]) or int(dictionary["version"]) != CURRENT_VERSION:
		return null
	if not _is_positive_integer(dictionary["next_hero_number"]):
		return null

	var canonical_unlocks: Array[StringName] = []
	if not dictionary["unlocks"] is Array:
		return null
	var seen_unlocks: Dictionary = {}
	for value: Variant in dictionary["unlocks"]:
		if not value is String:
			return null
		var unlock_id := StringName(value)
		if not RosterCapacity.UNLOCK_IDS.has(unlock_id) or seen_unlocks.has(unlock_id):
			return null
		seen_unlocks[unlock_id] = true
	for unlock_id: StringName in RosterCapacity.UNLOCK_IDS:
		if seen_unlocks.has(unlock_id):
			canonical_unlocks.append(unlock_id)

	if not dictionary["trial_clears"] is Dictionary:
		return null
	var normalized_clears: Dictionary = {}
	for key: Variant in dictionary["trial_clears"]:
		if not key is String or not EncounterCatalog.has_encounter(StringName(key)):
			return null
		if not _is_nonnegative_integer(dictionary["trial_clears"][key]):
			return null
		normalized_clears[key] = int(dictionary["trial_clears"][key])

	var is_pending := dictionary["pending"] != null
	var candidate_data: Variant = null
	var anchors := 0
	if is_pending:
		if not dictionary["pending"] is Dictionary:
			return null
		var pending_data: Dictionary = dictionary["pending"]
		if pending_data.size() != 2 or not pending_data.has("candidate") or not pending_data.has("anchors"):
			return null
		if not _is_nonnegative_integer(pending_data["anchors"]):
			return null
		anchors = int(pending_data["anchors"])
		if anchors > 1:
			return null
		candidate_data = pending_data["candidate"]

	var parsed_roster := Roster.from_dict(
		{
			"party": dictionary["roster"],
			"memorial": dictionary["memorial"],
			"candidate": candidate_data,
		},
		RosterCapacity.party_slots(canonical_unlocks),
		RosterCapacity.memorial_slots(canonical_unlocks)
	)
	if parsed_roster == null:
		return null
	var counter := int(dictionary["next_hero_number"])
	if not _counter_exceeds_records(counter, parsed_roster):
		return null

	var document := SaveDocument.new()
	document.next_hero_number = counter
	document.unlocks = canonical_unlocks
	document.trial_clears = normalized_clears
	document.roster = parsed_roster
	document.pending = is_pending
	document.pending_anchors = anchors
	return document


static func _counter_exceeds_records(counter: int, parsed_roster: Roster) -> bool:
	var records: Array[HeroRecord] = []
	records.append_array(parsed_roster.party)
	records.append_array(parsed_roster.memorial)
	if parsed_roster.candidate != null:
		records.append(parsed_roster.candidate)
	for record: HeroRecord in records:
		if not record.runtime_id.begins_with("hero-"):
			continue
		var suffix := record.runtime_id.trim_prefix("hero-")
		if suffix.is_valid_int() and int(suffix) >= 1 and counter <= int(suffix):
			return false
	return true


## Largest integer a JSON double represents exactly; larger values would
## overflow or lose precision when converted to `int`.
const MAX_SAFE_INTEGER := 9007199254740991


static func _is_nonnegative_integer(value: Variant) -> bool:
	if value is int:
		return value >= 0 and value <= MAX_SAFE_INTEGER
	if value is float:
		return (
			is_finite(value)
			and value >= 0.0
			and value <= float(MAX_SAFE_INTEGER)
			and value == floor(value)
		)
	return false


static func _is_positive_integer(value: Variant) -> bool:
	return _is_nonnegative_integer(value) and value >= 1
