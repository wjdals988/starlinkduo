class_name RunState
extends RefCounted

var run_id: String
var seed: int
var stage: int = 1
var step: int = 0
var team_health: int = 70
var team_max_health: int = 70
var keys: Array[bool] = [false, false, false]
var gold: Array[int] = [100, 100]
var characters: Array[StringName] = [&"guardian", &"engineer"]
var decks: Array[Array] = [[], []]
var relics: Array[Array] = [[], []]
var consumables: Array[Array] = [[], []]
var map: Dictionary = {}
var pending_routes: Dictionary = {}
var pending_card_rewards: Array[bool] = [false, false]
var shop_open: Array[bool] = [false, false]
var pending_event: Dictionary = {}
var last_event_result: Dictionary = {}
var checkpoint_reason := "new_run"
var phase := "traversal"

func _init(seed_value: int = 1) -> void:
	seed = seed_value
	run_id = "%08x-%08x" % [seed & 0xffffffff, (seed * 48_271) & 0xffffffff]

func unlock_key(stage_number: int) -> void:
	if stage_number >= 1 and stage_number <= 3:
		keys[stage_number - 1] = true

func can_enter_true_boss() -> bool:
	return keys.all(func(value: bool) -> bool: return value)

func to_snapshot() -> Dictionary:
	return {
		"run_id": run_id,
		"seed": seed,
		"stage": stage,
		"step": step,
		"team_health": team_health,
		"team_max_health": team_max_health,
		"keys": keys.duplicate(),
		"gold": gold.duplicate(),
		"characters": [String(characters[0]), String(characters[1])],
		"decks": decks.duplicate(true),
		"relics": relics.duplicate(true),
		"consumables": consumables.duplicate(true),
		"map": map.duplicate(true),
		"pending_routes": pending_routes.duplicate(true),
		"pending_card_rewards": pending_card_rewards.duplicate(),
		"shop_open": shop_open.duplicate(),
		"pending_event": pending_event.duplicate(true),
		"last_event_result": last_event_result.duplicate(true),
		"checkpoint_reason": checkpoint_reason,
		"phase": phase,
	}

static func from_snapshot(snapshot: Dictionary) -> RunState:
	var result := RunState.new(int(snapshot.seed))
	result.run_id = snapshot.run_id
	result.stage = int(snapshot.stage)
	result.step = int(snapshot.step)
	result.team_health = int(snapshot.team_health)
	result.team_max_health = int(snapshot.team_max_health)
	result.keys.assign(snapshot.keys)
	result.gold.assign([int(snapshot.gold[0]), int(snapshot.gold[1])])
	result.characters.assign([StringName(snapshot.characters[0]), StringName(snapshot.characters[1])])
	result.decks.assign(snapshot.decks)
	result.relics.assign(snapshot.relics)
	result.consumables.assign(snapshot.consumables)
	result.map = _normalize_json_numbers(snapshot.map)
	result.pending_routes = _normalize_json_numbers(snapshot.get("pending_routes", {}))
	result.pending_card_rewards.assign(snapshot.get("pending_card_rewards", [false, false]))
	result.shop_open.assign(snapshot.get("shop_open", [false, false]))
	result.pending_event = _normalize_json_numbers(snapshot.get("pending_event", {}))
	result.last_event_result = _normalize_json_numbers(snapshot.get("last_event_result", {}))
	result.checkpoint_reason = snapshot.checkpoint_reason
	result.phase = String(snapshot.get("phase", "traversal"))
	return result

static func _normalize_json_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		var normalized_dictionary: Dictionary = {}
		for key in value:
			normalized_dictionary[key] = _normalize_json_numbers(value[key])
		return normalized_dictionary
	if value is Array:
		var normalized_array: Array = []
		for item in value:
			normalized_array.append(_normalize_json_numbers(item))
		return normalized_array
	if value is float and is_equal_approx(value, roundf(value)):
		return int(value)
	return value
