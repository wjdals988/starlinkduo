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

func resume_or_start(seed: int) -> RunState:
	run = save_store.load_active()
	return run if run != null else start_new(seed)

func current_card_reward(player_slot: int, encounter_type: String = "combat") -> Array[StringName]:
	return reward_generator.card_reward(_content_seed(player_slot, 17), _scope_for_slot(player_slot), encounter_type)

func current_shop(player_slot: int) -> Dictionary:
	return reward_generator.shop_inventory(_content_seed(player_slot, 31), _scope_for_slot(player_slot))

func claim_card(player_slot: int, card_id: StringName) -> bool:
	if not _valid_slot(player_slot) or not catalog.has(card_id):
		return false
	var card: CardData = catalog[card_id]
	if card.owner_scope != _scope_for_slot(player_slot) and card.owner_scope != CardData.Scope.NEUTRAL:
		return false
	run.decks[player_slot].append(String(card_id))
	checkpoint("card_reward")
	return true

func buy_card(player_slot: int, entry: Dictionary) -> bool:
	if not _valid_slot(player_slot) or not entry.has("card_id") or not entry.has("price"):
		return false
	var card_id := StringName(entry.card_id)
	var price := int(entry.price)
	if price < 0 or run.gold[player_slot] < price or not catalog.has(card_id):
		return false
	var card: CardData = catalog[card_id]
	if card.owner_scope != _scope_for_slot(player_slot) and card.owner_scope != CardData.Scope.NEUTRAL:
		return false
	run.gold[player_slot] -= price
	run.decks[player_slot].append(String(card_id))
	checkpoint("shop_purchase")
	return true

func buy_relic(player_slot: int, entry: Dictionary) -> bool:
	if not _valid_shop_entry(player_slot, entry):
		return false
	var relic_id := String(entry.id)
	if run.relics[player_slot].has(relic_id):
		return false
	run.gold[player_slot] -= int(entry.price)
	run.relics[player_slot].append(relic_id)
	checkpoint("relic_purchase")
	return true

func buy_consumable(player_slot: int, entry: Dictionary) -> bool:
	if not _valid_shop_entry(player_slot, entry) or run.consumables[player_slot].size() >= 3:
		return false
	run.gold[player_slot] -= int(entry.price)
	run.consumables[player_slot].append(String(entry.id))
	checkpoint("consumable_purchase")
	return true

func choose_route(player_slot: int, node_id: String) -> Dictionary:
	if not _valid_slot(player_slot):
		return {"ok": false, "error": "invalid_slot"}
	if run.phase != "traversal" or run.step < 0 or run.step >= MapGenerator.TRAVERSAL_STEPS:
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
	var node_summary := _apply_noncombat_effects(completed_types)
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
	var summary := _apply_noncombat_effects(completed_types)
	var result := complete_routes(completed_types)
	return {"ok": result.ok, "summary": summary}

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
	return CardData.Scope.GUARDIAN if player_slot == 0 else CardData.Scope.ENGINEER

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
			"event":
				for slot in 2:
					run.gold[slot] += 12
				summary.append("각 플레이어 +12 C")
			"shop": summary.append("상점 방문 가능")
	return summary
