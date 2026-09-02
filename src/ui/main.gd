extends Control

const COLOR_VOID := Color("#10182f")
const COLOR_PANEL := Color("#202b4f")
const COLOR_PANEL_SOFT := Color("#2c3961")
const COLOR_TEXT := Color("#f6f8ff")
const COLOR_MUTED := Color("#aab5d6")
const COLOR_CYAN := Color("#43dfd0")
const COLOR_BLUE := Color("#62a8ff")
const COLOR_ORANGE := Color("#ffac5f")
const COLOR_RED := Color("#ff667d")
const COLOR_YELLOW := Color("#ffd45f")
const SERVICE_UUID := "61b27d6e-8139-4f95-9a34-904f2db81b23"

var engine: CombatEngine
var state: CombatState
var catalog: Dictionary
var run_coordinator: RunCoordinator
var bluetooth_transport: AndroidBluetoothTransport
var cooperative_session: CooperativeSession
var local_slot := 0
var selected_plays: Array[Dictionary] = []
var selected_hand_indices: Array[int] = []
var selected_energy: int = 0

var team_health_label: Label
var team_health_bar: ProgressBar
var enemy_health_label: Label
var enemy_health_bar: ProgressBar
var player_detail_labels: Array[Label] = []
var hand_container: HBoxContainer
var status_label: Label
var ready_button: Button
var turn_label: Label
var log_label: Label
var overlay: PanelContainer
var overlay_title: Label
var overlay_subtitle: Label
var overlay_content: VBoxContainer
var connection_label: Label

func _ready() -> void:
	catalog = DemoCardCatalog.build()
	run_coordinator = RunCoordinator.new(catalog)
	run_coordinator.resume_or_start(20260902)
	bluetooth_transport = AndroidBluetoothTransport.new()
	print("STARLINK_BT singleton=%s available=%s state=%s" % [
		Engine.has_singleton(AndroidBluetoothTransport.PLUGIN_NAME),
		bluetooth_transport.is_available(),
		bluetooth_transport.get_state(),
	])
	engine = CombatEngine.new(catalog)
	state = engine.create_demo_combat()
	_build_interface()
	_refresh()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_VOID)
	for index in range(8):
		var radius := 2.0 + float(index % 3)
		var point := Vector2(size.x * (0.09 + index * 0.125), size.y * (0.12 + (index % 2) * 0.28))
		draw_circle(point, radius, Color(0.55, 0.76, 1.0, 0.28))

func _process(_delta: float) -> void:
	if bluetooth_transport == null:
		return
	if cooperative_session != null:
		cooperative_session.poll()
	else:
		bluetooth_transport.poll()
	if connection_label != null:
		var next_text := _connection_status_text()
		if connection_label.text != next_text:
			connection_label.text = next_text

func _build_interface() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	root.add_child(_build_top_bar())
	root.add_child(_build_battlefield())
	root.add_child(_build_hand_section())
	_build_overlay()

