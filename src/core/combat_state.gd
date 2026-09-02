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
var relics: Array[Array] = [[], []]

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
		"relics": relics.duplicate(true),
	}

static func from_snapshot(snapshot: Dictionary) -> CombatState:
	snapshot = RunState._normalize_json_numbers(snapshot)
	var result := CombatState.new()
	result.combat_id = StringName(snapshot.combat_id)
	result.turn = int(snapshot.turn)
	result.phase = int(snapshot.phase) as Phase
	result.team_health = int(snapshot.team_health)
	result.team_max_health = int(snapshot.team_max_health)
	for player_snapshot in snapshot.players:
		result.players.append(CombatantState.from_snapshot(player_snapshot))
	for enemy_snapshot in snapshot.enemies:
		result.enemies.append(EnemyState.from_snapshot(enemy_snapshot))
	for key in snapshot.plans:
		var restored_plays: Array[Dictionary] = []
		for play in snapshot.plans[key]:
			var restored_play: Dictionary = play.duplicate(true)
			if restored_play.has("card_id"):
				restored_play.card_id = StringName(restored_play.card_id)
			restored_plays.append(restored_play)
		result.plans[int(key)] = restored_plays
	result.event_log.assign(snapshot.event_log)
	result.relics.assign(snapshot.get("relics", [[], []]))
	return result
