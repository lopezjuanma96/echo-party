class_name WeaponDefinition
extends Resource


enum AttackKind { MELEE, PROJECTILE }

@export var id: StringName
@export var display_name: String
@export var attack_kind: AttackKind = AttackKind.MELEE
@export var cooldown := 0.4
@export var attack_range := 80.0
@export var arc_degrees := 30.0
@export var projectile_speed := 560.0
@export var projectile_color := Color("78e6a3")