func _build_top_bar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 76
	panel.add_theme_stylebox_override("panel", _panel_style(COLOR_PANEL, 18, COLOR_BLUE, 1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	panel.add_child(row)

	var brand := Label.new()
	brand.text = "STARLINK  DUO"
	brand.add_theme_font_size_override("font_size", 22)
	brand.add_theme_color_override("font_color", COLOR_CYAN)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(brand)

	turn_label = Label.new()
	turn_label.add_theme_font_size_override("font_size", 18)
	turn_label.add_theme_color_override("font_color", COLOR_MUTED)
	row.add_child(turn_label)

	for item in [["연결", _show_connection], ["항로", _show_map], ["보상", _show_reward], ["상점", _show_shop]]:
		var navigation := Button.new()
		navigation.text = item[0]
		navigation.custom_minimum_size = Vector2(88, 42)
		navigation.add_theme_font_size_override("font_size", 16)
		navigation.add_theme_stylebox_override("normal", _panel_style(COLOR_PANEL_SOFT, 12))
		navigation.pressed.connect(item[1])
		row.add_child(navigation)

	connection_label = Label.new()
	connection_label.text = _connection_status_text()
	connection_label.tooltip_text = "Android Bluetooth 플러그인 감지됨" if Engine.has_singleton(AndroidBluetoothTransport.PLUGIN_NAME) else "에디터/에뮬레이터 로컬 모드"
	connection_label.add_theme_font_size_override("font_size", 17)
	connection_label.add_theme_color_override("font_color", COLOR_CYAN)
	row.add_child(connection_label)
	return panel

func _build_battlefield() -> Control:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	row.add_child(_build_player_panel("P1  수호자", COLOR_BLUE, 0))
	row.add_child(_build_enemy_panel())
	row.add_child(_build_player_panel("P2  기술자", COLOR_ORANGE, 1))
	return row

func _build_player_panel(title: String, accent: Color, slot: int) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(250, 280)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(COLOR_PANEL, 20, accent, 2))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", accent)
	column.add_child(title_label)

	var role := Label.new()
	role.text = "전방 방어 · 아군 엄호" if slot == 0 else "에너지 지원 · 장치 제어"
	role.add_theme_font_size_override("font_size", 15)
	role.add_theme_color_override("font_color", COLOR_MUTED)
	column.add_child(role)

	var portrait := ColorRect.new()
	portrait.custom_minimum_size.y = 112
	portrait.color = Color(accent, 0.18)
	column.add_child(portrait)

	var detail := Label.new()
	detail.add_theme_font_size_override("font_size", 18)
	detail.add_theme_color_override("font_color", COLOR_YELLOW if slot == local_slot else COLOR_TEXT)
	column.add_child(detail)
	player_detail_labels.append(detail)
	return panel

func _build_enemy_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(390, 280)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(COLOR_PANEL_SOFT, 20, COLOR_RED, 2))
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var encounter := Label.new()
	encounter.text = "일반 전투  ·  훈련 구역 01"
	encounter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	encounter.add_theme_font_size_override("font_size", 16)
	encounter.add_theme_color_override("font_color", COLOR_MUTED)
	column.add_child(encounter)

	var enemy_name := Label.new()
	enemy_name.text = "훈련 드론"
	enemy_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_name.add_theme_font_size_override("font_size", 29)
	enemy_name.add_theme_color_override("font_color", COLOR_TEXT)
	column.add_child(enemy_name)

	enemy_health_label = Label.new()
	enemy_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_health_label.add_theme_font_size_override("font_size", 17)
	column.add_child(enemy_health_label)
	enemy_health_bar = ProgressBar.new()
	enemy_health_bar.custom_minimum_size.y = 18
	enemy_health_bar.show_percentage = false
	enemy_health_bar.add_theme_stylebox_override("background", _panel_style(Color("#171e38"), 9))
	enemy_health_bar.add_theme_stylebox_override("fill", _panel_style(COLOR_RED, 9))
	column.add_child(enemy_health_bar)

	var intent := Label.new()
	intent.text = "다음 행동\n⚠  팀에 9 피해"
	intent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intent.add_theme_font_size_override("font_size", 21)
	intent.add_theme_color_override("font_color", COLOR_YELLOW)
	column.add_child(intent)
	return panel

func _build_hand_section() -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 10)

	var status_panel := PanelContainer.new()
	status_panel.add_theme_stylebox_override("panel", _panel_style(COLOR_PANEL, 16))
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 18)
	status_panel.add_child(status_row)

	var health_box := VBoxContainer.new()
	health_box.custom_minimum_size.x = 260
	team_health_label = Label.new()
	team_health_label.add_theme_font_size_override("font_size", 18)
	team_health_label.add_theme_color_override("font_color", COLOR_TEXT)
	health_box.add_child(team_health_label)
	team_health_bar = ProgressBar.new()
	team_health_bar.custom_minimum_size.y = 16
	team_health_bar.show_percentage = false
	team_health_bar.add_theme_stylebox_override("background", _panel_style(Color("#171e38"), 8))
	team_health_bar.add_theme_stylebox_override("fill", _panel_style(COLOR_CYAN, 8))
	health_box.add_child(team_health_bar)
	status_row.add_child(health_box)

	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 17)
	status_label.add_theme_color_override("font_color", COLOR_MUTED)
	status_row.add_child(status_label)

	ready_button = Button.new()
	ready_button.custom_minimum_size = Vector2(180, 52)
	ready_button.text = "준비 완료"
	ready_button.add_theme_font_size_override("font_size", 19)
	ready_button.add_theme_stylebox_override("normal", _panel_style(COLOR_CYAN, 14))
	ready_button.add_theme_stylebox_override("hover", _panel_style(Color("#6ef3e5"), 14))
	ready_button.add_theme_color_override("font_color", COLOR_VOID)
	ready_button.pressed.connect(_on_ready_pressed)
	status_row.add_child(ready_button)
	section.add_child(status_panel)

	hand_container = HBoxContainer.new()
	hand_container.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_container.add_theme_constant_override("separation", 10)
	section.add_child(hand_container)

	log_label = Label.new()
	log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	log_label.add_theme_font_size_override("font_size", 15)
	log_label.add_theme_color_override("font_color", COLOR_MUTED)
	section.add_child(log_label)
	return section

