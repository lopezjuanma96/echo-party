extends SceneTree


const HeroProgressionScript := preload("res://src/domain/hero_progression.gd")
const EnemyScene := preload("res://src/enemy/enemy.tscn")
const PlayerScript := preload("res://src/player/player.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_below_threshold()
	_test_crossing_threshold()
	_test_multi_level_grant()
	_test_attribute_stats_and_duplicate_rejection()
	_test_replay()
	_test_dictionary_and_json_round_trip()
	_test_invalid_documents()
	_test_enemy_rewards_once()
	_test_vitality_preserves_missing_health()

	if _failures.is_empty():
		print("Progression and XP reward tests passed (9 cases).")
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
	_expect(progression.apply_attribute_choice(3, HeroProgressionScript.ATTRIBUTE_VITALITY), "Vitality applies at level 3")
	_expect(progression.get_attack_damage() == 30, "Might adds 5 attack damage")
	_expect(progression.get_max_health() == 120, "Vitality adds 20 max health")


func _test_replay() -> void:
	var progression = HeroProgressionScript.new()
	progression.grant_experience(300)
	progression.apply_attribute_choice(2, HeroProgressionScript.ATTRIBUTE_VITALITY)
	progression.apply_attribute_choice(3, HeroProgressionScript.ATTRIBUTE_MIGHT)
	progression.apply_attribute_choice(4, HeroProgressionScript.ATTRIBUTE_MIGHT)
	var replayed = HeroProgressionScript.from_dict(progression.to_dict())
	_expect(replayed != null, "valid history replays")
	_expect(replayed.get_choices() == progression.get_choices(), "replay preserves choice order")
	_expect(replayed.get_attack_damage() == 35 and replayed.get_max_health() == 120, "replay derives identical stats")


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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
