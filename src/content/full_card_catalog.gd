class_name FullCardCatalog
extends RefCounted

const TARGET_CHARACTER_CARDS := 24
const TARGET_NEUTRAL_CARDS := 48

const CARD_NAMES := {
	CardData.Scope.GUARDIAN: [
		"중력 방패", "철벽 진형", "궤도 요격", "방호 전개", "충격 흡수", "수호 맹세",
		"반격 태세", "위기 봉쇄", "성간 갑주", "위협 유도", "불굴의 전선", "방벽 공명",
		"긴급 엄폐", "수호의 파동", "피해 전환", "선봉 돌진", "요새화", "동료 구출",
		"절대 방어", "항성 보루", "최후의 수호", "중력 역장", "방패 폭발", "불멸 프로토콜",
	],
	CardData.Scope.ENGINEER: [
		"과전류", "자동 수리", "터렛 전개", "전력 우회", "회로 증폭", "드론 호출",
		"냉각 순환", "응급 용접", "자기장 코일", "탄도 계산", "예비 축전지", "정밀 조율",
		"방전 덫", "재생 나노봇", "장치 복제", "출력 한계", "원격 정비", "플라즈마 망",
		"양자 배선", "연쇄 방전", "완전 자동화", "무한 동력", "특이점 포탑", "마스터 키",
	],
	CardData.Scope.HACKER: [
		"취약점 탐색", "신호 탈취", "루트 권한", "패킷 폭주", "방화벽 우회", "악성 주입",
		"지연 명령", "기억 소거", "백도어", "제로데이", "추적 차단", "가상 분신",
		"암호 해제", "의도 변조", "데이터 흡수", "오버클럭", "신경 교란", "연쇄 침투",
		"시스템 장악", "검은 파동", "관리자 모드", "시간 정지", "완전 침묵", "고스트 인 더 머신",
	],
	CardData.Scope.ASSAULT: [
		"집중 사격", "돌파 탄환", "연속 베기", "화력 집중", "추진 강타", "약점 포착",
		"탄창 교체", "충격 수류탄", "추격 사격", "과열 포격", "근접 돌파", "전투 감각",
		"쌍열 포화", "선제 타격", "방어 분쇄", "광폭 질주", "필살 조준", "유성 난사",
		"초신성 탄환", "처형 명령", "무차별 포화", "붉은 궤적", "한계 돌파", "종말의 일격",
	],
	CardData.Scope.NEUTRAL: [
		"응급 키트", "보조 배터리", "우주 식량", "신호 증폭기", "합금 장갑", "정찰 비콘",
		"전술 재배치", "비상 점프", "예비 방벽", "협동 신호", "집중 호흡", "공용 포탑",
		"수리 폼", "중력 갈고리", "섬광탄", "에너지 공유", "항법 보정", "행운의 부품",
		"구조 신호", "궤도 지도", "전투 자극제", "반사 코팅", "자동 주사기", "동기화 장치",
		"양자 주사위", "공명 수정", "시간 가속기", "복제 모듈", "예측 계산기", "불안정 코어",
		"초공간 주머니", "생존 매뉴얼", "함선 잔해", "별빛 나침반", "중력 렌즈", "재활용 장치",
		"이중 회로", "지원 요청", "완벽한 합", "공동 전선", "운명 공유", "연결 강화",
		"무중력 기동", "성운 은폐", "혜성 파편", "항성 에너지", "은하 공명", "최후의 연결",
	],
}

static func build() -> Dictionary:
	var cards := DemoCardCatalog.build()
	for scope in [CardData.Scope.GUARDIAN, CardData.Scope.ENGINEER, CardData.Scope.HACKER, CardData.Scope.ASSAULT]:
		_fill_scope(cards, scope, TARGET_CHARACTER_CARDS)
	_fill_scope(cards, CardData.Scope.NEUTRAL, TARGET_NEUTRAL_CARDS)
	return cards

static func _fill_scope(cards: Dictionary, scope: CardData.Scope, target_count: int) -> void:
	var existing := _count_scope(cards, scope)
	var names: Array = CARD_NAMES[scope]
	for index in range(existing, target_count):
		var prefix := _scope_prefix(scope)
		var id := StringName("%s_card_%02d" % [prefix, index + 1])
		var card := CardData.new()
		card.id = id
		card.display_name = String(names[index])
		card.owner_scope = scope
		card.rarity = _rarity_for_index(index)
		card.energy_cost = _cost_for_index(index)
		card.speed = 20 + ((index * 17 + scope * 7) % 61)
		_apply_archetype(card, index)
		cards[id] = card

static func _apply_archetype(card: CardData, index: int) -> void:
	var power := 4 + index / 4 + card.rarity * 2
	match index % 6:
		0:
			card.target = CardData.Target.ENEMY
			card.effects = [{"type": "damage", "amount": power + 2}]
			card.tags = PackedStringArray(["공격"])
		1:
			card.target = CardData.Target.SELF
			card.effects = [{"type": "block", "amount": power + 1}]
			card.tags = PackedStringArray(["방어"])
		2:
			card.target = CardData.Target.ALLY
			card.effects = [{"type": "block", "amount": power}]
			card.tags = PackedStringArray(["지원"])
		3:
			card.target = CardData.Target.TEAM
			card.effects = [{"type": "heal", "amount": maxi(2, power / 2)}]
			card.tags = PackedStringArray(["회복", "지원"])
		4:
			card.target = CardData.Target.ALLY
			card.effects = [{"type": "energy", "amount": 1}]
			card.tags = PackedStringArray(["에너지", "지원"])
		_:
			card.target = CardData.Target.ENEMY
			card.effects = [{"type": "damage", "amount": power}, {"type": "block", "amount": maxi(2, power / 2)}]
			card.tags = PackedStringArray(["복합"])
	if card.owner_scope == CardData.Scope.NEUTRAL:
		card.tags.append("공용")

static func _rarity_for_index(index: int) -> CardData.Rarity:
	var tier_index := index % 24
	if tier_index >= 22:
		return CardData.Rarity.LEGENDARY
	if tier_index >= 17:
		return CardData.Rarity.RARE
	if tier_index >= 9:
		return CardData.Rarity.MAGIC
	return CardData.Rarity.COMMON

static func _cost_for_index(index: int) -> int:
	return [1, 1, 1, 1, 0, 2][index % 6]

static func _count_scope(cards: Dictionary, scope: CardData.Scope) -> int:
	var count := 0
	for card in cards.values():
		if card.owner_scope == scope:
			count += 1
	return count

static func _scope_prefix(scope: CardData.Scope) -> String:
	return ["guardian", "engineer", "hacker", "assault", "neutral"][scope]