func _build_overlay() -> void:
	overlay = PanelContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.offset_left = 90
	overlay.offset_top = 54
	overlay.offset_right = -90
	overlay.offset_bottom = -54
	overlay.add_theme_stylebox_override("panel", _panel_style(Color("#18213eeF"), 24, COLOR_CYAN, 2))
	overlay.visible = false
	add_child(overlay)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	overlay.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	overlay_title = Label.new()
	overlay_title.add_theme_font_size_override("font_size", 30)
	overlay_title.add_theme_color_override("font_color", COLOR_TEXT)
	titles.add_child(overlay_title)
	overlay_subtitle = Label.new()
	overlay_subtitle.add_theme_font_size_override("font_size", 16)
	overlay_subtitle.add_theme_color_override("font_color", COLOR_MUTED)
	titles.add_child(overlay_subtitle)
	var close := Button.new()
	close.text = "전투로 돌아가기  ×"
	close.custom_minimum_size = Vector2(190, 48)
	close.pressed.connect(func() -> void: overlay.hide())
	header.add_child(close)
	overlay_content = VBoxContainer.new()
	overlay_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay_content.add_theme_constant_override("separation", 12)
	column.add_child(overlay_content)

func _clear_overlay() -> void:
	for child in overlay_content.get_children():
		child.queue_free()
	overlay.show()

func _show_connection() -> void:
	_clear_overlay()
	overlay_title.text = "근거리 협동 연결"
	if not Engine.has_singleton(AndroidBluetoothTransport.PLUGIN_NAME):
		overlay_subtitle.text = "현재 환경에는 Android Bluetooth 플러그인이 없어 로컬 데모로 실행 중입니다."
		_add_connection_notice("APK를 Android 12 이상 갤럭시에서 실행하세요.", COLOR_YELLOW)
		return
	if not bluetooth_transport.is_enabled():
		overlay_subtitle.text = "Bluetooth가 꺼져 있습니다. 빠른 설정에서 Bluetooth를 켠 뒤 새로고침하세요."
		_add_connection_action("상태 새로고침", _show_connection, COLOR_YELLOW)
		return
	if not bluetooth_transport.has_permissions():
		overlay_subtitle.text = "주변 기기 권한이 필요합니다. 위치 정보는 수집하지 않습니다."
		_add_connection_action("주변 기기 권한 허용", _request_bluetooth_permissions, COLOR_CYAN)
		return
	overlay_subtitle.text = "한 명은 방 만들기, 다른 한 명은 아래의 페어링된 기기를 선택하세요."
	var host_button := _add_connection_action("방 만들기 · 이 기기가 호스트", _start_bluetooth_host, COLOR_BLUE)
	host_button.tooltip_text = "연결을 기다리며 전투 결과를 판정합니다."
	var divider := HSeparator.new()
	overlay_content.add_child(divider)
	var paired := bluetooth_transport.get_paired_devices()
	if paired.is_empty():
		_add_connection_notice("페어링된 기기가 없습니다. Android 설정에서 두 기기를 먼저 페어링하세요.", COLOR_YELLOW)
	else:
		for device in paired:
			var label := "%s\n%s" % [device.name, device.address]
			_add_connection_action(label, _join_bluetooth_host.bind(device.address), COLOR_ORANGE)

func _request_bluetooth_permissions() -> void:
	bluetooth_transport.request_permissions()
	overlay_subtitle.text = "권한 요청을 보냈습니다. 허용 후 상태 새로고침을 누르세요."
	_add_connection_action("상태 새로고침", _show_connection, COLOR_CYAN)

