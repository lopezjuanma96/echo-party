extends SceneTree


const HeroProgressionScript := preload("res://src/domain/hero_progression.gd")
const EnemyScene := preload("res://src/enemy/enemy.tscn")
const PlayerScript := preload("res://src/player/player.gd")
const EnemySpawnerScript := preload("res://src/enemy/enemy_spawner.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_below_threshold()
	_test_crossing_threshold()
	_test_multi_level_grant()
	_test_attribute_stats_and_duplicate_rejection()
	_test_advancement_job_choice()
	_test_replay()
	_test_dictionary_and_json_round_trip()
	_test_invalid_documents()
	_test_enemy_rewards_once()
	_test_vitality_preserves_missing_health()
	_test_job_loadouts_and_selection()
	_test_weapon_properties()
	_test_deterministic_and_renewable_spawner()

	if _failures.is_empty():
		print("Progression, loadout, and spawner tests passed (13 cases).")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
	return


func _test_below_threshold() -> void:
	var progression = HeroProgressionScript.new()
	_expect(progression.level == 1, "new hero starts at level 1")
	_expect(progression.experience == 0, "new hero starts at 0 XP")
	_expect(progression.grant_experience(99) == 0, "99 XP gains no levels")
	_expect(not progression.has_pending_choice(), "below threshold has no choice")


func _test_crossing_threshold() -> void:
	var progression = HeroProgressionScript.new()
	progression.grant_experience(50)
	_expect(progression.grant_experience(50) == 1, "crossing 100 XP gains one level")
	_expect(progression.level == 2, "100 XP reaches level 2")
	_expect(progression.get_pending_choice_levels() == [2], "level 2 choice is pending")


func _test_multi_level_grant() -> void:
	var progression = HeroProgressionScript.new()
	_expect(progression.grant_experience(250) == 2, "one grant can gain multiple levels")
	_expect(progression.level == 3, "250 XP reaches level 3")
	_expect(progression.get_pending_choice_levels() == [2, 3], "pending choices stay ordered")


func _test_attribute_stats_and_duplicate_rejection() -> void:
	var progression = HeroProgressionScript.new()
	progression.grant_experience(200)
	_expect(progression.apply_attribute_choice(2, HeroProgressionScript.ATTRIBUTE_MIGHT), "Might applies at level 2")
	_expect(not progression.apply_attribute_choice(2, HeroProgressionScript.ATTRIBUTE_VITALITY), "resolved level cannot be chosen twice")
	_expect(not progression.apply_attribute_choice(3, HeroProgressionScript.ATTRIBUTE_VITALITY), "level 3 rejects an attribute choice")
	_expect(progression.apply_job_choice(3, HeroProgressionScript.JOB_VANGUARD), "Vanguard applies at level 3")
	progression.grant_experience(100)
	_expect(progression.apply_attribute_choice(4, HeroProgressionScript.ATTRIBUTE_VITALITY), "attribute choices resume at level 4")
	_expect(progression.get_attack_damage() == 30, "Might adds 5 attack damage")
	_expect(progression.get_max_health() == 120, "Vitality adds 20 max health")


func _test_advancement_job_choice() -> void:
	var progression = HeroProgressionScript.new()
	progression.grant_experience(200)
	_expect(progression.get_pending_choice_levels() == [2, 3], "200 total XP reaches the advancement choice")
	_expect(not progression.apply_job_choice(2, HeroProgressionScript.JOB_ARCANIST), "level 2 rejects a job choice")
	progression.apply_attribute_choice(2, HeroProgressionScript.ATTRIBUTE_MIGHT)
	_expect(progression.apply_job_choice(3, HeroProgressionScript.JOB_ARCANIST), "level 3 accepts Arcanist")
	_expect(progression.get_job_id() == HeroProgressionScript.JOB_ARCANIST, "chosen job becomes current job")
	_expect(not progression.has_pending_choice(), "there is exactly one choice per gained level")


func _test_replay() -> void:
	var progression = HeroProgressionScript.new()
	progression.grant_experience(300)
	progression.apply_attribute_choice(2, HeroProgressionScript.ATTRIBUTE_VITALITY)
	progression.apply_job_choice(3, HeroProgressionScript.JOB_VANGUARD)
	progression.apply_attribute_choice(4, HeroProgressionScript.ATTRIBUTE_MIGHT)
	var replayed = HeroProgressionScript.from_dict(progression.to_dict())
	_expect(replayed != null, "valid history replays")
	_expect(replayed.get_choices() == progression.get_choices(), "replay preserves choice order")
	_expect(replayed.get_attack_damage() == 30 and replayed.get_max_health() == 120, "replay derives identical stats")
	_expect(replayed.get_job_id() == HeroProgressionScript.JOB_VANGUARD, "replay restores job state")


func _test_dictionary_and_json_round_trip() -> void:
	var progression = HeroProgressionScript.new()
	progression.grant_experience(150)
	progression.apply_attribute_choice(2, HeroProgressionScript.ATTRIBUTE_MIGHT)
	var dictionary_copy = HeroProgressionScript.from_dict(progression.to_dict())
	_expect(dictionary_copy != null and dictionary_copy.to_dict() == progression.to_dict(), "dictionary round-trip is lossless")
	var parsed: Variant = JSON.parse_string(JSON.stringify(progression.to_dict()))
	var json_copy = HeroProgressionScript.from_dict(parsed)
	_expect(json_copy != null and json_copy.to_dict() == progression.to_dict(), "JSON round-trip is lossless")


func _test_invalid_documents() -> void:
	_expect(HeroProgressionScript.from_dict({}) == null, "malformed root is rejected")
	_expect(HeroProgressionScript.from_dict({"level": 2, "experience": 100, "choices": [{"level": 2, "attribute_id": "agility"}]}) == null, "unknown attribute ID is rejected")
	_expect(HeroProgressionScript.from_dict({"level": 3, "experience": 200, "choices": [{"level": 2, "attribute_id": "might"}, {"level": 2, "attribute_id": "vitality"}]}) == null, "duplicate choice level is rejected")
	_expect(HeroProgressionScript.from_dict({"level": 3, "experience": 200, "choices": [{"level": 2, "attribute_id": "might"}, {"level": 3, "attribute_id": "vitality"}]}) == null, "attribute entry at job level is rejected")
	_expect(HeroProgressionScript.from_dict({"level": 3, "experience": 200, "choices": [{"level": 2, "attribute_id": "might"}, {"level": 3, "job_id": "vanguard", "attribute_id": "might"}]}) == null, "mixed job and attribute entry is rejected")
	_expect(HeroProgressionScript.from_dict({"level": 2, "experience": 100, "choices": [{"level": 2, "job_id": "vanguard"}]}) == null, "job entry at attribute level is rejected")
	_expect(HeroProgressionScript.from_dict({"level": 4, "experience": 200, "choices": []}) == null, "inconsistent level is rejected")


func _test_enemy_rewards_once() -> void:
	var enemy = EnemyScene.instantiate()
	var rewards: Array[int] = []
	enemy.defeated.connect(func(reward: int) -> void: rewards.append(reward))
	root.add_child(enemy)
	enemy.take_damage(enemy.max_health)
	enemy.take_damage(enemy.max_health)
	_expect(rewards == [50], "enemy defeat emits its XP reward exactly once")


func _test_vitality_preserves_missing_health() -> void:
	var player = PlayerScript.new()
	player.health = 50.0
	player.max_health = 100.0
	player.apply_progression_stats(120.0, 25.0)
	_expect(player.health == 70.0, "Vitality adds health without fully healing")
	_expect(player.max_health == 120.0, "Vitality raises maximum health")
	player.free()


func _test_job_loadouts_and_selection() -> void:
	var player = PlayerScript.new()
	_expect(player.get_weapon_loadout() == [&"knife"], "Novice starts with Knife only")
	_expect(not player.select_weapon_slot(1), "Novice slot 2 does nothing")
	_expect(player.apply_job_loadout(HeroProgressionScript.JOB_VANGUARD), "Vanguard loadout applies")
	_expect(player.get_weapon_loadout() == [&"sword", &"lance"], "Vanguard has Sword and Lance")
	_expect(player.get_selected_weapon_id() == &"sword", "job change selects slot 1")
	_expect(player.select_weapon_slot(1) and player.get_selected_weapon_id() == &"lance", "slot 2 selects Lance")
	_expect(player.apply_job_loadout(HeroProgressionScript.JOB_ARCANIST), "Arcanist loadout applies")
	_expect(player.get_weapon_loadout() == [&"wand", &"staff"], "Arcanist has Wand and Staff")
	_expect(player.cycle_weapon(1) and player.get_selected_weapon_id() == &"staff", "wheel-style cycling uses available weapons")
	player.free()


func _test_weapon_properties() -> void:
	var knife := WeaponCatalog.get_weapon(&"knife")
	var sword := WeaponCatalog.get_weapon(&"sword")
	var lance := WeaponCatalog.get_weapon(&"lance")
	var wand := WeaponCatalog.get_weapon(&"wand")
	var staff := WeaponCatalog.get_weapon(&"staff")
	for job_id: StringName in WeaponCatalog.LOADOUTS:
		for weapon_id: StringName in WeaponCatalog.get_loadout(job_id):
			_expect(WeaponCatalog.get_weapon(weapon_id) != null, "%s loadout weapon resolves" % job_id)
	_expect(knife.attack_range < sword.attack_range and knife.cooldown < sword.cooldown, "Knife is shorter and quicker than Sword")
	_expect(lance.attack_range > sword.attack_range and lance.arc_degrees < sword.arc_degrees, "Lance is longer and narrower than Sword")
	_expect(wand.attack_range < staff.attack_range and wand.cooldown < staff.cooldown, "Wand is shorter and quicker than Staff")
	_expect(
		knife.attack_kind == WeaponDefinition.AttackKind.MELEE
		and sword.attack_kind == WeaponDefinition.AttackKind.MELEE
		and lance.attack_kind == WeaponDefinition.AttackKind.MELEE,
		"Knife, Sword, and Lance use melee attacks"
	)
	_expect(
		wand.attack_kind == WeaponDefinition.AttackKind.PROJECTILE
		and staff.attack_kind == WeaponDefinition.AttackKind.PROJECTILE,
		"Wand and Staff use projectile attacks"
	)


func _test_deterministic_and_renewable_spawner() -> void:
	var player := Node2D.new()
	player.name = "Player"
	root.add_child(player)
	var first = EnemySpawnerScript.new()
	first.target_population = 3
	first.simulation_seed = 77
	root.add_child(first)
	# This suite exits from SceneTree._init(), before children receive _ready().
	first._ready()
	var first_positions := _enemy_positions(first)
	for spawn_position in first_positions:
		_expect(
			spawn_position.distance_to(player.position) >= first.minimum_player_distance,
			"spawns respect minimum player distance"
		)

	var second = EnemySpawnerScript.new()
	second.target_population = 3
	second.simulation_seed = 77
	root.add_child(second)
	second._ready()
	_expect(_enemy_positions(second) == first_positions, "equal spawner seeds produce equal positions")

	first.respawn_delay = 0.5
	var defeated_enemy: Node = first.get_child(0)
	defeated_enemy.take_damage(defeated_enemy.max_health)
	_expect(first.get_pending_respawn_count() == 1, "defeat schedules one replacement")
	first._process(0.49)
	_expect(_living_enemy_count(first) == 2, "replacement waits for its delay")
	first._process(0.02)
	_expect(_living_enemy_count(first) == 3, "spawner restores its target population")
	first.free()
	second.free()
	player.free()


func _enemy_positions(spawner: Node) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for child in spawner.get_children():
		positions.append(child.position)
	return positions


func _living_enemy_count(spawner: Node) -> int:
	var count := 0
	for child in spawner.get_children():
		if not child.is_queued_for_deletion():
			count += 1
	return count


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
