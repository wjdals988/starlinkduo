class_name RunSaveStore
extends RefCounted

const SAVE_PATH := "user://active_run.json"

var save_path: String

func _init(path: String = SAVE_PATH) -> void:
	save_path = path

func save(run: RunState, reason: String) -> Error:
	run.checkpoint_reason = reason
	return CheckedJsonStore.save_payload(save_path, run.to_snapshot())

func load_active() -> RunState:
	var parsed: Variant = CheckedJsonStore.load_payload(save_path, ["run_id", "seed", "stage", "step", "team_health", "team_max_health", "keys", "gold", "characters", "decks", "relics", "consumables", "map", "checkpoint_reason"])
	if not parsed is Dictionary:
		return null
	return RunState.from_snapshot(parsed)

func clear() -> Error:
	return CheckedJsonStore.clear(save_path)
