extends Button

var accent := Color.WHITE
var selected := false
var seed_value := 0

func configure(card: CardData, rarity_text: String, effect_text: String, accent_color: Color, is_selected: bool) -> void:
	accent = accent_color
	selected = is_selected
	seed_value = String(card.id).hash()
	text = ""
	tooltip_text = "%s · %s. 탭하여 이번 턴 행동에 추가합니다." % [card.display_name, effect_text]
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
	var effect := _label(effect_text, 12, Color("#dce6f7"))
	effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(effect)
	var state_label := _label("◆ 선택됨" if is_selected else "탭하여 선택", 11, accent if is_selected else Color("#8fa0bc"))
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
	var offset := float(abs(seed_value) % 19)
	draw_circle(Vector2(width * 0.5 - 18 + offset * 0.12, y + 14), 13, Color(accent, 0.22))
	draw_arc(Vector2(width * 0.5 + 17, y + 14), 11, -PI * 0.75, PI * 0.75, 18, Color(accent, 0.72), 3, true)
	draw_line(Vector2(width * 0.5 - 2, y + 5), Vector2(width * 0.5 + 9, y + 23), accent, 2, true)
	if selected:
		draw_line(Vector2(18, 4), Vector2(width - 18, 4), Color("#ffffff"), 2, true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
