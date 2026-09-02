class_name RunSaveStore
extends RefCounted

const SAVE_PATH := "user://active_run.json"

var save_path: String

func _init(path: String = SAVE_PATH) -> void:
	save_path = path

func save(run: RunState, reason: String) -> Error:
	run.checkpoint_reason = reason
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(run.to_snapshot()))
	file.close()
	return OK

func load_active() -> RunState:
	if not FileAccess.file_exists(save_path):
		return null
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return null
	return RunState.from_snapshot(parsed)

func clear() -> Error:
	if not FileAccess.file_exists(save_path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
