class_name DuelSaveStore
extends RefCounted

const SAVE_PATH := "user://active_duel.json"
const PENDING_SUFFIX := ".pending"

var save_path: String

func _init(path: String = SAVE_PATH) -> void:
	save_path = path

func save(state: DuelState) -> Error:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(state.to_snapshot()))
	file.close()
	return OK

func load_active() -> DuelState:
	if not FileAccess.file_exists(save_path):
		return null
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return DuelState.from_snapshot(parsed) if parsed is Dictionary else null

func clear() -> Error:
	if not FileAccess.file_exists(save_path):
		return clear_pending()
	var state_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	var pending_error := clear_pending()
	return state_error if state_error != OK else pending_error

func save_pending_commitment(data: Dictionary) -> Error:
	var file := FileAccess.open(_pending_path(), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	file.close()
	return OK

func load_pending_commitment() -> Dictionary:
	if not FileAccess.file_exists(_pending_path()):
		return {}
	var file := FileAccess.open(_pending_path(), FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return RunState._normalize_json_numbers(parsed) if parsed is Dictionary else {}

func clear_pending() -> Error:
	if not FileAccess.file_exists(_pending_path()):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(_pending_path()))

func _pending_path() -> String:
	return save_path + PENDING_SUFFIX
