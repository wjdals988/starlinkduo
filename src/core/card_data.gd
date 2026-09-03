class_name CardData
extends Resource

enum Rarity { COMMON, MAGIC, RARE, LEGENDARY }
# Keep existing numeric values stable because saved cards serialize this enum.
enum Scope { GUARDIAN, ENGINEER, HACKER, ASSAULT, NEUTRAL, MEDIC, NAVIGATOR }
enum Target { SELF, ALLY, ENEMY, TEAM }

@export var id: StringName
@export var display_name: String
@export_multiline var rules_text: String
@export var energy_cost: int = 1
@export var speed: int = 50
@export var rarity: Rarity = Rarity.COMMON
@export var owner_scope: Scope = Scope.NEUTRAL
@export var target: Target = Target.ENEMY
@export var effects: Array[Dictionary] = []
@export var tags: PackedStringArray = []

func is_support() -> bool:
	return target == Target.ALLY or target == Target.TEAM

func to_snapshot() -> Dictionary:
	return {
		"id": String(id),
		"name": display_name,
		"cost": energy_cost,
		"speed": speed,
		"rarity": rarity,
		"scope": owner_scope,
		"target": target,
		"effects": effects.duplicate(true),
		"tags": Array(tags),
	}
