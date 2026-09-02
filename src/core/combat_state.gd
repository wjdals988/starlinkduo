class_name CombatState
extends RefCounted

enum Phase { PLANNING, RESOLVING, WON, LOST }

var combat_id: StringName = &"demo_combat"
var turn: int = 1
var phase: Phase = Phase.PLANNING
var team_health: int = 70
var team_max_health: int = 70
var players: Array[CombatantState] = []
var enemies: Array[EnemyState] = []
var plans: Dictionary = {}
var event_log: Array[Dictionary] = []

func to_snapshot() -> Dictionary:
	var player_snapshots: Array[Dictionary] = []
	for player in players:
		player_snapshots.append(player.to_snapshot())
	var enemy_snapshots: Array[Dictionary] = []
	for enemy in enemies:
		enemy_snapshots.append(enemy.to_snapshot())
	return {
		"combat_id": String(combat_id),
		"turn": turn,
		"phase": phase,
		"team_health": team_health,
		"team_max_health": team_max_health,
		"players": player_snapshots,
		"enemies": enemy_snapshots,
		"plans": plans.duplicate(true),
		"event_log": event_log.duplicate(true),
	}

