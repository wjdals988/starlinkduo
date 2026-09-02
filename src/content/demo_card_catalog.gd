class_name DemoCardCatalog
extends RefCounted

static func build() -> Dictionary:
	var cards: Dictionary = {}
	_add(cards, &"guardian_strike", "궤도 타격", 1, 55, CardData.Scope.GUARDIAN, CardData.Target.ENEMY, [{"type": "damage", "amount": 7}], ["공격"])
	_add(cards, &"guardian_guard", "전개 방벽", 1, 35, CardData.Scope.GUARDIAN, CardData.Target.SELF, [{"type": "block", "amount": 7}], ["방어"])
	_add(cards, &"guardian_cover", "엄호 프로토콜", 1, 25, CardData.Scope.GUARDIAN, CardData.Target.ALLY, [{"type": "block", "amount": 6}], ["방어", "지원"])
	_add(cards, &"engineer_bolt", "플라즈마 볼트", 1, 50, CardData.Scope.ENGINEER, CardData.Target.ENEMY, [{"type": "damage", "amount": 6}], ["공격"])
	_add(cards, &"engineer_charge", "비상 충전", 0, 15, CardData.Scope.ENGINEER, CardData.Target.SELF, [{"type": "energy", "amount": 1}], ["기술"])
	_add(cards, &"engineer_patch", "나노 패치", 1, 20, CardData.Scope.ENGINEER, CardData.Target.TEAM, [{"type": "heal", "amount": 4}], ["회복", "지원"])
	_add(cards, &"neutral_pulse", "공명 펄스", 1, 45, CardData.Scope.NEUTRAL, CardData.Target.ENEMY, [{"type": "damage", "amount": 5}], ["공용", "공격"])
	_add(cards, &"neutral_barrier", "휴대 방벽", 1, 30, CardData.Scope.NEUTRAL, CardData.Target.SELF, [{"type": "block", "amount": 5}], ["공용", "방어"])
	_add(cards, &"neutral_link", "동기화 링크", 1, 10, CardData.Scope.NEUTRAL, CardData.Target.ALLY, [{"type": "energy", "amount": 1}, {"type": "block", "amount": 3}], ["공용", "지원"])
	return cards

static func _add(
	cards: Dictionary,
	id: StringName,
	display_name: String,
	cost: int,
	speed: int,
	scope: CardData.Scope,
	target: CardData.Target,
	effects: Array[Dictionary],
	tags: Array[String]
) -> void:
	var card := CardData.new()
	card.id = id
	card.display_name = display_name
	card.energy_cost = cost
	card.speed = speed
	card.owner_scope = scope
	card.target = target
	card.effects = effects
	card.tags = PackedStringArray(tags)
	cards[id] = card

