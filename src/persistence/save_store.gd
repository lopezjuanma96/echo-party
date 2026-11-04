class_name SaveStore
extends RefCounted


var path: String
var read_only := false


func _init(new_path: String = "") -> void:
	path = new_path


func load_document() -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"document": SaveDocument.new_default(), "status": &"new"}
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null:
		return _corrupt_result()
	var text := source.get_as_text()
	source.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return _corrupt_result()
	var migration := SaveMigrations.migrate(json.data)
	if migration["status"] == &"too_new":
		read_only = true
		return {"document": SaveDocument.new_default(), "status": &"too_new"}
	if migration["status"] != &"ok" and migration["status"] != &"migrated":
		return _corrupt_result()
	var document := SaveDocument.from_dict(migration["data"])
	if document == null:
		return _corrupt_result()
	read_only = false
	return {"document": document, "status": migration["status"]}


func save_document(document: SaveDocument) -> bool:
	if document == null or read_only:
		return false
	if path.is_empty():
		return true
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return false
	var temporary_path := path + ".tmp"
	var text := JSON.stringify(document.to_dict(), "\t", true)
	var output := FileAccess.open(temporary_path, FileAccess.WRITE)
	if output == null:
		return false
	output.store_string(text)
	var write_error := output.get_error()
	output.close()
	# Never replace the existing save with an incomplete temporary file: a full
	# disk or a size limit can truncate the write without failing the call.
	if write_error != OK or FileAccess.get_file_as_string(temporary_path) != text:
		DirAccess.remove_absolute(temporary_path)
		return false
	var error := DirAccess.rename_absolute(temporary_path, path)
	if error == ERR_ALREADY_EXISTS and FileAccess.file_exists(path):
		if DirAccess.remove_absolute(path) != OK:
			DirAccess.remove_absolute(temporary_path)
			return false
		error = DirAccess.rename_absolute(temporary_path, path)
	if error != OK:
		DirAccess.remove_absolute(temporary_path)
		return false
	return true


## A corrupt save is replaced by defaults only after a verified backup. If the
## backup fails, the store turns read-only so the original is never overwritten.
func _corrupt_result() -> Dictionary:
	var backed_up := _backup_corrupt()
	read_only = not backed_up
	return {"document": SaveDocument.new_default(), "status": &"corrupt", "backed_up": backed_up}


func _backup_corrupt() -> bool:
	var bytes := FileAccess.get_file_as_bytes(path)
	if FileAccess.get_open_error() != OK:
		return false
	var backup_path := path + ".corrupt"
	var backup := FileAccess.open(backup_path, FileAccess.WRITE)
	if backup == null:
		return false
	backup.store_buffer(bytes)
	var write_error := backup.get_error()
	backup.close()
	return write_error == OK and FileAccess.get_file_as_bytes(backup_path) == bytes
