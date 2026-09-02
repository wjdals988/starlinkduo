class_name CombatEngine
extends RefCounted

const HAND_SIZE := 5

var cards: Dictionary

func _init(card_catalog: Dictionary) -> void:
	cards = card_catalog

func create_demo_combat() -> CombatState:
	var state := CombatState.new()
	var guardian := CombatantState.new(0, &"guardian")
	guardian.draw_pile.assign([
		&"guardian_strike", &"guardian_guard", &"guardian_cover",
		&"neutral_pulse", &"neutral_barrier", &"guardian_strike",
	])
	var engineer := CombatantState.new(1, &"engineer")
	engineer.draw_pile.assign([
		&"engineer_bolt", &"engineer_charge", &"engineer_patch",
		&"neutral_link", &"neutral_pulse", &"engineer_bolt",
	])
	state.players.assign([guardian, engineer])
	var drone := EnemyState.new(&"training_drone", "훈련 드론", 44)
	drone.intent_damage = 9
	state.enemies.append(drone)
	begin_turn(state)
	return state

func create_run_combat(run: RunState, route_types: Array[String], content: Dictionary) -> CombatState:
	var state := CombatState.new()
	state.combat_id = StringName("run-%s-s%d-r%d" % [run.run_id, run.stage, run.step])
	state.team_health = run.team_health
	state.team_max_health = run.team_max_health
	for slot in 2:
		var player := CombatantState.new(slot, run.characters[slot])
		for card_id in run.decks[slot]:
			player.draw_pile.append(StringName(card_id))
		state.players.append(player)
		state.relics[slot] = run.relics[slot].duplicate()
	var stage_content: Dictionary = content.stages[run.stage - 1]
	var encounter: Dictionary
	if route_types.has("true_boss"):
		encounter = content.true_boss
	elif route_types.has("boss"):
		encounter = stage_content.boss
	elif route_types.has("key_challenge"):
		encounter = stage_content.elites[(run.seed + run.step) % stage_content.elites.size()].duplicate(true)
		encounter.id = "%s_key" % encounter.id
		encounter.name = "열쇠 수호자 · %s" % encounter.name
		encounter.health = roundi(encounter.health * 1.15)
	elif route_types.has("elite"):
		encounter = stage_content.elites[(run.seed + run.step) % stage_content.elites.size()]
	else:
		encounter = stage_content.normal_formations[(run.seed + run.step) % stage_content.normal_formations.size()]
	var enemy := EnemyState.new(StringName(encounter.id), String(encounter.name), int(encounter.health))
	enemy.intent_damage = int(encounter.intent_damage)
	state.enemies.append(enemy)
	begin_turn(state)
	_apply_relic_trigger(state, "combat_start")
	return state

func begin_turn(state: CombatState) -> void:
	if state.phase == CombatState.Phase.WON or state.phase == CombatState.Phase.LOST:
		return
	state.phase = CombatState.Phase.PLANNING
	state.plans.clear()
	for player in state.players:
		player.energy = player.max_energy
		player.block = 0
		player.ready = false
		_draw_to_hand(player, HAND_SIZE)
	_apply_relic_trigger(state, "turn_start")
	state.event_log.append({"type": "turn_started", "turn": state.turn})

func submit_plan(state: CombatState, slot: int, plays: Array[Dictionary]) -> Dictionary:
	if state.phase != CombatState.Phase.PLANNING:
		return _error("not_planning")
	if slot < 0 or slot >= state.players.size():
		return _error("invalid_slot")
	var validation := _validate_plays(state, slot, plays)
	if not validation.ok:
		return validation
	state.plans[slot] = plays.duplicate(true)
	state.players[slot].ready = true
	return {"ok": true, "state_hash": StateHasher.hash_snapshot(state.to_snapshot())}

