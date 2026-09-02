extends Button

var accent := Color.WHITE
var selected := false
var seed_value := 0
var effect_kind := "utility"
var effect_accent := Color("#8fa0bc")
var primary_tag := "전술"

func configure(card: CardData, rarity_text: String, effect_text: String, accent_color: Color, is_selected: bool, footer_text: String = "") -> void:
	accent = accent_color
	selected = is_selected
	seed_value = String(card.id).hash()
	primary_tag = String(card.tags[0]) if not card.tags.is_empty() else "전술"
	effect_kind = String(card.effects[0].get("type", "utility")) if not card.effects.is_empty() else "utility"
	effect_accent = _effect_color(effect_kind)
	# Retain a native button label for focus tooling while visual copy uses child labels.
	# Android currently exposes the Godot canvas as one SurfaceView, so TalkBack still needs a platform bridge.
	text = String(card.display_name)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	tooltip_text = "%s · %s · %s · 에너지 %d" % [card.display_name, primary_tag, effect_text, card.energy_cost]
	var inset := MarginContainer.new()
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_theme_constant_override("margin_left", 11)
	inset.add_theme_constant_override("margin_right", 11)
	inset.add_theme_constant_override("margin_top", 8)
	inset.add_theme_constant_override("margin_bottom", 8)
	add_child(inset)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 1)
	inset.add_child(column)
	var meta := HBoxContainer.new()
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(meta)
	meta.add_child(_label("⚡ %d" % card.energy_cost, 18, Color("#ffffff")))
	var rarity := _label(rarity_text, 11, Color("#d6deef"))
	rarity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rarity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_child(rarity)
	var art_space := Control.new()
	art_space.custom_minimum_size.y = 32 if is_selected else 24
	art_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(art_space)
	var name_label := _label(String(card.display_name), 15, Color.WHITE)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(name_label)
	var divider := HSeparator.new()
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.add_theme_constant_override("separation", 2)
	column.add_child(divider)
	var effect := _label("%s · %s" % [primary_tag, effect_text], 12, Color("#dce6f7"))
	effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(effect)
	var resolved_footer := footer_text if not footer_text.is_empty() else ("◆ 선택됨" if is_selected else "탭하여 선택")
	var state_label := _label(resolved_footer, 11, accent if is_selected or not footer_text.is_empty() else Color("#8fa0bc"))
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	state_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	column.add_child(state_label)
	queue_redraw()

func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _draw() -> void:
	var width := size.x
	var y := 42.0
	draw_rect(Rect2(10, y, width - 20, 30 if selected else 23), Color(accent, 0.10), true)
	var center := Vector2(width * 0.5, y + 14)
	draw_circle(center, 13, Color(effect_accent, 0.12))
	match effect_kind:
		"damage":
			draw_arc(center, 11, 0, TAU, 24, effect_accent, 2, true)
			draw_line(center + Vector2(-14, 0), center + Vector2(14, 0), effect_accent, 2, true)
			draw_line(center + Vector2(-8, 9), center + Vector2(9, -8), Color.WHITE, 3, true)
		"block":
			var shield := PackedVector2Array([center + Vector2(0, -12), center + Vector2(11, -6), center + Vector2(8, 7), center + Vector2(0, 13), center + Vector2(-8, 7), center + Vector2(-11, -6)])
			draw_colored_polygon(shield, Color(effect_accent, 0.30))
			draw_polyline(shield, effect_accent, 2, true)
		"heal":
			draw_circle(center, 11, Color(effect_accent, 0.22))
			draw_line(center + Vector2(-7, 0), center + Vector2(7, 0), Color.WHITE, 4, true)
			draw_line(center + Vector2(0, -7), center + Vector2(0, 7), Color.WHITE, 4, true)
		"energy":
			var bolt := PackedVector2Array([center + Vector2(2, -13), center + Vector2(-8, 2), center + Vector2(-1, 2), center + Vector2(-4, 13), center + Vector2(9, -4), center + Vector2(2, -4)])
			draw_colored_polygon(bolt, effect_accent)
		_:
			draw_circle(center + Vector2(-7, 0), 7, Color(effect_accent, 0.28))
			draw_circle(center + Vector2(7, 0), 7, Color(accent, 0.28))
			draw_line(center + Vector2(-3, 0), center + Vector2(3, 0), Color.WHITE, 2, true)
	if selected:
		draw_line(Vector2(18, 4), Vector2(width - 18, 4), Color("#ffffff"), 2, true)

func _effect_color(kind: String) -> Color:
	return {
		"damage": Color("#ff647c"),
		"block": Color("#5fa8ff"),
		"heal": Color("#55e5ad"),
		"energy": Color("#ffd166"),
	}.get(kind, Color("#bc8cff"))

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
