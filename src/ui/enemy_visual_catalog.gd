class_name EnemyVisualCatalog
extends RefCounted

const TRAINING := {
	"tier": "training",
	"texture": "res://assets/art/rift-sentinel-enemy-v1.png",
	"description": "자홍색 코어와 네 개의 칼날을 지닌 훈련용 부유 전투체",
	"padding": Vector2(34, 22),
}
const STANDARD := {
	"tier": "standard",
	"texture": "res://assets/art/enemy-standard-scout-v1.png",
	"description": "청록색 코어와 세 갈래 날개를 지닌 일반 정찰 전투체",
	"padding": Vector2(26, 18),
}
const ELITE := {
	"tier": "elite",
	"texture": "res://assets/art/enemy-elite-sentinel-v1.png",
	"description": "주황색 삼중 코어와 넓은 육각 중장갑을 지닌 정예 전투체",
	"padding": Vector2(42, 12),
}
const BOSS := {
	"tier": "boss",
	"texture": "res://assets/art/enemy-stage-boss-v1.png",
	"description": "붉은 왕관형 뿔과 두 겹의 칼날 날개를 지닌 스테이지 지휘체",
	"padding": Vector2(42, 30),
}
const TRUE_BOSS := {
	"tier": "true_boss",
	"texture": "res://assets/art/enemy-true-boss-v1.png",
	"description": "백색 항성을 삼키는 비대칭 초승달 형상의 우주 포식체",
	"padding": Vector2(52, 18),
}

const STAGE_IDENTITIES := {
	0: {"name": "훈련 격자", "accent": Color("#ff5d91"), "motif": "training"},
	1: {"name": "폐선 궤도", "accent": Color("#43dfd0"), "motif": "wreckage"},
	2: {"name": "성운 초승달", "accent": Color("#ff647c"), "motif": "nebula"},
	3: {"name": "특이점 격자", "accent": Color("#bc8cff"), "motif": "singularity"},
	4: {"name": "항성 포식 고리", "accent": Color("#f6f8ff"), "motif": "star_eater"},
}

static func profile(enemy_id: StringName, route_types: Array[String]) -> Dictionary:
	if enemy_id == &"true_boss_star_eater" or route_types.has("true_boss"):
		return TRUE_BOSS
	if route_types.has("boss") or String(enemy_id).contains("_boss"):
		return BOSS
	if route_types.has("elite") or route_types.has("key_challenge") or String(enemy_id).contains("_elite_"):
		return ELITE
	if enemy_id == &"training_drone":
		return TRAINING
	return STANDARD

static func identity_profile(enemy_id: StringName, route_types: Array[String]) -> Dictionary:
	var result := profile(enemy_id, route_types).duplicate(true)
	var stage := stage_index(enemy_id)
	var identity: Dictionary = STAGE_IDENTITIES[stage]
	var variant := formation_index(enemy_id)
	result["enemy_id"] = enemy_id
	result["stage"] = stage
	result["variant"] = variant
	result["accent"] = identity.accent
	result["motif"] = identity.motif
	result["identity_name"] = "%s %s" % [identity.name, _variant_name(result.tier, variant)]
	result["description"] = "%s, %s 식별 문양" % [result.description, result.identity_name]
	result["signature"] = "%s:%s:%d" % [result.tier, result.motif, variant]
	return result

static func stage_index(enemy_id: StringName) -> int:
	var id := String(enemy_id)
	if enemy_id == &"training_drone":
		return 0
	if enemy_id == &"true_boss_star_eater":
		return 4
	if id.begins_with("s1_"):
		return 1
	if id.begins_with("s2_"):
		return 2
	if id.begins_with("s3_"):
		return 3
	return 0

static func formation_index(enemy_id: StringName) -> int:
	var tail := String(enemy_id).get_slice("_", String(enemy_id).get_slice_count("_") - 1)
	return int(tail) if tail.is_valid_int() else 1

static func _variant_name(tier: String, variant: int) -> String:
	if tier == "boss":
		return "지휘관"
	if tier == "true_boss":
		return "본체"
	if tier == "training":
		return "기준형"
	return "%d번 편대" % variant
