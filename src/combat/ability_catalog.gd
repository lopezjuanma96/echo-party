class_name AbilityCatalog
extends RefCounted


const MEND: AbilityDefinition = preload("res://src/combat/abilities/mend.tres")

const ABILITIES := {
	&"mend": MEND,
}


static func get_ability(ability_id: StringName) -> AbilityDefinition:
	return ABILITIES.get(ability_id)
