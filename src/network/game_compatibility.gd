class_name GameCompatibility
extends RefCounted

const RULESET_VERSION := 2

static var _cached_fingerprint := ""

static func fingerprint() -> String:
	if not _cached_fingerprint.is_empty():
		return _cached_fingerprint
	var card_snapshots: Array[Dictionary] = []
	var cards := FullCardCatalog.build()
	var card_ids := cards.keys()
	card_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for card_id in card_ids:
		card_snapshots.append((cards[card_id] as CardData).to_snapshot())
	_cached_fingerprint = StateHasher.hash_snapshot({
		"ruleset": RULESET_VERSION,
		"cards": card_snapshots,
		"run_content": RunContentCatalog.build(),
	})
	return _cached_fingerprint

static func code() -> String:
	return fingerprint().left(12).to_upper()
