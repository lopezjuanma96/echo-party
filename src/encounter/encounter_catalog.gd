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
		"large_party": {
			"min_echoes": 2,
			"enemy_health_multiplier": 1.25,
			"extra_waves": [
				{
					"time": 0.0,
					"spawns": [
						{"enemy_id": &"hexcaller", "position": Vector2(-330.0, 250.0), "count": 1},
						{"enemy_id": &"hexcaller", "position": Vector2(520.0, -40.0), "count": 1},
					],
				},
				{
					"time": 8.0,
					"spawns": [
						{"enemy_id": &"brute", "position": Vector2(300.0, 250.0), "count": 1},
					],
				},
			],
		},
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
	&"slinger_gallery": {
		"display_name": "Slinger Gallery",
		"banner_title": "THE SLINGER GALLERY",
		"trigger_level": 5,
		"needs": [&"interrupt", &"area", &"range"],
		"warning_duration": 3.0,
		"spawn_grace": 1.0,
		"seed": 9203,
		"pack_jitter_radius": 40.0,
		"enemy_overrides": {
			&"slinger": {
				"move_speed": 300.0,
				"flee_distance": 300.0,
				"keep_distance": 360.0,
				"max_health": 45.0,
				"shot_damage": 25.0,
			},
			&"hexcaller": {
				"move_speed": 160.0,
				"flee_distance": 250.0,
				"keep_distance": 400.0,
			},
		},
		"large_party": {
			"min_echoes": 2,
			"enemy_health_multiplier": 1.25,
			"extra_waves": [
				{
					"time": 0.0,
					"spawns": [
						{"enemy_id": &"slinger", "position": Vector2(265.0, -302.0), "count": 1},
					],
				},
			],
		},
		"waves": [
			{
				"time": 0.0,
				"spawns": [
					{"enemy_id": &"slinger", "position": Vector2(360.0, -30.0), "count": 1},
					{"enemy_id": &"slinger", "position": Vector2(540.0, 120.0), "count": 1},
					{"enemy_id": &"slinger", "position": Vector2(-440.0, 280.0), "count": 1},
					{"enemy_id": &"hexcaller", "position": Vector2(-330.0, 260.0), "count": 1},
					{"enemy_id": &"hexcaller", "position": Vector2(520.0, 0.0), "count": 1},
				],
			},
			{
				"time": 8.0,
				"max_alive": 2,
				"spawns": [
					{"enemy_id": &"skitter", "position": Vector2(300.0, 80.0), "count": 1},
					{"enemy_id": &"skitter", "position": Vector2(410.0, 80.0), "count": 1},
					{"enemy_id": &"skitter", "position": Vector2(300.0, 190.0), "count": 1},
					{"enemy_id": &"skitter", "position": Vector2(410.0, 190.0), "count": 1},
				],
			},
			{
				"time": 18.0,
				"max_alive": 2,
				"spawns": [
					{"enemy_id": &"slinger", "position": Vector2(-330.0, 150.0), "count": 1},
					{"enemy_id": &"slinger", "position": Vector2(240.0, 280.0), "count": 1},
					{"enemy_id": &"hexcaller", "position": Vector2(540.0, 270.0), "count": 1},
					{"enemy_id": &"slinger", "position": Vector2(-540.0, 280.0), "count": 1},
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


## Deterministic Trial rotation: odd hero numbers face the Bell Court, even
## numbers the Slinger Gallery. Hero numbers below 1 count as the first hero.
static func trial_for_hero(hero_number: int) -> StringName:
	return &"bell_court" if posmod(maxi(hero_number, 1), 2) == 1 else &"slinger_gallery"
