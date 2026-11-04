class_name EnemyCatalog
extends RefCounted


const SCENES := {
	&"drifter": preload("res://src/enemy/enemy.tscn"),
	&"skitter": preload("res://src/enemy/skitter.tscn"),
	&"brute": preload("res://src/enemy/brute.tscn"),
	&"hexcaller": preload("res://src/enemy/hexcaller.tscn"),
	&"slinger": preload("res://src/enemy/slinger.tscn"),
}


static func get_scene(enemy_id: StringName) -> PackedScene:
	return SCENES.get(enemy_id) as PackedScene


static func instantiate(enemy_id: StringName) -> EnemyActor:
	var scene := get_scene(enemy_id)
	if scene == null:
		return null
	return scene.instantiate() as EnemyActor