func use_consumable(state: CombatState, run: RunState, slot: int, item_index: int, content: Dictionary) -> Dictionary:
	if state.phase != CombatState.Phase.PLANNING:
		return _error("not_planning")
	if slot < 0 or slot >= state.players.size() or item_index < 0 or item_index >= run.consumables[slot].size():
		return _error("invalid_consumable")
	var item_id := String(run.consumables[slot][item_index])
	var item: Dictionary = {}
	for candidate in content.consumables:
		if String(candidate.id) == item_id:
			item = candidate
			break
	if item.is_empty():
		return _error("unknown_consumable")
	var player: CombatantState = state.players[slot]
	var value := int(item.value)
	var summary := ""
	match String(item.effect):
		"block":
			player.block += value
			summary = "방어 +%d" % value
		"energy":
			player.energy += value
			summary = "에너지 +%d" % value
		"heal":
			var before := state.team_health
			state.team_health = mini(state.team_max_health, state.team_health + value)
			summary = "팀 내구도 +%d" % (state.team_health - before)
		"damage":
			var living := _living_enemies(state)
			if living.is_empty():
				return _error("no_enemy")
			living[0].health = maxi(0, living[0].health - value)
			summary = "적에게 %d 피해" % value
			if _living_enemies(state).is_empty():
				state.phase = CombatState.Phase.WON
				_apply_relic_trigger(state, "combat_end")
		"draw":
			_draw_to_hand(player, player.hand.size() + value)
			summary = "카드 %d장 드로우" % value
		"duplicate":
			if player.hand.is_empty():
				return _error("empty_hand")
			player.hand.append(player.hand[0])
			summary = "첫 손패 1장 임시 복제"
		"escape":
			player.block += 20
			summary = "회피 방벽 +20"
		"upgrade":
			player.max_energy += value
			player.energy += value
			summary = "이번 전투 최대 에너지 +%d" % value
		_:
			return _error("unsupported_consumable")
	run.consumables[slot].remove_at(item_index)
	state.event_log.append({"type": "consumable_used", "slot": slot, "item_id": item_id})
	return {"ok": true, "item_id": item_id, "name": String(item.name), "summary": summary}

func resolve_if_ready(state: CombatState) -> Dictionary:
	if state.plans.size() != state.players.size():
		return _error("players_not_ready")
	state.phase = CombatState.Phase.RESOLVING
	var ordered_plays: Array[Dictionary] = []
	for slot in state.plans.keys():
		var selection_order := 0
		for play in state.plans[slot]:
			var card: CardData = cards[play.card_id]
			ordered_plays.append({
				"slot": int(slot),
				"selection_order": selection_order,
				"speed": card.speed,
				"play": play,
			})
			selection_order += 1
	ordered_plays.sort_custom(_sort_plays)
	for ordered in ordered_plays:
		_resolve_play(state, ordered.slot, ordered.play)
		if state.phase == CombatState.Phase.WON:
			break
	if state.phase != CombatState.Phase.WON:
		_resolve_enemy_turn(state)
	_finish_turn(state)
	return {"ok": true, "state_hash": StateHasher.hash_snapshot(state.to_snapshot())}

func _validate_plays(state: CombatState, slot: int, plays: Array[Dictionary]) -> Dictionary:
	var player: CombatantState = state.players[slot]
	var remaining_energy := player.energy
	var available := player.hand.duplicate()
	var support_count := 0
	for play in plays:
		if not play.has("card_id") or not cards.has(play.card_id):
			return _error("unknown_card")
		var card_id: StringName = play.card_id
		if not available.has(card_id):
			return _error("card_not_in_hand")
		var card: CardData = cards[card_id]
		remaining_energy -= card.energy_cost
		if remaining_energy < 0:
			return _error("insufficient_energy")
		if card.is_support():
			support_count += 1
			if support_count > 1:
				return _error("support_limit")
		if card.target == CardData.Target.ENEMY:
			var target_index: int = play.get("target", -1)
			if target_index < 0 or target_index >= state.enemies.size():
				return _error("invalid_target")
		available.erase(card_id)
	return {"ok": true}

