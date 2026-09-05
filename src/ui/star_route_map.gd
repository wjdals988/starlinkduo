class_name StarRouteMap
extends Control

signal node_selected(slot: int, node_id: String)

const MAP_SIZE := Vector2(1080, 326)
const NODE_SIZE := Vector2(84, 54)
const CYAN := Color("#43dfd0")
const BLUE := Color("#62a8ff")
const ORANGE := Color("#ffac5f")
const MUTED := Color("#516079")

var stage: Dictionary
var current_step := 0
var local_slot := 0
var pending_routes: Dictionary = {}
var node_positions: Array[Array] = []

func configure(stage_data: Dictionary, step_index: int, player_slot: int, selected_routes: Dictionary) -> void:
	stage = stage_data
	current_step = step_index
	local_slot = player_slot
	pending_routes = selected_routes.duplicate()
	custom_minimum_size = MAP_SIZE
	size = MAP_SIZE
	_build_nodes()
	queue_redraw()

func _build_nodes() -> void:
	for child in get_children():
		child.queue_free()
	node_positions.clear()
	for step_data in stage.steps:
		var step_index := int(step_data.index)
		var positions: Array = []
		var entries: Array[Dictionary] = []
		if step_data.kind == "common":
			entries.append({"option": step_data.options[0], "slot": -1, "row": 1.5})
		else:
			for slot in 2:
				for option_index in step_data.lanes[slot].options.size():
					entries.append({"option": step_data.lanes[slot].options[option_index], "slot": slot, "row": float(slot * 2 + option_index)})
		for entry in entries:
			var center := Vector2(60.0 + step_index * 137.0, 58.0 + float(entry.row) * 68.0)
			positions.append(center)
			_add_node_button(entry.option, int(entry.slot), step_index, center)
		node_positions.append(positions)

func _add_node_button(option: Dictionary, slot: int, step_index: int, center: Vector2) -> void:
	var button := Button.new()
	button.position = center - NODE_SIZE * 0.5
	button.size = NODE_SIZE
	var node_type := String(option.type)
	button.text = "%s\n%s" % [_icon(node_type), _label(node_type)]
	button.add_theme_font_size_override("font_size", 12)
	var accent := _type_color(node_type)
	var is_current := step_index == current_step
	var is_reachable := is_current and (slot < 0 or slot == local_slot) and not pending_routes.has(local_slot)
	var selected_node_id := String(pending_routes.get(local_slot, "")) if slot < 0 else String(pending_routes.get(slot, ""))
	var is_selected := is_current and selected_node_id == String(option.id)
	button.disabled = not is_reachable
	button.modulate = Color.WHITE if is_current else (Color(0.72, 0.80, 0.92, 0.84) if step_index > current_step else Color(0.52, 0.70, 0.82, 0.62))
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", accent if is_selected else Color("#a7b2c7"))
	button.add_theme_stylebox_override("normal", _diamond_style(Color(accent, 0.34), accent, 2))
	button.add_theme_stylebox_override("hover", _diamond_style(Color(accent, 0.58), Color.WHITE, 3))
	button.add_theme_stylebox_override("pressed", _diamond_style(Color(accent, 0.76), Color.WHITE, 3))
	button.add_theme_stylebox_override("disabled", _diamond_style(Color(accent, 0.28 if is_selected else 0.16), accent if is_selected else Color("#71819b"), 2 if is_selected else 1))
	button.tooltip_text = "%s · %s" % [_label(node_type), _preview(node_type)]
	button.accessibility_name = "%s 노드" % _label(node_type)
	button.accessibility_description = _preview(node_type)
	if is_reachable:
		button.pressed.connect(func() -> void: node_selected.emit(local_slot if slot < 0 else slot, String(option.id)))
	add_child(button)

func _draw() -> void:
	for x in range(0, int(MAP_SIZE.x), 32):
		draw_line(Vector2(x, 0), Vector2(x + 180, MAP_SIZE.y), Color("#30405a22"), 1.0)
	for y in range(0, int(MAP_SIZE.y), 32):
		draw_line(Vector2(0, y), Vector2(MAP_SIZE.x, y), Color("#30405a18"), 1.0)
	for index in range(maxi(0, node_positions.size() - 1)):
		var from_nodes: Array = node_positions[index]
		var to_nodes: Array = node_positions[index + 1]
		for from_position in from_nodes:
			var nearest := _nearest_positions(from_position, to_nodes, 2)
			for to_position in nearest:
				var passed := index < current_step
				draw_line(from_position + Vector2(NODE_SIZE.x * 0.48, 0), to_position - Vector2(NODE_SIZE.x * 0.48, 0), Color("#62a8ff88") if passed else Color("#8190a44d"), 2.0 if passed else 1.2, true)
	for star_index in 34:
		var star := Vector2(fposmod(float(star_index * 83 + 17), MAP_SIZE.x), fposmod(float(star_index * 47 + 29), MAP_SIZE.y))
		draw_circle(star, 1.2, Color("#b9ecff66"))

func _nearest_positions(origin: Vector2, candidates: Array, limit: int) -> Array:
	var sorted := candidates.duplicate()
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool: return absf(a.y - origin.y) < absf(b.y - origin.y))
	return sorted.slice(0, mini(limit, sorted.size()))

func _diamond_style(fill: Color, outline: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 27
	style.corner_radius_bottom_left = 27
	style.corner_radius_bottom_right = 0
	style.set_border_width_all(width)
	style.border_color = outline
	style.set_content_margin_all(4)
	return style

func _label(type: String) -> String:
	return {"combat": "전투", "event": "이벤트", "shop": "상점", "rest": "휴식", "elite": "엘리트", "key_challenge": "열쇠"}.get(type, type)

func _icon(type: String) -> String:
	return {"combat": "⚔", "event": "?", "shop": "▣", "rest": "＋", "elite": "◆", "key_challenge": "✦"}.get(type, "·")

func _type_color(type: String) -> Color:
	return {"combat": Color("#ff5f91"), "event": CYAN, "shop": Color("#ffb45f"), "rest": Color("#55d99a"), "elite": Color("#bc8cff"), "key_challenge": Color("#ffd45f")}.get(type, BLUE)

func _preview(type: String) -> String:
	return {"combat": "카드 보상이 있는 일반 교전", "event": "선택에 따라 결과가 달라지는 신호", "shop": "카드와 장비를 구매하는 안전 지대", "rest": "팀 내구도를 회복하는 정박지", "elite": "강한 적과 강화 보상", "key_challenge": "최종 항로 열쇠 획득"}.get(type, "미확인 목적지")