func _start_bluetooth_host() -> void:
	if bluetooth_transport.start_host(SERVICE_UUID):
		local_slot = 0
		cooperative_session = CooperativeSession.new(CooperativeSession.Role.HOST, bluetooth_transport, engine, state)
		cooperative_session.session_error.connect(_on_session_error)
		overlay_subtitle.text = "참가자를 기다리는 중… 상대 기기에서 이 기기를 선택하세요."
	else:
		overlay_subtitle.text = "방을 만들지 못했습니다. 권한과 Bluetooth 상태를 확인하세요."

func _join_bluetooth_host(address: String) -> void:
	if bluetooth_transport.connect_to(address, SERVICE_UUID):
		local_slot = 1
		cooperative_session = CooperativeSession.new(CooperativeSession.Role.GUEST, bluetooth_transport)
		cooperative_session.snapshot_received.connect(_on_remote_snapshot)
		cooperative_session.session_error.connect(_on_session_error)
		overlay_subtitle.text = "호스트에 연결하는 중…"
	else:
		overlay_subtitle.text = "연결을 시작하지 못했습니다. 페어링 상태를 확인하세요."

func _add_connection_action(text: String, callback: Callable, accent: Color) -> Button:
	var button := Button.new()
	button.custom_minimum_size.y = 64
	button.text = text
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_stylebox_override("normal", _panel_style(COLOR_PANEL, 14, accent, 2))
	button.pressed.connect(callback)
	overlay_content.add_child(button)
	return button

func _add_connection_notice(text: String, accent: Color) -> void:
	var notice := Label.new()
	notice.text = text
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.add_theme_font_size_override("font_size", 19)
	notice.add_theme_color_override("font_color", accent)
	overlay_content.add_child(notice)

func _connection_status_text() -> String:
	if not Engine.has_singleton(AndroidBluetoothTransport.PLUGIN_NAME):
		return "●  LOCAL DEMO"
	match bluetooth_transport.get_state():
		"listening": return "●  WAITING"
		"connecting": return "●  CONNECTING"
		"connected": return "●  CONNECTED"
		"error": return "●  CONNECTION ERROR"
		_: return "●  BLUETOOTH READY" if bluetooth_transport.is_available() else "●  BLUETOOTH OFF"

func _on_remote_snapshot(snapshot: Dictionary, _state_hash: String) -> void:
	state = CombatState.from_snapshot(snapshot)
	selected_hand_indices.clear()
	selected_plays.clear()
	selected_energy = 0
	log_label.text = "호스트 상태 동기화 완료 · TURN %d" % state.turn
	_refresh()

func _on_session_error(code: String, detail: String) -> void:
	log_label.text = "연결 오류 · %s (%s)" % [code, detail]

func _show_map() -> void:
	_clear_overlay()
	var run := run_coordinator.run
	overlay_title.text = "항로 선택 · STAGE %d" % run.stage
	overlay_subtitle.text = "진행 %d / 8   ·   열쇠 %d / 3   ·   런 %s" % [run.step, run.keys.count(true), run.run_id]
	var stage: Dictionary = run.map.stages[run.stage - 1]
	for step_data in stage.steps:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var marker := Label.new()
		marker.custom_minimum_size.x = 95
		marker.text = "%s %02d" % ["현재" if int(step_data.index) == run.step else "구간", int(step_data.index) + 1]
		marker.add_theme_color_override("font_color", COLOR_CYAN if int(step_data.index) == run.step else COLOR_MUTED)
		row.add_child(marker)
		if step_data.kind == "common":
			row.add_child(_route_chip("공동 · %s" % _node_label(step_data.options[0].type), COLOR_CYAN))
		else:
			for slot in 2:
				var option_texts: Array[String] = []
				for option in step_data.lanes[slot].options:
					option_texts.append(_node_label(option.type))
				row.add_child(_route_chip("P%d  %s" % [slot + 1, " / ".join(option_texts)], COLOR_BLUE if slot == 0 else COLOR_ORANGE))
		overlay_content.add_child(row)

func _show_reward() -> void:
	_clear_overlay()
	overlay_title.text = "전투 보상"
	overlay_subtitle.text = "전용 카드 2장 + 공용 카드 1장 · 선택 즉시 덱과 체크포인트에 반영"
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	overlay_content.add_child(row)
	for card_id in run_coordinator.current_card_reward(0):
		var card: CardData = catalog[card_id]
		var button := Button.new()
		button.custom_minimum_size = Vector2(260, 220)
		button.text = "%s\n\n%d 에너지\n%s\n\n%s" % [_rarity_label(card.rarity), card.energy_cost, card.display_name, _effect_summary(card)]
		button.add_theme_font_size_override("font_size", 19)
		button.add_theme_stylebox_override("normal", _panel_style(COLOR_PANEL, 18, _scope_color(card.owner_scope), 3))
		button.pressed.connect(_claim_reward.bind(card_id))
		row.add_child(button)

