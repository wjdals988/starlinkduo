class_name CombatEffectVisual
extends Control

var effect_type := "damage"
var source_slot := 0
var character_id: StringName = &"guardian"
var static_mode := false
var progress := 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()

const CHARACTER_PROFILES := {
	&"guardian": {"name": "수호자", "color": Color("#5fa8ff"), "damage": "결정 창", "block": "육각 방벽", "heal": "수호 십자", "energy": "방벽 셀"},
	&"engineer": {"name": "기술자", "color": Color("#ff9b45"), "damage": "리벳 드론", "block": "기계 브래킷", "heal": "수리 노드", "energy": "회전 코일"},
	&"hacker": {"name": "해커", "color": Color("#bc8cff"), "damage": "데이터 칼날", "block": "암호 격자", "heal": "복구 패킷", "energy": "오버클럭 파형"},
	&"assault": {"name": "강습병", "color": Color("#ff647c"), "damage": "쌍열 레일", "block": "반응 장갑", "heal": "전투 주입기", "energy": "탄창 펄스"},
	&"medic": {"name": "의무관", "color": Color("#55d99a"), "damage": "살균 펄스", "block": "생체 장막", "heal": "재생 파동", "energy": "활력 주입"},
	&"navigator": {"name": "항법사", "color": Color("#42d7d7"), "damage": "혜성 궤적", "block": "공간 편향", "heal": "귀환 좌표", "energy": "중력 가속"},
}

func configure(type: String, slot: int, reduced_motion: bool = false, source_character: StringName = &"guardian") -> void:
	effect_type = type
	source_slot = slot
	character_id = source_character if CHARACTER_PROFILES.has(source_character) else &"guardian"
	static_mode = reduced_motion
	if static_mode:
		progress = 0.82
	queue_redraw()

func effect_description() -> String:
	var profile: Dictionary = CHARACTER_PROFILES[character_id]
	return "%s의 %s" % [profile.name, profile.get(effect_type, "전투 효과")]

static func profile_signature(source_character: StringName, type: String) -> String:
	var character: StringName = source_character if CHARACTER_PROFILES.has(source_character) else &"guardian"
	return "%s:%s:%s" % [character, type, CHARACTER_PROFILES[character].get(type, "unknown")]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	match effect_type:
		"damage": _draw_damage()
		"block": _draw_block()
		"heal": _draw_heal()
		"energy": _draw_energy()

func _player_center(slot: int) -> Vector2:
	return Vector2(size.x * (0.27 if slot == 0 else 0.73), size.y * 0.43)

func _enemy_center() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.39)

func _profile_color(alpha: float = 1.0) -> Color:
	return Color(CHARACTER_PROFILES[character_id].color, alpha)

