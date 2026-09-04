class_name DrawPileVisual
extends Button

var card_count := 0
var player_slot := 0
var accent := Color("#43dfd0")

func configure(slot: int, count: int, color: Color) -> void:
	player_slot = slot
	card_count = count
	accent = color
	text = ""
	tooltip_text = "P%d 드로우 덱 · %d장 남음" % [slot + 1, count]
	accessibility_name = "P%d 드로우 덱" % [slot + 1]
	accessibility_description = "%d장 남음. 두 번 탭하여 현재 덱을 봅니다" % count
	queue_redraw()

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	queue_redraw()

func _draw() -> void:
	var card_size := Vector2(64, 90)
	var origin := Vector2((size.x - card_size.x) * 0.5, 12)
	for layer in range(3, -1, -1):
		var offset := Vector2(layer * 3.0, -layer * 2.0)
		var rect := Rect2(origin + offset, card_size)
		draw_style_box(_card_style(Color(accent, 0.13 + layer * 0.035)), rect)
	var center := origin + card_size * 0.5 + Vector2(4, -2)
	draw_circle(center, 25, Color("#07101fe8"))
	draw_arc(center, 25, 0, TAU, 32, Color(accent, 0.9), 2.5, true)
	draw_string(ThemeDB.fallback_font, center + Vector2(-14 if card_count >= 10 else -7, 9), str(card_count), HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(15, size.y - 8), "남은 카드", HORIZONTAL_ALIGNMENT_CENTER, size.x - 30, 13, Color(accent, 0.95))

func _card_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(accent, 0.64)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	return style

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
