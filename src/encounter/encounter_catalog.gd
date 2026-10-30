class_name EncounterCatalog
extends RefCounted
## Static encounter data keyed by stable ID. The director is the only consumer
## of `waves`; the HUD reads the display name, trigger level, and needs.


const ENCOUNTERS := {
	&"bell_court": {
		"display_name": "Bell Court",
		"banner_title": "THE BELL COURT",
		"trigger_level": 5,
		"needs": [&"interrupt", &"area", &"sustain"],
		"warning_duration": 3.0,
		"spawn_grace": 1.0,
		"seed": 7117,
		"pack_jitter_radius": 40.0,
		"waves": [
			{
				"time": 0.0,
				"spawns": [
					{"enemy_id": &"brute", "position": Vector2(-150.0, -170.0), "count": 1},
					{"enemy_id": &"brute", "position": Vector2(360.0, -150.0), "count": 1},
					{"enemy_id": &"hexcaller", "position": Vector2(420.0, 150.0), "count": 1},
				],
			},
			{
				"time": 4.0,
				"spawns": [
					{"enemy_id": &"skitter", "position": Vector2(-440.0, 220.0), "count": 4},
				],
			},
			{
				"time": 12.0,
				"spawns": [
					{"enemy_id": &"skitter", "position": Vector2(460.0, 230.0), "count": 4},
				],
			},
		],
	},
}


static func has_encounter(encounter_id: StringName) -> bool:
	return ENCOUNTERS.has(encounter_id)


static func get_encounter(encounter_id: StringName) -> Dictionary:
	return ENCOUNTERS.get(encounter_id, {})


static func get_display_name(encounter_id: StringName) -> String:
	return get_encounter(encounter_id).get("display_name", String(encounter_id))


static func get_trigger_level(encounter_id: StringName) -> int:
	return int(get_encounter(encounter_id).get("trigger_level", 1))


static func get_needs(encounter_id: StringName) -> Array:
	return get_encounter(encounter_id).get("needs", [])


static func get_total_enemy_count(encounter_id: StringName) -> int:
	var total := 0
	for wave: Dictionary in get_encounter(encounter_id).get("waves", []):
		for spawn: Dictionary in wave["spawns"]:
			total += int(spawn.get("count", 1))
	return total
