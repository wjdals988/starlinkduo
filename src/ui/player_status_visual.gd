class_name PlayerStatusVisual
extends Control

var accent := Color("#62a8ff")
var status := "waiting"

func configure(next_accent: Color) -> void:
	accent = next_accent
	queue_redraw()

func set_status(next_status: String) -> void:
	status = next_status
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.54)
	var radius := minf(size.x * 0.30, size.y * 0.47)
	draw_circle(center, radius + 18.0, Color(accent, 0.045))
	draw_circle(center, radius + 8.0, Color(accent, 0.055))
	var completion: float = float({"waiting": 0.34, "local": 0.68, "planning": 0.82, "ready": 1.0}.get(status, 0.34))
	var ring_color: Color = Color("#7d8ba8") if status == "waiting" else accent
	draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * completion, 64, Color(ring_color, 0.95), 4.0, true)
	draw_arc(center, radius + 7.0, PI * 0.5, PI * 0.5 + TAU * completion, 64, Color(ring_color, 0.38), 2.0, true)
	var dot_count: int = 3 if status == "ready" else (2 if status == "planning" else 1)
	for index in dot_count:
		var angle: float = -PI * 0.5 + TAU * completion * (float(index + 1) / float(dot_count + 1))
		var dot: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
		draw_circle(dot, 5.0, Color.WHITE if status == "ready" else ring_color)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
