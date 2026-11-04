class_name JobCatalog
extends RefCounted


const JOBS := {
	&"novice": {
		"display_name": "Novice",
		"ability_id": &"",
		"posture": &"frontline",
		"provides": [],
	},
	&"vanguard": {
		"display_name": "Vanguard",
		"ability_id": &"",
		"posture": &"frontline",
		"provides": [&"interrupt", &"area"],
	},
	&"arcanist": {
		"display_name": "Arcanist",
		"ability_id": &"",
		"posture": &"ranged",
		"provides": [&"area", &"range"],
	},
	&"mender": {
		"display_name": "Mender",
		"ability_id": &"mend",
		"posture": &"support",
		"provides": [&"sustain"],
	},
}


static func get_display_name(job_id: StringName) -> String:
	return JOBS.get(job_id, JOBS[&"novice"]).get("display_name", String(job_id))


static func get_ability_id(job_id: StringName) -> StringName:
	return JOBS.get(job_id, {}).get("ability_id", &"")


static func get_provides(job_id: StringName) -> Array:
	return JOBS.get(job_id, {}).get("provides", [])


static func get_posture(job_id: StringName) -> StringName:
	return JOBS.get(job_id, {}).get("posture", &"frontline")
