class_name CardIdentityVisual
extends Control

var card_id: StringName
var accent := Color("#43dfd0")
var signature := ""

func configure(id: StringName, accent_color: Color) -> void:
	card_id = id
	accent = accent_color
	signature = geometry_signature(id)
	queue_redraw()

static func geometry_signature(id: StringName) -> String:
	# Sixteen hexadecimal cells encode 64 bits into bar height and direction.
	# The exact card ID remains the gameplay identity; this is its stable visual mark.
	return String(id).sha256_text().left(16)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	if signature.length() != 16:
		return
	var panel_width := 39.0
	var panel_rect := Rect2(size.x - panel_width, 1.0, panel_width - 1.0, maxf(1.0, size.y - 2.0))
	draw_rect(panel_rect, Color("#07101fba"))
	draw_line(Vector2(panel_rect.position.x, 3.0), Vector2(panel_rect.position.x, size.y - 3.0), Color(accent, 0.72), 1.5, true)
	var baseline := size.y * 0.5
	for index in 16:
		var value := signature.substr(index, 1).hex_to_int()
		var height := 2.5 + float(value & 7) * 0.72
		var direction := -1.0 if (value & 8) != 0 else 1.0
		var x := panel_rect.position.x + 4.0 + float(index) * 2.0
		draw_line(Vector2(x, baseline), Vector2(x, baseline + direction * height), Color(accent, 0.66 + float(value & 3) * 0.08), 1.25, true)
	draw_circle(Vector2(size.x - 3.5, baseline), 2.0, Color("#f6f8ff"))

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
