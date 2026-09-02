class_name DuelSaveStore
extends RefCounted

const SAVE_PATH := "user://active_duel.json"

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
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
