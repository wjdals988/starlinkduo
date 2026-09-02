class_name DuelSaveStore
extends RefCounted

const SAVE_PATH := "user://active_duel.json"
const PENDING_SUFFIX := ".pending"
const TEMP_SUFFIX := ".tmp"
const BACKUP_SUFFIX := ".bak"
const SCHEMA_VERSION := 1

var save_path: String

func _init(path: String = SAVE_PATH) -> void:
	save_path = path

func save(state: DuelState) -> Error:
	return _write_checked(save_path, state.to_snapshot())

func load_active() -> DuelState:
	var parsed: Variant = _load_checked(save_path)
	return DuelState.from_snapshot(parsed) if parsed is Dictionary else null

func clear() -> Error:
	var state_error := _clear_checked(save_path)
	var pending_error := clear_pending()
	return state_error if state_error != OK else pending_error

func save_pending_commitment(data: Dictionary) -> Error:
	return _write_checked(_pending_path(), data)

func load_pending_commitment() -> Dictionary:
	var parsed: Variant = _load_checked(_pending_path())
	return RunState._normalize_json_numbers(parsed) if parsed is Dictionary else {}

func clear_pending() -> Error:
	return _clear_checked(_pending_path())

func _pending_path() -> String:
	return save_path + PENDING_SUFFIX

func _write_checked(path: String, payload: Dictionary) -> Error:
	var envelope := {
		"schema": SCHEMA_VERSION,
		"payload": payload,
		"checksum": StateHasher.hash_snapshot(payload),
	}
	var temp_path := path + TEMP_SUFFIX
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(envelope))
	file.flush()
	file.close()
	if _load_checked_file(temp_path) == null:
		_remove_if_exists(temp_path)
		return ERR_FILE_CORRUPT
	var absolute_path := ProjectSettings.globalize_path(path)
	var absolute_temp := ProjectSettings.globalize_path(temp_path)
	var backup_path := path + BACKUP_SUFFIX
	var absolute_backup := ProjectSettings.globalize_path(backup_path)
	var cleanup_error := _remove_if_exists(backup_path)
	if cleanup_error != OK:
		_remove_if_exists(temp_path)
		return cleanup_error
	if FileAccess.file_exists(path):
		var backup_error := DirAccess.rename_absolute(absolute_path, absolute_backup)
		if backup_error != OK:
			_remove_if_exists(temp_path)
			return backup_error
	var promote_error := DirAccess.rename_absolute(absolute_temp, absolute_path)
	if promote_error != OK:
		return promote_error
	return OK

func _load_checked(path: String) -> Variant:
	var primary: Variant = _load_checked_file(path)
	if primary != null:
		return primary
	var staged: Variant = _load_checked_file(path + TEMP_SUFFIX)
	if staged != null:
		return staged
	return _load_checked_file(path + BACKUP_SUFFIX)

func _load_checked_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var contents := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(contents) != OK:
		return null
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		return null
	# Legacy snapshots were stored without an envelope and remain readable.
	if not parsed.has("schema"):
		return parsed
	if int(parsed.get("schema", -1)) != SCHEMA_VERSION or not parsed.get("payload") is Dictionary:
		return null
	var payload: Dictionary = parsed.payload
	if String(parsed.get("checksum", "")) != StateHasher.hash_snapshot(payload):
		return null
	return payload

func _clear_checked(path: String) -> Error:
	var first_error := OK
	for candidate in [path, path + TEMP_SUFFIX, path + BACKUP_SUFFIX]:
		var result := _remove_if_exists(candidate)
		if first_error == OK and result != OK:
			first_error = result
	return first_error

func _remove_if_exists(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
