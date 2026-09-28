class_name HeroProgression
extends RefCounted


const ATTRIBUTE_MIGHT := &"might"
const ATTRIBUTE_VITALITY := &"vitality"
const ATTRIBUTE_IDS: Array[StringName] = [ATTRIBUTE_MIGHT, ATTRIBUTE_VITALITY]
const JOB_NOVICE := &"novice"
const JOB_VANGUARD := &"vanguard"
const JOB_ARCANIST := &"arcanist"
const ADVANCEMENT_LEVEL := 3
const JOB_IDS: Array[StringName] = [JOB_VANGUARD, JOB_ARCANIST]
const BASE_MAX_HEALTH := 100
const BASE_ATTACK_DAMAGE := 25
const MIGHT_ATTACK_BONUS := 5
const VITALITY_HEALTH_BONUS := 20
const XP_PER_LEVEL := 100

var _experience := 0
var _choices: Array[Dictionary] = []

var level: int:
	get:
		return 1 + int(_experience / XP_PER_LEVEL)

var experience: int:
	get:
		return _experience


func grant_experience(amount: int) -> int:
	if amount <= 0:
		return 0
	var previous_level := level
	_experience += amount
	return level - previous_level


func get_experience_into_level() -> int:
	return _experience % XP_PER_LEVEL


func get_pending_choice_levels() -> Array[int]:
	var pending: Array[int] = []
	for choice_level in range(2 + _choices.size(), level + 1):
		pending.append(choice_level)
	return pending


func has_pending_choice() -> bool:
	return _choices.size() < level - 1


func apply_attribute_choice(choice_level: int, attribute_id: StringName) -> bool:
	if not ATTRIBUTE_IDS.has(attribute_id):
		return false
	if not has_pending_choice() or choice_level != 2 + _choices.size():
		return false
	if choice_level == ADVANCEMENT_LEVEL:
		return false
	_choices.append({
		"level": choice_level,
		"attribute_id": String(attribute_id),
	})
	return true


func apply_job_choice(choice_level: int, job_id: StringName) -> bool:
	if not JOB_IDS.has(job_id):
		return false
	if not has_pending_choice() or choice_level != 2 + _choices.size():
		return false
	if choice_level != ADVANCEMENT_LEVEL:
		return false
	_choices.append({
		"level": choice_level,
		"job_id": String(job_id),
	})
	return true


func get_job_id() -> StringName:
	for choice in _choices:
		if choice.has("job_id"):
			return StringName(choice["job_id"])
	return JOB_NOVICE


func get_attack_damage() -> int:
	return BASE_ATTACK_DAMAGE + _count_attribute(ATTRIBUTE_MIGHT) * MIGHT_ATTACK_BONUS


func get_max_health() -> int:
	return BASE_MAX_HEALTH + _count_attribute(ATTRIBUTE_VITALITY) * VITALITY_HEALTH_BONUS


func get_choices() -> Array[Dictionary]:
	return _choices.duplicate(true)


func to_dict() -> Dictionary:
	return {
		"level": level,
		"experience": _experience,
		"choices": get_choices(),
	}


static func from_dict(data: Variant) -> HeroProgression:
	if not data is Dictionary:
		return null
	var dictionary: Dictionary = data
	if dictionary.size() != 3:
		return null
	if not dictionary.has("level") or not dictionary.has("experience") or not dictionary.has("choices"):
		return null
	if not _is_nonnegative_integer(dictionary["experience"]):
		return null
	if not _is_positive_integer(dictionary["level"]):
		return null
	if not dictionary["choices"] is Array:
		return null

	var experience_value := int(dictionary["experience"])
	var expected_level := 1 + int(experience_value / XP_PER_LEVEL)
	if int(dictionary["level"]) != expected_level:
		return null

	var choices_value: Array = dictionary["choices"]
	if choices_value.size() > expected_level - 1:
		return null
	var validated_choices: Array[Dictionary] = []
	for index in choices_value.size():
		var choice_value: Variant = choices_value[index]
		if not choice_value is Dictionary:
			return null
		var choice: Dictionary = choice_value
		if choice.size() != 2 or not choice.has("level"):
			return null
		if not _is_positive_integer(choice["level"]):
			return null
		if int(choice["level"]) != index + 2:
			return null
		var choice_level := index + 2
		if choice_level == ADVANCEMENT_LEVEL:
			if not choice.has("job_id") or not choice["job_id"] is String:
				return null
			var job_id := StringName(choice["job_id"])
			if not JOB_IDS.has(job_id):
				return null
			validated_choices.append({"level": choice_level, "job_id": String(job_id)})
		else:
			if not choice.has("attribute_id") or not choice["attribute_id"] is String:
				return null
			var attribute_id := StringName(choice["attribute_id"])
			if not ATTRIBUTE_IDS.has(attribute_id):
				return null
			validated_choices.append({
				"level": choice_level,
				"attribute_id": String(attribute_id),
			})

	var progression := new()
	progression._experience = experience_value
	progression._choices = validated_choices
	return progression


func _count_attribute(attribute_id: StringName) -> int:
	var count := 0
	for choice in _choices:
		if choice.has("attribute_id") and StringName(choice["attribute_id"]) == attribute_id:
			count += 1
	return count


static func _is_nonnegative_integer(value: Variant) -> bool:
	if value is int:
		return value >= 0
	if value is float:
		return is_finite(value) and value >= 0.0 and value == floor(value)
	return false


static func _is_positive_integer(value: Variant) -> bool:
	return _is_nonnegative_integer(value) and value >= 1
