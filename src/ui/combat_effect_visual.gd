class_name CombatEffectVisual
extends Control

var effect_type := "damage"
var source_slot := 0
var progress := 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()

func configure(type: String, slot: int) -> void:
	effect_type = type
	source_slot = slot
	queue_redraw()

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

func _draw_damage() -> void:
	var start := _player_center(source_slot)
	var finish := _enemy_center()
	var eased := 1.0 - pow(1.0 - progress, 3.0)
	var head := start.lerp(finish, eased)
	var direction := (finish - start).normalized()
	for trail_index in 6:
		var distance := float(trail_index) * 22.0
		var alpha := maxf(0.0, 0.72 - float(trail_index) * 0.11)
		draw_circle(head - direction * distance, maxf(3.0, 11.0 - trail_index), Color(1.0, 0.26, 0.43, alpha))
	draw_circle(head, 15.0, Color("#fff0f3"))
	draw_arc(head, 23.0, 0.0, TAU, 28, Color("#ff4565"), 4.0, true)
	if progress > 0.72:
		var burst := (progress - 0.72) / 0.28
		for ray_index in 8:
			var angle := TAU * float(ray_index) / 8.0
			var ray := Vector2(cos(angle), sin(angle))
			draw_line(finish + ray * 18.0, finish + ray * (34.0 + 34.0 * burst), Color(1.0, 0.3, 0.45, 1.0 - burst), 4.0, true)

func _draw_block() -> void:
	var center := _player_center(source_slot) + Vector2(0, 16)
	var pulse := sin(progress * PI)
	var radius := 52.0 + pulse * 18.0
	var points := PackedVector2Array([
		center + Vector2(0, -radius),
		center + Vector2(radius * 0.72, -radius * 0.48),
		center + Vector2(radius * 0.58, radius * 0.44),
		center + Vector2(0, radius),
		center + Vector2(-radius * 0.58, radius * 0.44),
		center + Vector2(-radius * 0.72, -radius * 0.48),
	])
	draw_colored_polygon(points, Color(0.2, 0.62, 1.0, 0.12 + pulse * 0.22))
	var outline := PackedVector2Array(points)
	outline.append(points[0])
	draw_polyline(outline, Color(0.38, 0.72, 1.0, 0.45 + pulse * 0.55), 6.0, true)
	draw_line(center + Vector2(-22, 0), center + Vector2(22, 0), Color("#dff4ff"), 5.0, true)

func _draw_heal() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.49)
	for ring_index in 3:
		var ring_progress := fposmod(progress + float(ring_index) * 0.22, 1.0)
		var radius := 40.0 + ring_progress * 150.0
		draw_arc(center, radius, 0.0, TAU, 64, Color(0.26, 0.88, 0.66, 1.0 - ring_progress), 5.0, true)
	var alpha := sin(progress * PI)
	draw_line(center + Vector2(-28, 0), center + Vector2(28, 0), Color(0.72, 1.0, 0.88, alpha), 10.0, true)
	draw_line(center + Vector2(0, -28), center + Vector2(0, 28), Color(0.72, 1.0, 0.88, alpha), 10.0, true)

func _draw_energy() -> void:
	var start := _player_center(source_slot)
	var finish := _player_center(1 - source_slot)
	var end := start.lerp(finish, progress)
	var points := PackedVector2Array()
	var segments := 18
	for index in segments + 1:
		var ratio := float(index) / float(segments)
		var point := start.lerp(end, ratio)
		point.y += sin(ratio * TAU * 5.0 + progress * TAU) * 9.0
		points.append(point)
	if points.size() > 1:
		draw_polyline(points, Color("#ffe45c"), 6.0, true)
		draw_polyline(points, Color("#fff8c2"), 2.0, true)
	draw_circle(end, 12.0, Color("#fff3a0"))