func _claim_reward(card_id: StringName) -> void:
	if run_coordinator.claim_card(0, card_id):
		overlay_subtitle.text = "%s 획득 완료 · 현재 덱 %d장 · 자동 저장됨" % [catalog[card_id].display_name, run_coordinator.run.decks[0].size()]

func _show_shop() -> void:
	_clear_overlay()
	var inventory := run_coordinator.current_shop(0)
	overlay_title.text = "궤도 정거장 상점"
	overlay_subtitle.text = "보유 크레딧 %d · 공용 카드는 희소성 때문에 10%% 할증" % run_coordinator.run.gold[0]
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	overlay_content.add_child(row)
	for entry in inventory.cards:
		var card: CardData = catalog[StringName(entry.card_id)]
		var button := Button.new()
		button.custom_minimum_size = Vector2(190, 190)
		button.text = "%s\n%s\n%s\n\n%d C" % [_rarity_label(card.rarity), card.display_name, _effect_summary(card), entry.price]
		button.disabled = run_coordinator.run.gold[0] < int(entry.price)
		button.add_theme_font_size_override("font_size", 16)
		button.add_theme_stylebox_override("normal", _panel_style(COLOR_PANEL, 16, _scope_color(card.owner_scope), 2))
		button.pressed.connect(_buy_shop_card.bind(entry))
		row.add_child(button)
	var services := Label.new()
	services.text = "유물 2종 · 소비 아이템 2종 · 카드 제거 %d C" % inventory.remove_card_cost
	services.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	services.add_theme_font_size_override("font_size", 18)
	services.add_theme_color_override("font_color", COLOR_MUTED)
	overlay_content.add_child(services)

func _buy_shop_card(entry: Dictionary) -> void:
	if run_coordinator.buy_card(0, entry):
		_show_shop()

