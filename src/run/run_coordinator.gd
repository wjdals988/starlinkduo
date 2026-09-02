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

func advance_step() -> void:
	run.step += 1
	if run.step > MapGenerator.TRAVERSAL_STEPS:
		run.unlock_key(run.stage)
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
