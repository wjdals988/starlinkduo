class_name CardFrameVisual
extends Control

var scope: CardData.Scope = CardData.Scope.NEUTRAL
var accent := Color("#8fa0bc")

func configure(next_scope: CardData.Scope, next_accent: Color) -> void:
	scope = next_scope
	accent = next_accent
	queue_redraw()

static func frame_signature(value: CardData.Scope) -> String:
	return ["double-shield", "circuit-bracket", "glitch-rail", "assault-slash", "orbit-arc", "medical-cross", "star-route"][value]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	var left := 5.0
	var right := size.x - 5.0
	var top := 5.0
	var bottom := size.y - 5.0
	match scope:
		CardData.Scope.GUARDIAN:
			_draw_guardian(left, right, top, bottom)
		CardData.Scope.ENGINEER:
			_draw_engineer(left, right, top, bottom)
		CardData.Scope.HACKER:
			_draw_hacker(left, right, top, bottom)
		CardData.Scope.ASSAULT:
			_draw_assault(left, right, top, bottom)
		CardData.Scope.MEDIC:
			_draw_medic(left, right, top, bottom)
		CardData.Scope.NAVIGATOR:
			_draw_navigator(left, right, top, bottom)
		_:
			_draw_neutral(left, right, top, bottom)

func _draw_guardian(left: float, right: float, top: float, bottom: float) -> void:
	draw_line(Vector2(left, top + 22), Vector2(left, bottom - 12), Color(accent, 0.92), 5.0, true)
	draw_line(Vector2(right, top + 22), Vector2(right, bottom - 12), Color(accent, 0.92), 5.0, true)
	draw_line(Vector2(left + 6, top + 28), Vector2(left + 6, bottom - 18), Color.WHITE, 1.5, true)
	draw_line(Vector2(right - 6, top + 28), Vector2(right - 6, bottom - 18), Color.WHITE, 1.5, true)
	draw_line(Vector2(left, top + 22), Vector2(left + 12, top + 10), Color(accent, 0.92), 4.0, true)
	draw_line(Vector2(right, top + 22), Vector2(right - 12, top + 10), Color(accent, 0.92), 4.0, true)

func _draw_engineer(left: float, right: float, top: float, bottom: float) -> void:
	for corner in [Vector2(left, top), Vector2(right, top), Vector2(left, bottom), Vector2(right, bottom)]:
		var horizontal := 1.0 if corner.x == left else -1.0
		var vertical := 1.0 if corner.y == top else -1.0
		draw_line(corner, corner + Vector2(horizontal * 26, 0), Color(accent, 0.95), 4.0, true)
		draw_line(corner, corner + Vector2(0, vertical * 18), Color(accent, 0.95), 4.0, true)
		draw_circle(corner + Vector2(horizontal * 28, vertical * 2), 3.5, Color.WHITE)

func _draw_hacker(left: float, right: float, top: float, bottom: float) -> void:
	var segments := 5
	var segment_width := (right - left - 24.0) / float(segments)
	for index in segments:
		var offset := float(index) * (segment_width + 6.0)
		var shift := 5.0 if index % 2 == 0 else 0.0
		draw_line(Vector2(left + offset + shift, top), Vector2(left + offset + segment_width + shift, top), Color(accent, 0.95), 3.0, true)
		draw_line(Vector2(right - offset - shift, bottom), Vector2(right - offset - segment_width - shift, bottom), Color(accent, 0.72), 3.0, true)
	draw_line(Vector2(left, top + 11), Vector2(left + 15, top + 11), Color.WHITE, 2.0, true)
	draw_line(Vector2(right, bottom - 11), Vector2(right - 15, bottom - 11), Color.WHITE, 2.0, true)

func _draw_assault(left: float, right: float, top: float, bottom: float) -> void:
	for offset in [0.0, 8.0, 16.0]:
		draw_line(Vector2(left + offset, bottom - 22), Vector2(left + 25 + offset, bottom), Color(accent, 0.95 - offset * 0.025), 4.0, true)
		draw_line(Vector2(right - offset, top + 22), Vector2(right - 25 - offset, top), Color(accent, 0.95 - offset * 0.025), 4.0, true)

func _draw_medic(left: float, right: float, top: float, bottom: float) -> void:
	var center := Vector2((left + right) * 0.5, top + 13)
	draw_line(center - Vector2(10, 0), center + Vector2(10, 0), Color(accent, 0.95), 4.0, true)
	draw_line(center - Vector2(0, 10), center + Vector2(0, 10), Color(accent, 0.95), 4.0, true)
	draw_arc(Vector2((left + right) * 0.5, bottom - 12), 18, PI, PI * 2.0, 16, Color(accent, 0.8), 3.0, true)

func _draw_navigator(left: float, right: float, top: float, bottom: float) -> void:
	var center := Vector2((left + right) * 0.5, top + 14)
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		draw_line(center + Vector2.from_angle(angle) * 6, center + Vector2.from_angle(angle) * 17, Color(accent, 0.9), 3.0, true)
	draw_circle(center, 4.0, Color.WHITE)
	draw_line(Vector2(left, bottom - 8), Vector2(right, bottom - 8), Color(accent, 0.72), 3.0, true)

func _draw_neutral(left: float, right: float, top: float, bottom: float) -> void:
	var radius := 19.0
	var top_left := Vector2(left + radius, top + radius)
	var bottom_right := Vector2(right - radius, bottom - radius)
	draw_arc(top_left, radius, PI, PI * 1.5, 16, Color(accent, 0.86), 3.0, true)
	draw_arc(bottom_right, radius, 0.0, PI * 0.5, 16, Color(accent, 0.86), 3.0, true)
	draw_circle(Vector2(left, top + radius), 3.5, Color.WHITE)
	draw_circle(Vector2(right, bottom - radius), 3.5, Color.WHITE)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