func _route_chip(text: String, accent: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.add_theme_stylebox_override("panel", _panel_style(COLOR_PANEL, 12, accent, 1))
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	chip.add_child(label)
	return chip

func _node_label(type: String) -> String:
	return {"combat": "전투", "event": "이벤트", "shop": "상점", "rest": "휴식", "elite": "엘리트", "key_challenge": "열쇠 도전"}.get(type, type)

func _refresh() -> void:
	turn_label.text = "TURN %02d" % state.turn
	team_health_label.text = "팀 내구도   %d / %d" % [state.team_health, state.team_max_health]
	team_health_bar.max_value = state.team_max_health
	team_health_bar.value = state.team_health
	var enemy: EnemyState = state.enemies[0]
	enemy_health_label.text = "%d / %d" % [enemy.health, enemy.max_health]
	enemy_health_bar.max_value = enemy.max_health
	enemy_health_bar.value = enemy.health
	for slot in state.players.size():
		var player: CombatantState = state.players[slot]
		var remaining := player.energy - selected_energy if slot == local_slot else player.energy
		var readiness := "준비 완료" if player.ready else ("내 캐릭터" if slot == local_slot else "선택 중")
		player_detail_labels[slot].text = "에너지  %d / %d   ·   방어 %d\n상태  %s" % [remaining, player.max_energy, player.block, readiness]
		player_detail_labels[slot].add_theme_color_override("font_color", COLOR_YELLOW if slot == local_slot else COLOR_TEXT)
	status_label.text = "선택 카드 %d장  ·  예상 비용 %d  ·  지원 카드 최대 1장" % [selected_plays.size(), selected_energy]
	ready_button.disabled = selected_plays.is_empty() or state.phase != CombatState.Phase.PLANNING
	_rebuild_hand()
	queue_redraw()

func _rebuild_hand() -> void:
	for child in hand_container.get_children():
		child.queue_free()
	for hand_index in state.players[local_slot].hand.size():
		var card_id: StringName = state.players[local_slot].hand[hand_index]
		var card: CardData = catalog[card_id]
		var card_button := Button.new()
		card_button.custom_minimum_size = Vector2(186, 126)
		card_button.text = "%d   %s\n%s\n%s" % [
			card.energy_cost,
			_rarity_label(card.rarity),
			card.display_name,
			_effect_summary(card),
		]
		card_button.tooltip_text = "탭하여 이번 턴 행동에 추가합니다."
		card_button.add_theme_font_size_override("font_size", 16)
		var accent := _scope_color(card.owner_scope)
		var selected := selected_hand_indices.has(hand_index)
		var base_color := COLOR_PANEL_SOFT if selected else COLOR_PANEL
		var border_width := 4 if selected else 2
		card_button.add_theme_stylebox_override("normal", _panel_style(base_color, 15, accent, border_width))
		card_button.add_theme_stylebox_override("hover", _panel_style(COLOR_PANEL_SOFT, 15, accent, 3))
		card_button.add_theme_stylebox_override("pressed", _panel_style(Color(accent, 0.28), 15, accent, 4))
		card_button.pressed.connect(_on_card_pressed.bind(hand_index, card))
		hand_container.add_child(card_button)

func _on_card_pressed(hand_index: int, card: CardData) -> void:
	if selected_hand_indices.has(hand_index):
		var selected_position := selected_hand_indices.find(hand_index)
		selected_hand_indices.remove_at(selected_position)
		selected_plays.remove_at(selected_position)
		selected_energy -= card.energy_cost
		log_label.text = "%s 선택 취소" % card.display_name
		_refresh()
		return
	if selected_energy + card.energy_cost > state.players[local_slot].energy:
		log_label.text = "에너지가 부족합니다."
		return
	if card.is_support():
		for play in selected_plays:
			var selected_card: CardData = catalog[play.card_id]
			if selected_card.is_support():
				log_label.text = "지원 카드는 한 턴에 1장만 사용할 수 있습니다."
				return
	selected_hand_indices.append(hand_index)
	selected_plays.append({"card_id": card.id, "target": 0})
	selected_energy += card.energy_cost
	log_label.text = "%s 선택 · 준비 완료 전까지 변경할 수 있습니다." % card.display_name
	_refresh()

func _on_ready_pressed() -> void:
	var previous_turn := state.turn
	var local_result := cooperative_session.submit_plan(local_slot, selected_plays) if cooperative_session != null else engine.submit_plan(state, local_slot, selected_plays)
	if not local_result.ok:
		log_label.text = "행동을 확정할 수 없습니다: %s" % local_result.get("error", "unknown")
		return
	if cooperative_session == null:
		var teammate_slot := 1 - local_slot
		var teammate_card: StringName = &"engineer_bolt" if state.players[teammate_slot].hand.has(&"engineer_bolt") else state.players[teammate_slot].hand[0]
		var teammate_result := engine.submit_plan(state, teammate_slot, [{"card_id": teammate_card, "target": 0}])
		if not teammate_result.ok:
			log_label.text = "동료 행동 오류: %s" % teammate_result.error
			return
		engine.resolve_if_ready(state)
	selected_hand_indices.clear()
	selected_plays.clear()
	selected_energy = 0
	var result_label := "상대 준비 대기 중" if cooperative_session != null and state.turn == previous_turn else "턴 해결 완료"
	log_label.text = "%s · 상태 해시 %s…" % [result_label, StateHasher.hash_snapshot(state.to_snapshot()).left(8)]
	_refresh()

func _effect_summary(card: CardData) -> String:
	var parts: Array[String] = []
	for effect in card.effects:
		match effect.get("type", ""):
			"damage": parts.append("피해 %d" % effect.amount)
			"block": parts.append("방어 %d" % effect.amount)
			"energy": parts.append("에너지 +%d" % effect.amount)
			"heal": parts.append("팀 회복 %d" % effect.amount)
	return " · ".join(parts)

func _rarity_label(rarity: CardData.Rarity) -> String:
	return ["● 일반", "◆ 매직", "⬢ 레어", "★ 전설"][rarity]

func _scope_color(scope: CardData.Scope) -> Color:
	match scope:
		CardData.Scope.GUARDIAN: return COLOR_BLUE
		CardData.Scope.ENGINEER: return COLOR_ORANGE
		CardData.Scope.HACKER: return Color("#bc8cff")
		CardData.Scope.ASSAULT: return COLOR_RED
		_: return COLOR_CYAN

func _panel_style(color: Color, radius: int, border_color: Color = Color.TRANSPARENT, border_width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.border_color = border_color
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style
