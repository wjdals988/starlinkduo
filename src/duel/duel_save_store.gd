class_name DuelSaveStore
extends RefCounted

const SAVE_PATH := "user://active_duel.json"
const PENDING_SUFFIX := ".pending"
const TEMP_SUFFIX := ".tmp"

var save_path: String

func _init(path: String = SAVE_PATH) -> void:
	save_path = path

func save(state: DuelState) -> Error:
	return CheckedJsonStore.save_payload(save_path, state.to_snapshot())

func load_active() -> DuelState:
	var parsed: Variant = CheckedJsonStore.load_payload(save_path, ["duel_id", "turn", "phase", "players", "health", "max_health", "plans", "winner", "event_log"])
	return DuelState.from_snapshot(parsed) if parsed is Dictionary else null

func clear() -> Error:
	var state_error := CheckedJsonStore.clear(save_path)
	var pending_error := clear_pending()
	return state_error if state_error != OK else pending_error

func save_pending_commitment(data: Dictionary) -> Error:
	return CheckedJsonStore.save_payload(_pending_path(), data)

func load_pending_commitment() -> Dictionary:
	var parsed: Variant = CheckedJsonStore.load_payload(_pending_path(), ["role", "duel_id", "turn", "commitment"])
	return RunState._normalize_json_numbers(parsed) if parsed is Dictionary else {}

func clear_pending() -> Error:
	return CheckedJsonStore.clear(_pending_path())

func _pending_path() -> String:
	return save_path + PENDING_SUFFIX
