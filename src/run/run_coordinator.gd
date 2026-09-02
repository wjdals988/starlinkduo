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
	run.decks[0] = ["guardian_strike", "guardian_guard", "guardian_cover", "neutral_pulse"]
	run.decks[1] = ["engineer_bolt", "engineer_charge", "engineer_patch", "neutral_barrier"]
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

func choose_route(player_slot: int, node_id: String) -> Dictionary:
	if not _valid_slot(player_slot):
		return {"ok": false, "error": "invalid_slot"}
	if run.step < 0 or run.step >= MapGenerator.TRAVERSAL_STEPS:
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
		run.stage = mini(run.stage + 1, 3)
		run.step = 0
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
