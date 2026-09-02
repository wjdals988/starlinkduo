class_name CheckedJsonStore
extends RefCounted

const TEMP_SUFFIX := ".tmp"
const BACKUP_SUFFIX := ".bak"
const SCHEMA_VERSION := 1

static func save_payload(path: String, payload: Dictionary) -> Error:
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
	return promote_error

static func load_payload(path: String, required_keys: Array = []) -> Variant:
	for candidate in [path, path + TEMP_SUFFIX, path + BACKUP_SUFFIX]:
		var payload: Variant = _load_checked_file(candidate)
		if payload is Dictionary and _has_required_keys(payload, required_keys):
			return payload
	return null

static func clear(path: String) -> Error:
	var first_error := OK
	for candidate in [path, path + TEMP_SUFFIX, path + BACKUP_SUFFIX]:
		var result := _remove_if_exists(candidate)
		if first_error == OK and result != OK:
			first_error = result
	return first_error

static func _load_checked_file(path: String) -> Variant:
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

static func _remove_if_exists(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

static func _has_required_keys(payload: Dictionary, required_keys: Array) -> bool:
	for key in required_keys:
		if not payload.has(key):
			return false
	return true