func _draw_damage() -> void:
	var start := _player_center(source_slot)
	var finish := _enemy_center()
	# Keep the projectile above the centered action panel so the character motif
	# remains visible in both animated and reduced-motion presentations.
	var eased := progress
	var head := start.lerp(finish, eased)
	head.y -= sin(eased * PI) * 115.0
	var direction := (finish - start).normalized()
	var normal := Vector2(-direction.y, direction.x)
	var charge := sin(minf(1.0, progress * 1.35) * PI)
	for glow_index in 3:
		draw_circle(head, 22.0 + glow_index * 13.0 + charge * 8.0, _profile_color(0.12 - glow_index * 0.025))
	var trail_count := 8 if character_id == &"hacker" else 6
	for trail_index in trail_count:
		var distance := float(trail_index) * 22.0
		var alpha := maxf(0.0, 0.72 - float(trail_index) * 0.11)
		var trail_point := head - direction * distance
		if character_id == &"hacker":
			trail_point.y += 10.0 if trail_index % 2 == 0 else -10.0
			draw_rect(Rect2(trail_point - Vector2(7, 4), Vector2(14, 8)), _profile_color(alpha))
		elif character_id == &"assault":
			draw_line(trail_point + Vector2(0, -7), trail_point + direction * 18.0 + Vector2(0, -7), _profile_color(alpha), 5.0, true)
			draw_line(trail_point + Vector2(0, 7), trail_point + direction * 18.0 + Vector2(0, 7), _profile_color(alpha), 5.0, true)
		else:
			draw_circle(trail_point, maxf(3.0, 11.0 - trail_index), _profile_color(alpha))
	if character_id == &"engineer":
		draw_rect(Rect2(head - Vector2(14, 10), Vector2(28, 20)), Color("#fff4df"))
		for offset in [Vector2(-19, -14), Vector2(19, -14), Vector2(-19, 14), Vector2(19, 14)]:
			draw_circle(head + offset, 5.0, _profile_color())
	elif character_id == &"guardian":
		var lance := PackedVector2Array([
			head + normal * 16.0,
			head + direction * 9.0,
			head - normal * 16.0,
			head - direction * 9.0,
		])
		draw_colored_polygon(lance, _profile_color())
		draw_line(head - normal * 10.0, head + normal * 10.0, Color("#e9f7ff"), 3.0, true)
	else:
		draw_circle(head, 15.0, Color("#fff0f3"))
	if character_id != &"guardian":
		draw_arc(head, 23.0, 0.0, TAU, 28, _profile_color(), 4.0, true)
	if progress > 0.72:
		var burst := (progress - 0.72) / 0.28
		for ring_index in 3:
			var ring_radius := 24.0 + burst * (42.0 + ring_index * 24.0)
			draw_arc(finish, ring_radius, 0.0, TAU, 40, _profile_color((1.0 - burst) * (0.72 - ring_index * 0.16)), 6.0 - ring_index, true)
		for ray_index in 12:
			var angle := TAU * float(ray_index) / 12.0
			var ray := Vector2(cos(angle), sin(angle))
			var burst_alpha := 0.82 if static_mode else 1.0 - burst
			draw_line(finish + ray * 18.0, finish + ray * (40.0 + 58.0 * burst), _profile_color(burst_alpha), 5.0, true)
		for particle_index in 9:
			var particle_angle := TAU * float(particle_index) / 9.0 + 0.24
			var particle_direction := Vector2(cos(particle_angle), sin(particle_angle))
			draw_circle(finish + particle_direction * (34.0 + burst * (58.0 + particle_index * 3.0)), maxf(2.0, 6.0 - burst * 3.0), Color(1.0, 0.94, 0.78, 1.0 - burst))

func _draw_block() -> void:
	var center := _player_center(source_slot) + Vector2(0, 16)
	var pulse := sin(progress * PI)
	var radius := 52.0 + pulse * 18.0
	var sides := 6
	var rotation := -PI / 2.0
	if character_id == &"engineer":
		sides = 4
		rotation = PI / 4.0
	elif character_id == &"hacker":
		sides = 8
	elif character_id == &"assault":
		sides = 3
	var points := PackedVector2Array()
	for index in sides:
		var angle := rotation + TAU * float(index) / float(sides)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, _profile_color(0.12 + pulse * 0.22))
	var outline := PackedVector2Array(points)
	outline.append(points[0])
	draw_polyline(outline, _profile_color(0.45 + pulse * 0.55), 6.0, true)
	for ring_index in 2:
		draw_arc(center, radius + 15.0 + ring_index * 13.0, -PI * 0.82, PI * 0.82, 28, _profile_color((0.52 - ring_index * 0.16) * pulse), 3.0, true)
	draw_line(center + Vector2(-22, 0), center + Vector2(22, 0), Color("#dff4ff"), 5.0, true)
	if character_id == &"engineer":
		draw_line(center + Vector2(0, -22), center + Vector2(0, 22), Color("#fff4df"), 5.0, true)
	elif character_id == &"hacker":
		for offset in [-28.0, 28.0]:
			draw_rect(Rect2(center + Vector2(offset - 5, -5), Vector2(10, 10)), _profile_color())
	elif character_id == &"assault":
		draw_polyline(PackedVector2Array([center + Vector2(-28, 16), center, center + Vector2(28, 16)]), Color("#fff0f3"), 5.0, true)

