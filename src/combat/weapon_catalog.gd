class_name WeaponCatalog
extends RefCounted


const KNIFE: WeaponDefinition = preload("res://src/combat/weapons/knife.tres")
const SWORD: WeaponDefinition = preload("res://src/combat/weapons/sword.tres")
const LANCE: WeaponDefinition = preload("res://src/combat/weapons/lance.tres")
const WAND: WeaponDefinition = preload("res://src/combat/weapons/wand.tres")
const STAFF: WeaponDefinition = preload("res://src/combat/weapons/staff.tres")

const WEAPONS := {
	&"knife": KNIFE,
	&"sword": SWORD,
	&"lance": LANCE,
	&"wand": WAND,
	&"staff": STAFF,
}
const LOADOUTS := {
	&"novice": [&"knife"],
	&"vanguard": [&"sword", &"lance"],
	&"arcanist": [&"wand", &"staff"],
}


static func get_weapon(weapon_id: StringName) -> WeaponDefinition:
	return WEAPONS.get(weapon_id)


static func get_loadout(job_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for weapon_id: StringName in LOADOUTS.get(job_id, []):
		result.append(weapon_id)
	return result


static func get_display_name(weapon_id: StringName) -> String:
	var weapon := get_weapon(weapon_id)
	return weapon.display_name if weapon != null else String(weapon_id)
