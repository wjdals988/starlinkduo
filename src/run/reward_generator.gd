class_name RewardGenerator
extends RefCounted

const RARITY_WEIGHTS := {
	"combat": [70, 25, 5, 0],
	"elite": [25, 45, 27, 3],
	"boss": [0, 15, 70, 15],
}

var catalog: Dictionary
var run_content: Dictionary

func _init(card_catalog: Dictionary, content_catalog: Dictionary = {}) -> void:
	catalog = card_catalog
	run_content = content_catalog if not content_catalog.is_empty() else RunContentCatalog.build()

func card_reward(seed: int, character_scope: CardData.Scope, encounter_type: String) -> Array[StringName]:
	var rng := SeededRng.new(seed)
	var reward: Array[StringName] = []
	var desired_scopes := [character_scope, character_scope, CardData.Scope.NEUTRAL]
	for scope in desired_scopes:
		var rarity := _roll_rarity(rng, encounter_type)
		var candidates := _without(_cards_for(scope, rarity), reward)
		if candidates.is_empty():
			candidates = _without(_cards_for(scope, -1), reward)
		if candidates.is_empty():
			candidates = _without(_all_card_ids(), reward)
		var choice: StringName = rng.pick(candidates)
		reward.append(choice)
	return reward

func shop_inventory(seed: int, character_scope: CardData.Scope) -> Dictionary:
	var rng := SeededRng.new(seed)
	var cards: Array[Dictionary] = []
	var picked: Array[StringName] = []
	for index in 3:
		var card_id := _pick_any(rng, character_scope, picked)
		picked.append(card_id)
		cards.append(_shop_entry(card_id))
	for index in 2:
		var card_id := _pick_any(rng, CardData.Scope.NEUTRAL, picked)
		picked.append(card_id)
		cards.append(_shop_entry(card_id, 1.1))
	var relics: Array[Dictionary] = []
	var relic_indices := rng.shuffled(range(run_content.relics.size()))
	for index in 2:
		var relic: Dictionary = run_content.relics[relic_indices[index]]
		relics.append({"id": relic.id, "name": relic.name, "price": 125 + index * 20})
	var consumables: Array[Dictionary] = []
	var consumable_indices := rng.shuffled(range(run_content.consumables.size()))
	for index in 2:
		var consumable: Dictionary = run_content.consumables[consumable_indices[index]]
		consumables.append({"id": consumable.id, "name": consumable.name, "price": 45 + index * 10})
	return {
		"cards": cards,
		"relics": relics,
		"consumables": consumables,
		"remove_card_cost": 75,
	}

func _pick_any(rng: SeededRng, scope: CardData.Scope, excluded: Array[StringName] = []) -> StringName:
	var candidates := _without(_cards_for(scope, -1), excluded)
	if candidates.is_empty():
		candidates = _without(_all_card_ids(), excluded)
	return rng.pick(candidates)

func _all_card_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(catalog.keys())
	return result

func _without(candidates: Array[StringName], excluded: Array[StringName]) -> Array[StringName]:
	var result: Array[StringName] = []
	for card_id in candidates:
		if not excluded.has(card_id):
			result.append(card_id)
	return result

func _shop_entry(card_id: StringName, multiplier: float = 1.0) -> Dictionary:
	var card: CardData = catalog[card_id]
	var base_prices := [50, 75, 110, 180]
	return {"card_id": String(card_id), "price": roundi(base_prices[card.rarity] * multiplier)}

func _cards_for(scope: int, rarity: int) -> Array[StringName]:
	var result: Array[StringName] = []
	for card_id in catalog:
		var card: CardData = catalog[card_id]
		if card.owner_scope == scope and (rarity < 0 or card.rarity == rarity):
			result.append(card_id)
	result.sort()
	return result

func _roll_rarity(rng: SeededRng, encounter_type: String) -> int:
	var weights: Array = RARITY_WEIGHTS.get(encounter_type, RARITY_WEIGHTS.combat)
	var roll := rng.range_int(0, 100)
	var cumulative := 0
	for rarity in weights.size():
		cumulative += weights[rarity]
		if roll < cumulative:
			return rarity
	return CardData.Rarity.COMMON
