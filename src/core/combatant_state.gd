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

static func _string_names(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(String(value))
	return result

