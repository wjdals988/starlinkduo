extends Control

var accent := Color("#ff667d")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	var center := size * Vector2(0.5, 0.52)
	var scale_factor := minf(size.x, size.y) / 260.0
	for ring in range(4, 0, -1):
		var alpha := 0.025 + float(4 - ring) * 0.018
		draw_circle(center, (58.0 + ring * 18.0) * scale_factor, Color(accent, alpha))
	var points := PackedVector2Array()
	for index in 12:
		var angle := TAU * float(index) / 12.0 - PI / 2.0
		var radius := (78.0 if index % 2 == 0 else 58.0) * scale_factor
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, Color("#111a31e8"))
	var outline := PackedVector2Array(points)
	outline.append(points[0])
	draw_polyline(outline, accent, 3.0 * scale_factor, true)
	draw_circle(center, 34.0 * scale_factor, Color("#07101f"))
	draw_arc(center, 44.0 * scale_factor, 0.0, TAU, 48, Color("#ffd45f"), 3.0 * scale_factor, true)
	draw_line(center + Vector2(-20, 0) * scale_factor, center + Vector2(20, 0) * scale_factor, accent, 5.0 * scale_factor, true)
	draw_circle(center + Vector2(-30, -38) * scale_factor, 7.0 * scale_factor, accent)
	draw_circle(center + Vector2(30, -38) * scale_factor, 7.0 * scale_factor, accent)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
