class_name DuelEngine
extends RefCounted

const HAND_SIZE := 5

var cards: Dictionary

func _init(card_catalog: Dictionary) -> void:
	cards = card_catalog

func create_duel(characters: Array, decks: Array) -> DuelState:
	var state := DuelState.new()
	state.duel_id = StringName("duel-%d" % Time.get_ticks_msec())
	for slot in 2:
		var player := CombatantState.new(slot, StringName(characters[slot]))
		for card_id in decks[slot]:
			player.draw_pile.append(StringName(card_id))
		state.players.append(player)
	begin_turn(state)
	return state

func begin_turn(state: DuelState) -> void:
	if state.phase == DuelState.Phase.FINISHED:
		return
	state.phase = DuelState.Phase.PLANNING
	state.plans.clear()
	for player in state.players:
		player.energy = player.max_energy
		player.block = 0
		player.ready = false
		_draw_to_hand(player, HAND_SIZE)
	state.event_log.append({"type": "turn_started", "turn": state.turn})

func submit_plan(state: DuelState, slot: int, plays: Array[Dictionary]) -> Dictionary:
	if state.phase != DuelState.Phase.PLANNING:
		return _error("not_planning")
	if slot < 0 or slot >= 2:
		return _error("invalid_slot")
	var validation := _validate_plays(state, slot, plays)
	if not validation.ok:
		return validation
	state.plans[slot] = plays.duplicate(true)
	state.players[slot].ready = true
	return {"ok": true, "state_hash": StateHasher.hash_snapshot(state.to_snapshot())}

func resolve_if_ready(state: DuelState) -> Dictionary:
	if state.plans.size() != 2:
		return _error("players_not_ready")
	state.phase = DuelState.Phase.RESOLVING
	var ordered: Array[Dictionary] = []
	for slot in state.plans:
		var selection_order := 0
		for play in state.plans[slot]:
			var card: CardData = cards[play.card_id]
			ordered.append({"slot": int(slot), "order": selection_order, "speed": card.speed, "play": play})
			selection_order += 1
	ordered.sort_custom(_sort_plays)
	for item in ordered:
		_resolve_play(state, item.slot, item.play)
	_finish_or_advance(state)
	return {"ok": true, "state_hash": StateHasher.hash_snapshot(state.to_snapshot())}

func _validate_plays(state: DuelState, slot: int, plays: Array[Dictionary]) -> Dictionary:
	if plays.size() > 3:
		return _error("card_limit")
	var player := state.players[slot]
	var available := player.hand.duplicate()
	var remaining_energy := player.energy
	for play in plays:
		if not play.has("card_id") or not cards.has(play.card_id):
			return _error("unknown_card")
		var card_id: StringName = play.card_id
		if not available.has(card_id):
			return _error("card_not_in_hand")
		remaining_energy -= (cards[card_id] as CardData).energy_cost
		if remaining_energy < 0:
			return _error("insufficient_energy")
		available.erase(card_id)
	return {"ok": true}

func _resolve_play(state: DuelState, slot: int, play: Dictionary) -> void:
	var player := state.players[slot]
	var card: CardData = cards[play.card_id]
	player.energy -= card.energy_cost
	player.hand.erase(card.id)
	player.discard_pile.append(card.id)
	for effect in card.effects:
		var amount := int(effect.get("amount", 0))
		match String(effect.get("type", "")):
			"damage": _deal_damage(state, 1 - slot, amount)
			"block": player.block += amount
			"energy": player.energy += amount
			"heal": state.health[slot] = mini(state.max_health[slot], state.health[slot] + amount)
	state.event_log.append({"type": "card_played", "slot": slot, "card_id": String(card.id)})

func _deal_damage(state: DuelState, target: int, amount: int) -> void:
	var blocked := mini(state.players[target].block, amount)
	state.players[target].block -= blocked
	var damage := amount - blocked
	state.health[target] = maxi(0, state.health[target] - damage)
	state.event_log.append({"type": "duel_damage", "target": target, "damage": damage, "blocked": blocked})

func _finish_or_advance(state: DuelState) -> void:
	if state.health[0] <= 0 or state.health[1] <= 0:
		state.phase = DuelState.Phase.FINISHED
		state.winner = -1 if state.health[0] <= 0 and state.health[1] <= 0 else (1 if state.health[0] <= 0 else 0)
		state.event_log.append({"type": "duel_finished", "winner": state.winner})
		return
	for player in state.players:
		player.discard_pile.append_array(player.hand)
		player.hand.clear()
	state.turn += 1
	begin_turn(state)

func _draw_to_hand(player: CombatantState, target_size: int) -> void:
	while player.hand.size() < target_size:
		if player.draw_pile.is_empty():
			if player.discard_pile.is_empty():
				break
			player.draw_pile.assign(player.discard_pile)
			player.discard_pile.clear()
		player.hand.append(player.draw_pile.pop_front())

static func _sort_plays(a: Dictionary, b: Dictionary) -> bool:
	if a.speed != b.speed:
		return a.speed < b.speed
	if a.slot != b.slot:
		return a.slot < b.slot
	return a.order < b.order

static func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code}
