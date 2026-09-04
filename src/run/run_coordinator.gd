class_name RunCoordinator
extends RefCounted

signal run_changed(snapshot: Dictionary)

var catalog: Dictionary
var reward_generator: RewardGenerator
var save_store: RunSaveStore
var run: RunState

func _init(card_catalog: Dictionary, store: RunSaveStore = null) -> void:
	catalog = card_catalog
	reward_generator = RewardGenerator.new(catalog)
	save_store = store if store != null else RunSaveStore.new()

func start_new(seed: int) -> RunState:
	run = RunState.new(seed)
	run.map = MapGenerator.new().generate_run(seed)
	run.decks[0] = ["guardian_strike", "guardian_guard", "guardian_cover", "neutral_pulse", "guardian_strike", "guardian_guard", "neutral_barrier", "neutral_pulse"]
	run.decks[1] = ["engineer_bolt", "engineer_charge", "engineer_patch", "neutral_barrier", "engineer_bolt", "engineer_charge", "neutral_link", "neutral_pulse"]
	checkpoint("new_run")
	return run

func select_character(player_slot: int, character_id: StringName) -> Dictionary:
	if not _valid_slot(player_slot) or not can_select_characters():
		return {"ok": false, "error": "character_selection_closed"}
	if not character_id in [&"guardian", &"engineer", &"hacker", &"assault", &"medic", &"navigator"]:
		return {"ok": false, "error": "unknown_character"}
	if run.characters[1 - player_slot] == character_id:
		return {"ok": false, "error": "character_already_taken"}
	run.characters[player_slot] = character_id
	run.decks[player_slot] = starter_deck_for(character_id)
	checkpoint("character_selected")
	return {"ok": true, "character_id": String(character_id)}

func can_select_characters() -> bool:
	return run != null and run.phase == "traversal" and run.stage == 1 and run.step == 0 and run.pending_routes.is_empty()

func resume_or_start(seed: int) -> RunState:
	run = save_store.load_active()
	return run if run != null else start_new(seed)

func current_card_reward(player_slot: int, encounter_type: String = "combat") -> Array[StringName]:
	if not _valid_slot(player_slot) or not run.pending_card_rewards[player_slot]:
		return []
	return reward_generator.card_reward(_content_seed(player_slot, 17), _scope_for_slot(player_slot), encounter_type)

func current_shop(player_slot: int) -> Dictionary:
	return reward_generator.shop_inventory(_content_seed(player_slot, 31), _scope_for_slot(player_slot))

func claim_card(player_slot: int, card_id: StringName) -> bool:
	if not _valid_slot(player_slot) or not run.pending_card_rewards[player_slot] or not catalog.has(card_id):
		return false
	var card: CardData = catalog[card_id]
	if card.owner_scope != _scope_for_slot(player_slot) and card.owner_scope != CardData.Scope.NEUTRAL:
		return false
	run.decks[player_slot].append(String(card_id))
	run.pending_card_rewards[player_slot] = false
	checkpoint("card_reward")
	return true

func buy_card(player_slot: int, entry: Dictionary) -> bool:
	if not _valid_slot(player_slot) or not run.shop_open[player_slot] or not entry.has("card_id") or not entry.has("price"):
		return false
	var card_id := StringName(entry.card_id)
	var price := int(entry.price)
	var purchase_key := "card:%s" % card_id
	if price < 0 or run.gold[player_slot] < price or not catalog.has(card_id) or run.shop_purchases[player_slot].has(purchase_key):
		return false
	var card: CardData = catalog[card_id]
	if card.owner_scope != _scope_for_slot(player_slot) and card.owner_scope != CardData.Scope.NEUTRAL:
		return false
	run.gold[player_slot] -= price
	run.decks[player_slot].append(String(card_id))
	run.shop_purchases[player_slot].append(purchase_key)
	checkpoint("shop_purchase")
	return true

func buy_relic(player_slot: int, entry: Dictionary) -> bool:
	var purchase_key := "relic:%s" % String(entry.get("id", ""))
	if not _valid_slot(player_slot) or not run.shop_open[player_slot] or not _valid_shop_entry(player_slot, entry) or run.shop_purchases[player_slot].has(purchase_key):
		return false
	var relic_id := String(entry.id)
	if run.relics[player_slot].has(relic_id):
		return false
	run.gold[player_slot] -= int(entry.price)
	run.relics[player_slot].append(relic_id)
	run.shop_purchases[player_slot].append(purchase_key)
	checkpoint("relic_purchase")
	return true

