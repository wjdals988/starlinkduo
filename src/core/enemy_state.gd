class_name EnemyState
extends RefCounted

var id: StringName
var display_name: String
var health: int
var max_health: int
var block: int = 0
var intent_damage: int = 0
var statuses: Dictionary = {}

func _init(p_id: StringName = &"training_drone", p_name: String = "훈련 드론", p_health: int = 40) -> void:
	id = p_id
	display_name = p_name
	health = p_health
	max_health = p_health

func to_snapshot() -> Dictionary:
	return {
		"id": String(id),
		"name": display_name,
		"health": health,
		"max_health": max_health,
		"block": block,
		"intent_damage": intent_damage,
		"statuses": statuses.duplicate(true),
	}

static func from_snapshot(snapshot: Dictionary) -> EnemyState:
	var result := EnemyState.new(StringName(snapshot.id), String(snapshot.name), int(snapshot.max_health))
	result.health = int(snapshot.health)
	result.block = int(snapshot.block)
	result.intent_damage = int(snapshot.intent_damage)
	result.statuses = snapshot.statuses.duplicate(true)
	return result