func _resolve_play(state: CombatState, slot: int, play: Dictionary) -> void:
	var source: CombatantState = state.players[slot]
	var card: CardData = cards[play.card_id]
	source.energy -= card.energy_cost
	source.hand.erase(card.id)
	source.discard_pile.append(card.id)
	for effect in card.effects:
		_resolve_effect(state, source, card, play, effect)
	state.event_log.append({"type": "card_played", "slot": slot, "card_id": String(card.id)})
	_apply_relic_trigger(state, "card_played", slot)
	if card.is_support():
		_apply_relic_trigger(state, "support_played", slot)
	if _living_enemies(state).is_empty():
		state.phase = CombatState.Phase.WON
		state.event_log.append({"type": "combat_won", "turn": state.turn})
		_apply_relic_trigger(state, "combat_end")

func _resolve_effect(state: CombatState, source: CombatantState, card: CardData, play: Dictionary, effect: Dictionary) -> void:
	var amount: int = effect.get("amount", 0)
	match effect.get("type", ""):
		"damage":
			var enemy: EnemyState = state.enemies[play.get("target", 0)]
			var unblocked := maxi(0, amount - enemy.block)
			enemy.block = maxi(0, enemy.block - amount)
			enemy.health = maxi(0, enemy.health - unblocked)
		"block":
			var recipient := _recipient_for(state, source, card)
			recipient.block += amount
		"energy":
			var recipient := _recipient_for(state, source, card)
			recipient.energy += amount
		"heal":
			state.team_health = mini(state.team_max_health, state.team_health + amount)

func _recipient_for(state: CombatState, source: CombatantState, card: CardData) -> CombatantState:
	if card.target == CardData.Target.ALLY:
		return state.players[1 - source.slot]
	return source

func _resolve_enemy_turn(state: CombatState) -> void:
	for enemy in _living_enemies(state):
		_apply_relic_trigger(state, "damage_taken")
		if enemy.health <= 0:
			continue
		var total_block := 0
		for player in state.players:
			total_block += player.block
		var damage := maxi(0, enemy.intent_damage - total_block)
		state.team_health = maxi(0, state.team_health - damage)
		state.event_log.append({"type": "enemy_attack", "enemy_id": String(enemy.id), "damage": damage})
	if _living_enemies(state).is_empty():
		state.phase = CombatState.Phase.WON
		state.event_log.append({"type": "combat_won", "turn": state.turn})
		_apply_relic_trigger(state, "combat_end")
		return
	if state.team_health <= 0:
		state.phase = CombatState.Phase.LOST
		state.event_log.append({"type": "combat_lost", "turn": state.turn})

func _apply_relic_trigger(state: CombatState, trigger: String, triggering_slot: int = -1) -> void:
	var content := RunContentCatalog.build()
	for slot in state.relics.size():
		if triggering_slot >= 0 and slot != triggering_slot:
			continue
		for relic_id in state.relics[slot]:
			for relic in content.relics:
				if String(relic.id) == String(relic_id) and String(relic.trigger) == trigger:
					_apply_relic_effect(state, slot, relic, trigger)
					break

func _apply_relic_effect(state: CombatState, slot: int, relic: Dictionary, trigger: String) -> void:
	var value := int(relic.value)
	match String(relic.effect):
		"block": state.players[slot].block += value
		"energy": state.players[slot].energy += value
		"damage":
			var living := _living_enemies(state)
			if not living.is_empty():
				living[0].health = maxi(0, living[0].health - value)
		"heal": state.team_health = mini(state.team_max_health, state.team_health + value)
	state.event_log.append({
		"type": "relic_triggered",
		"slot": slot,
		"relic_id": String(relic.id),
		"trigger": trigger,
		"effect": String(relic.effect),
		"value": value,
	})

func _finish_turn(state: CombatState) -> void:
	if state.phase == CombatState.Phase.WON or state.phase == CombatState.Phase.LOST:
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
		var card_id: StringName = player.draw_pile.pop_front()
		player.hand.append(card_id)

func _living_enemies(state: CombatState) -> Array[EnemyState]:
	var result: Array[EnemyState] = []
	for enemy in state.enemies:
		if enemy.health > 0:
			result.append(enemy)
	return result

static func _sort_plays(a: Dictionary, b: Dictionary) -> bool:
	if a.speed != b.speed:
		return a.speed < b.speed
	if a.slot != b.slot:
		return a.slot < b.slot
	return a.selection_order < b.selection_order

static func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code}
