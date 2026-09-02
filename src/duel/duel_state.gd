class_name DuelState
extends RefCounted

enum Phase { PLANNING, RESOLVING, FINISHED }

var duel_id: StringName = &"local_duel"
var turn := 1
var phase: Phase = Phase.PLANNING
var players: Array[CombatantState] = []
var health: Array[int] = [36, 36]
var max_health: Array[int] = [36, 36]
var plans: Dictionary = {}
var winner := -2 # -2 ongoing, -1 draw, 0/1 winner
var event_log: Array[Dictionary] = []

func to_snapshot() -> Dictionary:
	var player_snapshots: Array[Dictionary] = []
	for player in players:
		player_snapshots.append(player.to_snapshot())
	return {
		"duel_id": String(duel_id),
		"turn": turn,
		"phase": phase,
		"players": player_snapshots,
		"health": health.duplicate(),
		"max_health": max_health.duplicate(),
		"plans": plans.duplicate(true),
		"winner": winner,
		"event_log": event_log.duplicate(true),
	}

static func from_snapshot(snapshot: Dictionary) -> DuelState:
	snapshot = RunState._normalize_json_numbers(snapshot)
	var result := DuelState.new()
	result.duel_id = StringName(snapshot.duel_id)
	result.turn = int(snapshot.turn)
	result.phase = int(snapshot.phase) as Phase
	for player_snapshot in snapshot.players:
		result.players.append(CombatantState.from_snapshot(player_snapshot))
	result.health.assign(snapshot.health)
	result.max_health.assign(snapshot.max_health)
	for key in snapshot.plans:
		var restored: Array[Dictionary] = []
		for play in snapshot.plans[key]:
			var entry: Dictionary = play.duplicate(true)
			entry.card_id = StringName(entry.card_id)
			restored.append(entry)
		result.plans[int(key)] = restored
	result.winner = int(snapshot.winner)
	result.event_log.assign(snapshot.event_log)
	return result
