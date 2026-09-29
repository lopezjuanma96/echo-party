class_name HeroRecord
extends RefCounted


var runtime_id: String
var display_name: String
var _progression_data: Dictionary


func _init(
	new_runtime_id: String = "",
	new_display_name: String = "",
	progression_data: Dictionary = {}
) -> void:
	runtime_id = new_runtime_id
	display_name = new_display_name
	_progression_data = progression_data.duplicate(true)


static func capture(
	new_runtime_id: String,
	new_display_name: String,
	progression: HeroProgression
) -> HeroRecord:
	if new_runtime_id.is_empty() or new_display_name.is_empty() or progression == null:
		return null
	return HeroRecord.new(new_runtime_id, new_display_name, progression.to_dict())


func replay_progression() -> HeroProgression:
	return HeroProgression.from_dict(_progression_data.duplicate(true))


func to_dict() -> Dictionary:
	return {
		"runtime_id": runtime_id,
		"display_name": display_name,
		"progression": _progression_data.duplicate(true),
	}


static func from_dict(data: Variant) -> HeroRecord:
	if not data is Dictionary:
		return null
	var dictionary: Dictionary = data
	if dictionary.size() != 3:
		return null
	if (
		not dictionary.has("runtime_id")
		or not dictionary.has("display_name")
		or not dictionary.has("progression")
	):
		return null
	if (
		not dictionary["runtime_id"] is String
		or String(dictionary["runtime_id"]).is_empty()
		or not dictionary["display_name"] is String
		or String(dictionary["display_name"]).is_empty()
	):
		return null
	var replayed := HeroProgression.from_dict(dictionary["progression"])
	if replayed == null:
		return null
	return HeroRecord.new(
		String(dictionary["runtime_id"]),
		String(dictionary["display_name"]),
		replayed.to_dict()
	)
