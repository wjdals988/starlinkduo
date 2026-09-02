class_name RunContentCatalog
extends RefCounted

const RELIC_NAMES := [
	"공명 코어", "수리 나노봇", "중력 나침반", "전술 렌즈", "쌍성 배터리", "반사 장갑",
	"시간 결정", "재활용 로봇", "연결 증폭기", "선봉 휘장", "행운 회로", "비상 송신기",
	"양자 주사위", "항성 파편", "정찰 위성", "압축 창고", "무한 코일", "의료 드론",
	"고대 항법기", "붉은 엔진", "수호 인장", "유령 프로세서", "동기화 왕관", "초신성 심장",
]

const CONSUMABLE_NAMES := [
	"방벽 셀", "에너지 젤", "응급 수리 키트", "섬광 수류탄",
	"냉각 캡슐", "복제 칩", "탈출 비콘", "성간 촉매",
]

const EVENT_NAMES := [
	"표류하는 화물선", "정지된 구조 신호", "무중력 정원", "고장 난 상점", "해적의 통신",
	"미지의 알", "시간 균열", "버려진 연구소", "중력 폭풍", "잠든 인공지능",
	"연료 없는 순례자", "붉은 성운", "거울 함선", "고대 관문", "전장의 잔해",
	"두 개의 탈출정", "침묵하는 위성", "마지막 별빛",
]

const STAGE_THEMES := [
	{"id": "orbital_graveyard", "name": "궤도 폐선 지대", "enemy": "드론"},
	{"id": "crimson_nebula", "name": "붉은 성운", "enemy": "약탈자"},
	{"id": "singularity_gate", "name": "특이점 관문", "enemy": "감시자"},
]

static func build() -> Dictionary:
	return {
		"relics": _build_relics(),
		"consumables": _build_consumables(),
		"events": _build_events(),
		"stages": _build_stages(),
		"true_boss": {"id": "true_boss_star_eater", "name": "별을 삼키는 자", "health": 420, "intent_damage": 22},
	}

static func _build_relics() -> Array[Dictionary]:
	var relics: Array[Dictionary] = []
	var triggers := ["combat_start", "turn_start", "card_played", "support_played", "damage_taken", "combat_end"]
	for index in RELIC_NAMES.size():
		var trigger: String = triggers[index % triggers.size()]
		relics.append({
			"id": "relic_%02d" % (index + 1),
			"name": RELIC_NAMES[index],
			"trigger": trigger,
			"effect": "heal" if trigger == "combat_end" else ["block", "energy", "damage", "heal"][index % 4],
			"value": 1 + index / 8,
		})
	return relics

static func _build_consumables() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in CONSUMABLE_NAMES.size():
		result.append({
			"id": "consumable_%02d" % (index + 1),
			"name": CONSUMABLE_NAMES[index],
			"effect": ["block", "energy", "heal", "damage", "draw", "duplicate", "escape", "upgrade"][index],
			"value": [12, 2, 14, 16, 2, 1, 1, 1][index],
		})
	return result

static func _build_events() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for index in EVENT_NAMES.size():
		events.append({
			"id": "event_%02d" % (index + 1),
			"name": EVENT_NAMES[index],
			"body": "두 사람의 선택이 이번 런의 자원과 위험도를 바꿉니다.",
			"choices": [
				{"label": "함께 조사한다", "effect": "team_reward", "risk": 1 + index % 3},
				{"label": "안전을 우선한다", "effect": "safe_exit", "risk": 0},
			],
		})
	return events

static func _build_stages() -> Array[Dictionary]:
	var stages: Array[Dictionary] = []
	for stage_index in STAGE_THEMES.size():
		var theme: Dictionary = STAGE_THEMES[stage_index]
		var stage_number := stage_index + 1
		var normal: Array[Dictionary] = []
		for formation in 4:
			normal.append(_enemy("s%d_normal_%d" % [stage_number, formation + 1], "%s 편대 %d" % [theme.enemy, formation + 1], 34 + stage_index * 18 + formation * 5, 7 + stage_index * 3 + formation))
		var elites: Array[Dictionary] = []
		for elite_index in 2:
			elites.append(_enemy("s%d_elite_%d" % [stage_number, elite_index + 1], "%s 정예 %d" % [theme.enemy, elite_index + 1], 82 + stage_index * 28 + elite_index * 14, 13 + stage_index * 4 + elite_index * 2))
		stages.append({
			"id": theme.id,
			"name": theme.name,
			"normal_formations": normal,
			"elites": elites,
			"boss": _enemy("s%d_boss" % stage_number, "%s 지휘체" % theme.enemy, 150 + stage_index * 65, 17 + stage_index * 4),
		})
	return stages

static func _enemy(id: String, name: String, health: int, damage: int) -> Dictionary:
	return {"id": id, "name": name, "health": health, "intent_damage": damage}
