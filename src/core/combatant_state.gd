class_name CombatantState
extends RefCounted

var slot: int
var character_id: StringName
var energy: int = 3
var max_energy: int = 3
var block: int = 0
var draw_pile: Array[StringName] = []
var hand: Array[StringName] = []
var discard_pile: Array[StringName] = []
var statuses: Dictionary = {}
var ready: bool = false

func _init(p_slot: int = 0, p_character_id: StringName = &"") -> void:
	slot = p_slot
	character_id = p_character_id

func to_snapshot() -> Dictionary:
	return {
		"slot": slot,
		"character_id": String(character_id),
		"energy": energy,
		"max_energy": max_energy,
		"block": block,
		"draw_pile": _string_names(draw_pile),
		"hand": _string_names(hand),
		"discard_pile": _string_names(discard_pile),
		"statuses": statuses.duplicate(true),
		"ready": ready,
	}

static func from_snapshot(snapshot: Dictionary) -> CombatantState:
	var result := CombatantState.new(int(snapshot.slot), StringName(snapshot.character_id))
	result.energy = int(snapshot.energy)
	result.max_energy = int(snapshot.max_energy)
	result.block = int(snapshot.block)
	result.draw_pile.assign(_to_string_names(snapshot.draw_pile))
	result.hand.assign(_to_string_names(snapshot.hand))
	result.discard_pile.assign(_to_string_names(snapshot.discard_pile))
	result.statuses = snapshot.statuses.duplicate(true)
	result.ready = bool(snapshot.ready)
	return result

static func _string_names(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(String(value))
	return result

static func _to_string_names(values: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for value in values:
		result.append(StringName(value))
	return result
