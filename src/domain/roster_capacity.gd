class_name RosterCapacity
extends RefCounted


const BASE_PARTY_SLOTS := 1
const BASE_MEMORIAL_SLOTS := 1
const UNLOCKS := [
	{"id": &"party_slot_2", "total_clears": 1, "party_slots": 1},
	{"id": &"memorial_slot_2", "total_clears": 3, "memorial_slots": 1},
]
const UNLOCK_IDS: Array[StringName] = [&"party_slot_2", &"memorial_slot_2"]


static func party_slots(unlocks: Array) -> int:
	var count := BASE_PARTY_SLOTS
	for unlock: Dictionary in UNLOCKS:
		if _has_unlock(unlocks, unlock["id"]):
			count += int(unlock.get("party_slots", 0))
	return count


static func memorial_slots(unlocks: Array) -> int:
	var count := BASE_MEMORIAL_SLOTS
	for unlock: Dictionary in UNLOCKS:
		if _has_unlock(unlocks, unlock["id"]):
			count += int(unlock.get("memorial_slots", 0))
	return count


static func newly_earned(unlocks: Array, total_clears: int) -> Array[StringName]:
	var earned: Array[StringName] = []
	for unlock: Dictionary in UNLOCKS:
		var unlock_id := StringName(unlock["id"])
		if total_clears >= int(unlock["total_clears"]) and not _has_unlock(unlocks, unlock_id):
			earned.append(unlock_id)
	return earned


static func next_unlock(unlocks: Array, total_clears: int) -> Dictionary:
	for unlock: Dictionary in UNLOCKS:
		if not _has_unlock(unlocks, unlock["id"]):
			var result := unlock.duplicate(true)
			result["current_clears"] = clampi(total_clears, 0, int(unlock["total_clears"]))
			return result
	return {}


static func hint_text(unlocks: Array, total_clears: int) -> String:
	var next := next_unlock(unlocks, total_clears)
	if next.is_empty():
		return "All roster slots unlocked."
	var unlock_id := StringName(next["id"])
	var label := "Party slot 2" if unlock_id == &"party_slot_2" else "Memorial slot 2"
	var requirement := "clear a Trial" if int(next["total_clears"]) == 1 else "clear Trials"
	return "Next unlock: %s — %s (%d/%d)" % [
		label,
		requirement,
		int(next["current_clears"]),
		int(next["total_clears"]),
	]


static func _has_unlock(unlocks: Array, unlock_id: StringName) -> bool:
	for value: Variant in unlocks:
		if (value is String or value is StringName) and StringName(value) == unlock_id:
			return true
	return false
