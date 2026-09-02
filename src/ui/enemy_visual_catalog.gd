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