func buy_consumable(player_slot: int, entry: Dictionary) -> bool:
	var purchase_key := "consumable:%s" % String(entry.get("id", ""))
	if not _valid_slot(player_slot) or not run.shop_open[player_slot] or not _valid_shop_entry(player_slot, entry) or run.consumables[player_slot].size() >= 3 or run.shop_purchases[player_slot].has(purchase_key):
		return false
	run.gold[player_slot] -= int(entry.price)
	run.consumables[player_slot].append(String(entry.id))
	run.shop_purchases[player_slot].append(purchase_key)
	checkpoint("consumable_purchase")
	return true

func remove_card(player_slot: int, deck_index: int, cost: int) -> bool:
	var purchase_key := "service:remove_card"
	if not _valid_slot(player_slot) or not run.shop_open[player_slot] or cost < 0:
		return false
	if run.shop_purchases[player_slot].has(purchase_key) or run.gold[player_slot] < cost:
		return false
	if deck_index < 0 or deck_index >= run.decks[player_slot].size() or run.decks[player_slot].size() <= 5:
		return false
	run.gold[player_slot] -= cost
	run.decks[player_slot].remove_at(deck_index)
	run.shop_purchases[player_slot].append(purchase_key)
	checkpoint("card_removed")
	return true

func use_consumable(combat: CombatState, player_slot: int, item_index: int, engine: CombatEngine) -> Dictionary:
	if not _valid_slot(player_slot):
		return {"ok": false, "error": "invalid_slot"}
	var result := engine.use_consumable(combat, run, player_slot, item_index, RunContentCatalog.build())
	if result.ok:
		checkpoint("consumable_used")
	return result

func choose_route(player_slot: int, node_id: String) -> Dictionary:
	if not _valid_slot(player_slot):
		return {"ok": false, "error": "invalid_slot"}
	if run.pending_card_rewards.any(func(pending: bool) -> bool: return pending):
		return {"ok": false, "error": "rewards_pending"}
	if run.phase != "traversal" or not run.pending_event.is_empty() or run.step < 0 or run.step >= MapGenerator.TRAVERSAL_STEPS:
		return {"ok": false, "error": "route_unavailable"}
	var step_data: Dictionary = run.map.stages[run.stage - 1].steps[run.step]
	if step_data.kind == "common":
		if step_data.options[0].id != node_id:
			return {"ok": false, "error": "invalid_node"}
		run.pending_routes = {0: node_id, 1: node_id}
		checkpoint("routes_ready")
		return {"ok": true, "ready": true, "node_type": step_data.options[0].type}
	var valid_node := false
	var node_type := ""
	for option in step_data.lanes[player_slot].options:
		if option.id == node_id:
			valid_node = true
			node_type = option.type
			break
	if not valid_node:
		return {"ok": false, "error": "invalid_node"}
	run.pending_routes[player_slot] = node_id
	checkpoint("route_selected")
	return {"ok": true, "ready": run.pending_routes.size() == 2, "node_type": node_type}

func complete_routes(completed_types: Array[String]) -> Dictionary:
	if run.pending_routes.size() != 2:
		return {"ok": false, "error": "routes_not_ready"}
	if completed_types.has("key_challenge"):
		run.unlock_key(run.stage)
	run.pending_routes.clear()
	advance_step()
	return {"ok": true}

func complete_combat(combat: CombatState, completed_types: Array[String]) -> Dictionary:
	if combat.phase != CombatState.Phase.WON:
		return {"ok": false, "error": "combat_not_won"}
	run.team_health = combat.team_health
	var gold_reward := 45 if completed_types.has("elite") or completed_types.has("key_challenge") else 25
	for slot in 2:
		run.gold[slot] += gold_reward
		run.pending_card_rewards[slot] = true
	_set_shop_access(completed_types)
	var node_summary := _apply_noncombat_effects(completed_types)
	if completed_types.has("event"):
		var event_result := begin_event(completed_types)
		return {"ok": event_result.ok, "gold": gold_reward, "summary": node_summary, "event_pending": event_result.ok}
	var result := complete_routes(completed_types)
	if result.ok:
		checkpoint("combat_reward")
	return {"ok": result.ok, "gold": gold_reward, "summary": node_summary}

