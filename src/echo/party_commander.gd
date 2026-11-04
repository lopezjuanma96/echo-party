class_name PartyCommander
extends RefCounted


const ADDRESS_ALL := -1

var address := ADDRESS_ALL
var last_command := {}


func cycle_address(direction: int, echo_count: int) -> void:
	if direction == 0 or echo_count <= 0:
		address = ADDRESS_ALL
		return
	var sequence_index := posmod(address + 1 + signi(direction), echo_count + 1)
	address = sequence_index - 1


func addressed(echoes: Array[EchoActor]) -> Array[EchoActor]:
	var result: Array[EchoActor] = []
	for echo in echoes:
		if not _is_commandable(echo):
			continue
		if address == ADDRESS_ALL or echo.slot_index == address:
			result.append(echo)
	return result


func focus(echoes: Array[EchoActor], target: Node2D) -> int:
	var command_address := address
	var accepted := 0
	for echo in addressed(echoes):
		if echo.command_focus(target):
			accepted += 1
	_record_command(command_address, "focus", _target_order(target))
	return accepted


func regroup(echoes: Array[EchoActor]) -> int:
	var command_address := address
	var targets := addressed(echoes)
	for echo in targets:
		echo.command_regroup()
	_record_command(command_address, "regroup", "")
	return targets.size()


func toggle_hold(echoes: Array[EchoActor]) -> bool:
	var command_address := address
	var targets := addressed(echoes)
	# One addressed echo toggles its own stance. All holds everyone unless
	# everyone already holds, in which case it releases everyone.
	var should_hold := targets.size() == 1 and not targets[0].is_holding_position
	if command_address == ADDRESS_ALL:
		should_hold = false
		for echo in targets:
			if not echo.is_holding_position:
				should_hold = true
				break
	for echo in targets:
		if echo.is_holding_position != should_hold:
			echo.toggle_hold_position()
	_record_command(command_address, "hold", "")
	return should_hold and not targets.is_empty()


func address_label(echoes: Array[EchoActor]) -> String:
	if address == ADDRESS_ALL:
		return "All"
	for echo in echoes:
		if is_instance_valid(echo) and echo.slot_index == address:
			return "Echo %d · %s" % [address + 1, JobCatalog.get_display_name(echo.hero_record.replay_progression().get_job_id())]
	return "Echo %d" % (address + 1)


func on_echoes_changed(echo_count: int) -> void:
	if address < ADDRESS_ALL or address >= echo_count:
		address = ADDRESS_ALL


func _record_command(command_address: int, verb: String, target: String) -> void:
	last_command = {
		"tick": Engine.get_physics_frames(),
		"address": command_address,
		"verb": verb,
		"target": target,
	}
	address = ADDRESS_ALL


func _target_order(target: Node2D) -> String:
	if not is_instance_valid(target):
		return ""
	var order: Variant = target.get("stable_spawn_order")
	return "" if order == null else str(order)


func _is_commandable(echo: EchoActor) -> bool:
	return (
		is_instance_valid(echo)
		and not echo.is_queued_for_deletion()
		and not echo.is_defeated
	)
