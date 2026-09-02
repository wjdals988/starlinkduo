class_name CardArtCatalog
extends RefCounted

const EFFECT_KINDS := ["damage", "block", "heal", "energy"]

const ART := {
	CardData.Scope.GUARDIAN: {
		"damage": preload("res://assets/art/card-guardian-damage-v1.png"),
		"block": preload("res://assets/art/card-guardian-block-v1.png"),
		"heal": preload("res://assets/art/card-guardian-heal-v1.png"),
		"energy": preload("res://assets/art/card-guardian-energy-v1.png"),
	},
	CardData.Scope.ENGINEER: {
		"damage": preload("res://assets/art/card-engineer-damage-v1.png"),
		"block": preload("res://assets/art/card-engineer-block-v1.png"),
		"heal": preload("res://assets/art/card-engineer-heal-v1.png"),
		"energy": preload("res://assets/art/card-engineer-energy-v1.png"),
	},
	CardData.Scope.HACKER: {
		"damage": preload("res://assets/art/card-hacker-damage-v1.png"),
		"block": preload("res://assets/art/card-hacker-block-v1.png"),
		"heal": preload("res://assets/art/card-hacker-heal-v1.png"),
		"energy": preload("res://assets/art/card-hacker-energy-v1.png"),
	},
	CardData.Scope.ASSAULT: {
		"damage": preload("res://assets/art/card-assault-damage-v1.png"),
		"block": preload("res://assets/art/card-assault-block-v1.png"),
		"heal": preload("res://assets/art/card-assault-heal-v1.png"),
		"energy": preload("res://assets/art/card-assault-energy-v1.png"),
	},
	CardData.Scope.NEUTRAL: {
		"damage": preload("res://assets/art/card-effect-damage-v1.png"),
		"block": preload("res://assets/art/card-effect-block-v1.png"),
		"heal": preload("res://assets/art/card-effect-heal-v1.png"),
		"energy": preload("res://assets/art/card-effect-energy-v1.png"),
	},
}

static func texture_for(scope: CardData.Scope, effect_kind: String) -> Texture2D:
	var scope_art: Dictionary = ART.get(scope, ART[CardData.Scope.NEUTRAL])
	return scope_art.get(effect_kind, scope_art["energy"])

static func profile_key(scope: CardData.Scope, effect_kind: String) -> String:
	return "%d:%s" % [scope, effect_kind]

static func profile_count() -> int:
	return ART.size() * EFFECT_KINDS.size()