func complete_boss_combat(combat: CombatState, true_boss: bool = false) -> Dictionary:
	var expected_phase := "true_boss" if true_boss else "stage_boss"
	if run.phase != expected_phase:
		return {"ok": false, "error": "boss_unavailable"}
	if combat.phase != CombatState.Phase.WON:
		return {"ok": false, "error": "combat_not_won"}
	run.team_health = combat.team_health
	var reward := 100 if true_boss else 60
	for slot in 2:
		run.gold[slot] += reward
		run.pending_card_rewards[slot] = true
	if true_boss:
		run.phase = "completed"
		checkpoint("run_completed")
		return {"ok": true, "gold": reward, "run_completed": true}
	if run.stage < 3:
		run.stage += 1
		run.step = 0
		run.phase = "traversal"
		checkpoint("stage_complete")
		return {"ok": true, "gold": reward, "stage_advanced": true}
	if run.can_enter_true_boss():
		run.phase = "true_boss"
		checkpoint("true_boss_unlocked")
		return {"ok": true, "gold": reward, "true_boss_unlocked": true}
	run.phase = "failed"
	checkpoint("run_failed_missing_keys")
	return {"ok": true, "gold": reward, "run_failed": true}

func resolve_noncombat(completed_types: Array[String]) -> Dictionary:
	if run.pending_routes.size() != 2:
		return {"ok": false, "error": "routes_not_ready"}
	_set_shop_access(completed_types)
	var summary := _apply_noncombat_effects(completed_types)
	if completed_types.has("event"):
		var event_result := begin_event(completed_types)
		return {"ok": event_result.ok, "summary": summary, "event_pending": event_result.ok}
	var result := complete_routes(completed_types)
	return {"ok": result.ok, "summary": summary}

func begin_event(route_types: Array[String]) -> Dictionary:
	if run.pending_routes.size() != 2 or not route_types.has("event") or not run.pending_event.is_empty():
		return {"ok": false, "error": "event_unavailable"}
	var events: Array = RunContentCatalog.build().events
	var event: Dictionary = events[absi(_content_seed(0, 73)) % events.size()]
	run.pending_event = {
		"id": String(event.id),
		"route_types": route_types.duplicate(),
		"votes": {},
	}
	run.last_event_result.clear()
	checkpoint("event_started")
	return {"ok": true, "event": event}

func current_event() -> Dictionary:
	if run == null or run.pending_event.is_empty():
		return {}
	for event in RunContentCatalog.build().events:
		if String(event.id) == String(run.pending_event.id):
			return event
	return {}

func submit_event_choice(player_slot: int, choice_index: int) -> Dictionary:
	if not _valid_slot(player_slot) or run.pending_event.is_empty():
		return {"ok": false, "error": "event_unavailable"}
	var event := current_event()
	if event.is_empty() or choice_index < 0 or choice_index >= event.choices.size():
		return {"ok": false, "error": "invalid_event_choice"}
	var votes: Dictionary = run.pending_event.votes
	if votes.has(player_slot) or votes.has(str(player_slot)):
		return {"ok": false, "error": "choice_already_submitted"}
	votes[player_slot] = choice_index
	run.pending_event.votes = votes
	if votes.size() < 2:
		checkpoint("event_vote")
		return {"ok": true, "ready": false}
	var first := int(votes.get(0, votes.get("0", -1)))
	var second := int(votes.get(1, votes.get("1", -1)))
	var result := _resolve_event(event, first, second)
	var route_types: Array[String] = []
	for node_type in run.pending_event.route_types:
		route_types.append(String(node_type))
	run.last_event_result = result.duplicate(true)
	run.pending_event.clear()
	var completion := complete_routes(route_types)
	checkpoint("event_resolved")
	result["ok"] = completion.ok
	result["ready"] = true
	return result

func selected_route_types() -> Array[String]:
	var result: Array[String] = []
	if run.pending_routes.size() != 2:
		return result
	var step_data: Dictionary = run.map.stages[run.stage - 1].steps[run.step]
	if step_data.kind == "common":
		return [String(step_data.options[0].type), String(step_data.options[0].type)]
	for slot in 2:
		for option in step_data.lanes[slot].options:
			if option.id == run.pending_routes.get(slot, ""):
				result.append(String(option.type))
	return result

func advance_step() -> void:
	run.step += 1
	if run.step >= MapGenerator.TRAVERSAL_STEPS:
		run.step = MapGenerator.TRAVERSAL_STEPS
		run.phase = "stage_boss"
	checkpoint("step_complete")

