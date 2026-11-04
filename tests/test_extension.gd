extends SceneTree
## Slice 4: party echoes keep growing past their record; the player authors each
## extension level through the shared choice modal.


const EchoScene := preload("res://src/echo/echo.tscn")
const MainScene := preload("res://src/main/main.tscn")

var _failures: Array[String] = []
var _checks := 0


func _init() -> void:
	call_deferred(&"_run_tests")


func _run_tests() -> void:
	_test_pending_levels_at_and_past_the_record()
	_test_extension_choice_ordering_and_rejection()
	_test_extended_with_prefix_validation()
	_test_prompt_order_titles_and_stats()
	_test_multi_level_jump_and_no_lost_xp()
	_test_defeated_echo_keeps_only_chosen_levels()
	await _test_hero_death_drops_pending_extension()
	_test_extended_record_replays_next_run()
	_test_two_echoes_prompt_by_slot()
	_test_mcp_state_subjects_and_plain_types()
	_test_extension_scenarios()
	_test_chosen_only_trims_pending_levels()

	if _failures.is_empty():
		print("History extension tests passed (12 cases, %d checks)." % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_pending_levels_at_and_past_the_record() -> void:
	var active := Node2D.new()
	root.add_child(active)
	var echo := _configured_echo(active, &"mender", 4)
	var signal_count: Array[int] = [0]
	echo.extension_pending.connect(func(_echo: EchoActor) -> void: signal_count[0] += 1)
	echo.grant_shared_experience(300)
	_expect(
		echo.progression.level == 4
		and echo.get_pending_extension_levels().is_empty()
		and echo.get_record_level() == 4
		and signal_count[0] == 0,
		"an echo replaying exactly to its record level has nothing pending and does not signal"
	)
	_expect(
		echo.grant_shared_experience(100) == 1
		and echo.progression.level == 5
		and echo.get_pending_extension_levels() == [5]
		and signal_count[0] == 1,
		"the first level past the record is pending and signals once"
	)
	_expect(
		echo.grant_shared_experience(150) == 1
		and echo.progression.experience == 550
		and echo.get_pending_extension_levels() == [5, 6]
		and signal_count[0] == 2,
		"further XP keeps the pending levels in order and loses nothing"
	)
	_expect(
		echo.attack_damage == HeroProgression.BASE_ATTACK_DAMAGE + 2 * HeroProgression.MIGHT_ATTACK_BONUS
		and echo.max_health == HeroProgression.BASE_MAX_HEALTH,
		"stats come only from chosen levels: the pending levels 5 and 6 add nothing yet"
	)
	echo.ability_cooldown_left = 4.0
	echo.select_weapon(echo.get_weapon_loadout()[1])
	echo.grant_shared_experience(100)
	_expect(
		echo.ability_cooldown_left == 4.0 and echo.selected_weapon_id == echo.get_weapon_loadout()[1],
		"leveling past the record does not reset the Mend cooldown or the selected weapon"
	)
	var label := echo.get_node("EchoLabel") as Label
	_expect(label.text.begins_with("ECHO 1 · Lv 7*"), "the world label marks a pending extension with *: %s" % label.text)
	echo.free()
	active.free()


func _test_extension_choice_ordering_and_rejection() -> void:
	var active := Node2D.new()
	root.add_child(active)
	var echo := _configured_echo(active, &"vanguard", 4)
	echo.grant_shared_experience(300)
	_expect(
		not echo.apply_extension_choice(5, HeroProgression.ATTRIBUTE_MIGHT),
		"an echo with nothing pending rejects an extension choice"
	)
	echo.grant_shared_experience(250)
	var max_health_before := echo.max_health
	_expect(
		not echo.apply_extension_choice(6, HeroProgression.ATTRIBUTE_MIGHT)
		and not echo.apply_extension_choice(5, &"hexcraft")
		and not echo.apply_extension_choice(5, HeroProgression.JOB_MENDER)
		and echo.get_pending_extension_levels() == [5, 6],
		"out-of-order levels, unknown attributes, and job IDs are rejected without changing state"
	)
	_expect(
		echo.apply_extension_choice(5, HeroProgression.ATTRIBUTE_VITALITY)
		and echo.max_health == max_health_before + HeroProgression.VITALITY_HEALTH_BONUS
		and echo.get_pending_extension_levels() == [6],
		"the first pending level accepts Vitality and raises max health"
	)
	_expect(
		echo.apply_extension_choice(6, HeroProgression.ATTRIBUTE_MIGHT)
		and echo.get_pending_extension_levels().is_empty()
		and echo.progression.get_choices().size() == 5
		and (echo.get_node("EchoLabel") as Label).text.begins_with("ECHO 1 · Lv 6")
		and not (echo.get_node("EchoLabel") as Label).text.begins_with("ECHO 1 · Lv 6*"),
		"the last pending level clears the marker"
	)
	echo.is_defeated = true
	echo.grant_shared_experience(100)
	_expect(
		not echo.apply_extension_choice(7, HeroProgression.ATTRIBUTE_MIGHT),
		"a defeated echo accepts no extension choice"
	)
	echo.free()
	active.free()


func _test_extended_with_prefix_validation() -> void:
	var recorded := _build_progression(&"mender", 4)
	var record := HeroRecord.capture("hero-3", "Hero 3", recorded)
	var before := record.to_dict()
	# Level 2 was Might in the record; a divergent history chose Vitality there.
	var divergent_choices := HeroProgression.new()
	divergent_choices.grant_experience(400)
	divergent_choices.apply_attribute_choice(2, HeroProgression.ATTRIBUTE_VITALITY)
	divergent_choices.apply_job_choice(3, HeroProgression.JOB_MENDER)
	divergent_choices.apply_attribute_choice(4, HeroProgression.ATTRIBUTE_MIGHT)
	divergent_choices.apply_attribute_choice(5, HeroProgression.ATTRIBUTE_MIGHT)
	_expect(
		record.extended_with(divergent_choices) == null,
		"a history that diverges from the record's choices is not an extension"
	)
	var active := Node2D.new()
	root.add_child(active)
	var echo := EchoScene.instantiate() as EchoActor
	root.add_child(echo)
	echo.configure(record, active)
	echo.grant_shared_experience(300)
	_expect(echo.extension_record() == null, "an echo that chose nothing past its record leaves no extended record")
	echo.grant_shared_experience(250)
	_expect(
		echo.extension_record() == null,
		"reaching a level without choosing it is not recorded"
	)
	echo.apply_extension_choice(5, HeroProgression.ATTRIBUTE_VITALITY)
	var extended := echo.extension_record()
	var extended_progression := extended.replay_progression() if extended != null else null
	_expect(
		extended != null
		and extended != record
		and extended.runtime_id == "hero-3"
		and extended_progression.level == 5
		and extended_progression.experience == 400
		and extended_progression.get_choices().size() == 4
		and extended_progression.get_choices().slice(0, 3) == recorded.get_choices(),
		"only the chosen level is recorded: level 5, XP trimmed to the chosen level, prefix preserved"
	)
	_expect(record.to_dict() == before, "extending never mutates the source record")
	echo.free()
	active.free()


func _test_prompt_order_titles_and_stats() -> void:
	var main := _extension_main([&"mender"], [4])
	var original: HeroRecord = main.roster.party[0]
	var original_dict := original.to_dict()
	main._on_enemy_defeated(100)
	var state: Dictionary = main._mcp_state()
	_expect(
		state["pending_choice_subjects"] == [
			{"subject": "hero", "slot": 0, "level": 5, "pending": 1},
			{"subject": "echo", "slot": 1, "level": 5, "pending": 1},
		]
		and paused
		and main.choice_modal.visible
		and main.choice_title.text == "LEVEL 5 — CHOOSE AN ATTRIBUTE"
		and main.choice_prompt.text == _choice_prompt(false),
		"the hero's choice comes first with the unchanged title: %s" % main.choice_title.text
	)
	var hero_attack_before: float = main.player.attack_damage
	main._apply_pending_choice(0)
	_expect(
		main.player.attack_damage == hero_attack_before + HeroProgression.MIGHT_ATTACK_BONUS
		and main.choice_modal.visible
		and paused,
		"the hero's Might choice applies and the modal stays open for the echo"
	)
	_expect(
		main.choice_title.text == "ECHO 1 · Hero 1 (Mender) · LEVEL 5 — CHOOSE AN ATTRIBUTE"
		and main.choice_prompt.text == _choice_prompt(true)
		and not main.choice_three_button.visible
		and main.choice_one_button.text.begins_with("[1] MIGHT")
		and main.choice_two_button.text.begins_with("[2] VITALITY"),
		"the echo's modal names the echo, its record name, and its job: %s" % main.choice_title.text
	)
	var echo_health_before: float = main.echo.max_health
	var echo_attack_before: float = main.echo.attack_damage
	main._apply_pending_choice(1)
	var extended: HeroRecord = main.roster.party[0]
	_expect(
		main.echo.max_health == echo_health_before + HeroProgression.VITALITY_HEALTH_BONUS
		and main.echo.attack_damage == echo_attack_before
		and not paused
		and not main.choice_modal.visible,
		"the echo's Vitality choice raises its max health and closes the modal"
	)
	_expect(
		extended != original
		and extended.replay_progression().level == 5
		and extended.replay_progression().get_choices().size() == original.replay_progression().get_choices().size() + 1
		and extended.replay_progression().get_choices()[-1] == {"level": 5, "attribute_id": "vitality"}
		and original.to_dict() == original_dict
		and main.echo.hero_record == extended
		and main.latest_echo_record == extended,
		"the roster holds a new, longer record immediately; the previous record object is untouched"
	)
	main.free()
	paused = false


func _test_multi_level_jump_and_no_lost_xp() -> void:
	var main := _extension_main([&"mender"], [4])
	main._on_enemy_defeated(300)
	var titles: Array[String] = []
	var guard := 0
	while main.choice_modal.visible and guard < 20:
		titles.append(main.choice_title.text)
		main._apply_pending_choice(guard % 2)
		guard += 1
	_expect(
		titles == [
			"LEVEL 5 — CHOOSE AN ATTRIBUTE",
			"LEVEL 6 — CHOOSE AN ATTRIBUTE",
			"LEVEL 7 — CHOOSE AN ATTRIBUTE",
			"ECHO 1 · Hero 1 (Mender) · LEVEL 5 — CHOOSE AN ATTRIBUTE",
			"ECHO 1 · Hero 1 (Mender) · LEVEL 6 — CHOOSE AN ATTRIBUTE",
			"ECHO 1 · Hero 1 (Mender) · LEVEL 7 — CHOOSE AN ATTRIBUTE",
		],
		"a three-level jump asks hero then echo once per level, in order: %s" % [titles]
	)
	var record_progression: HeroProgression = main.roster.party[0].replay_progression()
	_expect(
		not paused
		and main.progression.experience == 600
		and main.echo.progression.experience == 600
		and record_progression.level == 7
		and record_progression.get_choices().size() == 6,
		"no XP is lost and the roster record holds all three extension levels"
	)
	main.free()
	paused = false


func _test_defeated_echo_keeps_only_chosen_levels() -> void:
	var main := _extension_main([&"mender"], [4])
	main._on_enemy_defeated(200)
	main._apply_pending_choice(0)
	main._apply_pending_choice(0)
	_expect(
		main.choice_title.text.begins_with("ECHO 1")
		and main.echo.get_pending_extension_levels() == [5, 6],
		"two hero choices resolve before the echo is asked"
	)
	main._apply_pending_choice(1)
	_expect(
		main.echo.get_pending_extension_levels() == [6] and main.choice_modal.visible,
		"the echo is asked again for level 6"
	)
	main.echo.invulnerability_time_left = 0.0
	main.echo.take_damage(100000.0)
	var recorded: HeroProgression = main.roster.party[0].replay_progression()
	_expect(
		not main.choice_modal.visible
		and not paused
		and main.echo == null
		and main._pending_choice_subjects().is_empty()
		and recorded.level == 5
		and recorded.experience == 400
		and recorded.get_choices().size() == 4,
		"an echo defeated with a pending level keeps only the level it chose and stops prompting"
	)
	main._on_enemy_defeated(100)
	_expect(
		main.choice_modal.visible
		and main.choice_title.text == "LEVEL 7 — CHOOSE AN ATTRIBUTE"
		and main._mcp_state()["pending_choice_subjects"].size() == 1,
		"later XP prompts only the hero"
	)
	main.free()
	paused = false


func _test_hero_death_drops_pending_extension() -> void:
	var main := _extension_main([&"mender"], [4])
	var original: HeroRecord = main.roster.party[0]
	main._on_enemy_defeated(100)
	main._apply_pending_choice(0)
	_expect(main.choice_title.text.begins_with("ECHO 1"), "the echo's choice is pending when the hero falls")
	main._on_player_defeated()
	await process_frame
	_expect(
		not main.choice_modal.visible
		and main.resolution_screen.visible
		and paused
		and main.roster.party[0] == original
		and main.roster.candidate != null
		and main.roster.candidate.replay_progression().get_job_id() == HeroProgression.JOB_VANGUARD
		and main.roster.candidate.replay_progression().level == 5
		and main.echoes.is_empty(),
		"the pending extension is dropped; the roster screen opens with the fallen hero as candidate"
	)
	_expect(main.resolve_default() and not paused and main.echo != null, "the roster screen resolves and the next run starts")
	_expect(
		main.echo.progression.level == 1
		and main.roster.party[0].replay_progression().level == 4,
		"the unextended echo record still replays from level 1"
	)
	main.free()
	paused = false

	var main_two := _extension_main([&"mender"], [4])
	main_two._on_enemy_defeated(200)
	main_two._apply_pending_choice(0)
	main_two._apply_pending_choice(0)
	main_two._apply_pending_choice(0)
	main_two._on_player_defeated()
	await process_frame
	var recorded: HeroProgression = main_two.roster.party[0].replay_progression()
	_expect(
		not main_two.choice_modal.visible
		and main_two.resolution_screen.visible
		and recorded.level == 5
		and recorded.get_choices().size() == 4
		and main_two.roster.candidate.replay_progression().level == 6,
		"with one of two levels chosen, the record keeps level 5 and the candidate is the level-6 hero"
	)
	main_two.free()
	paused = false


func _test_extended_record_replays_next_run() -> void:
	var main := _extension_main([&"mender"], [4])
	main._on_enemy_defeated(100)
	main._apply_pending_choice(0)
	main._apply_pending_choice(1)
	var extended: HeroRecord = main.roster.party[0]
	var expected := extended.replay_progression()
	main._start_next_run()
	main.resolve_default()
	var next_echo: EchoActor = main.echo
	_expect(
		next_echo != null
		and next_echo.progression.level == 1
		and next_echo.job_id == HeroProgression.JOB_NOVICE
		and next_echo.get_replay_level_limit() == 5,
		"the next run starts the extended echo as a level-1 Novice with a level-5 replay limit"
	)
	next_echo.grant_shared_experience(400)
	_expect(
		next_echo.progression.level == 5
		and next_echo.get_pending_extension_levels().is_empty()
		and next_echo.progression.get_choices() == expected.get_choices()
		and next_echo.max_health == float(expected.get_max_health())
		and next_echo.attack_damage == float(expected.get_attack_damage())
		and next_echo.max_health == float(HeroProgression.BASE_MAX_HEALTH + HeroProgression.VITALITY_HEALTH_BONUS),
		"the extended echo replays every recorded choice, including the new Vitality level"
	)
	_expect(
		next_echo.grant_shared_experience(100) == 1
		and next_echo.get_pending_extension_levels() == [6],
		"and extends again from the end of the longer record"
	)
	main.free()
	paused = false


func _test_two_echoes_prompt_by_slot() -> void:
	var main := _extension_main([&"mender", &"arcanist"], [4, 4])
	main._on_enemy_defeated(100)
	var order: Array[String] = []
	var guard := 0
	while main.choice_modal.visible and guard < 10:
		order.append(main.choice_title.text)
		main._apply_pending_choice(0 if order.size() != 3 else 1)
		guard += 1
	_expect(
		order == [
			"LEVEL 5 — CHOOSE AN ATTRIBUTE",
			"ECHO 1 · Hero 1 (Mender) · LEVEL 5 — CHOOSE AN ATTRIBUTE",
			"ECHO 2 · Hero 2 (Arcanist) · LEVEL 5 — CHOOSE AN ATTRIBUTE",
		],
		"hero first, then echoes in slot order: %s" % [order]
	)
	_expect(
		main.roster.party[0].replay_progression().get_choices()[-1] == {"level": 5, "attribute_id": "might"}
		and main.roster.party[1].replay_progression().get_choices()[-1] == {"level": 5, "attribute_id": "vitality"}
		and main.echoes[0].attack_damage == main.echoes[1].attack_damage + HeroProgression.MIGHT_ATTACK_BONUS
		and main.echoes[1].max_health == main.echoes[0].max_health + HeroProgression.VITALITY_HEALTH_BONUS,
		"each slot's record and stats follow its own choice"
	)
	main.free()
	paused = false


func _test_mcp_state_subjects_and_plain_types() -> void:
	var main := _extension_main([&"mender", &"arcanist"], [4, 4])
	var idle_state: Dictionary = main._mcp_state()
	_expect(
		idle_state["pending_choice_subjects"] == []
		and idle_state["echoes"][0]["pending_extension_levels"] == []
		and idle_state["echoes"][0]["record_level"] == 4
		and idle_state["echoes"][1]["record_level"] == 4,
		"with nothing pending the subjects list is empty and each echo reports its record level"
	)
	main._on_enemy_defeated(250)
	var state: Dictionary = main._mcp_state()
	_expect(
		state["pending_choice_subjects"] == [
			{"subject": "hero", "slot": 0, "level": 5, "pending": 2},
			{"subject": "echo", "slot": 1, "level": 5, "pending": 2},
			{"subject": "echo", "slot": 2, "level": 5, "pending": 2},
		]
		and state["echoes"][0]["pending_extension_levels"] == [5, 6]
		and state["echoes"][0]["level"] == 6
		and state["echoes"][0]["record_level"] == 4
		and state["choice_title_text"] == "LEVEL 5 — CHOOSE AN ATTRIBUTE"
		and _is_plain(state),
		"MCP state lists every subject in prompt order with plain types"
	)
	main.free()
	paused = false


func _test_extension_scenarios() -> void:
	var single: Node = (load("res://tests/scenarios/vanguard_mender_4_extend.tscn") as PackedScene).instantiate()
	root.add_child(single)
	var single_main: Node = single.get_node("Main")
	var single_state: Dictionary = single_main._mcp_state()
	_expect(
		single_state["choice_modal_visible"]
		and single_state["pending_choice_subjects"] == [
			{"subject": "hero", "slot": 0, "level": 5, "pending": 1},
			{"subject": "echo", "slot": 1, "level": 5, "pending": 1},
		]
		and single_state["echoes"][0]["record_level"] == 4,
		"vanguard_mender_4_extend opens the hero modal, then the Mender extension"
	)
	single.free()
	paused = false

	var double: Node = (load("res://tests/scenarios/vanguard_mender_arcanist_4_extend2.tscn") as PackedScene).instantiate()
	root.add_child(double)
	var double_main: Node = double.get_node("Main")
	var double_state: Dictionary = double_main._mcp_state()
	_expect(
		double_state["pending_choice_subjects"] == [
			{"subject": "hero", "slot": 0, "level": 5, "pending": 2},
			{"subject": "echo", "slot": 1, "level": 5, "pending": 2},
		]
		and double_state["echo_count"] == 2
		and double_state["echoes"][1]["level"] == 6
		and double_state["echoes"][1]["record_level"] == 6
		and double_state["echoes"][1]["pending_extension_levels"] == [],
		"vanguard_mender_arcanist_4_extend2 prompts Echo 1 only; Echo 2 stays inside its level-6 record"
	)
	double.free()
	paused = false


## Builds a Main whose roster holds scenario echoes recorded at `levels` and whose
## Vanguard hero is at level 4, with the live echoes replayed to their record.
func _extension_main(jobs: Array[StringName], levels: Array[int]) -> Node:
	var main := MainScene.instantiate()
	main.party_slots = 2
	root.add_child(main)
	var echo_levels: Array[int] = levels
	main.apply_scenario(&"vanguard", &"", 4, &"", jobs, echo_levels)
	var spawner := main.get_node("Enemies") as EnemySpawner
	spawner.set_population(0)
	return main


func _choice_prompt(is_echo: bool) -> String:
	return (
		"Combat is paused. This extends the echo's saved history."
		if is_echo
		else "Combat is paused. Choose one permanent build step."
	)


func _configured_echo(active: Node2D, job_id: StringName, record_level: int) -> EchoActor:
	var record := HeroRecord.capture("hero-9", "Hero 9", _build_progression(job_id, record_level))
	var echo := EchoScene.instantiate() as EchoActor
	root.add_child(echo)
	echo.configure(record, active)
	return echo


func _build_progression(job_id: StringName, level: int) -> HeroProgression:
	var progression := HeroProgression.new()
	progression.grant_experience((level - 1) * HeroProgression.XP_PER_LEVEL)
	for choice_level in range(2, level + 1):
		if choice_level == HeroProgression.ADVANCEMENT_LEVEL:
			progression.apply_job_choice(choice_level, job_id)
		else:
			progression.apply_attribute_choice(
				choice_level,
				HeroProgression.ATTRIBUTE_MIGHT if choice_level % 2 == 0 else HeroProgression.ATTRIBUTE_VITALITY
			)
	return progression


func _is_plain(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return true
		TYPE_ARRAY:
			for item: Variant in value:
				if not _is_plain(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not key is String or not _is_plain(value[key]):
					return false
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


## A hero captured with an unchosen level must not record it, or a later
## extension of that record could not commit until it passed the stale level.
func _test_chosen_only_trims_pending_levels() -> void:
	var progression := HeroProgression.new()
	progression.grant_experience(200)
	progression.apply_attribute_choice(2, HeroProgression.ATTRIBUTE_MIGHT)
	progression.apply_job_choice(3, &"mender")
	progression.grant_experience(150)
	var trimmed := progression.chosen_only()
	_expect(
		progression.level == 4
		and progression.has_pending_choice()
		and trimmed != null
		and trimmed.level == 3
		and trimmed.experience == 200
		and trimmed.get_choices() == progression.get_choices()
		and not trimmed.has_pending_choice(),
		"chosen_only drops the unchosen level and its XP but keeps every choice"
	)
	var full := HeroProgression.new()
	full.grant_experience(150)
	full.apply_attribute_choice(2, HeroProgression.ATTRIBUTE_VITALITY)
	var copy := full.chosen_only()
	_expect(
		copy != null and copy.level == 2 and copy.experience == 150 and copy != full,
		"chosen_only keeps partial XP when nothing is pending and returns a copy"
	)
	var record := HeroRecord.capture("hero-9", "Hero 9", trimmed)
	var extended := trimmed.chosen_only()
	extended.grant_experience(100)
	extended.apply_attribute_choice(4, HeroProgression.ATTRIBUTE_VITALITY)
	_expect(
		record != null and record.extended_with(extended) != null,
		"a trimmed record accepts the very next extension level"
	)