func _draw_heal() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.49)
	for ring_index in 3:
		var ring_progress := fposmod(progress + float(ring_index) * 0.22, 1.0)
		var radius := 40.0 + ring_progress * 150.0
		draw_arc(center, radius, 0.0, TAU, 64, _profile_color(1.0 - ring_progress), 5.0, true)
	var alpha := sin(progress * PI)
	for spark_index in 10:
		var spark_angle := TAU * float(spark_index) / 10.0 + progress * 1.8
		var spark_radius := 34.0 + float(spark_index % 3) * 18.0 + progress * 35.0
		var spark := center + Vector2(cos(spark_angle), sin(spark_angle)) * spark_radius
		draw_circle(spark, 4.0 + float(spark_index % 2) * 2.0, Color(0.86, 1.0, 0.94, alpha * 0.85))
	if character_id == &"engineer":
		for index in 6:
			var angle := TAU * float(index) / 6.0
			draw_circle(center + Vector2(cos(angle), sin(angle)) * 34.0, 8.0, _profile_color(alpha))
		draw_arc(center, 19.0, 0.0, TAU, 24, Color("#fff4df"), 7.0, true)
	elif character_id == &"hacker":
		for offset in [Vector2(-32, -22), Vector2(24, -22), Vector2(-32, 20), Vector2(24, 20)]:
			draw_rect(Rect2(center + offset, Vector2(10, 10)), _profile_color(alpha))
		draw_line(center + Vector2(-27, 0), center + Vector2(27, 0), _profile_color(alpha), 5.0, true)
	elif character_id == &"assault":
		draw_line(center + Vector2(-34, 18), center + Vector2(26, -18), Color("#fff0f3"), 12.0, true)
		draw_circle(center + Vector2(30, -20), 10.0, _profile_color(alpha))
	else:
		draw_line(center + Vector2(-28, 0), center + Vector2(28, 0), Color(0.72, 0.92, 1.0, alpha), 10.0, true)
		draw_line(center + Vector2(0, -28), center + Vector2(0, 28), Color(0.72, 0.92, 1.0, alpha), 10.0, true)

func _draw_energy() -> void:
	var start := _player_center(source_slot)
	var finish := _player_center(1 - source_slot)
	var end := start.lerp(finish, progress)
	var points := PackedVector2Array()
	var segments := 18
	for index in segments + 1:
		var ratio := float(index) / float(segments)
		var point := start.lerp(end, ratio)
		if character_id == &"hacker":
			point.y += (8.0 if index % 2 == 0 else -8.0)
		elif character_id == &"assault":
			point.y += sin(ratio * TAU * 3.0 + progress * TAU) * 4.0
		else:
			point.y += sin(ratio * TAU * 5.0 + progress * TAU) * 9.0
		points.append(point)
	if points.size() > 1:
		draw_polyline(points, _profile_color(0.18), 16.0, true)
		draw_polyline(points, _profile_color(), 6.0, true)
		draw_polyline(points, Color("#fff8c2"), 2.0, true)
	for pulse_index in 4:
		var pulse_ratio := fposmod(progress * 1.8 - float(pulse_index) * 0.18, 1.0)
		var pulse_point := start.lerp(end, pulse_ratio)
		draw_circle(pulse_point, 7.0, Color("#fff8c2"))
		draw_arc(pulse_point, 13.0, 0.0, TAU, 18, _profile_color(0.72), 3.0, true)
	if character_id == &"engineer":
		draw_arc(end, 18.0, progress * TAU, progress * TAU + PI * 1.5, 18, _profile_color(), 6.0, true)
	elif character_id == &"assault":
		draw_rect(Rect2(end - Vector2(15, 9), Vector2(30, 18)), _profile_color())
	elif character_id == &"hacker":
		draw_rect(Rect2(end - Vector2(11, 11), Vector2(22, 22)), _profile_color())
	else:
		draw_circle(end, 12.0, _profile_color())