func checkpoint(reason: String) -> Error:
	run.checkpoint_reason = reason
	var result := save_store.save(run, reason)
	if result == OK:
		run_changed.emit(run.to_snapshot())
	return result

func _content_seed(player_slot: int, salt: int) -> int:
	return run.seed + run.stage * 100_003 + run.step * 1_009 + player_slot * 97 + salt

func _scope_for_slot(player_slot: int) -> CardData.Scope:
	return {
		&"guardian": CardData.Scope.GUARDIAN,
		&"engineer": CardData.Scope.ENGINEER,
		&"hacker": CardData.Scope.HACKER,
		&"assault": CardData.Scope.ASSAULT,
		&"medic": CardData.Scope.MEDIC,
		&"navigator": CardData.Scope.NAVIGATOR,
	}.get(run.characters[player_slot], CardData.Scope.NEUTRAL)

func starter_deck_for(character_id: StringName) -> Array:
	if character_id == &"guardian":
		return ["guardian_strike", "guardian_guard", "guardian_cover", "neutral_pulse", "guardian_strike", "guardian_guard", "neutral_barrier", "neutral_pulse"]
	if character_id == &"engineer":
		return ["engineer_bolt", "engineer_charge", "engineer_patch", "neutral_barrier", "engineer_bolt", "engineer_charge", "neutral_link", "neutral_pulse"]
	if character_id == &"medic":
		return ["medic_card_04", "medic_card_04", "medic_card_03", "medic_card_02", "medic_card_04", "medic_card_05", "neutral_barrier", "neutral_link"]
	if character_id == &"navigator":
		return ["navigator_card_01", "navigator_card_01", "navigator_card_04", "navigator_card_04", "navigator_card_05", "navigator_card_05", "neutral_pulse", "neutral_link"]
	var prefix := String(character_id)
	return [
		"%s_card_01" % prefix, "%s_card_02" % prefix, "%s_card_03" % prefix,
		"%s_card_04" % prefix, "%s_card_01" % prefix, "%s_card_02" % prefix,
		"neutral_pulse", "neutral_barrier",
	]

func _valid_slot(player_slot: int) -> bool:
	return run != null and player_slot >= 0 and player_slot < 2

func _valid_shop_entry(player_slot: int, entry: Dictionary) -> bool:
	return _valid_slot(player_slot) and entry.has("id") and entry.has("price") and int(entry.price) >= 0 and run.gold[player_slot] >= int(entry.price)

func _node_summary(node_type: String) -> String:
	return {"combat": "전투", "elite": "엘리트", "key_challenge": "열쇠 도전"}.get(node_type, node_type)

func _apply_noncombat_effects(completed_types: Array[String]) -> Array[String]:
	var summary: Array[String] = []
	for node_type in completed_types:
		match node_type:
			"rest":
				var before := run.team_health
				run.team_health = mini(run.team_max_health, run.team_health + 12)
				summary.append("팀 내구도 +%d" % (run.team_health - before))
			"event": pass
			"shop": summary.append("상점 방문 가능")
	return summary

func _set_shop_access(completed_types: Array[String]) -> void:
	for slot in 2:
		var opens_shop := slot < completed_types.size() and completed_types[slot] == "shop"
		if opens_shop:
			run.shop_purchases[slot].clear()
		run.shop_open[slot] = opens_shop

func _resolve_event(event: Dictionary, first: int, second: int) -> Dictionary:
	if first != second:
		for slot in 2:
			run.gold[slot] += 8
		return {"outcome": "compromise", "summary": "의견이 달라 안전한 절충안을 택했습니다 · 각 +8 C"}
	if first == 1:
		var before := run.team_health
		run.team_health = mini(run.team_max_health, run.team_health + 4)
		return {"outcome": "safe", "summary": "안전을 우선했습니다 · 팀 내구도 +%d" % (run.team_health - before)}
	var risk := int(event.choices[0].risk)
	var roll := absi(_content_seed(0, 211)) % 100
	var success_threshold := 65 - risk * 10
	if roll < success_threshold:
		var reward := 24 + risk * 8
		for slot in 2:
			run.gold[slot] += reward
		return {"outcome": "success", "summary": "위험한 조사 성공 · 각 +%d C" % reward, "roll": roll}
	var damage := risk * 6
	run.team_health = maxi(1, run.team_health - damage)
	for slot in 2:
		run.gold[slot] += 10
	return {"outcome": "setback", "summary": "조사 중 사고 발생 · 팀 내구도 -%d · 각 +10 C" % damage, "roll": roll}
