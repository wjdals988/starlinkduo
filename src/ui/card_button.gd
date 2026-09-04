extends Button

var accent := Color.WHITE
var selected := false
var seed_value := 0
var effect_kind := "utility"
var effect_accent := Color("#8fa0bc")
var primary_tag := "전술"
var card_role := "tactic"
var role_accent := Color("#bc8cff")

const CardArt := preload("res://src/ui/card_art_catalog.gd")
const CardIdentity := preload("res://src/ui/card_identity_visual.gd")

func configure(card: CardData, rarity_text: String, effect_text: String, accent_color: Color, is_selected: bool, footer_text: String = "") -> void:
	accent = accent_color
	selected = is_selected
	seed_value = String(card.id).hash()
	primary_tag = String(card.tags[0]) if not card.tags.is_empty() else "전술"
	effect_kind = _primary_effect_kind(card)
	effect_accent = _effect_color(effect_kind)
	card_role = _card_role(card)
	role_accent = _role_color(card_role)
	# Visual copy uses child labels. Android exposes the canvas as one SurfaceView,
	# so a hidden native button caption would not improve TalkBack and can cause duplicate rendering.
	text = ""
	tooltip_text = "%s · %s · %s · 에너지 %d" % [card.display_name, _role_name(card_role), effect_text, card.energy_cost]
	accessibility_name = "%s 카드%s" % [card.display_name, ", 선택됨" if is_selected else ""]
	var action_hint := footer_text if not footer_text.is_empty() else ("누르면 선택을 취소합니다" if is_selected else "누르면 행동 큐에 추가합니다")
	accessibility_description = "%s, %s, 에너지 %d, %s, 대상 %s. %s" % [
		rarity_text.lstrip("●◆✦ "),
		_role_name(card_role),
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
	inset.add_theme_constant_override("margin_left", 10)
	inset.add_theme_constant_override("margin_right", 10)
	inset.add_theme_constant_override("margin_top", 7)
	inset.add_theme_constant_override("margin_bottom", 6)
	add_child(inset)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 3)
	inset.add_child(column)
	var meta := HBoxContainer.new()
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(meta)
	var cost_badge := PanelContainer.new()
	cost_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_badge.add_theme_stylebox_override("panel", _badge_style(effect_accent, 9))
	var cost := _label("⚡ %d" % card.energy_cost, 17, Color.WHITE)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.custom_minimum_size.x = 48
	cost_badge.add_child(cost)
	meta.add_child(cost_badge)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_child(spacer)
	var role_badge := PanelContainer.new()
	role_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	role_badge.add_theme_stylebox_override("panel", _badge_style(role_accent, 9))
	var role := _label(_role_badge_text(card_role), 11, Color.WHITE)
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_badge.add_child(role)
	meta.add_child(role_badge)
	var art := TextureRect.new()
	art.custom_minimum_size.y = 38
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.size_flags_stretch_ratio = 1.35
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.texture = CardArt.texture_for(card.owner_scope, effect_kind)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	column.add_child(art)
	var identity := CardIdentity.new()
	identity.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	identity.configure(card.id, accent)
	art.add_child(identity)
	var name_band := PanelContainer.new()
	name_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_band.add_theme_stylebox_override("panel", _name_style(accent))
	var name_label := _label(String(card.display_name), 15, Color.WHITE)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_band.add_child(name_label)
	column.add_child(name_band)
	var effect := _label(effect_text, 13, Color.WHITE)
	effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect.add_theme_color_override("font_shadow_color", Color("#000000b8"))
	effect.add_theme_constant_override("shadow_offset_x", 1)
	effect.add_theme_constant_override("shadow_offset_y", 1)
	column.add_child(effect)
	var detail := "%s  ·  대상 %s" % [rarity_text, _target_name(card.target)]
	if card_role == "support":
		detail = "＋ 지원 카드  ·  턴당 1장"
	var target := _label(detail, 10, role_accent.lightened(0.22) if card_role == "support" else Color("#aebbd2"))
	target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(target)
	var resolved_footer := footer_text if not footer_text.is_empty() else ("◆ 선택됨" if is_selected else "탭하여 선택")
	var state_label := _label(resolved_footer, 10, accent.lightened(0.18) if is_selected or not footer_text.is_empty() else Color("#8fa0bc"))
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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

func _badge_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.88)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style

func _name_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.darkened(0.55), 0.96)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 9
	style.corner_radius_bottom_right = 9
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 2
	style.content_margin_bottom = 3
	return style

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

func _card_role(card: CardData) -> String:
	if card.is_support():
		return "support"
	if card.effects.any(func(effect: Dictionary) -> bool: return String(effect.get("type", "")) == "damage"):
		return "attack"
	if card.effects.any(func(effect: Dictionary) -> bool: return String(effect.get("type", "")) == "block"):
		return "defense"
	return "tactic"

func _role_name(role: String) -> String:
	return {"attack": "공격 카드", "defense": "방어 카드", "support": "지원 카드", "tactic": "전술 카드"}.get(role, "전술 카드")

func _role_badge_text(role: String) -> String:
	return {"attack": "⚔ 공격", "defense": "⬡ 방어", "support": "＋ 지원 1/턴", "tactic": "✦ 전술"}.get(role, "✦ 전술")

func _role_color(role: String) -> Color:
	return {"attack": Color("#ef536c"), "defense": Color("#4d91ec"), "support": Color("#24b987"), "tactic": Color("#9a70df")}.get(role, Color("#9a70df"))

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
