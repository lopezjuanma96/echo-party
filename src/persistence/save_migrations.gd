class_name SaveMigrations
extends RefCounted


const CURRENT_VERSION := 1


static func migrate(raw: Variant) -> Dictionary:
	return migrate_with({}, CURRENT_VERSION, raw)


static func migrate_with(steps: Dictionary, current: int, raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return _result(&"invalid", {}, 0)
	var data: Dictionary = raw.duplicate(true)
	if not data.has("version") or not _is_positive_integer(data["version"]):
		return _result(&"invalid", {}, 0)
	var version := int(data["version"])
	var from_version := version
	if current < 1 or version > current:
		return _result(&"too_new" if version > current else &"invalid", {}, from_version)
	data["version"] = version
	while version < current:
		var step_value: Variant = steps.get(version)
		if not step_value is Callable or not Callable(step_value).is_valid():
			return _result(&"invalid", {}, from_version)
		var migrated: Variant = Callable(step_value).call(data)
		if not migrated is Dictionary:
			return _result(&"invalid", {}, from_version)
		data = migrated.duplicate(true)
		version += 1
		data["version"] = version
	return _result(&"ok" if version == from_version else &"migrated", data, from_version)


static func _result(status: StringName, data: Dictionary, from_version: int) -> Dictionary:
	return {"status": status, "data": data, "from_version": from_version}


static func _is_positive_integer(value: Variant) -> bool:
	if value is int:
		return value >= 1 and value <= SaveDocument.MAX_SAFE_INTEGER
	if value is float:
		return (
			is_finite(value)
			and value >= 1.0
			and value <= float(SaveDocument.MAX_SAFE_INTEGER)
			and value == floor(value)
		)
	return false
