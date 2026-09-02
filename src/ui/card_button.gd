extends Button

var accent := Color.WHITE
var selected := false
var seed_value := 0
var effect_kind := "utility"
var effect_accent := Color("#8fa0bc")
var primary_tag := "전술"

const CardArt := preload("res://src/ui/card_art_catalog.gd")

func configure(card: CardData, rarity_text: String, effect_text: String, accent_color: Color, is_selected: bool, footer_text: String = "") -> void:
	accent = accent_color
	selected = is_selected
	seed_value = String(card.id).hash()
	primary_tag = String(card.tags[0]) if not card.tags.is_empty() else "전술"
	effect_kind = _primary_effect_kind(card)
	effect_accent = _effect_color(effect_kind)
	# Visual copy uses child labels. Android exposes the canvas as one SurfaceView,
	# so a hidden native button caption would not improve TalkBack and can cause duplicate rendering.
	text = ""
	tooltip_text = "%s · %s · %s · 에너지 %d" % [card.display_name, primary_tag, effect_text, card.energy_cost]
	accessibility_name = "%s 카드%s" % [card.display_name, ", 선택됨" if is_selected else ""]
	var action_hint := footer_text if not footer_text.is_empty() else ("누르면 선택을 취소합니다" if is_selected else "누르면 행동 큐에 추가합니다")
	accessibility_description = "%s, %s, 에너지 %d, %s, 대상 %s. %s" % [
		rarity_text.lstrip("●◆✦ "),
		primary_tag,
		card.energy_cost,
		effect_text,
		_target_name(card.target),
		action_hint,
	]
	add_theme_stylebox_override("focus", _focus_style())
	var frame := preload("res://src/ui/card_frame_visual.gd").new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.configure(card.owner_scope, accent)
	add_child(frame)
	var inset := MarginContainer.new()
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_theme_constant_override("margin_left", 11)
	inset.add_theme_constant_override("margin_right", 11)
	inset.add_theme_constant_override("margin_top", 5)
	inset.add_theme_constant_override("margin_bottom", 3)
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
	var art := TextureRect.new()
	art.custom_minimum_size.y = 34 if is_selected else 26
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.texture = CardArt.texture_for(card.owner_scope, effect_kind)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	column.add_child(art)
	var name_label := _label(String(card.display_name), 14, Color.WHITE)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(name_label)
	var divider := HSeparator.new()
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.add_theme_constant_override("separation", 2)
	column.add_child(divider)
	var effect := _label("%s · %s" % [primary_tag, effect_text], 11, Color("#dce6f7"))
	effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(effect)
	var resolved_footer := footer_text if not footer_text.is_empty() else ("◆ 선택됨" if is_selected else "탭하여 선택")
	var state_label := _label(resolved_footer, 10, accent if is_selected or not footer_text.is_empty() else Color("#8fa0bc"))
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
	if selected:
		draw_line(Vector2(18, 4), Vector2(width - 18, 4), Color("#ffffff"), 2, true)

func _primary_effect_kind(card: CardData) -> String:
	for priority in ["damage", "block", "heal", "energy"]:
		for effect in card.effects:
			if String(effect.get("type", "")) == priority:
				return priority
	return "energy"

func _effect_color(kind: String) -> Color:
	return {
		"damage": Color("#ff647c"),
		"block": Color("#5fa8ff"),
		"heal": Color("#55e5ad"),
		"energy": Color("#ffd166"),
	}.get(kind, Color("#bc8cff"))

func _target_name(target: CardData.Target) -> String:
	return ["자신", "동료", "적", "팀 전체"][target]

func _focus_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#162441")
	style.border_color = Color.WHITE
	style.set_border_width_all(4)
	style.set_corner_radius_all(16)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
