extends Control

var accent := Color("#ff667d")
var enemy_id: StringName = &"training_drone"
var tier := "training"
var motif := "training"
var variant := 1

func configure(profile: Dictionary) -> void:
	enemy_id = StringName(profile.get("enemy_id", &"training_drone"))
	tier = String(profile.get("tier", "training"))
	motif = String(profile.get("motif", "training"))
	variant = int(profile.get("variant", 1))
	accent = Color(profile.get("accent", Color("#ff667d")))
	queue_redraw()

static func geometry_signature(profile: Dictionary) -> String:
	return "%s:%s:%d" % [profile.get("tier", "training"), profile.get("motif", "training"), int(profile.get("variant", 1))]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	var left := size.x * 0.13
	var right := size.x * 0.87
	var top := 8.0
	var bottom := size.y - 8.0
	var corner := 24.0
	var line_width := 4.0 if tier in ["elite", "boss", "true_boss"] else 3.0
	_draw_corner(Vector2(left, top), Vector2(1, 1), corner, line_width)
	_draw_corner(Vector2(right, top), Vector2(-1, 1), corner, line_width)
	_draw_corner(Vector2(left, bottom), Vector2(1, -1), corner, line_width)
	_draw_corner(Vector2(right, bottom), Vector2(-1, -1), corner, line_width)
	if tier in ["elite", "boss", "true_boss"]:
		var inset := 8.0
		_draw_corner(Vector2(left + inset, top + inset), Vector2(1, 1), corner * 0.62, 2.0)
		_draw_corner(Vector2(right - inset, top + inset), Vector2(-1, 1), corner * 0.62, 2.0)
	var node_count := clampi(variant, 1, 4)
	for index in node_count:
		var node_x := size.x * 0.5 + (float(index) - float(node_count - 1) * 0.5) * 18.0
		draw_circle(Vector2(node_x, top + 4.0), 5.0, accent)
		draw_circle(Vector2(node_x, top + 4.0), 2.0, Color("#f6f8ff"))
	_draw_stage_motif(Vector2(left, (top + bottom) * 0.5), Vector2(right, (top + bottom) * 0.5))

func _draw_corner(origin: Vector2, direction: Vector2, length: float, width: float) -> void:
	draw_line(origin, origin + Vector2(direction.x * length, 0), Color(accent, 0.88), width, true)
	draw_line(origin, origin + Vector2(0, direction.y * length), Color(accent, 0.88), width, true)

func _draw_stage_motif(left_center: Vector2, right_center: Vector2) -> void:
	match motif:
		"wreckage":
			draw_polyline(PackedVector2Array([left_center + Vector2(0, -18), left_center + Vector2(12, 0), left_center + Vector2(0, 18)]), Color(accent, 0.78), 4.0, true)
			draw_polyline(PackedVector2Array([right_center + Vector2(0, -18), right_center + Vector2(-12, 0), right_center + Vector2(0, 18)]), Color(accent, 0.78), 4.0, true)
		"nebula":
			draw_arc(left_center, 18.0, -PI * 0.5, PI * 0.5, 18, Color(accent, 0.82), 5.0, true)
			draw_arc(right_center, 18.0, PI * 0.5, PI * 1.5, 18, Color(accent, 0.82), 5.0, true)
		"singularity":
			for center in [left_center, right_center]:
				var diamond := PackedVector2Array([center + Vector2(0, -15), center + Vector2(10, 0), center + Vector2(0, 15), center + Vector2(-10, 0), center + Vector2(0, -15)])
				draw_polyline(diamond, Color(accent, 0.82), 4.0, true)
		"star_eater":
			draw_arc(left_center + Vector2(8, 0), 22.0, -PI * 0.65, PI * 0.65, 22, accent, 6.0, true)
			draw_circle(right_center, 7.0, Color("#f6f8ff"))
		_:
			draw_line(left_center + Vector2(0, -12), left_center + Vector2(12, 0), accent, 4.0, true)
			draw_line(left_center + Vector2(12, 0), left_center + Vector2(0, 12), accent, 4.0, true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
