extends Control

const COLOR_VOID := Color("#07101f")
const COLOR_PANEL := Color("#111a31e8")
const COLOR_PANEL_SOFT := Color("#1a2848ee")
const COLOR_TEXT := Color("#f6f8ff")
const COLOR_MUTED := Color("#aab5d6")
const COLOR_CYAN := Color("#43dfd0")
const COLOR_BLUE := Color("#62a8ff")
const COLOR_ORANGE := Color("#ffac5f")
const COLOR_RED := Color("#ff667d")
const COLOR_YELLOW := Color("#ffd45f")
const SERVICE_UUID := "61b27d6e-8139-4f95-9a34-904f2db81b23"
const CURRENT_VERSION := "0.1.4"
const VERSION_FEED_URL := "https://coldbrewventi.vercel.app/starlink-duo/latest.json"
const DOWNLOAD_PAGE_URL := "https://coldbrewventi.vercel.app/projects/starlink-duo"
const RELEASE_HISTORY := [
	{"version": "0.1.4", "date": "2026.09.05", "notes": ["공격·방어·지원·전술 역할 배지", "지원 카드 녹색 표시와 턴당 1장 안내", "중복 지원 선택 제한 사유 표시"]},
	{"version": "0.1.3", "date": "2026.09.05", "notes": ["카드 비용·이름·효과 정보 위계 개선", "통신 휠 형태의 빠른 메시지", "카드 더미 형태의 남은 덱 표시", "버전별 게임 내 업데이트 기록"]},
	{"version": "0.1.2", "date": "2026.09.05", "notes": ["현재 버전 표시와 신규 업데이트 감지", "업데이트 레드닷·최초 1회 안내", "대시보드 다운로드와 변경 기록 연결"]},
	{"version": "0.1.1", "date": "2026.09.05", "notes": ["공통 첫 전투 뒤 4갈래 항로 선택", "덱 카드 최대 6열·세로 스크롤", "Android 맵·덱 화면 검증"]},
	{"version": "0.1.0", "date": "2026.09.04", "notes": ["싱글 원정과 캐릭터 편성", "분기형 성계 지도와 순차 카드 전투", "Bluetooth 대기실·빠른 메시지 기반"]},
]
const EnemyVisuals := preload("res://src/ui/enemy_visual_catalog.gd")
const StarRouteMapView := preload("res://src/ui/star_route_map.gd")

var engine: CombatEngine
var state: CombatState
var duel_engine: DuelEngine
var duel_state: DuelState
var duel_save_store: DuelSaveStore
var game_mode := "cooperative"
var catalog: Dictionary
var run_coordinator: RunCoordinator
var bluetooth_transport: AndroidBluetoothTransport
var accessibility_bridge: AndroidAccessibilityBridge
var cooperative_session: CooperativeSession
var local_slot := 0
var roster_edit_slot := 0
var deck_view_slot := 0
var selected_plays: Array[Dictionary] = []
var selected_hand_indices: Array[int] = []
var selected_energy: int = 0
var singleplayer_pending_cards: Array[CardData] = []
var active_route_types: Array[String] = []
var active_route_combat := false
var reduce_motion := false
var haptics_enabled := true
var ui_sound_enabled := true
var glow_enabled := true
var large_text_enabled := false
var system_font_scale := 1.0
var game_started := false
var in_multiplayer_lobby := false
var lobby_signature := ""
var lobby_preview_active := false

var team_health_label: Label
var team_health_bar: ProgressBar
var enemy_health_label: Label
var enemy_health_bar: ProgressBar
var player_detail_labels: Array[Label] = []
var player_title_labels: Array[Label] = []
var player_role_labels: Array[Label] = []
var player_portraits: Array[TextureRect] = []
var player_panels: Array[PanelContainer] = []
var player_status_visuals: Array[PlayerStatusVisual] = []
var player_status_badges: Array[Label] = []
var hand_container: HBoxContainer
var draw_pile_badge: DrawPileVisual
var status_label: Label
var ready_button: Button
var quick_chat_button: Button
var turn_label: Label
var log_label: Label
var overlay: Control
var overlay_scrim: ColorRect
var main_menu_backdrop: TextureRect
var main_menu_shade: ColorRect
var overlay_panel: PanelContainer
var overlay_title: Label
var overlay_subtitle: Label
var overlay_content: VBoxContainer
var overlay_close_button: Button
var connection_label: Label
var encounter_label: Label
var enemy_name_label: Label
var intent_label: Label
var intent_panel: PanelContainer
var energy_label: Label
var background_focus_modes: Dictionary = {}
var previous_focus_owner: Control
var handling_back_request := false
var accessibility_sync_pending := false
var interaction_locked := false
var battle_fx_layer: Control
var enemy_art: Control
var enemy_aura: Control
var chat_bubbles: Array[PanelContainer] = []
var chat_bubble_labels: Array[Label] = []
var chat_bubble_tokens := [0, 0]
var ui_audio_players: Dictionary = {}
var overlay_transition: Tween
var version_request: HTTPRequest
var version_button: Button
var latest_release: Dictionary = {}

func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	get_window().go_back_requested.connect(_on_go_back_requested)
	accessibility_name = "스타링크 듀오 전투 화면"
	accessibility_description = "두 명이 협동하거나 대전하는 오프라인 카드 게임"
	_load_accessibility_settings()
	_read_system_font_scale()
	get_tree().node_added.connect(_on_ui_node_added)
	_build_ui_audio()
	catalog = FullCardCatalog.build()
	run_coordinator = RunCoordinator.new(catalog)
	run_coordinator.resume_or_start(20260902)
	run_coordinator.run_changed.connect(_on_run_changed)
	bluetooth_transport = AndroidBluetoothTransport.new()
	accessibility_bridge = AndroidAccessibilityBridge.new()
	print("STARLINK_BT singleton=%s available=%s state=%s" % [
		Engine.has_singleton(AndroidBluetoothTransport.PLUGIN_NAME),
		bluetooth_transport.is_available(),
		bluetooth_transport.get_state(),
	])
	engine = CombatEngine.new(catalog)
	state = _create_training_combat()
	duel_save_store = DuelSaveStore.new()
	duel_state = duel_save_store.load_active()
	if duel_state != null:
		duel_engine = DuelEngine.new(catalog)
		game_mode = "duel"
	_build_interface()
	_start_version_check()
	_apply_text_scale_tree(self)
	_refresh()
	_sync_android_accessibility.call_deferred()
	_show_main_menu.call_deferred()
	var lobby_preview := _debug_lobby_preview()
	if not lobby_preview.is_empty():
		_show_multiplayer_lobby.bind(lobby_preview).call_deferred()
	else:
		var ui_preview := _debug_ui_preview_name()
		if not ui_preview.is_empty():
			_show_debug_ui_preview.bind(ui_preview).call_deferred()

func _exit_tree() -> void:
	if cooperative_session != null:
		cooperative_session.close()
	elif bluetooth_transport != null:
		bluetooth_transport.close()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_VOID)

func _build_ui_audio() -> void:
	var specs := {
		"tap": {"notes": [520.0], "duration": 0.055, "volume": -18.0},
		"open": {"notes": [330.0, 495.0], "duration": 0.12, "volume": -17.0},
		"confirm": {"notes": [440.0, 660.0, 880.0], "duration": 0.16, "volume": -15.0},
		"cancel": {"notes": [390.0, 260.0], "duration": 0.11, "volume": -18.0},
	}
	for sound_name in specs:
		var player := AudioStreamPlayer.new()
		var spec: Dictionary = specs[sound_name]
		player.stream = _synth_ui_tone(spec.notes, float(spec.duration))
		player.volume_db = float(spec.volume)
		player.bus = "Master"
		add_child(player)
		ui_audio_players[sound_name] = player

func _synth_ui_tone(notes: Array, duration: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	var sample_rate := 22050
	var sample_count := maxi(1, roundi(duration * sample_rate))
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for sample_index in sample_count:
		var time := float(sample_index) / sample_rate
		var envelope := minf(1.0, time / 0.008) * pow(1.0 - float(sample_index) / sample_count, 2.2)
		var value := 0.0
		for note_index in notes.size():
			var note_time := time - float(note_index) * duration * 0.18
			if note_time >= 0.0:
				value += sin(TAU * float(notes[note_index]) * note_time)
		value = value / maxf(1.0, float(notes.size())) * envelope * 0.68
		bytes.encode_s16(sample_index * 2, roundi(clampf(value, -1.0, 1.0) * 32767.0))
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = bytes
	return stream

func _on_ui_node_added(node: Node) -> void:
	if node is BaseButton:
		var button := node as BaseButton
		if not button.pressed.is_connected(_play_button_sound.bind(button)):
			button.pressed.connect(_play_button_sound.bind(button))

func _play_button_sound(button: BaseButton) -> void:
	var label: String = button.text.to_lower() if button is Button else button.accessibility_name.to_lower()
	if "닫기" in label or "취소" in label or "메인" in label:
		_play_ui_sound("cancel")
	elif "확정" in label or "완료" in label or "시작" in label or "진입" in label or "구매" in label:
		_play_ui_sound("confirm")
	else:
		_play_ui_sound("tap")

func _play_ui_sound(sound_name: String) -> void:
	if not ui_sound_enabled or not ui_audio_players.has(sound_name):
		return
	var player: AudioStreamPlayer = ui_audio_players[sound_name]
	player.stop()
	player.play()

func _on_go_back_requested() -> void:
	if handling_back_request:
		return
	handling_back_request = true
	_reset_back_request_guard.call_deferred()
	if overlay != null and overlay.visible:
		if overlay_title.text == "STARLINK DUO":
			get_tree().quit()
		else:
			_play_ui_sound("cancel")
			_close_overlay()
	else:
		get_tree().quit()

func _reset_back_request_guard() -> void:
	handling_back_request = false

func _process(_delta: float) -> void:
	if accessibility_bridge != null:
		accessibility_bridge.poll_action()
	if not interaction_locked and game_mode != "duel" and state != null and state.phase == CombatState.Phase.WON and not overlay.visible:
		if active_route_combat:
			if cooperative_session == null or cooperative_session.role == CooperativeSession.Role.HOST:
				_finish_route_combat()
		elif state.combat_id == &"demo_combat":
			_show_training_victory()
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
	if in_multiplayer_lobby and not lobby_preview_active and overlay != null and overlay.visible:
		var next_lobby_signature := "%s:%s:%s" % [bluetooth_transport.get_state(), cooperative_session != null and cooperative_session.handshake_complete, cooperative_session != null and cooperative_session.handshake_failed]
		if next_lobby_signature != lobby_signature:
			_show_multiplayer_lobby()

func _build_interface() -> void:
	var backdrop := TextureRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.texture = load("res://assets/art/orbital-battlefield-v2.png")
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color("#03101d35")
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	root.add_child(_build_top_bar())
	root.add_child(_build_battlefield())
	root.add_child(_build_hand_section())
	_build_battle_fx_layer()
	_build_chat_bubbles()
	_build_overlay()

func _build_battle_fx_layer() -> void:
	battle_fx_layer = Control.new()
	battle_fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battle_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle_fx_layer.accessibility_name = "전투 결과 연출"
	battle_fx_layer.accessibility_live = AccessibilityServer.LIVE_ASSERTIVE
	battle_fx_layer.visible = false
	add_child(battle_fx_layer)

func _build_chat_bubbles() -> void:
	for side in 2:
		var bubble := PanelContainer.new()
		bubble.set_anchor(SIDE_LEFT, 0.06 if side == 0 else 0.68)
		bubble.set_anchor(SIDE_RIGHT, 0.32 if side == 0 else 0.94)
		bubble.set_anchor(SIDE_TOP, 0.39)
		bubble.set_anchor(SIDE_BOTTOM, 0.49)
		bubble.add_theme_stylebox_override("panel", _panel_style(Color("#153a46f2") if side == 0 else Color("#432c20f2"), 22, Color.TRANSPARENT, 0, 18, 10))
		bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bubble.z_index = 12
		bubble.visible = false
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.accessibility_name = "내 메시지" if side == 0 else "상대 메시지"
		label.accessibility_live = AccessibilityServer.LIVE_POLITE
		bubble.add_child(label)
		add_child(bubble)
		chat_bubbles.append(bubble)
		chat_bubble_labels.append(label)

func _build_top_bar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 58
	panel.add_theme_stylebox_override("panel", _panel_style(Color("#081326c9"), 16, Color("#5fe8dd44"), 1, 12, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)

	var brand := Label.new()
	brand.text = "✦  STARLINK DUO"
	brand.add_theme_font_size_override("font_size", 20)
	brand.add_theme_color_override("font_color", COLOR_CYAN)
	row.add_child(brand)
	var mission := Label.new()
	mission.text = "ORBITAL EXPEDITION"
	mission.add_theme_font_size_override("font_size", 12)
	mission.add_theme_color_override("font_color", COLOR_MUTED)
	mission.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mission)

	turn_label = Label.new()
	turn_label.add_theme_font_size_override("font_size", 16)
	turn_label.add_theme_color_override("font_color", COLOR_MUTED)
	turn_label.accessibility_name = "현재 턴"
	row.add_child(turn_label)

	connection_label = Label.new()
	connection_label.text = _connection_status_text()
	connection_label.tooltip_text = "Android Bluetooth 플러그인 감지됨" if Engine.has_singleton(AndroidBluetoothTransport.PLUGIN_NAME) else "에디터/에뮬레이터 로컬 모드"
	connection_label.add_theme_font_size_override("font_size", 14)
	connection_label.add_theme_color_override("font_color", COLOR_CYAN)
	connection_label.accessibility_name = "연결 상태"
	row.add_child(connection_label)
	var deck_button := Button.new()
	deck_button.text = "▤  덱"
	_set_button_accessibility(deck_button, "현재 덱 보기", "보유 카드와 남은 카드 구성을 확인합니다")
	deck_button.custom_minimum_size = Vector2(76, 48)
	deck_button.add_theme_stylebox_override("normal", _panel_style(Color("#14213ddf"), 12, Color.TRANSPARENT, 0, 12, 8))
	deck_button.add_theme_stylebox_override("hover", _panel_style(COLOR_PANEL_SOFT, 12, Color.TRANSPARENT, 0, 12, 8))
	deck_button.add_theme_stylebox_override("focus", _focus_style(COLOR_CYAN, 12))
	deck_button.pressed.connect(_show_current_deck)
	row.add_child(deck_button)
	var menu := Button.new()
	menu.text = "☰  메뉴"
	_set_button_accessibility(menu, "함선 메뉴", "원정 정보, 편성, 항로, 보상, 상점, 설정을 엽니다")
	menu.custom_minimum_size = Vector2(104, 48)
	menu.add_theme_font_size_override("font_size", 16)
	menu.add_theme_stylebox_override("normal", _panel_style(Color("#14213ddf"), 12, Color("#8aa5d144"), 1, 16, 8))
	menu.add_theme_stylebox_override("hover", _panel_style(COLOR_PANEL_SOFT, 12, COLOR_CYAN, 1, 16, 8))
	menu.add_theme_stylebox_override("focus", _focus_style(COLOR_CYAN, 12))
	menu.pressed.connect(_show_hub)
	row.add_child(menu)
	return panel

func _show_main_menu() -> void:
	_reset_pending_single_plan()
	game_started = false
	_clear_overlay()
	_set_overlay_compact(duel_state == null)
	_set_main_menu_visual(true)
	overlay_close_button.hide()
	overlay_title.text = "STARLINK DUO"
	overlay_subtitle.text = "TACTICAL CO-OP DECKBUILDER  ·  OFFLINE 1–2 PLAYERS"
	var hero := HBoxContainer.new()
	hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero.add_theme_constant_override("separation", 24)
	overlay_content.add_child(hero)
	var actions := VBoxContainer.new()
	actions.custom_minimum_size.x = 500
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 8)
	hero.add_child(actions)
	var eyebrow := Label.new()
	eyebrow.text = "ORBITAL EXPEDITION  /  READY"
	eyebrow.add_theme_font_size_override("font_size", 14)
	eyebrow.add_theme_color_override("font_color", COLOR_CYAN)
	actions.add_child(eyebrow)
	var pitch := Label.new()
	pitch.text = "두 대원의 선택이\n하나의 항로를 바꿉니다"
	pitch.add_theme_font_size_override("font_size", 24)
	pitch.add_theme_color_override("font_color", COLOR_TEXT)
	pitch.add_theme_constant_override("line_spacing", 4)
	actions.add_child(pitch)
	var description := Label.new()
	description.text = "카드를 한 장씩 연결해 세 개의 성계를 돌파하세요."
	description.add_theme_font_size_override("font_size", 15)
	description.add_theme_color_override("font_color", COLOR_MUTED)
	actions.add_child(description)
	if duel_state != null:
		var resume_title := "↻  최근 결투 결과 보기" if duel_state.phase == DuelState.Phase.FINISHED else "▶  결투 이어하기"
		var resume_hint := "P%d 승리 · %d턴" % [duel_state.winner + 1, duel_state.turn] if duel_state.phase == DuelState.Phase.FINISHED and duel_state.winner >= 0 else ("무승부 · %d턴" % duel_state.turn if duel_state.phase == DuelState.Phase.FINISHED else "TURN %02d · P1 %d / P2 %d" % [duel_state.turn, duel_state.health[0], duel_state.health[1]])
		actions.add_child(_main_action_button(resume_title, resume_hint, _resume_saved_duel, COLOR_RED, false))
	var fresh_run := run_coordinator.is_pristine_run()
	var single_title := "▶  싱글플레이 시작"
	var single_hint := "혼자 두 대원을 지휘합니다"
	if not fresh_run:
		single_title = "▶  싱글플레이"
		single_hint = "STAGE %d · 구간 %d/8 · 덱 %d+%d장" % [run_coordinator.run.stage, mini(run_coordinator.run.step + 1, 8), run_coordinator.run.decks[0].size(), run_coordinator.run.decks[1].size()]
	actions.add_child(_main_action_button(single_title, single_hint, _start_singleplayer, COLOR_CYAN, true))
	actions.add_child(_main_action_button("◇  Bluetooth 멀티플레이", "방 만들기 · 참가하기 · 대기실", _show_connection, COLOR_BLUE, false))
	var settings := Button.new()
	settings.text = "⚙  화면 · 조작 설정"
	settings.alignment = HORIZONTAL_ALIGNMENT_LEFT
	settings.custom_minimum_size.y = 48
	settings.add_theme_font_size_override("font_size", 15)
	settings.add_theme_color_override("font_color", COLOR_MUTED)
	settings.add_theme_stylebox_override("normal", _panel_style(Color.TRANSPARENT, 12, Color.TRANSPARENT, 0, 14, 6))
	settings.add_theme_stylebox_override("hover", _panel_style(Color("#ffffff12"), 12, Color.TRANSPARENT, 0, 14, 6))
	settings.add_theme_stylebox_override("focus", _focus_style(COLOR_CYAN, 12))
	_set_button_accessibility(settings, "설정", "화면과 조작 설정을 엽니다")
	settings.pressed.connect(_show_settings)
	actions.add_child(settings)
	version_button = Button.new()
	_refresh_version_button()
	version_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	version_button.custom_minimum_size.y = 48
	version_button.add_theme_font_size_override("font_size", 13)
	version_button.add_theme_stylebox_override("normal", _panel_style(Color.TRANSPARENT, 10, Color.TRANSPARENT, 0, 14, 4))
	version_button.add_theme_stylebox_override("hover", _panel_style(Color("#ffffff12"), 10, Color.TRANSPARENT, 0, 14, 4))
	version_button.add_theme_stylebox_override("focus", _focus_style(COLOR_CYAN, 10))
	version_button.pressed.connect(_show_version_info)
	actions.add_child(version_button)
	hero.add_child(_build_main_menu_art())

func _start_version_check() -> void:
	version_request = HTTPRequest.new()
	version_request.timeout = 8.0
	version_request.request_completed.connect(_on_version_check_completed)
	add_child(version_request)
	var request_error := version_request.request(VERSION_FEED_URL)
	if request_error != OK:
		push_warning("Version check could not start: %s" % error_string(request_error))

func _on_version_check_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		return
	var release := parsed as Dictionary
	if not release.has("version") or not release.has("downloadPageUrl"):
		return
	latest_release = release
	_refresh_version_button()
	if not _is_update_available():
		return
	var config := ConfigFile.new()
	config.load("user://accessibility.cfg")
	var notified_version := str(config.get_value("updates", "notified_version", ""))
	if notified_version == str(latest_release.version):
		return
	if not game_started and overlay.visible and overlay_title.text == "STARLINK DUO":
		_mark_update_notified()
		_show_version_info()

func _refresh_version_button() -> void:
	if version_button == null or not is_instance_valid(version_button):
		return
	if _is_update_available():
		version_button.text = "●  업데이트 v%s  ·  현재 v%s" % [latest_release.version, CURRENT_VERSION]
		version_button.add_theme_color_override("font_color", COLOR_RED)
		_set_button_accessibility(version_button, "새 버전 있음", "버전 %s 업데이트 안내와 다운로드 페이지를 엽니다" % latest_release.version)
	else:
		version_button.text = "ⓘ  VERSION %s" % CURRENT_VERSION
		version_button.add_theme_color_override("font_color", COLOR_MUTED)
		_set_button_accessibility(version_button, "버전 정보", "현재 설치 버전은 %s입니다" % CURRENT_VERSION)

func _is_update_available() -> bool:
	return not latest_release.is_empty() and _compare_versions(str(latest_release.get("version", CURRENT_VERSION)), CURRENT_VERSION) > 0

func _compare_versions(left: String, right: String) -> int:
	var left_parts := left.trim_prefix("v").split(".")
	var right_parts := right.trim_prefix("v").split(".")
	for index in maxi(left_parts.size(), right_parts.size()):
		var left_value := int(left_parts[index]) if index < left_parts.size() else 0
		var right_value := int(right_parts[index]) if index < right_parts.size() else 0
		if left_value != right_value:
			return 1 if left_value > right_value else -1
	return 0

func _show_version_info() -> void:
	_clear_overlay()
	_set_overlay_immersive()
	var update_available := _is_update_available()
	var remote_version := str(latest_release.get("version", CURRENT_VERSION))
	var newest_version := remote_version if update_available else CURRENT_VERSION
	overlay_title.text = "항해 기록"
	overlay_subtitle.text = "함선 시스템 변경 이력  ·  설치 v%s  /  최신 v%s" % [CURRENT_VERSION, newest_version]
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 18)
	overlay_content.add_child(status_row)
	var status := Label.new()
	status.text = "●  신규 항해 데이터 수신" if update_available else "◆  항해 데이터 동기화 완료"
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 17)
	status.add_theme_color_override("font_color", COLOR_RED if update_available else COLOR_CYAN)
	status_row.add_child(status)
	if update_available:
		var download := _action_button("⇩  최신 버전 받기", _open_download_page, COLOR_RED, 52)
		download.custom_minimum_size.x = 250
		status_row.add_child(download)
	var section_label := Label.new()
	section_label.text = "FLIGHT LOG  /  최근 변경"
	section_label.add_theme_font_size_override("font_size", 13)
	section_label.add_theme_color_override("font_color", Color(COLOR_CYAN, 0.78))
	overlay_content.add_child(section_label)
	var history: Array = latest_release.get("releases", RELEASE_HISTORY)
	for release in history:
		var is_latest := str(release.get("version", "")) == newest_version
		if is_latest:
			var latest_notes: Array = release.get("notes", [])
			overlay_subtitle.accessibility_name = "대화상자 안내. 최신 버전 변경 내용: %s" % ", ".join(latest_notes)
		_add_release_log(release, is_latest)
	var navigation := HBoxContainer.new()
	navigation.alignment = BoxContainer.ALIGNMENT_END
	navigation.add_theme_constant_override("separation", 16)
	navigation.add_child(_log_link_button("↗  전체 기록", _open_download_page, COLOR_BLUE))
	navigation.add_child(_log_link_button("←  메인 화면", _show_main_menu, COLOR_MUTED))
	overlay_content.add_child(navigation)

func _add_release_log(release: Dictionary, is_latest: bool) -> void:
	var entry := PanelContainer.new()
	entry.custom_minimum_size.y = 92
	entry.add_theme_stylebox_override("panel", _panel_style(Color(COLOR_CYAN, 0.10) if is_latest else Color("#06101c88"), 16, Color.TRANSPARENT, 0, 0, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	entry.add_child(row)
	var signal_bar := ColorRect.new()
	signal_bar.custom_minimum_size.x = 5
	signal_bar.color = COLOR_CYAN if is_latest else Color("#53617f88")
	signal_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(signal_bar)
	var version := VBoxContainer.new()
	version.custom_minimum_size.x = 184
	version.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(version)
	var version_name := Label.new()
	version_name.text = "v%s%s" % [release.get("version", "-"), "  ·  최신" if is_latest else ""]
	version_name.add_theme_font_size_override("font_size", 18)
	version_name.add_theme_color_override("font_color", COLOR_CYAN if is_latest else COLOR_TEXT)
	version.add_child(version_name)
	var date := Label.new()
	date.text = str(release.get("date", ""))
	date.add_theme_font_size_override("font_size", 12)
	date.add_theme_color_override("font_color", COLOR_MUTED)
	version.add_child(date)
	var notes: Array = release.get("notes", [])
	var note_grid := GridContainer.new()
	note_grid.columns = 2
	note_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_grid.add_theme_constant_override("h_separation", 22)
	note_grid.add_theme_constant_override("v_separation", 6)
	row.add_child(note_grid)
	for note in notes:
		var copy := Label.new()
		copy.text = "◆  %s" % note
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		copy.add_theme_font_size_override("font_size", 13)
		copy.add_theme_color_override("font_color", COLOR_TEXT if is_latest else Color("#c7d0e6"))
		note_grid.add_child(copy)
	entry.accessibility_name = "버전 %s%s" % [release.get("version", "-"), ", 최신 버전" if is_latest else ""]
	entry.accessibility_description = "%s. %s" % [release.get("date", ""), ", ".join(notes)]
	overlay_content.add_child(entry)

func _log_link_button(text_value: String, callback: Callable, accent: Color) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(170, 48)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", accent)
	button.add_theme_stylebox_override("normal", _panel_style(Color.TRANSPARENT, 18, Color.TRANSPARENT, 0, 10, 5))
	button.add_theme_stylebox_override("hover", _panel_style(Color(accent, 0.14), 18, Color.TRANSPARENT, 0, 10, 5))
	button.add_theme_stylebox_override("focus", _focus_style(accent, 18))
	button.pressed.connect(callback)
	return button

func _open_download_page() -> void:
	OS.shell_open(str(latest_release.get("downloadPageUrl", DOWNLOAD_PAGE_URL)))

func _mark_update_notified() -> void:
	var config := ConfigFile.new()
	config.load("user://accessibility.cfg")
	config.set_value("updates", "notified_version", str(latest_release.get("version", "")))
	config.save("user://accessibility.cfg")

func _reset_pending_single_plan() -> void:
	if cooperative_session != null or state == null or state.phase != CombatState.Phase.PLANNING:
		return
	state.plans.clear()
	for player in state.players:
		player.ready = false
	singleplayer_pending_cards.clear()
	selected_hand_indices.clear()
	selected_plays.clear()
	selected_energy = 0
	local_slot = 0

func _resume_saved_duel() -> void:
	if duel_state == null:
		_show_main_menu()
		return
	game_started = true
	game_mode = "duel"
	local_slot = 0
	selected_hand_indices.clear()
	selected_plays.clear()
	selected_energy = 0
	log_label.text = "저장된 결투 결과를 불러왔습니다." if duel_state.phase == DuelState.Phase.FINISHED else "저장된 결투를 이어서 진행합니다."
	_close_overlay()
	_refresh()

func _start_singleplayer() -> void:
	if not run_coordinator.is_pristine_run():
		_show_single_resume_confirmation()
		return
	_continue_singleplayer()

func _show_single_resume_confirmation() -> void:
	_clear_overlay()
	_set_overlay_minimal()
	overlay_title.text = "진행 중인 게임이 있습니다"
	overlay_subtitle.text = "기존 원정을 이어하시겠습니까?"
	var run := run_coordinator.run
	_info_panel("저장된 원정", "STAGE %d · 구간 %d/8 · 팀 내구도 %d/%d\n덱 %d+%d장 · 스타 키 %d개" % [run.stage, mini(run.step + 1, 8), run.team_health, run.team_max_health, run.decks[0].size(), run.decks[1].size(), run.keys.count(true)], COLOR_CYAN)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	var restart := _action_button("↻  새 원정 시작", _confirm_single_reset, COLOR_RED, 64)
	restart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_button_accessibility(restart, "새 원정 시작", "현재 저장된 STAGE %d 원정을 삭제하고 캐릭터 선택부터 다시 시작합니다" % run.stage)
	actions.add_child(restart)
	var resume := _action_button("▶  이어하기", _continue_singleplayer, COLOR_CYAN, 64)
	resume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_button_accessibility(resume, "원정 이어하기", "저장된 STAGE %d 구간 %d부터 계속합니다" % [run.stage, mini(run.step + 1, 8)])
	actions.add_child(resume)
	overlay_content.add_child(actions)

func _continue_singleplayer() -> void:
	var resume_hub := not run_coordinator.can_select_characters()
	game_started = true
	game_mode = "cooperative"
	local_slot = 0
	if cooperative_session != null:
		cooperative_session.close()
		cooperative_session = null
	selected_hand_indices.clear()
	selected_plays.clear()
	selected_energy = 0
	log_label.text = "싱글플레이 · 두 대원을 직접 지휘합니다."
	_close_overlay()
	_refresh()
	if not run_coordinator.run.pending_event.is_empty():
		_show_event.call_deferred()
	elif not resume_hub:
		_show_roster.call_deferred()
	elif resume_hub:
		_show_hub.call_deferred()

func _show_hub() -> void:
	_clear_overlay()
	_set_overlay_immersive()
	overlay_title.text = "일시정지"
	var run := run_coordinator.run
	overlay_subtitle.text = "아스트라이아 항해 기록 · STAGE %d-%02d" % [run.stage, mini(run.step + 1, 8)]
	var next_title := "다음 항로 선택"
	var next_hint := "분기 위험과 보상 확인"
	var next_action: Callable = _show_map
	var next_accent := COLOR_CYAN
	if not run.pending_event.is_empty():
		next_title = "이벤트 선택 계속"
		next_hint = "두 대원의 결정을 완료"
		next_action = _show_event
		next_accent = Color("#bc8cff")
	elif run.phase in ["completed", "failed"]:
		next_title = "원정 결과 확인"
		next_hint = "최종 기록과 덱 보기"
		next_action = _show_map
		next_accent = COLOR_YELLOW if run.phase == "completed" else COLOR_RED
	elif run.phase in ["stage_boss", "true_boss"]:
		next_title = "보스 브리핑"
		next_hint = "진입 전 전력 비교"
		next_action = _show_map
		next_accent = COLOR_RED
	elif run.pending_card_rewards[local_slot]:
		next_title = "카드 보상 선택"
		next_hint = "3장 중 1장 획득"
		next_action = _show_reward
		next_accent = COLOR_YELLOW
	elif run.shop_open[local_slot]:
		next_title = "상점 이용 가능"
		next_hint = "%d C로 덱 정비" % run.gold[local_slot]
		next_action = _show_shop
		next_accent = COLOR_ORANGE
	elif run.pending_routes.size() == 2:
		next_title = "선택 노드 진입"
		next_hint = "P1/P2 항로 선택 완료"
		next_action = _enter_selected_routes
	var mission := VBoxContainer.new()
	mission.alignment = BoxContainer.ALIGNMENT_CENTER
	mission.add_theme_constant_override("separation", 10)
	var mission_callout := Label.new()
	mission_callout.text = "현재 목표"
	mission_callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mission_callout.add_theme_font_size_override("font_size", 13)
	mission_callout.add_theme_color_override("font_color", next_accent)
	mission.add_child(mission_callout)
	var objective := Button.new()
	objective.text = "⌁  %s  ⌁\n%s" % [next_title, next_hint]
	objective.custom_minimum_size = Vector2(560, 82)
	objective.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	objective.add_theme_font_size_override("font_size", 22)
	objective.add_theme_color_override("font_color", COLOR_TEXT)
	objective.add_theme_stylebox_override("normal", _mission_objective_style(next_accent, 0.04, 2))
	objective.add_theme_stylebox_override("hover", _mission_objective_style(next_accent, 0.14, 3))
	objective.add_theme_stylebox_override("pressed", _mission_objective_style(next_accent, 0.24, 4))
	objective.add_theme_stylebox_override("focus", _mission_objective_style(next_accent, 0.10, 4))
	_set_button_accessibility(objective, "현재 목표 · %s" % next_title, "%s. 두 번 탭하여 계속 진행합니다" % next_hint)
	objective.pressed.connect(next_action)
	mission.add_child(objective)
	var voyage_status := Label.new()
	voyage_status.text = "내구도 %d/%d    ✦ 열쇠 %d/3    ◈ %d C" % [run.team_health, run.team_max_health, run.keys.count(true), run.gold[local_slot]]
	voyage_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	voyage_status.add_theme_font_size_override("font_size", 14)
	voyage_status.add_theme_color_override("font_color", COLOR_MUTED)
	mission.add_child(voyage_status)
	overlay_content.add_child(mission)
	var action_strip := HBoxContainer.new()
	action_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	action_strip.add_theme_constant_override("separation", 18)
	overlay_content.add_child(action_strip)
	for item in [["▤  현재 덱", _show_current_deck, COLOR_BLUE], ["◆  대원 편성", _show_roster, COLOR_BLUE], ["⌁  항로 지도", _show_map, COLOR_CYAN], ["✦  전투 보상", _show_reward, COLOR_YELLOW], ["▣  궤도 상점", _show_shop, COLOR_ORANGE], ["＋  유물 · 소비품", _show_consumables, Color("#bc8cff")]]:
		action_strip.add_child(_pause_action_button(item[0], item[1], item[2]))
	var utility_strip := HBoxContainer.new()
	utility_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	utility_strip.add_theme_constant_override("separation", 30)
	for item in [["⚙  화면 · 조작 설정", _show_settings, COLOR_MUTED], ["↻  새 원정 시작", _show_single_reset_confirmation, COLOR_RED], ["←  메인 화면으로", _confirm_return_to_main, COLOR_RED]]:
		var button := _menu_link_button(item[0], item[1], item[2])
		button.custom_minimum_size = Vector2(210, 48)
		utility_strip.add_child(button)
	overlay_content.add_child(utility_strip)
	var crew_strip := HBoxContainer.new()
	crew_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	crew_strip.add_theme_constant_override("separation", 44)
	crew_strip.add_child(_briefing_actor(_character_portrait(run.characters[0]), "P1 · %s" % _character_name(run.characters[0]), _character_role(run.characters[0]), COLOR_BLUE, Vector2(180, 150)))
	var link_status := VBoxContainer.new()
	link_status.custom_minimum_size = Vector2(180, 76)
	link_status.alignment = BoxContainer.ALIGNMENT_CENTER
	var link_icon := Label.new()
	link_icon.text = "⌁  LINK  ⌁"
	link_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	link_icon.add_theme_font_size_override("font_size", 18)
	link_icon.add_theme_color_override("font_color", COLOR_CYAN)
	link_status.add_child(link_icon)
	var link_copy := Label.new()
	link_copy.text = "두 대원 전술 동기화"
	link_copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	link_copy.add_theme_font_size_override("font_size", 13)
	link_copy.add_theme_color_override("font_color", COLOR_MUTED)
	link_status.add_child(link_copy)
	crew_strip.add_child(link_status)
	crew_strip.add_child(_briefing_actor(_character_portrait(run.characters[1]), "P2 · %s" % _character_name(run.characters[1]), _character_role(run.characters[1]), COLOR_ORANGE, Vector2(180, 150)))
	overlay_content.add_child(crew_strip)

func _pause_action_button(text: String, callback: Callable, accent: Color) -> Button:
	var parts := text.split("  ", false, 1)
	var action_name := String(parts[1] if parts.size() > 1 else parts[0]).strip_edges()
	var button := Button.new()
	button.text = "%s\n%s" % [parts[0], parts[1] if parts.size() > 1 else ""]
	button.custom_minimum_size = Vector2(132, 72)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", COLOR_MUTED)
	button.add_theme_stylebox_override("normal", _panel_style(Color.TRANSPARENT, 30, Color.TRANSPARENT, 0, 8, 6))
	button.add_theme_stylebox_override("hover", _panel_style(Color(accent, 0.16), 30, Color.TRANSPARENT, 0, 8, 6))
	button.add_theme_stylebox_override("pressed", _panel_style(Color(accent, 0.28), 30, Color.TRANSPARENT, 0, 8, 6))
	button.add_theme_stylebox_override("focus", _focus_style(accent, 30))
	_set_button_accessibility(button, action_name, "%s 화면을 엽니다" % action_name)
	button.pressed.connect(callback)
	return button

func _mission_objective_style(accent: Color, fill_alpha: float, signal_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent, fill_alpha)
	style.border_color = Color(accent, 0.9)
	style.border_width_left = signal_width
	style.border_width_right = signal_width
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _show_single_reset_confirmation() -> void:
	_clear_overlay()
	_set_overlay_minimal()
	overlay_title.text = "새 원정을 시작할까요?"
	overlay_subtitle.text = "싱글플레이 진행만 초기화합니다. 설정과 최근 2인 결투 기록은 유지됩니다."
	var run := run_coordinator.run
	_info_panel("사라지는 진행", "STAGE %d · 구간 %d/8\n획득 카드 %d장 · 재화 %d C · 스타 키 %d개" % [run.stage, mini(run.step + 1, 8), run.decks[0].size() + run.decks[1].size(), run.gold[0] + run.gold[1], run.keys.count(true)], COLOR_RED)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	var cancel_callback := _show_hub if game_started else _show_main_menu
	var cancel := _action_button("기존 원정 유지", cancel_callback, COLOR_CYAN, 64)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(cancel)
	var reset := _action_button("처음부터 시작", _confirm_single_reset, COLOR_RED, 64)
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(reset)
	overlay_content.add_child(actions)

func _confirm_single_reset() -> void:
	_start_fresh_run()
	game_started = true
	game_mode = "cooperative"
	local_slot = 0
	log_label.text = "새 싱글 원정을 시작했습니다. 두 대원을 편성하세요."
	_show_roster()

func _start_fresh_run() -> void:
	run_coordinator.start_new(int(Time.get_unix_time_from_system()))
	state = _create_training_combat()
	active_route_combat = false
	active_route_types.clear()
	selected_hand_indices.clear()
	selected_plays.clear()
	singleplayer_pending_cards.clear()
	selected_energy = 0
	_refresh_character_identity()

func _create_training_combat() -> CombatState:
	if run_coordinator == null or run_coordinator.run == null:
		return engine.create_demo_combat()
	return engine.create_demo_combat(run_coordinator.run.characters, [
		run_coordinator.starter_deck_for(run_coordinator.run.characters[0]),
		run_coordinator.starter_deck_for(run_coordinator.run.characters[1]),
	])

func _confirm_return_to_main() -> void:
	_clear_overlay()
	_set_overlay_minimal()
	overlay_title.text = "메인 화면으로 돌아가기"
	overlay_subtitle.text = "현재 진행은 마지막 체크포인트에 저장됩니다. Bluetooth 연결은 종료됩니다."
	_info_panel("진행 중인 행동", "아직 확정하지 않은 카드 선택은 취소됩니다. 확정된 전투·보상·상점 결과는 유지됩니다.", COLOR_YELLOW)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	var cancel := _action_button("계속 플레이", _close_overlay, COLOR_CYAN, 64)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(cancel)
	var leave := _action_button("메인 화면으로", _return_to_main_menu, COLOR_RED, 64)
	leave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(leave)
	overlay_content.add_child(actions)

func _return_to_main_menu() -> void:
	if cooperative_session != null:
		cooperative_session.close()
		cooperative_session = null
	elif bluetooth_transport != null:
		bluetooth_transport.close()
	selected_hand_indices.clear()
	selected_plays.clear()
	selected_energy = 0
	_show_main_menu()

func _show_current_deck(requested_slot: int = -1) -> void:
	deck_view_slot = local_slot if requested_slot < 0 else clampi(requested_slot, 0, 1)
	var inspected_slot := deck_view_slot
	_clear_overlay()
	_set_overlay_immersive()
	overlay_title.text = "현재 덱"
	if cooperative_session == null and game_mode != "duel":
		var pilot_switcher := HBoxContainer.new()
		pilot_switcher.alignment = BoxContainer.ALIGNMENT_CENTER
		pilot_switcher.add_theme_constant_override("separation", 24)
		for slot in 2:
			var pilot_button := Button.new()
			var selected := slot == inspected_slot
			pilot_button.text = "%s  P%d · %s" % ["◆" if selected else "◇", slot + 1, _character_name(run_coordinator.run.characters[slot])]
			pilot_button.custom_minimum_size = Vector2(260, 48)
			pilot_button.add_theme_font_size_override("font_size", 15)
			pilot_button.add_theme_color_override("font_color", COLOR_TEXT if selected else COLOR_MUTED)
			pilot_button.add_theme_stylebox_override("normal", _panel_style(Color(_character_color(run_coordinator.run.characters[slot]), 0.20) if selected else Color.TRANSPARENT, 20, Color.TRANSPARENT, 0, 14, 6))
			pilot_button.add_theme_stylebox_override("hover", _panel_style(Color(_character_color(run_coordinator.run.characters[slot]), 0.30), 20, Color.TRANSPARENT, 0, 14, 6))
			pilot_button.add_theme_stylebox_override("focus", _focus_style(_character_color(run_coordinator.run.characters[slot]), 20))
			_set_button_accessibility(pilot_button, "P%d %s 덱%s" % [slot + 1, _character_name(run_coordinator.run.characters[slot]), ", 현재 표시 중" if selected else ""], "이 대원의 현재 덱을 표시합니다")
			pilot_button.pressed.connect(_show_current_deck.bind(slot))
			pilot_switcher.add_child(pilot_button)
		overlay_content.add_child(pilot_switcher)
	var deck: Array = []
	var hand_count := 0
	var draw_count := 0
	var discard_count := 0
	var progression_deck_count := run_coordinator.run.decks[inspected_slot].size()
	if game_mode == "duel" and duel_state != null:
		var player := duel_state.players[inspected_slot]
		deck.append_array(player.draw_pile)
		deck.append_array(player.hand)
		deck.append_array(player.discard_pile)
		hand_count = player.hand.size()
		draw_count = player.draw_pile.size()
		discard_count = player.discard_pile.size()
		progression_deck_count = deck.size()
	elif state != null and state.players.size() > inspected_slot and (active_route_combat or (game_started and run_coordinator.is_pristine_run())):
		var player := state.players[inspected_slot]
		deck.append_array(player.draw_pile)
		deck.append_array(player.hand)
		deck.append_array(player.discard_pile)
		hand_count = player.hand.size()
		draw_count = player.draw_pile.size()
		discard_count = player.discard_pile.size()
	else:
		deck = run_coordinator.run.decks[inspected_slot].duplicate()
	var counts := {}
	for card_id in deck:
		counts[StringName(card_id)] = int(counts.get(StringName(card_id), 0)) + 1
	overlay_subtitle.text = "P%d %s  ·  %d장 / %d종" % [inspected_slot + 1, _character_name(run_coordinator.run.characters[inspected_slot]), deck.size(), counts.size()]
	var total_cost := 0
	var attack_count := 0
	var defense_count := 0
	var support_count := 0
	var tactic_count := 0
	for card_id in deck:
		if catalog.has(StringName(card_id)):
			var deck_card: CardData = catalog[StringName(card_id)]
			total_cost += deck_card.energy_cost
			match _card_tactical_role(deck_card):
				"attack": attack_count += 1
				"defense": defense_count += 1
				"support": support_count += 1
				_: tactic_count += 1
	overlay_subtitle.text = "P%d %s  ·  %d장 / %d종  ·  평균 에너지 %.1f" % [inspected_slot + 1, _character_name(run_coordinator.run.characters[inspected_slot]), deck.size(), counts.size(), float(total_cost) / maxf(float(deck.size()), 1.0)]
	overlay_content.add_child(_game_status_line([
		["⚔", "공격 %d" % attack_count, Color("#ef536c")],
		["⬡", "방어 %d" % defense_count, Color("#4d91ec")],
		["＋", "지원 %d · 1/턴" % support_count, Color("#24b987")],
		["✦", "전술 %d" % tactic_count, Color("#9a70df")],
	]))
	if hand_count + draw_count + discard_count > 0:
		var pile_status := Label.new()
		pile_status.text = "현재 전투   손 %d   ⌁   드로우 %d   ⌁   버림 %d   ·   원정 덱 %d장" % [hand_count, draw_count, discard_count, progression_deck_count]
		pile_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pile_status.add_theme_font_size_override("font_size", 13)
		pile_status.add_theme_color_override("font_color", COLOR_MUTED)
		overlay_content.add_child(pile_status)
	var ids := counts.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 12)
	overlay_content.add_child(grid)
	for card_id in ids:
		if not catalog.has(card_id):
			continue
		var card: CardData = catalog[card_id]
		var preview := preload("res://src/ui/card_button.gd").new()
		preview.custom_minimum_size = Vector2(172, 252)
		var accent := _scope_color(card.owner_scope)
		preview.configure(card, "%s · %s" % [_rarity_label(card.rarity), _scope_label(card.owner_scope)], _effect_summary(card), accent, false, "보유 %d장" % int(counts[card_id]))
		preview.disabled = true
		preview.add_theme_stylebox_override("disabled", _panel_style(Color(accent, 0.14), 22, Color(accent, 0.42), 1, 16, 12))
		grid.add_child(preview)

func _show_quick_chat() -> void:
	_clear_overlay()
	_set_overlay_immersive()
	overlay_title.text = "✉  COMMS LINK"
	overlay_subtitle.text = "동료에게 보낼 전술 신호를 선택하세요"
	var comms_signal := Label.new()
	comms_signal.text = "·  · ─── ◉ ─── ·  ·"
	comms_signal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	comms_signal.add_theme_font_size_override("font_size", 24)
	comms_signal.add_theme_color_override("font_color", COLOR_CYAN)
	overlay_content.add_child(comms_signal)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	overlay_content.add_child(grid)
	for macro_id in ["ready", "wait", "attack", "defend", "nice", "sorry"]:
		var button := _comms_button(macro_id)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(button)

func _comms_button(macro_id: String) -> Button:
	var icons := {"ready": "✓", "wait": "⌛", "attack": "⚔", "defend": "⬡", "nice": "★", "sorry": "…"}
	var accents := {"ready": COLOR_CYAN, "wait": COLOR_YELLOW, "attack": COLOR_RED, "defend": COLOR_BLUE, "nice": COLOR_ORANGE, "sorry": COLOR_MUTED}
	var accent: Color = accents.get(macro_id, COLOR_CYAN)
	var button := Button.new()
	button.text = "%s\n%s" % [icons.get(macro_id, "✉"), _macro_chat_text(macro_id)]
	button.custom_minimum_size = Vector2(250, 112)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_stylebox_override("normal", _panel_style(Color(accent, 0.12), 56, Color.TRANSPARENT, 0, 18, 12))
	button.add_theme_stylebox_override("hover", _panel_style(Color(accent, 0.32), 56, Color.TRANSPARENT, 0, 18, 12))
	button.add_theme_stylebox_override("pressed", _panel_style(Color(accent, 0.46), 56, Color.TRANSPARENT, 0, 18, 12))
	button.add_theme_stylebox_override("focus", _focus_style(accent, 56))
	_set_button_accessibility(button, "%s 메시지" % _macro_chat_text(macro_id), "동료에게 이 메시지를 전송합니다")
	button.pressed.connect(_send_quick_chat.bind(macro_id))
	return button

func _send_quick_chat(macro_id: String) -> void:
	var text := _macro_chat_text(macro_id)
	if cooperative_session == null:
		log_label.text = "빠른 메시지 · %s" % text
		_close_overlay()
		_show_chat_bubble.call_deferred(text, true)
		return
	var result := cooperative_session.send_macro_chat(macro_id)
	if result.ok:
		_play_ui_sound("confirm")
		_close_overlay()
	else:
		overlay_subtitle.text = "전송 실패 · 연결 상태를 확인하세요."
		overlay_subtitle.queue_accessibility_update()
		_play_ui_sound("cancel")
		if haptics_enabled:
			Input.vibrate_handheld(52, 0.38)
		_sync_android_accessibility.call_deferred()

func _on_macro_chat_received(from_slot: int, macro_id: String) -> void:
	var text := _macro_chat_text(macro_id)
	var is_local := from_slot == local_slot
	log_label.text = "%s 메시지 · %s" % ["내" if is_local else "상대", text]
	_show_chat_bubble(text, is_local)

func _show_chat_bubble(text: String, is_local: bool) -> void:
	var index := 0 if is_local else 1
	if chat_bubbles.size() <= index:
		return
	chat_bubble_tokens[index] = int(chat_bubble_tokens[index]) + 1
	var token := int(chat_bubble_tokens[index])
	var bubble := chat_bubbles[index]
	chat_bubble_labels[index].text = "%s  %s" % [text, "◢" if is_local else "◣"]
	bubble.modulate = Color.WHITE
	bubble.show()
	await get_tree().create_timer(4.5).timeout
	if token != int(chat_bubble_tokens[index]) or not is_instance_valid(bubble):
		return
	var tween := bubble.create_tween()
	tween.tween_property(bubble, "modulate:a", 0.0, 0.25)
	await tween.finished
	if token == int(chat_bubble_tokens[index]):
		bubble.hide()

func _macro_chat_text(macro_id: String) -> String:
	return {"ready": "준비됐어요", "wait": "잠시만요", "attack": "공격에 집중해요", "defend": "방어가 필요해요", "nice": "좋아요!", "sorry": "미안해요"}.get(macro_id, macro_id)

func _show_settings() -> void:
	_clear_overlay()
	_set_overlay_immersive()
	overlay_title.text = "SHIP SYSTEMS · 설정"
	overlay_subtitle.text = "연출 강도와 소리·진동을 기기별로 조절합니다. 변경 사항은 이 기기에 자동 저장됩니다."
	_add_setting_toggle("큰 글씨", "앱 기본 확대 115%를 사용합니다. 시스템 글자 크기가 더 크면 안전 레이아웃이 우선합니다.", large_text_enabled, _set_large_text)
	_add_setting_toggle("모션 줄이기", "카드 선택 전환을 즉시 표시해 화면 움직임을 줄입니다.", reduce_motion, _set_reduce_motion)
	_add_setting_toggle("진동 피드백", "카드를 선택하거나 취소할 때 짧은 햅틱 신호를 사용합니다.", haptics_enabled, _set_haptics)
	_add_setting_toggle("효과음", "화면 전환·선택·확정·취소에 짧은 전술 신호음을 사용합니다.", ui_sound_enabled, _set_ui_sound)
	_add_setting_toggle("선택 카드 발광", "선택 카드의 강조 테두리 강도를 높입니다.", glow_enabled, _set_glow)
	_add_settings_note("접근성 적용", "Android 글자 %d%% · HUD %d%% · 터치 48dp 이상 · 색상과 문자로 상태 병기" % [roundi(system_font_scale * 100.0), roundi(_effective_text_scale() * 100.0)], COLOR_CYAN)

func _add_setting_toggle(title: String, description: String, value: bool, callback: Callable) -> void:
	var row := PanelContainer.new()
	row.custom_minimum_size.y = 68
	row.add_theme_stylebox_override("panel", _panel_style(Color.TRANSPARENT, 0, Color.TRANSPARENT, 0, 16, 10))
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	row.add_child(content)
	var marker := Label.new()
	marker.text = "●"
	marker.custom_minimum_size.x = 18
	marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marker.add_theme_font_size_override("font_size", 11)
	marker.add_theme_color_override("font_color", COLOR_CYAN if value else COLOR_MUTED)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(marker)
	var copy := Label.new()
	copy.text = "%s\n%s" % [title, description]
	copy.accessibility_name = title
	copy.accessibility_description = description
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_font_size_override("font_size", 15)
	copy.add_theme_color_override("font_color", COLOR_TEXT)
	content.add_child(copy)
	var toggle := CheckButton.new()
	toggle.text = "켜짐" if value else "꺼짐"
	toggle.button_pressed = value
	toggle.accessibility_name = title
	toggle.accessibility_description = _setting_toggle_accessibility_description(value)
	toggle.custom_minimum_size = Vector2(120, 48)
	toggle.toggled.connect(func(enabled: bool) -> void:
		toggle.text = "켜짐" if enabled else "꺼짐"
		toggle.accessibility_description = _setting_toggle_accessibility_description(enabled)
		callback.call(enabled)
	)
	content.add_child(toggle)
	overlay_content.add_child(row)

func _setting_toggle_accessibility_description(enabled: bool) -> String:
	return "현재 %s. 두 번 탭하여 설정을 변경합니다" % ("켜짐" if enabled else "꺼짐")

func _add_settings_note(title: String, body: String, accent: Color) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 58
	row.add_theme_constant_override("separation", 14)
	var marker := Label.new()
	marker.text = "◆"
	marker.custom_minimum_size.x = 18
	marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marker.add_theme_font_size_override("font_size", 11)
	marker.add_theme_color_override("font_color", accent)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(marker)
	var copy := Label.new()
	copy.text = "%s\n%s" % [title, body]
	copy.accessibility_name = title
	copy.accessibility_description = body
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	copy.add_theme_font_size_override("font_size", 14)
	copy.add_theme_color_override("font_color", COLOR_TEXT)
	row.add_child(copy)
	overlay_content.add_child(row)

func _set_reduce_motion(enabled: bool) -> void:
	reduce_motion = enabled
	_save_accessibility_settings()

func _set_haptics(enabled: bool) -> void:
	haptics_enabled = enabled
	_save_accessibility_settings()

func _set_ui_sound(enabled: bool) -> void:
	ui_sound_enabled = enabled
	_save_accessibility_settings()
	if enabled:
		_play_ui_sound("confirm")

func _set_glow(enabled: bool) -> void:
	glow_enabled = enabled
	_save_accessibility_settings()
	_refresh()

func _set_large_text(enabled: bool) -> void:
	large_text_enabled = enabled
	_save_accessibility_settings()
	_apply_text_scale_tree(self)

func _load_accessibility_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://accessibility.cfg") != OK:
		return
	reduce_motion = bool(config.get_value("presentation", "reduce_motion", false))
	haptics_enabled = bool(config.get_value("presentation", "haptics", true))
	ui_sound_enabled = bool(config.get_value("presentation", "ui_sound", true))
	glow_enabled = bool(config.get_value("presentation", "glow", true))
	large_text_enabled = bool(config.get_value("presentation", "large_text", false))

func _read_system_font_scale() -> void:
	system_font_scale = 1.0
	if not Engine.has_singleton(AndroidBluetoothTransport.PLUGIN_NAME):
		return
	var plugin := Engine.get_singleton(AndroidBluetoothTransport.PLUGIN_NAME)
	if plugin != null:
		system_font_scale = clampf(float(plugin.getSystemFontScale()), 1.0, 2.0)
		print("STARLINK_FONT system=%.2f applied=%.2f" % [system_font_scale, _effective_text_scale()])

func _save_accessibility_settings() -> void:
	var config := ConfigFile.new()
	config.load("user://accessibility.cfg")
	config.set_value("presentation", "reduce_motion", reduce_motion)
	config.set_value("presentation", "haptics", haptics_enabled)
	config.set_value("presentation", "ui_sound", ui_sound_enabled)
	config.set_value("presentation", "glow", glow_enabled)
	config.set_value("presentation", "large_text", large_text_enabled)
	config.save("user://accessibility.cfg")

func _apply_text_scale_tree(node: Node) -> void:
	var scale_factor := _effective_text_scale()
	if node is Label or node is Button:
		var control := node as Control
		if not control.has_meta("base_font_size"):
			control.set_meta("base_font_size", control.get_theme_font_size("font_size"))
		var base_size := int(control.get_meta("base_font_size"))
		control.add_theme_font_size_override("font_size", maxi(1, roundi(base_size * scale_factor)))
	for child in node.get_children():
		_apply_text_scale_tree(child)

func _effective_text_scale() -> float:
	var app_scale := 1.15 if large_text_enabled else 1.0
	var system_safe_scale := 1.0
	# Android may report configured values such as 1.30 as 1.29999995.
	# Keep thresholds tolerant so the matching accessibility tier is not skipped.
	if system_font_scale >= 1.74:
		system_safe_scale = 1.30
	elif system_font_scale >= 1.29:
		system_safe_scale = 1.20
	elif system_font_scale > 1.0:
		system_safe_scale = 1.10
	return maxf(app_scale, system_safe_scale)

func _build_battlefield() -> Control:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 20)
	row.add_child(_build_player_panel("P1  수호자", COLOR_BLUE, 0))
	row.add_child(_build_enemy_panel())
	row.add_child(_build_player_panel("P2  기술자", COLOR_ORANGE, 1))
	return row

func _build_player_panel(title: String, accent: Color, slot: int) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(260, 238)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(Color("#07101f66"), 22, Color(accent, 0.45), 1, 14, 10))
	player_panels.append(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 19)
	title_label.add_theme_color_override("font_color", accent)
	column.add_child(title_label)
	player_title_labels.append(title_label)

	var role := Label.new()
	role.text = "전방 방어 · 아군 엄호" if slot == 0 else "에너지 지원 · 장치 제어"
	role.add_theme_font_size_override("font_size", 13)
	role.add_theme_color_override("font_color", COLOR_MUTED)
	column.add_child(role)
	player_role_labels.append(role)

	var player_stage := Control.new()
	player_stage.custom_minimum_size.y = 128
	player_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(player_stage)
	var status_visual := preload("res://src/ui/player_status_visual.gd").new()
	status_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	status_visual.configure(accent)
	player_stage.add_child(status_visual)
	player_status_visuals.append(status_visual)
	var portrait := TextureRect.new()
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.texture = load("res://assets/art/guardian-portrait.png" if slot == 0 else "res://assets/art/engineer-portrait.png")
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_stage.add_child(portrait)
	player_portraits.append(portrait)
	var status_badge := Label.new()
	status_badge.set_anchor(SIDE_LEFT, 0.18)
	status_badge.set_anchor(SIDE_TOP, 0.78)
	status_badge.set_anchor(SIDE_RIGHT, 0.82)
	status_badge.set_anchor(SIDE_BOTTOM, 0.98)
	status_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_badge.add_theme_font_size_override("font_size", 11)
	status_badge.add_theme_color_override("font_color", Color.WHITE)
	status_badge.add_theme_stylebox_override("normal", _panel_style(Color("#07101fe8"), 14, accent, 2, 8, 3))
	status_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_stage.add_child(status_badge)
	player_status_badges.append(status_badge)

	var detail := Label.new()
	detail.accessibility_name = "P%d 상태" % (slot + 1)
	detail.add_theme_font_size_override("font_size", 14)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_color_override("font_color", COLOR_YELLOW if slot == local_slot else COLOR_TEXT)
	column.add_child(detail)
	player_detail_labels.append(detail)
	return panel

func _build_enemy_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(430, 238)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(Color("#07101f24"), 24, Color("#ff667d33"), 1, 16, 8))
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)

	encounter_label = Label.new()
	encounter_label.text = "일반 전투  ·  훈련 구역 01"
	encounter_label.accessibility_name = "조우 정보"
	encounter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	encounter_label.add_theme_font_size_override("font_size", 13)
	encounter_label.add_theme_color_override("font_color", COLOR_MUTED)
	column.add_child(encounter_label)

	enemy_name_label = Label.new()
	enemy_name_label.text = "훈련 드론"
	enemy_name_label.accessibility_name = "전투 상대"
	enemy_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_name_label.add_theme_font_size_override("font_size", 23)
	enemy_name_label.add_theme_color_override("font_color", COLOR_TEXT)
	column.add_child(enemy_name_label)

	enemy_health_label = Label.new()
	enemy_health_label.accessibility_name = "적 내구도"
	enemy_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_health_label.add_theme_font_size_override("font_size", 14)
	column.add_child(enemy_health_label)
	enemy_health_bar = ProgressBar.new()
	enemy_health_bar.custom_minimum_size.y = 12
	enemy_health_bar.show_percentage = false
	enemy_health_bar.add_theme_stylebox_override("background", _panel_style(Color("#171e38"), 9))
	enemy_health_bar.add_theme_stylebox_override("fill", _panel_style(COLOR_RED, 9))
	column.add_child(enemy_health_bar)
	var enemy_stage := Control.new()
	enemy_stage.custom_minimum_size = Vector2(300, 128)
	enemy_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	enemy_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(enemy_stage)
	enemy_aura = preload("res://src/ui/enemy_visual.gd").new()
	enemy_aura.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	enemy_stage.add_child(enemy_aura)
	enemy_art = TextureRect.new()
	enemy_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	enemy_art.offset_left = -34
	enemy_art.offset_top = -22
	enemy_art.offset_right = 34
	enemy_art.offset_bottom = 22
	enemy_art.texture = load("res://assets/art/rift-sentinel-enemy-v1.png")
	enemy_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	enemy_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	enemy_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	enemy_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_art.accessibility_name = "적 캐릭터"
	enemy_art.accessibility_description = "자홍색 코어와 네 개의 칼날을 지닌 부유 전투체"
	enemy_stage.add_child(enemy_art)
	# Identity arcs stay above the transparent enemy art so stage and formation
	# markers remain visible without replacing the tier silhouette.
	enemy_stage.move_child(enemy_aura, enemy_stage.get_child_count() - 1)

	intent_panel = PanelContainer.new()
	intent_panel.add_theme_stylebox_override("panel", _panel_style(Color("#241221df"), 18, Color("#ff667d88"), 2, 14, 7))
	column.add_child(intent_panel)
	intent_label = Label.new()
	intent_label.accessibility_name = "적의 다음 행동"
	intent_label.text = "⚠  다음 행동 · 팀에 9 피해"
	intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intent_label.add_theme_font_size_override("font_size", 16)
	intent_label.add_theme_color_override("font_color", COLOR_YELLOW)
	intent_panel.add_child(intent_label)
	return panel

func _build_hand_section() -> Control:
	var section := VBoxContainer.new()
	section.custom_minimum_size.y = 225
	section.add_theme_constant_override("separation", 5)

	var status_panel := PanelContainer.new()
	status_panel.add_theme_stylebox_override("panel", _panel_style(Color("#081326dc"), 16, Color("#64e9dd33"), 1, 14, 7))
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 18)
	status_panel.add_child(status_row)

	var health_box := VBoxContainer.new()
	health_box.custom_minimum_size.x = 225
	team_health_label = Label.new()
	team_health_label.accessibility_name = "팀 내구도"
	team_health_label.add_theme_font_size_override("font_size", 14)
	team_health_label.add_theme_color_override("font_color", COLOR_TEXT)
	health_box.add_child(team_health_label)
	team_health_bar = ProgressBar.new()
	team_health_bar.custom_minimum_size.y = 10
	team_health_bar.show_percentage = false
	team_health_bar.add_theme_stylebox_override("background", _panel_style(Color("#171e38"), 8))
	team_health_bar.add_theme_stylebox_override("fill", _panel_style(COLOR_CYAN, 8))
	health_box.add_child(team_health_bar)
	status_row.add_child(health_box)

	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", COLOR_MUTED)
	status_label.accessibility_name = "행동 계획"
	status_label.accessibility_live = AccessibilityServer.LIVE_POLITE
	status_row.add_child(status_label)

	ready_button = Button.new()
	quick_chat_button = Button.new()
	quick_chat_button.text = "✉"
	quick_chat_button.tooltip_text = "빠른 메시지"
	_set_button_accessibility(quick_chat_button, "빠른 메시지", "연결된 동료에게 미리 정한 짧은 메시지를 보냅니다")
	quick_chat_button.custom_minimum_size = Vector2(48, 48)
	quick_chat_button.add_theme_font_size_override("font_size", 24)
	quick_chat_button.add_theme_stylebox_override("normal", _panel_style(Color("#17233de8"), 24, Color.TRANSPARENT, 0, 8, 6))
	quick_chat_button.add_theme_stylebox_override("hover", _panel_style(Color(COLOR_CYAN, 0.22), 24, Color.TRANSPARENT, 0, 8, 6))
	quick_chat_button.add_theme_stylebox_override("focus", _focus_style(COLOR_CYAN, 24))
	quick_chat_button.pressed.connect(_show_quick_chat)
	quick_chat_button.visible = false
	status_row.add_child(quick_chat_button)
	energy_label = Label.new()
	energy_label.accessibility_name = "남은 에너지"
	energy_label.custom_minimum_size = Vector2(82, 48)
	energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	energy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	energy_label.add_theme_font_size_override("font_size", 25)
	energy_label.add_theme_color_override("font_color", COLOR_CYAN)
	status_row.add_child(energy_label)
	ready_button.custom_minimum_size = Vector2(136, 52)
	ready_button.text = "✓  행동 확정"
	_set_button_accessibility(ready_button, "행동 확정", "선택한 카드의 실행을 확정합니다")
	ready_button.add_theme_font_size_override("font_size", 17)
	ready_button.add_theme_stylebox_override("normal", _panel_style(COLOR_CYAN, 26, Color("#d9fffb"), 2, 16, 8))
	ready_button.add_theme_stylebox_override("hover", _panel_style(Color("#76f4e8"), 26, Color.WHITE, 2, 16, 8))
	ready_button.add_theme_stylebox_override("disabled", _panel_style(Color("#34445c"), 26, Color("#77869d"), 1, 16, 8))
	ready_button.add_theme_stylebox_override("focus", _focus_style(COLOR_CYAN, 26))
	ready_button.add_theme_color_override("font_color", COLOR_VOID)
	ready_button.pressed.connect(_on_ready_pressed)
	status_row.add_child(ready_button)
	section.add_child(status_panel)

	var hand_row := HBoxContainer.new()
	hand_row.add_theme_constant_override("separation", 10)
	section.add_child(hand_row)
	draw_pile_badge = preload("res://src/ui/draw_pile_visual.gd").new()
	draw_pile_badge.custom_minimum_size = Vector2(112, 168)
	draw_pile_badge.add_theme_stylebox_override("normal", _panel_style(Color.TRANSPARENT, 18, Color.TRANSPARENT, 0, 4, 4))
	draw_pile_badge.add_theme_stylebox_override("hover", _panel_style(Color(COLOR_CYAN, 0.10), 18, Color.TRANSPARENT, 0, 4, 4))
	draw_pile_badge.add_theme_stylebox_override("focus", _focus_style(COLOR_CYAN, 18))
	draw_pile_badge.pressed.connect(_show_current_deck)
	hand_row.add_child(draw_pile_badge)
	hand_container = HBoxContainer.new()
	hand_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_container.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_container.add_theme_constant_override("separation", -5)
	hand_row.add_child(hand_container)

	log_label = Label.new()
	log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	log_label.add_theme_font_size_override("font_size", 13)
	log_label.add_theme_color_override("font_color", COLOR_MUTED)
	log_label.accessibility_name = "전투 알림"
	log_label.accessibility_live = AccessibilityServer.LIVE_POLITE
	section.add_child(log_label)
	return section

func _build_overlay() -> void:
	overlay = Control.new()
	overlay.accessibility_name = "함선 메뉴 대화상자"
	overlay.accessibility_description = "닫기 버튼 다음에 현재 화면의 행동이 이어집니다"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	add_child(overlay)
	overlay_scrim = ColorRect.new()
	overlay_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_scrim.color = Color("#020713c2")
	overlay_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(overlay_scrim)
	main_menu_backdrop = TextureRect.new()
	main_menu_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_menu_backdrop.texture = load("res://assets/art/orbital-battlefield-v2.png")
	main_menu_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	main_menu_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	main_menu_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_menu_backdrop.visible = false
	overlay.add_child(main_menu_backdrop)
	main_menu_shade = ColorRect.new()
	main_menu_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_menu_shade.color = Color("#020a18a8")
	main_menu_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_menu_shade.visible = false
	overlay.add_child(main_menu_shade)
	overlay_panel = PanelContainer.new()
	overlay_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_panel.offset_left = 150
	overlay_panel.offset_top = 42
	overlay_panel.offset_right = -150
	overlay_panel.offset_bottom = -42
	overlay_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_panel.add_theme_stylebox_override("panel", _panel_style(Color("#0c1730fa"), 28, Color("#55e8dc88"), 1, 28, 22))
	overlay.add_child(overlay_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	overlay_panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	overlay_title = Label.new()
	overlay_title.add_theme_font_size_override("font_size", 28)
	overlay_title.add_theme_color_override("font_color", COLOR_TEXT)
	overlay_title.accessibility_name = "대화상자 제목"
	overlay_title.accessibility_live = AccessibilityServer.LIVE_ASSERTIVE
	titles.add_child(overlay_title)
	overlay_subtitle = Label.new()
	overlay_subtitle.add_theme_font_size_override("font_size", 16)
	overlay_subtitle.add_theme_color_override("font_color", COLOR_MUTED)
	overlay_subtitle.accessibility_name = "대화상자 안내"
	overlay_subtitle.accessibility_live = AccessibilityServer.LIVE_POLITE
	overlay_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(overlay_subtitle)
	overlay_close_button = Button.new()
	overlay_close_button.text = "×  닫기"
	_set_button_accessibility(overlay_close_button, "닫기", "이전 화면으로 돌아갑니다")
	overlay_close_button.custom_minimum_size = Vector2(104, 48)
	overlay_close_button.add_theme_stylebox_override("normal", _panel_style(Color("#192541"), 24, Color("#91a5c655"), 1, 16, 8))
	overlay_close_button.add_theme_stylebox_override("focus", _focus_style(COLOR_CYAN, 24))
	overlay_close_button.pressed.connect(_close_overlay)
	header.add_child(overlay_close_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	overlay_content = VBoxContainer.new()
	overlay_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay_content.add_theme_constant_override("separation", 12)
	scroll.add_child(overlay_content)

func _show_mode() -> void:
	_clear_overlay()
	_set_overlay_compact(true, true)
	overlay_title.text = "플레이 모드"
	overlay_subtitle.text = "하나의 앱에서 협동 원정과 2인 결투를 선택합니다. Bluetooth 연결 시 호스트가 모드를 확정합니다."
	var mode_row := HBoxContainer.new()
	mode_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mode_row.add_theme_constant_override("separation", 18)
	overlay_content.add_child(mode_row)
	var expedition := _action_button("협동 원정\n\n두 대원이 하나의 항로를 완주합니다\n공동 체력 · 역할 조합 · 덱 성장\n\n3 STAGES  ·  45–60 MIN", _activate_mode.bind("cooperative"), COLOR_CYAN, 170)
	expedition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_row.add_child(expedition)
	var duel := _action_button("2인 결투\n\n같은 조건에서 전술을 겨룹니다\n개별 내구도 · 비공개 동시 계획\n\n36 HP  ·  FAIR DECK", _activate_mode.bind("duel"), COLOR_RED, 170)
	duel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_row.add_child(duel)
	_add_connection_action("Bluetooth 연결 설정", _show_connection, COLOR_BLUE)

func _activate_mode(mode: String) -> void:
	if cooperative_session != null and cooperative_session.role == CooperativeSession.Role.GUEST:
		overlay_subtitle.text = "모드는 호스트가 선택합니다. 호스트의 확정을 기다려 주세요."
		return
	game_mode = mode
	if cooperative_session != null:
		var network_result := cooperative_session.set_game_mode(mode)
		if not network_result.ok:
			overlay_subtitle.text = "모드를 변경하지 못했습니다: %s" % network_result.error
			return
	if mode == "duel":
		duel_engine = DuelEngine.new(catalog)
		duel_state = cooperative_session.duel_state if cooperative_session != null else duel_engine.create_duel(run_coordinator.run.characters, [
			run_coordinator.starter_deck_for(run_coordinator.run.characters[0]),
			run_coordinator.starter_deck_for(run_coordinator.run.characters[1]),
		])
		local_slot = 0 if cooperative_session == null else local_slot
		duel_save_store.save(duel_state)
		log_label.text = "2인 결투 시작 · 두 플레이어가 행동을 확정하면 동시에 해결됩니다."
	else:
		duel_save_store.clear()
		duel_state = null
		duel_engine = null
		state = _create_training_combat() if not active_route_combat else state
		log_label.text = "협동 원정 모드 · 공동 체력과 항로 진행을 공유합니다."
	selected_hand_indices.clear()
	selected_plays.clear()
	selected_energy = 0
	_close_overlay()
	_refresh()

func _clear_overlay() -> void:
	in_multiplayer_lobby = false
	lobby_preview_active = false
	_set_overlay_compact(false)
	if overlay_scrim != null:
		overlay_scrim.color = Color("#020713ff") if not game_started else Color("#020713c2")
	_set_main_menu_visual(false)
	if overlay_close_button != null:
		overlay_close_button.show()
		overlay_close_button.add_theme_stylebox_override("normal", _panel_style(Color("#192541"), 24, Color.TRANSPARENT, 0, 16, 8))
		overlay_close_button.add_theme_stylebox_override("hover", _panel_style(Color("#24365a"), 24, Color.TRANSPARENT, 0, 16, 8))
	if not overlay.visible:
		previous_focus_owner = get_viewport().gui_get_focus_owner()
		background_focus_modes.clear()
		_set_background_focus_enabled(self, false)
	for child in overlay_content.get_children():
		child.queue_free()
	overlay.show()
	_animate_overlay_in.call_deferred()
	overlay.queue_accessibility_update()
	_focus_first_overlay_control.call_deferred()
	_apply_text_scale_tree.call_deferred(overlay)
	_sync_android_accessibility.call_deferred()

func _set_overlay_compact(compact: bool, dense: bool = false) -> void:
	if overlay_panel == null:
		return
	overlay_panel.offset_left = 150
	overlay_panel.offset_right = -150
	if not compact:
		overlay_panel.offset_top = 42
		overlay_panel.offset_bottom = -42
	else:
		overlay_panel.offset_top = 92 if dense else 65
		overlay_panel.offset_bottom = -218 if dense else -115

func _set_overlay_minimal() -> void:
	if overlay_panel == null:
		return
	overlay_panel.offset_left = 150
	overlay_panel.offset_right = -150
	var enlarged_text := _effective_text_scale() >= 1.20
	overlay_panel.offset_top = 90 if enlarged_text else 112
	overlay_panel.offset_bottom = -230 if enlarged_text else -300

func _set_overlay_balanced() -> void:
	if overlay_panel == null:
		return
	overlay_panel.offset_left = 150
	overlay_panel.offset_right = -150
	overlay_panel.offset_top = 72
	overlay_panel.offset_bottom = -148

func _set_overlay_tall() -> void:
	if overlay_panel == null:
		return
	overlay_panel.offset_left = 150
	overlay_panel.offset_right = -150
	overlay_panel.offset_top = 54
	overlay_panel.offset_bottom = -66

func _destructive_confirm_needs_tall_layout() -> bool:
	return _effective_text_scale() >= 1.20

func _set_overlay_immersive() -> void:
	if overlay_panel == null:
		return
	main_menu_backdrop.visible = true
	main_menu_shade.visible = true
	main_menu_shade.color = Color("#020a18c9")
	overlay_panel.offset_left = 96
	overlay_panel.offset_right = -96
	overlay_panel.offset_top = 26
	overlay_panel.offset_bottom = -34
	overlay_panel.add_theme_stylebox_override("panel", _panel_style(Color.TRANSPARENT, 0, Color.TRANSPARENT, 0, 24, 18))
	overlay_scrim.color = Color.TRANSPARENT
	overlay_close_button.add_theme_stylebox_override("normal", _panel_style(Color.TRANSPARENT, 0, Color.TRANSPARENT, 0, 12, 6))
	overlay_close_button.add_theme_stylebox_override("hover", _panel_style(Color("#ffffff12"), 14, Color.TRANSPARENT, 0, 12, 6))
	overlay_close_button.add_theme_stylebox_override("focus", _main_menu_choice_style(COLOR_CYAN, 0.10, 3))

func _set_main_menu_visual(enabled: bool) -> void:
	if overlay_panel == null or overlay_scrim == null or main_menu_backdrop == null or main_menu_shade == null:
		return
	main_menu_backdrop.visible = enabled
	main_menu_shade.visible = enabled
	if enabled:
		overlay_scrim.color = Color.TRANSPARENT
		overlay_panel.add_theme_stylebox_override("panel", _panel_style(Color.TRANSPARENT, 0, Color.TRANSPARENT, 0, 30, 24))
	else:
		overlay_panel.add_theme_stylebox_override("panel", _panel_style(Color("#0c1730fa"), 28, Color.TRANSPARENT, 0, 28, 22))

func _close_overlay() -> void:
	if overlay_title.text == "훈련 전투 완료":
		_return_to_main_menu()
		return
	if not game_started:
		if in_multiplayer_lobby and cooperative_session != null:
			cooperative_session.close()
			cooperative_session = null
			_show_main_menu()
			return
	if reduce_motion:
		_finish_close_overlay()
		return
	if overlay_transition != null and overlay_transition.is_valid():
		overlay_transition.kill()
	overlay_panel.pivot_offset = overlay_panel.size * 0.5
	overlay_transition = create_tween().set_parallel(true)
	overlay_transition.tween_property(overlay_panel, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	overlay_transition.tween_property(overlay_panel, "scale", Vector2(0.985, 0.985), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	overlay_transition.chain().tween_callback(_finish_close_overlay)

func _animate_overlay_in() -> void:
	if overlay_panel == null or not overlay.visible:
		return
	if overlay_transition != null and overlay_transition.is_valid():
		overlay_transition.kill()
	overlay_panel.pivot_offset = overlay_panel.size * 0.5
	if reduce_motion:
		overlay_panel.modulate.a = 1.0
		overlay_panel.scale = Vector2.ONE
		return
	overlay_panel.modulate.a = 0.0
	overlay_panel.scale = Vector2(0.985, 0.985)
	overlay_transition = create_tween().set_parallel(true)
	overlay_transition.tween_property(overlay_panel, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	overlay_transition.tween_property(overlay_panel, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_play_ui_sound("open")

func _finish_close_overlay() -> void:
	overlay.hide()
	overlay_panel.modulate.a = 1.0
	overlay_panel.scale = Vector2.ONE
	for control in background_focus_modes:
		if is_instance_valid(control):
			control.focus_mode = background_focus_modes[control]
	background_focus_modes.clear()
	if is_instance_valid(previous_focus_owner) and previous_focus_owner.is_visible_in_tree():
		previous_focus_owner.grab_focus()
	previous_focus_owner = null
	_sync_android_accessibility.call_deferred()

func _sync_android_accessibility() -> void:
	if accessibility_bridge == null or accessibility_sync_pending:
		return
	accessibility_sync_pending = true
	await get_tree().process_frame
	await get_tree().process_frame
	accessibility_sync_pending = false
	accessibility_bridge.sync(overlay if overlay != null and overlay.visible else self)

func _set_background_focus_enabled(node: Node, enabled: bool) -> void:
	for child in node.get_children():
		if child == overlay:
			continue
		if child is Control:
			var control := child as Control
			if enabled:
				if background_focus_modes.has(control):
					control.focus_mode = background_focus_modes[control]
			elif control.focus_mode != Control.FOCUS_NONE:
				background_focus_modes[control] = control.focus_mode
				control.focus_mode = Control.FOCUS_NONE
		_set_background_focus_enabled(child, enabled)

func _focus_first_overlay_control() -> void:
	if not overlay.visible:
		return
	# Start inside the screen content so opening a menu emphasizes its first
	# meaningful choice instead of making the persistent close affordance look
	# like the primary action. The close button remains the keyboard fallback.
	var controls := overlay_content.find_children("*", "Button", true, false)
	for candidate in controls:
		var button := candidate as Button
		if button != null and button.visible and not button.disabled:
			button.grab_focus()
			return
	if overlay_close_button.visible and not overlay_close_button.disabled:
		overlay_close_button.grab_focus()

func _show_connection() -> void:
	_clear_overlay()
	_set_overlay_immersive()
	overlay_title.text = "멀티플레이 · 방 만들기 / 참가하기"
	var protocol := Label.new()
	protocol.text = "LINK PROTOCOL   01 BLUETOOTH  ›  02 ROLE  ›  03 VERIFY     ·     %s" % GameCompatibility.code()
	protocol.add_theme_font_size_override("font_size", 14)
	protocol.add_theme_color_override("font_color", COLOR_CYAN)
	overlay_content.add_child(protocol)
	if not Engine.has_singleton(AndroidBluetoothTransport.PLUGIN_NAME):
		overlay_subtitle.text = "현재 환경에는 Android Bluetooth 플러그인이 없어 로컬 데모로 실행 중입니다."
		_add_connection_briefing("ANDROID DEVICE REQUIRED", "APK를 Android 12 이상 Galaxy에서 실행하면 방 만들기와 참가하기가 활성화됩니다.", COLOR_YELLOW)
		return
	if not bluetooth_transport.is_enabled():
		overlay_subtitle.text = "Bluetooth가 꺼져 있습니다. 빠른 설정에서 Bluetooth를 켠 뒤 새로고침하세요."
		_add_connection_briefing("비행기 안에서 연결하기", "01  비행기 모드는 유지\n02  빠른 설정에서 Bluetooth만 켜기\n03  Android 설정에서 두 Galaxy를 페어링", COLOR_CYAN)
		_add_connection_action("상태 새로고침", _show_connection, COLOR_YELLOW)
		return
	if not bluetooth_transport.has_permissions():
		overlay_subtitle.text = "주변 기기 권한이 필요합니다. 위치 정보는 수집하지 않습니다."
		_add_connection_briefing("주변 기기 권한", "Bluetooth 연결에만 사용합니다. 위치 정보와 인터넷 연결은 사용하지 않습니다.", COLOR_BLUE)
		_add_connection_action("주변 기기 권한 허용", _request_bluetooth_permissions, COLOR_CYAN)
		return
	overlay_subtitle.text = "방장은 방을 만들고, 참가자는 페어링된 방장의 기기를 선택하세요. 연결되면 대기실로 이동합니다."
	var roles := HBoxContainer.new()
	roles.add_theme_constant_override("separation", 16)
	roles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay_content.add_child(roles)
	var host_button := _action_button("①  방 만들기\n이 기기가 판정하고 참가자를 기다립니다", _start_bluetooth_host, COLOR_BLUE, 108)
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_button.tooltip_text = "연결을 기다리며 전투 결과를 판정합니다."
	roles.add_child(host_button)
	var join_column := VBoxContainer.new()
	join_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_column.add_theme_constant_override("separation", 8)
	roles.add_child(join_column)
	var join_title := Label.new()
	join_title.text = "②  참가하기\n페어링된 방장의 기기를 선택합니다"
	join_title.add_theme_font_size_override("font_size", 16)
	join_title.add_theme_color_override("font_color", COLOR_ORANGE)
	join_column.add_child(join_title)
	var paired := bluetooth_transport.get_paired_devices()
	if paired.is_empty():
		var empty := Label.new()
		empty.text = "페어링된 기기 없음\nAndroid 설정에서 상대 Galaxy를 먼저 페어링하세요."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", COLOR_MUTED)
		join_column.add_child(empty)
	else:
		for device in paired:
			var label := "%s\n%s" % [device.name, device.address]
			var device_button := _action_button(label, _join_bluetooth_host.bind(device.address), COLOR_ORANGE, 72)
			device_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			join_column.add_child(device_button)
	_add_connection_briefing("연결 전 확인", "두 기기에 같은 APK가 필요합니다. 연결 뒤 12자리 호환 코드가 일치하면 방장이 게임을 시작합니다.", COLOR_CYAN)

func _add_connection_briefing(title: String, body: String, accent: Color) -> void:
	var briefing := VBoxContainer.new()
	briefing.add_theme_constant_override("separation", 6)
	briefing.add_theme_constant_override("margin_left", 18)
	var heading := Label.new()
	heading.text = "◆  %s" % title
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", accent)
	briefing.add_child(heading)
	var description := Label.new()
	description.text = body
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", 15)
	description.add_theme_color_override("font_color", COLOR_TEXT)
	briefing.add_child(description)
	overlay_content.add_child(briefing)

func _request_bluetooth_permissions() -> void:
	bluetooth_transport.request_permissions()
	overlay_subtitle.text = "권한 요청을 보냈습니다. 허용 후 상태 새로고침을 누르세요."
	_add_connection_action("상태 새로고침", _show_connection, COLOR_CYAN)
	_sync_android_accessibility.call_deferred()
	for attempt in 20:
		await get_tree().create_timer(0.5).timeout
		if not overlay.visible:
			return
		if bluetooth_transport.has_permissions():
			_show_connection()
			return

func _start_bluetooth_host() -> void:
	if bluetooth_transport.start_host(SERVICE_UUID):
		local_slot = 0
		if cooperative_session == null or cooperative_session.role != CooperativeSession.Role.HOST:
			cooperative_session = CooperativeSession.new(CooperativeSession.Role.HOST, bluetooth_transport, engine, state, run_coordinator, duel_save_store)
			cooperative_session.session_error.connect(_on_session_error)
			if game_mode == "duel" and duel_state != null:
				cooperative_session.game_mode = "duel"
				cooperative_session.duel_engine = DuelEngine.new(catalog)
				cooperative_session.duel_state = duel_state
			else:
				cooperative_session.set_game_mode(game_mode)
		_bind_session_ui_signals()
		_show_multiplayer_lobby()
	else:
		overlay_subtitle.text = "방을 만들지 못했습니다. 권한과 Bluetooth 상태를 확인하세요."

func _join_bluetooth_host(address: String) -> void:
	if bluetooth_transport.connect_to(address, SERVICE_UUID):
		local_slot = 1
		if cooperative_session == null or cooperative_session.role != CooperativeSession.Role.GUEST:
			cooperative_session = CooperativeSession.new(CooperativeSession.Role.GUEST, bluetooth_transport, null, null, null, duel_save_store)
			cooperative_session.snapshot_received.connect(_on_remote_snapshot)
			cooperative_session.run_snapshot_received.connect(_on_remote_run_snapshot)
			cooperative_session.duel_snapshot_received.connect(_on_remote_duel_snapshot)
			cooperative_session.game_mode_changed.connect(_on_remote_game_mode)
			cooperative_session.session_error.connect(_on_session_error)
		_bind_session_ui_signals()
		_show_multiplayer_lobby()
	else:
		overlay_subtitle.text = "연결을 시작하지 못했습니다. 페어링 상태를 확인하세요."

func _bind_session_ui_signals() -> void:
	if cooperative_session == null:
		return
	if not cooperative_session.game_started.is_connected(_on_multiplayer_game_started):
		cooperative_session.game_started.connect(_on_multiplayer_game_started)
	if not cooperative_session.macro_chat_received.is_connected(_on_macro_chat_received):
		cooperative_session.macro_chat_received.connect(_on_macro_chat_received)
	if not cooperative_session.run_reset_requested.is_connected(_on_multiplayer_reset_requested):
		cooperative_session.run_reset_requested.connect(_on_multiplayer_reset_requested)
	if not cooperative_session.run_reset_response_received.is_connected(_on_multiplayer_reset_response):
		cooperative_session.run_reset_response_received.connect(_on_multiplayer_reset_response)
	if not cooperative_session.run_reset_approved.is_connected(_on_multiplayer_reset_approved):
		cooperative_session.run_reset_approved.connect(_on_multiplayer_reset_approved)

func _show_multiplayer_lobby(preview: Dictionary = {}) -> void:
	_clear_overlay()
	_set_overlay_compact(true)
	in_multiplayer_lobby = true
	lobby_preview_active = not preview.is_empty()
	overlay_title.text = "멀티플레이 대기실"
	var is_host := bool(preview.get("is_host", cooperative_session != null and cooperative_session.role == CooperativeSession.Role.HOST))
	var transport_state := String(preview.get("transport_state", bluetooth_transport.get_state()))
	var verified := bool(preview.get("verified", cooperative_session != null and cooperative_session.handshake_complete))
	var handshake_failed := bool(preview.get("handshake_failed", cooperative_session != null and cooperative_session.handshake_failed))
	if handshake_failed or transport_state == "error":
		_set_overlay_compact(false)
	lobby_signature = "%s:%s:%s" % [transport_state, verified, handshake_failed]
	overlay_subtitle.text = "참가자를 기다리는 중입니다. 이 화면을 유지하세요." if is_host and not verified else ("방장에게 연결하는 중입니다. 이 화면을 유지하세요." if not verified else "두 기기의 연결과 콘텐츠 호환성 확인이 완료되었습니다.")
	var steps := HBoxContainer.new()
	steps.add_theme_constant_override("separation", 8)
	steps.add_child(_status_chip("1  방 생성" if is_host else "1  방 참가", COLOR_BLUE))
	steps.add_child(_status_chip("✓  연결 확인" if verified else "2  연결 확인", COLOR_CYAN if verified else COLOR_MUTED))
	steps.add_child(_status_chip("3  방장 시작", COLOR_ORANGE))
	overlay_content.add_child(steps)
	var stations := HBoxContainer.new()
	stations.add_theme_constant_override("separation", 14)
	stations.add_child(_lobby_player_card("P1 · 방장", "연결 완료" if verified else "참가자 기다리는 중", run_coordinator.run.characters[0], COLOR_BLUE, verified or is_host))
	stations.add_child(_lobby_player_card("P2 · 참가자", "호환 확인 완료" if verified else "방장에게 연결 중", run_coordinator.run.characters[1], COLOR_ORANGE, verified))
	overlay_content.add_child(stations)
	_info_panel("대기실 상태", "%s\n역할 · %s\n호환 코드 · %s" % [_connection_status_text(), "방장" if is_host else "참가자", GameCompatibility.code()], COLOR_CYAN if verified else COLOR_BLUE)
	if handshake_failed:
		_info_panel("입장 실패", "두 기기에 같은 버전의 APK를 설치한 뒤 다시 연결하세요.", COLOR_RED)
		_add_connection_action("↻  연결 다시 설정", _reset_multiplayer_connection, COLOR_RED)
		return
	if transport_state == "error":
		_info_panel("연결 오류", "Bluetooth 상태와 페어링을 확인한 뒤 방 만들기 또는 참가를 다시 선택하세요.", COLOR_RED)
		_add_connection_action("↻  연결 다시 설정", _reset_multiplayer_connection, COLOR_RED)
		return
	if not verified:
		_info_panel("대기 중", "방장은 이 화면에서 기다리고, 참가자는 방장의 기기를 선택해야 합니다. 연결 중에는 앱을 닫지 마세요.", COLOR_YELLOW)
		return
	if is_host:
		var modes := HBoxContainer.new()
		modes.add_theme_constant_override("separation", 12)
		modes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		overlay_content.add_child(modes)
		var expedition := _action_button("협동 원정 시작\n공동 체력 · 역할 조합", _start_multiplayer_game.bind("cooperative"), COLOR_CYAN, 96)
		expedition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		modes.add_child(expedition)
		var duel := _action_button("2인 결투 시작\n비공개 동시 계획", _start_multiplayer_game.bind("duel"), COLOR_RED, 96)
		duel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		modes.add_child(duel)
	else:
		_info_panel("방장 선택 대기", "방장이 협동 원정 또는 2인 결투를 선택하면 두 기기가 함께 게임으로 이동합니다.", COLOR_ORANGE)
	_add_connection_action("↻  원정 초기화 요청", _request_multiplayer_reset, COLOR_RED)

func _request_multiplayer_reset() -> void:
	if cooperative_session == null:
		return
	var result := cooperative_session.request_run_reset()
	if not result.ok:
		overlay_subtitle.text = "초기화를 요청하지 못했습니다: %s" % result.error
		return
	_clear_overlay()
	_set_overlay_minimal()
	overlay_title.text = "상대 동의 대기 중"
	overlay_subtitle.text = "상대가 승인하기 전에는 어떤 진행 데이터도 삭제되지 않습니다."
	_info_panel("초기화 요청 전송됨", "상대 기기에서 승인 또는 거절을 선택해야 합니다. 연결이 끊기면 기존 원정이 유지됩니다.", COLOR_YELLOW)

func _on_multiplayer_reset_requested(requester_slot: int) -> void:
	_clear_overlay()
	_set_overlay_minimal()
	overlay_close_button.hide()
	overlay_title.text = "P%d가 초기화를 요청했습니다" % [requester_slot + 1]
	overlay_subtitle.text = "승인하면 양쪽의 현재 협동 원정이 새 원정으로 교체됩니다."
	_info_panel("공동 동의 필요", "거절하면 현재 체크포인트와 덱, 보상, 재화가 모두 그대로 유지됩니다.", COLOR_RED)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	var decline := _action_button("거절 · 진행 유지", _respond_multiplayer_reset.bind(false), COLOR_CYAN, 64)
	decline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(decline)
	var accept := _action_button("동의 · 처음부터", _respond_multiplayer_reset.bind(true), COLOR_RED, 64)
	accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(accept)
	overlay_content.add_child(actions)

func _respond_multiplayer_reset(accepted: bool) -> void:
	if cooperative_session == null:
		_show_connection()
		return
	var result := cooperative_session.respond_run_reset(accepted)
	if not result.ok:
		overlay_subtitle.text = "응답을 보내지 못했습니다: %s" % result.error
		return
	_show_multiplayer_lobby()
	overlay_subtitle.text = "초기화에 동의했습니다. 새 원정을 동기화하는 중입니다." if accepted else "초기화를 거절했습니다. 기존 원정을 유지합니다."

func _on_multiplayer_reset_response(accepted: bool, _responder_slot: int) -> void:
	_show_multiplayer_lobby()
	overlay_subtitle.text = "상대가 동의했습니다. 새 원정을 동기화합니다." if accepted else "상대가 초기화를 거절했습니다. 기존 원정을 유지합니다."

func _on_multiplayer_reset_approved() -> void:
	if cooperative_session == null or cooperative_session.role != CooperativeSession.Role.HOST:
		return
	game_mode = "cooperative"
	_start_fresh_run()
	cooperative_session.set_game_mode("cooperative")
	cooperative_session.replace_combat_state(state)
	cooperative_session.publish_run_state("consensual_reset")
	_show_multiplayer_lobby()
	overlay_subtitle.text = "양쪽 동의 완료 · 새 원정이 생성되었습니다. 대원을 다시 편성하세요."

func _debug_lobby_preview() -> Dictionary:
	if not OS.is_debug_build():
		return {}
	for argument in OS.get_cmdline_args():
		if not argument.begins_with("--ui-preview="):
			continue
		match argument.trim_prefix("--ui-preview="):
			"host_waiting": return {"is_host": true, "transport_state": "listening", "verified": false, "handshake_failed": false}
			"guest_verified": return {"is_host": false, "transport_state": "connected", "verified": true, "handshake_failed": false}
			"incompatible": return {"is_host": true, "transport_state": "connected", "verified": false, "handshake_failed": true}
			"transport_error": return {"is_host": false, "transport_state": "error", "verified": false, "handshake_failed": false}
	return {}

func _debug_ui_preview_name() -> String:
	if not OS.is_debug_build():
		return ""
	for argument in OS.get_cmdline_args():
		if argument.begins_with("--ui-preview="):
			return argument.trim_prefix("--ui-preview=")
	return ""

func _show_debug_ui_preview(preview_name: String) -> void:
	if preview_name == "gallery":
		for gallery_screen in ["settings", "version_update", "roster", "map", "deck", "hub", "quick_chat", "reward", "shop", "remove_card_picker", "remove_card_confirm", "event", "route_result", "training_victory", "run_victory", "run_failed", "consumables"]:
			_show_debug_ui_preview(gallery_screen)
			print("STARLINK_UI_PREVIEW %s" % gallery_screen)
			await get_tree().create_timer(2.0).timeout
		return
	game_started = true
	game_mode = "cooperative"
	local_slot = 0
	var run := run_coordinator.run
	match preview_name:
		"settings":
			game_started = false
			_show_settings()
		"version_update":
			game_started = false
			var preview_releases: Array = [{"version": "0.1.5", "date": "2026.09.06", "notes": ["큰 글씨 확인창 개선", "메뉴 포커스 순서 개선", "빠른 메시지 레이아웃 검증"]}]
			preview_releases.append_array(RELEASE_HISTORY)
			latest_release = {"version": "0.1.5", "downloadPageUrl": DOWNLOAD_PAGE_URL, "releases": preview_releases}
			_show_version_info()
		"quick_chat":
			game_started = true
			game_mode = "cooperative"
			_show_quick_chat()
		"remove_card_picker":
			game_started = true
			game_mode = "cooperative"
			local_slot = 0
			run.gold[local_slot] = 100
			_show_remove_card_picker(35)
		"remove_card_confirm":
			game_started = true
			game_mode = "cooperative"
			local_slot = 0
			run.gold[local_slot] = 100
			_show_remove_card_confirmation(0, 35)
		"connection":
			game_started = false
			_show_connection()
		"combat":
			active_route_combat = false
			state = _create_training_combat()
			_finish_close_overlay()
			_refresh()
		"roster":
			run.phase = "traversal"
			run.stage = 1
			run.step = 0
			run.pending_routes.clear()
			_show_roster()
		"map":
			run.phase = "traversal"
			run.stage = 1
			run.step = 0
			run.pending_routes.clear()
			_show_map()
		"map_branch":
			run.phase = "traversal"
			run.stage = 1
			run.step = 1
			run.pending_routes.clear()
			_show_map()
		"single_resume":
			game_started = false
			run.phase = "traversal"
			run.stage = 2
			run.step = 3
			run.team_health = 52
			run.keys = [true, false, false]
			_show_single_resume_confirmation()
		"deck":
			_show_current_deck()
		"hub":
			_show_hub()
		"reward":
			run.pending_card_rewards[0] = true
			_show_reward()
		"shop":
			run.gold[0] = maxi(run.gold[0], 200)
			run.shop_open[0] = true
			_show_shop()
		"event":
			var content := RunContentCatalog.build()
			var event: Dictionary = content.events[0]
			run.pending_event = {"id": event.id, "route_types": ["event", "rest"], "votes": {}}
			_show_event()
		"route_result":
			_show_route_result("항로 전투 승리", "두 대원의 연계로 전투를 마쳤습니다. 각 플레이어 +35 C")
		"training_victory":
			state.phase = CombatState.Phase.WON
			state.turn = 4
			state.team_health = 56
			_show_training_victory()
		"run_victory":
			run.phase = "completed"
			run.stage = 3
			run.step = 8
			run.keys = [true, true, true]
			_show_run_outcome(true)
		"run_failed":
			run.phase = "failed"
			run.stage = 2
			run.step = 5
			run.keys = [true, false, false]
			_show_run_outcome(false)
		"consumables":
			var content := RunContentCatalog.build()
			run.consumables[0] = [content.consumables[0].id, content.consumables[1].id]
			_show_consumables()

func _reset_multiplayer_connection() -> void:
	if cooperative_session != null:
		cooperative_session.close()
		cooperative_session = null
	elif bluetooth_transport != null:
		bluetooth_transport.close()
	in_multiplayer_lobby = false
	lobby_signature = ""
	_show_connection()

func _start_multiplayer_game(mode: String) -> void:
	if cooperative_session == null:
		overlay_subtitle.text = "세션이 없습니다. 메인 화면에서 다시 연결해 주세요."
		return
	var result := cooperative_session.start_game(mode)
	if not result.ok:
		overlay_subtitle.text = "게임을 시작하지 못했습니다: %s" % result.error

func _on_multiplayer_game_started(mode: String) -> void:
	_enter_started_game(mode)

func _enter_started_game(mode: String) -> void:
	game_started = true
	game_mode = mode
	if cooperative_session != null and cooperative_session.role == CooperativeSession.Role.HOST:
		state = cooperative_session.combat_state
		if mode == "duel":
			duel_engine = cooperative_session.duel_engine
			duel_state = cooperative_session.duel_state
	selected_hand_indices.clear()
	selected_plays.clear()
	selected_energy = 0
	log_label.text = "멀티플레이 %s 시작 · 연결된 두 기기가 같은 상태를 사용합니다." % ("2인 결투" if mode == "duel" else "협동 원정")
	_close_overlay()
	_refresh()

func _add_connection_action(text: String, callback: Callable, accent: Color) -> Button:
	var button := _action_button(text, callback, accent, 64)
	overlay_content.add_child(button)
	return button

func _main_action_button(title: String, subtitle: String, callback: Callable, accent: Color, primary: bool) -> Button:
	var button := Button.new()
	button.text = "%s  %s\n     %s" % ["◆" if primary else "◇", title.trim_prefix("▶  ").trim_prefix("◇  "), subtitle]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 76 if primary else 66
	button.add_theme_font_size_override("font_size", 18 if primary else 16)
	button.add_theme_color_override("font_color", Color.WHITE if primary else COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _main_menu_choice_style(accent, 0.18 if primary else 0.03, 5 if primary else 2))
	button.add_theme_stylebox_override("hover", _main_menu_choice_style(accent, 0.30 if primary else 0.13, 6))
	button.add_theme_stylebox_override("pressed", _main_menu_choice_style(accent, 0.42, 7))
	button.add_theme_stylebox_override("focus", _main_menu_choice_style(Color.WHITE, 0.08, 6))
	_set_button_accessibility(button, title, subtitle)
	button.pressed.connect(callback)
	return button

func _main_menu_choice_style(accent: Color, fill_alpha: float, rail_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent, fill_alpha)
	style.border_color = Color(accent, 0.95)
	style.border_width_left = rail_width
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_right = 18
	style.content_margin_left = 22
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _lobby_player_card(title: String, state_text: String, character_id: StringName, accent: Color, ready: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.y = 96
	panel.add_theme_stylebox_override("panel", _panel_style(Color(accent, 0.12 if ready else 0.05), 18, Color.TRANSPARENT, 0, 14, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(70, 82)
	portrait.texture = load(_character_portrait(character_id))
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = "%s\n%s  %s\n%s" % [title, "●" if ready else "○", state_text, _character_name(character_id)]
	label.accessibility_name = title
	label.accessibility_description = "%s. 캐릭터 %s" % [state_text, _character_name(character_id)]
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", accent if ready else COLOR_MUTED)
	row.add_child(label)
	return panel

func _build_main_menu_art() -> Control:
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(430, 330)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.accessibility_name = "수호자와 기술자 원정대"
	var guardian := TextureRect.new()
	guardian.texture = load("res://assets/art/guardian-portrait.png")
	guardian.set_anchor(SIDE_LEFT, -0.05)
	guardian.set_anchor(SIDE_RIGHT, 0.57)
	guardian.set_anchor(SIDE_TOP, 0.02)
	guardian.set_anchor(SIDE_BOTTOM, 1.0)
	guardian.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	guardian.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	guardian.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(guardian)
	var engineer := TextureRect.new()
	engineer.texture = load("res://assets/art/engineer-portrait.png")
	engineer.set_anchor(SIDE_LEFT, 0.40)
	engineer.set_anchor(SIDE_RIGHT, 1.04)
	engineer.set_anchor(SIDE_TOP, 0.04)
	engineer.set_anchor(SIDE_BOTTOM, 1.0)
	engineer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	engineer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	engineer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(engineer)
	var badge := Label.new()
	badge.text = "P1  수호자    ×    P2  기술자"
	badge.set_anchor(SIDE_LEFT, 0.12)
	badge.set_anchor(SIDE_RIGHT, 0.88)
	badge.set_anchor(SIDE_TOP, 0.87)
	badge.set_anchor(SIDE_BOTTOM, 0.98)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 14)
	badge.add_theme_color_override("font_color", COLOR_TEXT)
	badge.add_theme_color_override("font_shadow_color", Color("#000000e6"))
	badge.add_theme_constant_override("shadow_offset_x", 2)
	badge.add_theme_constant_override("shadow_offset_y", 2)
	stage.add_child(badge)
	return stage

func _menu_link_button(text: String, callback: Callable, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 58
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_stylebox_override("normal", _panel_style(Color.TRANSPARENT, 14, Color.TRANSPARENT, 0, 20, 8))
	button.add_theme_stylebox_override("hover", _panel_style(Color(accent, 0.16), 14, Color.TRANSPARENT, 0, 20, 8))
	button.add_theme_stylebox_override("pressed", _panel_style(Color(accent, 0.24), 14, Color.TRANSPARENT, 0, 20, 8))
	button.add_theme_stylebox_override("focus", _focus_style(accent, 14))
	_set_button_accessibility(button, _first_text_line(text), _remaining_text_lines(text))
	button.pressed.connect(callback)
	return button

func _action_button(text: String, callback: Callable, accent: Color, height: int = 64) -> Button:
	var button := Button.new()
	button.custom_minimum_size.y = height
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_set_button_accessibility(button, _first_text_line(text), _remaining_text_lines(text))
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_stylebox_override("normal", _panel_style(Color(accent, 0.13), 24, Color.TRANSPARENT, 0, 24, 12))
	button.add_theme_stylebox_override("hover", _panel_style(Color(accent, 0.25), 24, Color.TRANSPARENT, 0, 28, 12))
	button.add_theme_stylebox_override("pressed", _panel_style(Color(accent, 0.38), 24, Color.TRANSPARENT, 0, 30, 12))
	button.add_theme_stylebox_override("disabled", _panel_style(Color("#11182788"), 24, Color.TRANSPARENT, 0, 24, 12))
	button.add_theme_stylebox_override("focus", _focus_style(accent, 24))
	button.add_theme_color_override("font_disabled_color", Color("#718099"))
	button.pressed.connect(callback)
	return button

func _set_button_accessibility(button: BaseButton, accessible_name: String, description: String = "") -> void:
	button.accessibility_name = accessible_name.strip_edges()
	button.accessibility_description = description.strip_edges()

func _first_text_line(value: String) -> String:
	for line in value.split("\n"):
		var cleaned := String(line).strip_edges()
		if not cleaned.is_empty():
			return cleaned.lstrip("◈◆⌁✦▣＋⚙←✂↻✓×☰ ")
	return value.strip_edges()

func _remaining_text_lines(value: String) -> String:
	var lines: Array[String] = []
	var found_title := false
	for line in value.split("\n"):
		var cleaned := String(line).strip_edges()
		if cleaned.is_empty():
			continue
		if not found_title:
			found_title = true
			continue
		lines.append(cleaned)
	return ". ".join(lines)

func _add_connection_notice(text: String, accent: Color) -> void:
	var notice := Label.new()
	notice.text = text
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.add_theme_font_size_override("font_size", 19)
	notice.add_theme_color_override("font_color", accent)
	overlay_content.add_child(notice)

func _status_chip(text: String, accent: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.custom_minimum_size.y = 48
	chip.add_theme_stylebox_override("panel", _panel_style(Color(accent, 0.12), 24, Color.TRANSPARENT, 0, 12, 6))
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	chip.add_child(label)
	return chip

func _info_panel(title: String, body: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color.TRANSPARENT, 0, Color.TRANSPARENT, 0, 6, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var marker := Label.new()
	marker.text = "✦"
	marker.custom_minimum_size.x = 28
	marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marker.add_theme_font_size_override("font_size", 20)
	marker.add_theme_color_override("font_color", accent)
	row.add_child(marker)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 2)
	row.add_child(copy)
	var title_label := Label.new()
	title_label.text = title.to_upper()
	title_label.accessibility_name = title
	title_label.accessibility_description = body
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", accent)
	copy.add_child(title_label)
	var body_label := Label.new()
	body_label.text = body
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.add_theme_font_size_override("font_size", 15)
	body_label.add_theme_color_override("font_color", COLOR_TEXT)
	copy.add_child(body_label)
	overlay_content.add_child(panel)
	return panel

func _connection_status_text() -> String:
	if not Engine.has_singleton(AndroidBluetoothTransport.PLUGIN_NAME):
		return "●  LOCAL DEMO"
	if cooperative_session == null and game_started:
		return "●  LOCAL DUEL" if game_mode == "duel" else "●  SOLO COMMAND"
	if cooperative_session != null and cooperative_session.handshake_failed:
		return "●  VERSION MISMATCH"
	if bluetooth_transport.get_state() == "connected" and cooperative_session != null and not cooperative_session.handshake_complete:
		return "●  VERIFYING"
	match bluetooth_transport.get_state():
		"listening": return "●  WAITING"
		"connecting": return "●  CONNECTING"
		"connected": return "●  CONNECTED"
		"error": return "●  CONNECTION ERROR"
		_: return "●  BLUETOOTH READY" if bluetooth_transport.is_available() else "●  BLUETOOTH OFF"

func _on_remote_snapshot(snapshot: Dictionary, _state_hash: String) -> void:
	game_mode = "cooperative"
	state = CombatState.from_snapshot(snapshot)
	selected_hand_indices.clear()
	selected_plays.clear()
	selected_energy = 0
	log_label.text = "호스트 상태 동기화 완료 · TURN %d" % state.turn
	_refresh()

func _on_remote_duel_snapshot(snapshot: Dictionary, _state_hash: String) -> void:
	game_mode = "duel"
	duel_state = DuelState.from_snapshot(snapshot)
	duel_save_store.save(duel_state)
	selected_hand_indices.clear()
	selected_plays.clear()
	selected_energy = 0
	log_label.text = "호스트 결투 상태 동기화 완료 · TURN %d" % duel_state.turn
	_refresh()

func _on_remote_game_mode(mode: String) -> void:
	game_mode = mode
	log_label.text = "호스트가 %s 모드를 선택했습니다." % ("2인 결투" if mode == "duel" else "협동 원정")

func _on_remote_run_snapshot(snapshot: Dictionary) -> void:
	var was_event_pending := not run_coordinator.run.pending_event.is_empty()
	run_coordinator.run = RunState.from_snapshot(snapshot)
	_refresh_character_identity()
	if overlay.visible and overlay_title.text == "카드 획득 완료" and not run_coordinator.run.pending_card_rewards.any(func(pending: bool) -> bool: return pending):
		_show_post_reward_destination()
		return
	if overlay.visible and overlay_title.text == "승무원 편성":
		_show_roster()
		return
	if not run_coordinator.run.pending_event.is_empty() and not run_coordinator.run.pending_card_rewards.any(func(pending: bool) -> bool: return pending):
		_show_event()
		return
	if was_event_pending and not run_coordinator.run.last_event_result.is_empty():
		_show_route_result("이벤트 해결", String(run_coordinator.run.last_event_result.summary))
		return
	if overlay.visible and overlay_title.text == "소비 아이템":
		_show_consumables()
		return
	if overlay.visible and overlay_title.text.begins_with("항로 선택"):
		_show_map()

func _on_run_changed(_snapshot: Dictionary) -> void:
	if overlay != null and overlay.visible and overlay_title.text == "카드 획득 완료" and not run_coordinator.run.pending_card_rewards.any(func(pending: bool) -> bool: return pending):
		_show_post_reward_destination.call_deferred()

func _show_post_reward_destination() -> void:
	if not run_coordinator.run.pending_event.is_empty():
		_show_event()
	else:
		_show_map()

func _on_session_error(code: String, detail: String) -> void:
	if code == "incompatible_content":
		log_label.text = "연결 차단 · 두 기기의 앱 또는 카드 콘텐츠가 다릅니다. 같은 APK를 설치해 주세요."
		return
	if code == "role_mismatch":
		log_label.text = "연결 차단 · 두 기기 모두 같은 역할을 선택했습니다. 한 명은 방 만들기, 다른 한 명은 참가를 선택하세요."
		return
	if code == "peer_disconnected" and overlay.visible and overlay_title.text in ["상대 동의 대기 중", "P1가 초기화를 요청했습니다", "P2가 초기화를 요청했습니다"]:
		_show_connection()
		overlay_subtitle.text = "연결이 끊겨 초기화가 취소되었습니다. 기존 원정은 그대로 유지됩니다."
		return
	log_label.text = "연결 오류 · %s (%s)" % [code, detail]

func _show_roster() -> void:
	if game_mode == "duel":
		_show_mode_locked_notice("편성", "결투를 종료하고 협동 모드에서 다음 결투의 승무원을 편성하세요.")
		return
	_clear_overlay()
	var selection_open := run_coordinator.can_select_characters()
	_set_overlay_immersive()
	overlay_title.text = "승무원 편성"
	if cooperative_session != null:
		roster_edit_slot = local_slot
	overlay_subtitle.text = "P%d 캐릭터 선택 · 서로 다른 직업 2개를 편성하세요." % (roster_edit_slot + 1) if selection_open else "현재 원정의 편성이 확정되었습니다 · 새 원정에서 다시 선택할 수 있습니다."
	var crew_row := HBoxContainer.new()
	crew_row.custom_minimum_size.x = 900
	crew_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	crew_row.add_theme_constant_override("separation", 10)
	for slot in 2:
		var identity := Button.new()
		identity.custom_minimum_size = Vector2(0, 48)
		identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var slot_accent := COLOR_BLUE if slot == 0 else COLOR_ORANGE
		identity.text = "P%d  %s   ·   %s" % [slot + 1, _character_name(run_coordinator.run.characters[slot]), _character_role(run_coordinator.run.characters[slot])]
		identity.alignment = HORIZONTAL_ALIGNMENT_LEFT
		identity.disabled = cooperative_session != null or roster_edit_slot == slot or not selection_open
		identity.add_theme_stylebox_override("normal", _panel_style(Color.TRANSPARENT, 0, Color.TRANSPARENT, 0, 10, 7))
		identity.add_theme_stylebox_override("hover", _panel_style(Color(slot_accent, 0.10), 12, Color.TRANSPARENT, 0, 10, 7))
		identity.add_theme_stylebox_override("disabled", _panel_style(Color(slot_accent, 0.10) if roster_edit_slot == slot else Color.TRANSPARENT, 12, Color.TRANSPARENT, 0, 10, 7))
		identity.add_theme_color_override("font_disabled_color", Color.WHITE)
		_set_button_accessibility(identity, "P%d 편집" % (slot + 1), "%s. %s" % [_character_name(run_coordinator.run.characters[slot]), "현재 선택 중" if roster_edit_slot == slot else "탭하여 이 슬롯 편집"])
		identity.pressed.connect(_set_roster_edit_slot.bind(slot))
		crew_row.add_child(identity)
	overlay_content.add_child(crew_row)
	var role_legend := Label.new()
	role_legend.text = _roster_role_legend()
	role_legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_legend.add_theme_font_size_override("font_size", 12)
	role_legend.add_theme_color_override("font_color", COLOR_MUTED)
	role_legend.accessibility_name = "시작 덱 역할 범례"
	role_legend.accessibility_description = "공격, 방어, 지원, 전술 카드 수를 뜻하며 지원 카드는 한 턴에 한 장만 사용할 수 있습니다"
	overlay_content.add_child(role_legend)
	var lineup := HBoxContainer.new()
	lineup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lineup.add_theme_constant_override("separation", 8)
	var can_edit := cooperative_session == null or roster_edit_slot == local_slot
	for character_id in [&"guardian", &"engineer", &"hacker", &"assault", &"medic", &"navigator"]:
		var candidate := VBoxContainer.new()
		candidate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		candidate.add_theme_constant_override("separation", 2)
		var is_current: bool = run_coordinator.run.characters[roster_edit_slot] == character_id
		var is_teammate: bool = run_coordinator.run.characters[1 - roster_edit_slot] == character_id
		var art_frame := PanelContainer.new()
		art_frame.custom_minimum_size.y = 190
		art_frame.add_theme_stylebox_override("panel", _panel_style(Color(_character_color(character_id), 0.16) if is_current else Color.TRANSPARENT, 22, Color.TRANSPARENT, 0, 2, 2))
		var art := TextureRect.new()
		art.texture = load(_character_portrait(character_id))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.modulate = Color.WHITE if not is_teammate else Color(0.62, 0.68, 0.78, 0.72)
		art_frame.add_child(art)
		var portrait_button := Button.new()
		portrait_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		portrait_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		portrait_button.disabled = not selection_open or not can_edit or is_current or is_teammate
		portrait_button.add_theme_stylebox_override("normal", _panel_style(Color.TRANSPARENT, 22, Color.TRANSPARENT, 0))
		portrait_button.add_theme_stylebox_override("hover", _panel_style(Color(_character_color(character_id), 0.10), 22, _character_color(character_id), 2))
		portrait_button.add_theme_stylebox_override("pressed", _panel_style(Color(_character_color(character_id), 0.20), 22, _character_color(character_id), 3))
		portrait_button.add_theme_stylebox_override("disabled", _panel_style(Color.TRANSPARENT, 22, Color.TRANSPARENT, 0))
		portrait_button.add_theme_stylebox_override("focus", _focus_style(_character_color(character_id), 22))
		_set_button_accessibility(portrait_button, "P%d %s 초상화 선택" % [roster_edit_slot + 1, _character_name(character_id)], "%s. %s. %s" % [_character_role(character_id), _starter_deck_profile(character_id), _disabled_character_reason(roster_edit_slot, character_id, selection_open, can_edit)])
		if not portrait_button.disabled:
			portrait_button.pressed.connect(_select_character.bind(roster_edit_slot, character_id))
		art_frame.add_child(portrait_button)
		candidate.add_child(art_frame)
		var assignment := Label.new()
		assignment.text = "◆ P%d SELECTED" % [roster_edit_slot + 1] if is_current else ("P%d 편성됨" % [2 - roster_edit_slot] if is_teammate else " ")
		assignment.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		assignment.add_theme_font_size_override("font_size", 11)
		assignment.add_theme_color_override("font_color", _character_color(character_id) if is_current else COLOR_MUTED)
		candidate.add_child(assignment)
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 72
		var deck_profile := _starter_deck_profile_compact(character_id) if _effective_text_scale() >= 1.20 else _starter_deck_profile(character_id)
		button.text = "%s\n%s" % [_character_name(character_id), deck_profile]
		button.clip_text = true
		button.disabled = not selection_open or not can_edit or is_current or is_teammate
		_set_button_accessibility(button, "P%d %s 선택" % [roster_edit_slot + 1, _character_name(character_id)], "%s. %s. %s" % [_character_role(character_id), _starter_deck_profile(character_id), _disabled_character_reason(roster_edit_slot, character_id, selection_open, can_edit)])
		button.add_theme_font_size_override("font_size", 13)
		button.add_theme_stylebox_override("normal", _panel_style(Color.TRANSPARENT, 0, Color.TRANSPARENT, 0, 6, 5))
		button.add_theme_stylebox_override("hover", _panel_style(Color(_character_color(character_id), 0.16), 10, Color.TRANSPARENT, 0, 6, 5))
		button.add_theme_stylebox_override("disabled", _panel_style(Color(_character_color(character_id), 0.16) if is_current else Color.TRANSPARENT, 10, Color.TRANSPARENT, 0, 6, 5))
		button.add_theme_color_override("font_disabled_color", Color.WHITE if is_current else Color("#76839a"))
		button.pressed.connect(_select_character.bind(roster_edit_slot, character_id))
		candidate.add_child(button)
		lineup.add_child(candidate)
	overlay_content.add_child(lineup)
	if selection_open and cooperative_session == null:
		var confirm_roster := _add_connection_action("편성 확정 · 첫 항로 보기", _show_map, COLOR_CYAN)
		confirm_roster.custom_minimum_size.x = 620
		confirm_roster.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

func _set_roster_edit_slot(slot: int) -> void:
	roster_edit_slot = slot
	_show_roster()

func _select_character(slot: int, character_id: StringName) -> void:
	var is_guest := cooperative_session != null and cooperative_session.role == CooperativeSession.Role.GUEST
	var result := cooperative_session.select_character(slot, character_id) if cooperative_session != null else run_coordinator.select_character(slot, character_id)
	if not result.ok:
		overlay_subtitle.text = "편성을 변경할 수 없습니다: %s" % result.get("error", "unknown")
		return
	if is_guest:
		overlay_subtitle.text = "호스트의 편성 확정을 기다리는 중입니다."
		return
	_refresh_character_identity()
	_show_roster()

func _disabled_character_reason(slot: int, character_id: StringName, selection_open: bool, can_edit: bool) -> String:
	if not selection_open:
		return "현재 원정의 편성이 확정되어 변경할 수 없습니다"
	if not can_edit:
		return "상대 플레이어의 슬롯은 변경할 수 없습니다"
	if run_coordinator.run.characters[slot] == character_id:
		return "현재 선택된 직업입니다"
	if run_coordinator.run.characters[1 - slot] == character_id:
		return "다른 플레이어가 이미 선택한 직업입니다"
	return "두 번 탭하여 이 직업을 선택합니다"

func _refresh_character_identity() -> void:
	if player_title_labels.size() < 2:
		return
	for slot in 2:
		var character_id: StringName = duel_state.players[slot].character_id if game_mode == "duel" and duel_state != null else run_coordinator.run.characters[slot]
		player_title_labels[slot].text = "P%d  %s" % [slot + 1, _character_name(character_id)]
		player_title_labels[slot].add_theme_color_override("font_color", _character_color(character_id))
		player_role_labels[slot].text = _character_role(character_id)
		player_portraits[slot].texture = load(_character_portrait(character_id))
		player_status_visuals[slot].configure(_character_color(character_id))

func _character_name(character_id: StringName) -> String:
	return {&"guardian": "수호자", &"engineer": "기술자", &"hacker": "해커", &"assault": "강습병", &"medic": "의무관", &"navigator": "항법사"}.get(character_id, String(character_id))

func _starter_deck_profile(character_id: StringName) -> String:
	var counts := _starter_deck_role_counts(character_id)
	return "시작덱 %d · 공%d 방%d 지%d 전%d" % [counts.total, counts.attack, counts.defense, counts.support, counts.tactic]

func _roster_role_legend() -> String:
	return "공  공격   ·   방  방어   ·   지  지원(턴당 1장)   ·   전  전술"

func _starter_deck_profile_compact(character_id: StringName) -> String:
	var counts := _starter_deck_role_counts(character_id)
	return "%d장 · 공%d 방%d\n지%d 전%d" % [counts.total, counts.attack, counts.defense, counts.support, counts.tactic]

func _starter_deck_role_counts(character_id: StringName) -> Dictionary:
	var deck := run_coordinator.starter_deck_for(character_id)
	var attack := 0
	var defense := 0
	var support := 0
	var tactic := 0
	for card_id in deck:
		if not catalog.has(StringName(card_id)):
			continue
		var card: CardData = catalog[StringName(card_id)]
		var kind := _card_tactical_role(card)
		if kind == "attack":
			attack += 1
		elif kind == "defense":
			defense += 1
		elif kind == "support":
			support += 1
		else:
			tactic += 1
	return {"total": deck.size(), "attack": attack, "defense": defense, "support": support, "tactic": tactic}

func _card_tactical_role(card: CardData) -> String:
	if card.is_support():
		return "support"
	if card.effects.any(func(effect: Dictionary) -> bool: return String(effect.get("type", "")) == "damage"):
		return "attack"
	if card.effects.any(func(effect: Dictionary) -> bool: return String(effect.get("type", "")) == "block"):
		return "defense"
	return "tactic"

func _character_role(character_id: StringName) -> String:
	return {
		&"guardian": "전방 방어 · 아군 엄호",
		&"engineer": "에너지 지원 · 장치 제어",
		&"hacker": "적 약화 · 행동 교란",
		&"assault": "집중 화력 · 마무리 공격",
		&"medic": "팀 회복 · 위기 안정화",
		&"navigator": "선제 행동 · 에너지 순환",
	}.get(character_id, "미확인 역할")

func _character_portrait(character_id: StringName) -> String:
	return "res://assets/art/%s-portrait.png" % String(character_id)

func _character_color(character_id: StringName) -> Color:
	return {
		&"guardian": COLOR_BLUE,
		&"engineer": COLOR_ORANGE,
		&"hacker": Color("#bc8cff"),
		&"assault": COLOR_RED,
		&"medic": Color("#55d99a"),
		&"navigator": Color("#42d7d7"),
	}.get(character_id, COLOR_CYAN)

func _show_map() -> void:
	if game_mode == "duel":
		_show_mode_locked_notice("항로", "항로 진행은 협동 원정 전용입니다.")
		return
	_clear_overlay()
	_set_overlay_immersive()
	var run := run_coordinator.run
	overlay_title.text = "성계 항로 · STAGE %d" % run.stage
	overlay_subtitle.text = "빛나는 노드를 선택해 다음 목적지를 정하세요   ·   열쇠 %d / 3" % run.keys.count(true)
	if run.phase == "stage_boss":
		_set_overlay_compact(true)
		overlay_title.text = "스테이지 보스 · STAGE %d" % run.stage
		overlay_subtitle.text = "8개 항로 완료 · 보스를 격파해야 다음 스테이지로 이동합니다."
		_show_boss_briefing(false)
		_add_connection_action("스테이지 보스 진입", _start_boss_encounter.bind(false), COLOR_RED)
		return
	if run.phase == "true_boss":
		_set_overlay_compact(true)
		overlay_title.text = "진 최종 보스 해금"
		overlay_subtitle.text = "3개 열쇠 확보 완료 · 마지막 협동 전투입니다."
		_show_boss_briefing(true)
		_add_connection_action("별을 삼키는 자에게 도전", _start_boss_encounter.bind(true), COLOR_YELLOW)
		return
	if run.phase == "completed" or run.phase == "failed":
		_show_run_outcome(run.phase == "completed")
		return
	var stage: Dictionary = run.map.stages[run.stage - 1]
	var map_header := HBoxContainer.new()
	map_header.alignment = BoxContainer.ALIGNMENT_CENTER
	map_header.add_theme_constant_override("separation", 36)
	var sector_status := Label.new()
	sector_status.text = "SECTOR %d   ◈   HULL %d/%d" % [run.stage, run.team_health, run.team_max_health]
	sector_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sector_status.add_theme_font_size_override("font_size", 14)
	sector_status.add_theme_color_override("font_color", COLOR_CYAN)
	map_header.add_child(sector_status)
	var location := Label.new()
	location.text = "현재 좌표  %02d / %02d" % [run.step + 1, MapGenerator.TRAVERSAL_STEPS]
	location.add_theme_font_size_override("font_size", 13)
	location.add_theme_color_override("font_color", COLOR_MUTED)
	map_header.add_child(location)
	overlay_content.add_child(map_header)
	var route_map := StarRouteMapView.new()
	route_map.configure(stage, run.step, local_slot, run.pending_routes, cooperative_session == null)
	route_map.node_selected.connect(_choose_route)
	overlay_content.add_child(route_map)
	var route_guide := Label.new()
	var step_data: Dictionary = stage.steps[run.step]
	if step_data.kind == "common":
		route_guide.text = "공통 전투 선택 완료  ·  아래 버튼으로 두 대원이 함께 진입" if run.pending_routes.size() == 2 else "두 대원이 함께 진입하는 첫 전투  ·  승리 후 항로가 4갈래로 나뉩니다"
	elif cooperative_session == null:
		var remaining_slots: Array[String] = []
		for slot in 2:
			if not run.pending_routes.has(slot):
				remaining_slots.append("P%d" % [slot + 1])
		route_guide.text = "P1 상단 · P2 하단  ·  %s 목적지를 선택하세요  ·  선택한 노드는 다시 변경 가능" % [" / ".join(remaining_slots)] if not remaining_slots.is_empty() else "P1 · P2 항로 선택 완료  ·  선택 변경 또는 아래 버튼으로 진입"
	else:
		route_guide.text = "P1 상단 · P2 하단  ·  자신의 목적지를 선택  ·  진입 전 변경 가능"
	route_guide.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	route_guide.add_theme_font_size_override("font_size", 12)
	route_guide.add_theme_color_override("font_color", COLOR_MUTED)
	route_guide.accessibility_name = "항로 선택 안내"
	overlay_content.add_child(route_guide)
	if run.pending_routes.size() == 2:
		_add_connection_action("워프 좌표 확정 · 선택 노드 진입", _enter_selected_routes, COLOR_CYAN)

func _show_boss_briefing(true_boss: bool) -> void:
	var run := run_coordinator.run
	var accent := COLOR_YELLOW if true_boss else COLOR_RED
	var content := RunContentCatalog.build()
	var enemy: Dictionary = content.true_boss if true_boss else content.stages[run.stage - 1].boss
	var route_types: Array[String] = ["true_boss" if true_boss else "boss"]
	var enemy_profile := EnemyVisuals.profile(StringName(enemy.id), route_types)
	var confrontation := HBoxContainer.new()
	confrontation.alignment = BoxContainer.ALIGNMENT_CENTER
	confrontation.add_theme_constant_override("separation", 28)
	confrontation.add_child(_briefing_actor(_character_portrait(run.characters[0]), "P1 · %s" % _character_name(run.characters[0]), "덱 %d장" % run.decks[0].size(), COLOR_BLUE, Vector2(150, 150)))
	confrontation.add_child(_briefing_actor(String(enemy_profile.texture), String(enemy.name), "보스 교전", accent, Vector2(300, 150)))
	confrontation.add_child(_briefing_actor(_character_portrait(run.characters[1]), "P2 · %s" % _character_name(run.characters[1]), "덱 %d장" % run.decks[1].size(), COLOR_ORANGE, Vector2(150, 150)))
	overlay_content.add_child(confrontation)
	overlay_content.add_child(_game_status_line([
		["☠", "적 내구도 %d" % int(enemy.health), accent],
		["⚠", "예고 피해 %d" % int(enemy.intent_damage), COLOR_RED],
		["♥", "팀 %d/%d" % [run.team_health, run.team_max_health], COLOR_CYAN],
		["✦", "열쇠 %d/3" % run.keys.count(true), COLOR_YELLOW],
	]))
	var warning := "승리하면 런을 완주합니다. 패배 시 현재 체크포인트에서 다시 준비할 수 있습니다." if true_boss else "승리하면 다음 스테이지가 열립니다. P1/P2 보유 크레딧 %d + %d C · 진입 전 덱과 소비품을 점검하세요." % [run.gold[0], run.gold[1]]
	_info_panel("최종 교전 브리핑" if true_boss else "보스 교전 브리핑", warning, accent)

func _briefing_actor(texture_path: String, title: String, subtitle: String, accent: Color, minimum_size: Vector2) -> VBoxContainer:
	var actor := VBoxContainer.new()
	actor.custom_minimum_size = minimum_size
	actor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actor.add_theme_constant_override("separation", 2)
	var art := TextureRect.new()
	art.custom_minimum_size.y = minimum_size.y - 46
	art.texture = load(texture_path)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actor.add_child(art)
	var title_label := Label.new()
	title_label.text = title
	title_label.accessibility_name = "브리핑 인물"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", accent)
	actor.add_child(title_label)
	var subtitle_label := Label.new()
	subtitle_label.text = subtitle
	subtitle_label.accessibility_name = "%s 상태" % title
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 12)
	subtitle_label.add_theme_color_override("font_color", COLOR_MUTED)
	actor.add_child(subtitle_label)
	return actor

func _choose_route(slot: int, node_id: String) -> void:
	var result := cooperative_session.select_route(slot, node_id) if cooperative_session != null else run_coordinator.choose_route(slot, node_id)
	if not result.ok:
		overlay_subtitle.text = "항로를 선택하지 못했습니다: %s" % result.error
		return
	_show_map()

func _enter_selected_routes() -> void:
	if cooperative_session != null and cooperative_session.role == CooperativeSession.Role.GUEST:
		overlay_subtitle.text = "호스트가 조우를 시작할 때까지 기다려 주세요."
		return
	var types := run_coordinator.selected_route_types()
	var combat_types := ["combat", "elite", "key_challenge", "boss"]
	if types.any(func(type: String) -> bool: return combat_types.has(type)):
		active_route_types = types
		active_route_combat = true
		state = engine.create_run_combat(run_coordinator.run, types, RunContentCatalog.build())
		if cooperative_session != null and cooperative_session.role == CooperativeSession.Role.HOST:
			cooperative_session.replace_combat_state(state)
		selected_hand_indices.clear()
		selected_plays.clear()
		selected_energy = 0
		_close_overlay()
		log_label.text = "%s 조우 시작 · 승리해야 항로가 진행됩니다." % " + ".join(types.map(func(type: String) -> String: return _node_label(type)))
		_refresh()
		return
	var result := run_coordinator.resolve_noncombat(types)
	if result.ok:
		if cooperative_session != null:
			cooperative_session.publish_run_state("node_resolved")
		state.team_health = run_coordinator.run.team_health
		if result.get("event_pending", false):
			_show_event()
		else:
			_show_route_result("노드 해결 완료", " · ".join(result.summary))

func _start_boss_encounter(true_boss: bool) -> void:
	if cooperative_session != null and cooperative_session.role == CooperativeSession.Role.GUEST:
		overlay_subtitle.text = "호스트가 보스전을 시작할 때까지 기다려 주세요."
		return
	active_route_types.clear()
	active_route_types.append("true_boss" if true_boss else "boss")
	active_route_combat = true
	state = engine.create_run_combat(run_coordinator.run, active_route_types, RunContentCatalog.build())
	if cooperative_session != null:
		cooperative_session.replace_combat_state(state)
	selected_hand_indices.clear()
	selected_plays.clear()
	selected_energy = 0
	_close_overlay()
	log_label.text = "%s 시작 · 승리 전에는 진행되지 않습니다." % _encounter_kind()
	_refresh()

func _finish_route_combat() -> void:
	active_route_combat = false
	var is_true_boss := active_route_types.has("true_boss")
	var is_boss := active_route_types.has("boss") or is_true_boss
	var result := run_coordinator.complete_boss_combat(state, is_true_boss) if is_boss else run_coordinator.complete_combat(state, active_route_types)
	if not result.ok:
		log_label.text = "전투 보상을 저장하지 못했습니다: %s" % result.get("error", "unknown")
		return
	if cooperative_session != null:
		cooperative_session.publish_run_state("combat_reward")
	if result.get("event_pending", false):
		_show_route_result("항로 전투 승리", "각 플레이어 +%d C · 보상 획득 후 이벤트를 해결합니다." % result.gold)
	elif result.get("run_completed", false):
		_show_route_result("최종 보스 격파", "각 플레이어 +%d C · 마지막 보상 획득 후 원정 결과를 확인합니다." % result.gold)
	elif result.get("run_failed", false):
		_show_route_result("보스 격파 · 원정 종료", "각 플레이어 +%d C · 마지막 보상 획득 후 원정 기록을 확인합니다." % result.gold)
	elif result.get("true_boss_unlocked", false):
		_show_route_result("세 번째 보스 격파", "열쇠 3개 확인 · 진 최종 보스가 해금됐습니다.")
	elif result.get("stage_advanced", false):
		_show_route_result("스테이지 보스 격파", "각 플레이어 +%d C · STAGE %d 진입" % [result.gold, run_coordinator.run.stage])
	else:
		_show_route_result("항로 전투 승리", "각 플레이어 +%d C · 진행 상황 자동 저장" % result.gold)
	active_route_types.clear()

func _show_event() -> void:
	_clear_overlay()
	_set_overlay_immersive()
	var event := run_coordinator.current_event()
	if event.is_empty():
		overlay_title.text = "이벤트 오류"
		overlay_subtitle.text = "이벤트 데이터를 불러오지 못했습니다."
		return
	overlay_title.text = String(event.name)
	overlay_subtitle.text = "협동 조우 · 두 대원의 선택을 비교한 뒤 결과를 함께 적용합니다."
	var votes: Dictionary = run_coordinator.run.pending_event.votes
	var event_header := HBoxContainer.new()
	event_header.add_theme_constant_override("separation", 14)
	var emblem := VBoxContainer.new()
	emblem.custom_minimum_size = Vector2(156, 100)
	emblem.add_theme_constant_override("separation", 2)
	var emblem_label := Label.new()
	emblem_label.text = "◌  SIGNAL"
	emblem_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emblem_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	emblem_label.add_theme_font_size_override("font_size", 22)
	emblem_label.add_theme_color_override("font_color", Color("#bc8cff"))
	emblem.add_child(emblem_label)
	var event_index := int(String(event.id).trim_prefix("event_"))
	var signal_id := Label.new()
	signal_id.text = "ANOMALY %02d" % event_index
	signal_id.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	signal_id.add_theme_font_size_override("font_size", 13)
	signal_id.add_theme_color_override("font_color", COLOR_MUTED)
	emblem.add_child(signal_id)
	event_header.add_child(emblem)
	var status_row := HBoxContainer.new()
	status_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.alignment = BoxContainer.ALIGNMENT_END
	status_row.add_theme_constant_override("separation", 34)
	event_header.add_child(status_row)
	for slot in 2:
		var voted := votes.has(slot) or votes.has(str(slot))
		status_row.add_child(_event_vote_status(slot, voted))
	overlay_content.add_child(event_header)
	var risky_choice: Dictionary = event.choices[0]
	var risk := int(risky_choice.risk)
	overlay_content.add_child(_game_status_line([
		["◌", "조사 성공 %d%%" % (65 - risk * 10), Color("#bc8cff")],
		["◈", "성공 시 각 +%d C" % (24 + risk * 8), COLOR_YELLOW],
		["⚠", "실패 시 내구도 -%d" % (risk * 6), COLOR_RED],
		["♥", "안전 선택 +4", COLOR_CYAN],
	]))
	var local_voted := votes.has(local_slot) or votes.has(str(local_slot))
	if local_voted:
		_info_panel("내 선택 확정", "동료의 결정을 기다리고 있습니다. 두 선택이 다르면 이벤트 규칙에 따라 절충 결과가 적용됩니다.", COLOR_CYAN)
		return
	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation", 14)
	overlay_content.add_child(choices)
	for choice_index in event.choices.size():
		var choice: Dictionary = event.choices[choice_index]
		var choice_risk := int(choice.risk)
		var risk_text := "확정 효과 · 팀 내구도 최대 +4" if choice_risk == 0 else "%d%% 성공 · 각 +%d C / 실패 내구도 -%d" % [65 - choice_risk * 10, 24 + choice_risk * 8, choice_risk * 6]
		var accent := COLOR_BLUE if choice_risk == 0 else COLOR_YELLOW
		var choice_button := _action_button("%s\n\n%s" % [choice.label, risk_text], _choose_event.bind(choice_index), accent, 132)
		choice_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choices.add_child(choice_button)
	_info_panel("협동 판정", "두 플레이어가 각각 선택합니다. 같은 선택은 그대로 실행되고, 선택이 다르면 안전과 보상 사이의 절충 결과를 적용합니다.", Color("#bc8cff"))

func _event_vote_status(slot: int, voted: bool) -> HBoxContainer:
	var station := HBoxContainer.new()
	station.custom_minimum_size = Vector2(260, 76)
	station.add_theme_constant_override("separation", 10)
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(64, 76)
	portrait.texture = load(_character_portrait(run_coordinator.run.characters[slot]))
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	station.add_child(portrait)
	var copy := VBoxContainer.new()
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", 3)
	var callsign := Label.new()
	callsign.text = "P%d · %s" % [slot + 1, _character_name(run_coordinator.run.characters[slot])]
	callsign.add_theme_font_size_override("font_size", 15)
	callsign.add_theme_color_override("font_color", COLOR_BLUE if slot == 0 else COLOR_ORANGE)
	copy.add_child(callsign)
	var state_label := Label.new()
	state_label.text = "✓ 선택 완료" if voted else "◌ 선택 신호 대기"
	state_label.add_theme_font_size_override("font_size", 14)
	state_label.add_theme_color_override("font_color", COLOR_CYAN if voted else COLOR_MUTED)
	copy.add_child(state_label)
	station.add_child(copy)
	return station

func _choose_event(choice_index: int) -> void:
	var result := cooperative_session.submit_event_choice(local_slot, choice_index) if cooperative_session != null else run_coordinator.submit_event_choice(local_slot, choice_index)
	if not result.ok:
		overlay_subtitle.text = "선택을 확정하지 못했습니다: %s" % result.get("error", "unknown")
		return
	if cooperative_session == null and not result.get("ready", false):
		result = run_coordinator.submit_event_choice(1 - local_slot, choice_index)
	if cooperative_session != null and cooperative_session.role == CooperativeSession.Role.HOST:
		cooperative_session.publish_run_state("event_choice")
	state.team_health = run_coordinator.run.team_health
	if result.get("ready", false):
		_show_route_result("이벤트 해결", String(result.summary))
	else:
		_show_event()

func _show_route_result(title: String, summary: String) -> void:
	_clear_overlay()
	_set_overlay_immersive()
	var combat_victory := "승리" in title or "격파" in title
	if combat_victory:
		_set_overlay_immersive()
	else:
		_set_overlay_compact(true)
	overlay_title.text = title
	overlay_subtitle.text = summary
	var outcome_text := "CHECKPOINT · 진행 저장 완료"
	var outcome_description := "항로 결과가 저장되었습니다."
	var outcome_color := COLOR_CYAN
	if combat_victory:
		var victory_hero := VBoxContainer.new()
		victory_hero.add_theme_constant_override("separation", 2)
		var victory_label := Label.new()
		victory_label.text = "V I C T O R Y"
		victory_label.accessibility_name = "전투 승리"
		victory_label.accessibility_description = "%s. %s" % [title, summary]
		victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		victory_label.add_theme_font_size_override("font_size", 46)
		victory_label.add_theme_color_override("font_color", COLOR_CYAN)
		victory_hero.add_child(victory_label)
		var victory_rule := ProgressBar.new()
		victory_rule.custom_minimum_size = Vector2(0, 5)
		victory_rule.max_value = 100
		victory_rule.value = 100
		victory_rule.show_percentage = false
		victory_rule.add_theme_stylebox_override("background", _panel_style(Color.TRANSPARENT, 3))
		victory_rule.add_theme_stylebox_override("fill", _panel_style(Color("#55e8dcaa"), 3))
		victory_hero.add_child(victory_rule)
		var grade_label := Label.new()
		var health_ratio := float(run_coordinator.run.team_health) / maxf(1.0, float(run_coordinator.run.team_max_health))
		var grade := "S" if health_ratio >= 0.75 else ("A" if health_ratio >= 0.45 else "B")
		grade_label.text = "COMBAT GRADE  %s   ·   TURN %02d   ·   TEAM SURVIVAL %d%%" % [grade, state.turn, roundi(health_ratio * 100.0)]
		grade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grade_label.add_theme_font_size_override("font_size", 15)
		grade_label.add_theme_color_override("font_color", COLOR_MUTED)
		victory_hero.add_child(grade_label)
		overlay_content.add_child(victory_hero)
		outcome_text = "전투 기록 확정 · 다음 항로 개방"
		outcome_description = "적을 격파하고 전투 보상을 저장했습니다."
	if title == "이벤트 해결":
		match String(run_coordinator.run.last_event_result.get("outcome", "")):
			"success":
				outcome_text = "합의 성공 · 위험 조사 완료"
				outcome_description = "두 플레이어의 합의 선택이 성공 판정되었습니다."
				outcome_color = COLOR_YELLOW
			"safe":
				outcome_text = "안전 합의 · 내구도 회복"
				outcome_description = "두 플레이어가 안전 선택에 합의했습니다."
				outcome_color = COLOR_CYAN
			"compromise":
				outcome_text = "선택 불일치 · 절충안 적용"
				outcome_description = "두 플레이어의 선택이 달라 절충 결과가 적용되었습니다."
				outcome_color = Color("#bc8cff")
			"setback":
				outcome_text = "합의 실행 · 조사 중 사고"
				outcome_description = "두 플레이어의 합의 선택이 실패 판정되었습니다."
				outcome_color = COLOR_RED
	var verdict := PanelContainer.new()
	verdict.custom_minimum_size.y = 76
	verdict.add_theme_stylebox_override("panel", _panel_style(Color(outcome_color, 0.13), 18, Color.TRANSPARENT, 0, 20, 10))
	var verdict_row := HBoxContainer.new()
	verdict_row.add_theme_constant_override("separation", 20)
	var p1_status := Label.new()
	p1_status.text = "P1  ✓ 판정 완료"
	p1_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p1_status.add_theme_font_size_override("font_size", 15)
	p1_status.add_theme_color_override("font_color", COLOR_BLUE)
	verdict_row.add_child(p1_status)
	var outcome_label := Label.new()
	outcome_label.text = outcome_text
	outcome_label.accessibility_name = outcome_text
	outcome_label.accessibility_description = outcome_description
	outcome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	outcome_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outcome_label.add_theme_font_size_override("font_size", 24)
	outcome_label.add_theme_color_override("font_color", outcome_color)
	verdict_row.add_child(outcome_label)
	var p2_status := Label.new()
	p2_status.text = "P2  ✓ 판정 완료"
	p2_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p2_status.add_theme_font_size_override("font_size", 15)
	p2_status.add_theme_color_override("font_color", COLOR_ORANGE)
	verdict_row.add_child(p2_status)
	verdict.add_child(verdict_row)
	overlay_content.add_child(verdict)
	overlay_content.add_child(_game_status_line([
		["♥", "팀 %d/%d" % [run_coordinator.run.team_health, run_coordinator.run.team_max_health], COLOR_CYAN],
		["⌁", "항로 %d/8" % run_coordinator.run.step, COLOR_BLUE],
		["◈", "P1 %d C" % run_coordinator.run.gold[0], COLOR_BLUE],
		["◈", "P2 %d C" % run_coordinator.run.gold[1], COLOR_ORANGE],
	]))
	_info_panel("체크포인트 저장 완료", "결과와 두 플레이어의 진행 상황을 이 기기에 저장했습니다.", COLOR_CYAN)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	if run_coordinator.run.pending_card_rewards[local_slot]:
		var reward_button := _action_button("✦  카드 보상 확인", _show_reward, COLOR_YELLOW, 64)
		reward_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(reward_button)
	else:
		var route_button := _action_button("⌁  다음 항로 선택", _show_map, COLOR_CYAN, 64)
		route_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(route_button)
	overlay_content.add_child(actions)

func _show_training_victory() -> void:
	_clear_overlay()
	_set_overlay_immersive()
	overlay_title.text = "훈련 전투 완료"
	overlay_subtitle.text = "두 대원의 연계로 훈련 드론을 격파했습니다."
	var hero := VBoxContainer.new()
	hero.add_theme_constant_override("separation", 3)
	var victory := Label.new()
	victory.text = "V I C T O R Y"
	victory.accessibility_name = "전투 승리"
	victory.accessibility_description = "훈련 드론 격파. 전투 결과 화면입니다."
	victory.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory.add_theme_font_size_override("font_size", 48)
	victory.add_theme_color_override("font_color", COLOR_CYAN)
	hero.add_child(victory)
	var health_ratio := float(state.team_health) / maxf(1.0, float(state.team_max_health))
	var grade := "S" if health_ratio >= 0.75 else ("A" if health_ratio >= 0.45 else "B")
	var record := Label.new()
	record.text = "COMBAT GRADE  %s   ·   TURN %02d   ·   TEAM SURVIVAL %d%%" % [grade, state.turn, roundi(health_ratio * 100.0)]
	record.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	record.add_theme_font_size_override("font_size", 16)
	record.add_theme_color_override("font_color", COLOR_MUTED)
	hero.add_child(record)
	overlay_content.add_child(hero)
	var crew := HBoxContainer.new()
	crew.alignment = BoxContainer.ALIGNMENT_CENTER
	crew.add_theme_constant_override("separation", 16)
	crew.add_child(_briefing_actor(_character_portrait(run_coordinator.run.characters[0]), "P1 · %s" % _character_name(run_coordinator.run.characters[0]), "연계 전투 완료", COLOR_BLUE, Vector2(190, 132)))
	var clear_mark := Label.new()
	clear_mark.text = "✦\nCLEAR"
	clear_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clear_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clear_mark.custom_minimum_size = Vector2(180, 110)
	clear_mark.add_theme_font_size_override("font_size", 25)
	clear_mark.add_theme_color_override("font_color", COLOR_YELLOW)
	crew.add_child(clear_mark)
	crew.add_child(_briefing_actor(_character_portrait(run_coordinator.run.characters[1]), "P2 · %s" % _character_name(run_coordinator.run.characters[1]), "연계 전투 완료", COLOR_ORANGE, Vector2(190, 132)))
	overlay_content.add_child(crew)
	overlay_content.add_child(_game_status_line([
		["✦", "전투 등급 %s" % grade, COLOR_YELLOW],
		["⌛", "%02d턴" % state.turn, COLOR_CYAN],
		["♥", "팀 생존 %d/%d" % [state.team_health, state.team_max_health], COLOR_BLUE],
	]))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	var retry := _action_button("↻  다시 훈련", _activate_mode.bind("cooperative"), COLOR_BLUE, 64)
	retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(retry)
	var main := _action_button("←  메인 화면으로", _return_to_main_menu, COLOR_CYAN, 64)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(main)
	overlay_content.add_child(actions)

func _show_run_outcome(victory: bool) -> void:
	_clear_overlay()
	_set_overlay_immersive()
	overlay_title.text = "런 완주 · 두 별의 승리" if victory else "런 종료 · 열쇠 부족"
	overlay_subtitle.text = "별을 삼키는 자를 격파했습니다. 최종 기록이 저장되었습니다." if victory else "3개 열쇠를 모두 확보하지 못해 진 최종 보스에 진입할 수 없습니다."
	var outcome_color := COLOR_CYAN if victory else COLOR_RED
	var crew := HBoxContainer.new()
	crew.alignment = BoxContainer.ALIGNMENT_CENTER
	crew.custom_minimum_size.y = 240
	crew.add_theme_constant_override("separation", 36)
	crew.add_child(_briefing_actor(_character_portrait(run_coordinator.run.characters[0]), "P1 · %s" % _character_name(run_coordinator.run.characters[0]), "최종 덱 %d장" % run_coordinator.run.decks[0].size(), COLOR_BLUE, Vector2(280, 230)))
	var outcome_mark := VBoxContainer.new()
	outcome_mark.custom_minimum_size = Vector2(300, 210)
	var outcome_label := Label.new()
	outcome_label.text = "✦\nMISSION\nCOMPLETE" if victory else "×\nKEY GATE\nCLOSED"
	outcome_label.accessibility_name = "원정 성공" if victory else "열쇠 관문 진입 실패"
	outcome_label.accessibility_description = "최종 원정 결과"
	outcome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	outcome_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outcome_label.add_theme_font_size_override("font_size", 34)
	outcome_label.add_theme_color_override("font_color", outcome_color)
	outcome_mark.add_child(outcome_label)
	crew.add_child(outcome_mark)
	crew.add_child(_briefing_actor(_character_portrait(run_coordinator.run.characters[1]), "P2 · %s" % _character_name(run_coordinator.run.characters[1]), "최종 덱 %d장" % run_coordinator.run.decks[1].size(), COLOR_ORANGE, Vector2(280, 230)))
	overlay_content.add_child(crew)
	overlay_content.add_child(_game_status_line([
		["♥", "팀 %d/%d" % [run_coordinator.run.team_health, run_coordinator.run.team_max_health], outcome_color],
		["✦", "열쇠 %d/3" % run_coordinator.run.keys.count(true), COLOR_YELLOW],
		["⌁", "STAGE %d/3" % run_coordinator.run.stage, COLOR_BLUE],
		["◈", "%d + %d C" % [run_coordinator.run.gold[0], run_coordinator.run.gold[1]], COLOR_ORANGE],
	]))
	var record_subject := "완주한 원정" if victory else "종료된 원정"
	_info_panel("원정 기록 저장됨", "%s의 편성·덱·항로 결과를 로컬 체크포인트에 반영했습니다." % record_subject, outcome_color)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	var deck_button := _action_button("▤  최종 덱 확인", _show_current_deck, COLOR_BLUE, 64)
	deck_button.custom_minimum_size.x = 460
	actions.add_child(deck_button)
	var main_button := _action_button("←  메인 화면으로", _return_to_main_menu, COLOR_CYAN, 64)
	main_button.custom_minimum_size.x = 460
	actions.add_child(main_button)
	overlay_content.add_child(actions)

func _game_status_line(items: Array) -> HFlowContainer:
	var line := HFlowContainer.new()
	line.alignment = FlowContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 30)
	line.add_theme_constant_override("v_separation", 8)
	line.custom_minimum_size.y = 38
	for item in items:
		var status := Label.new()
		status.text = "%s  %s" % [item[0], item[1]]
		status.add_theme_font_size_override("font_size", 15)
		status.add_theme_color_override("font_color", item[2])
		status.accessibility_name = String(item[1])
		line.add_child(status)
	return line

func _show_reward() -> void:
	if game_mode == "duel":
		_show_mode_locked_notice("전투 보상", "결투는 공정한 시작 덱을 사용하며 원정 보상을 소비하지 않습니다.")
		return
	_clear_overlay()
	_set_overlay_immersive()
	overlay_title.text = "SALVAGE DRAFT · 전투 보상"
	overlay_subtitle.text = "전용 카드 2장 + 공용 카드 1장 · 선택 즉시 덱과 체크포인트에 반영"
	var rewards := run_coordinator.current_card_reward(local_slot)
	if rewards.is_empty():
		_set_overlay_compact(true, true)
		overlay_subtitle.text = "받을 수 있는 카드 보상이 없습니다. 전투에서 승리하면 보상이 해금됩니다."
		overlay_content.add_child(_game_status_line([
			["▤", "현재 덱 %d장" % run_coordinator.run.decks[local_slot].size(), COLOR_BLUE],
			["✦", "다음 보상 전용 2 + 공용 1", COLOR_YELLOW],
			["⚔", "전투 승리 시 해금", COLOR_CYAN],
		]))
		_info_panel("다음 보상 흐름", "전투에서 승리한 뒤 3장 중 1장을 선택합니다. 선택 즉시 덱과 체크포인트에 반영되고 나머지 카드는 사라집니다.", COLOR_YELLOW)
		return
	_set_overlay_compact(true)
	var deck := run_coordinator.run.decks[local_slot]
	var total_cost := 0
	for card_id in deck:
		if catalog.has(StringName(card_id)):
			total_cost += (catalog[StringName(card_id)] as CardData).energy_cost
	overlay_content.add_child(_game_status_line([
		["▤", "덱 %d장" % deck.size(), COLOR_BLUE],
		["⚡", "평균 비용 %.1f" % (float(total_cost) / maxf(float(deck.size()), 1.0)), COLOR_CYAN],
		["✦", "3장 중 1장 획득", COLOR_YELLOW],
		["✓", "선택 즉시 저장", COLOR_ORANGE],
	]))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	overlay_content.add_child(row)
	for card_id in rewards:
		var card: CardData = catalog[card_id]
		var button := preload("res://src/ui/card_button.gd").new()
		button.custom_minimum_size = Vector2(250, 248)
		var accent := _scope_color(card.owner_scope)
		button.configure(card, "%s · %s" % [_rarity_label(card.rarity), _scope_label(card.owner_scope)], _effect_summary(card), accent, false, "＋ 이 카드 획득")
		button.accessibility_description += ". 선택하면 나머지 두 장은 사라지고 즉시 저장됩니다"
		button.add_theme_stylebox_override("normal", _panel_style(COLOR_PANEL, 18, accent, 3, 14, 10))
		button.add_theme_stylebox_override("hover", _panel_style(Color(accent, 0.18), 18, accent, 4, 14, 10))
		button.pressed.connect(_claim_reward.bind(card_id))
		row.add_child(button)
	_info_panel("선택 가이드", "전용 카드는 현재 직업의 조합을 강화하고, 공용 카드는 두 직업의 약점을 보완합니다. 한 장을 선택하면 나머지 카드는 사라집니다.", COLOR_MUTED)

func _claim_reward(card_id: StringName) -> void:
	var claim_result := cooperative_session.claim_card_reward(local_slot, card_id) if cooperative_session != null else {"ok": run_coordinator.claim_card(local_slot, card_id)}
	if claim_result.ok:
		var card: CardData = catalog[card_id]
		if cooperative_session == null and local_slot == 0 and run_coordinator.run.pending_card_rewards[1]:
			local_slot = 1
			_show_reward()
			overlay_subtitle.text = "P1 보상 획득 완료 · 이어서 P2 보상 카드를 선택하세요."
			return
		_clear_overlay()
		_set_overlay_compact(true)
		overlay_title.text = "카드 획득 완료"
		overlay_subtitle.text = "%s이(가) P%d 덱과 체크포인트에 반영됐습니다." % [card.display_name, local_slot + 1]
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		overlay_content.add_child(row)
		var acquired := preload("res://src/ui/card_button.gd").new()
		acquired.custom_minimum_size = Vector2(280, 260)
		var accent := _scope_color(card.owner_scope)
		acquired.configure(card, "%s · %s" % [_rarity_label(card.rarity), _scope_label(card.owner_scope)], _effect_summary(card), accent, true, "✓ 덱에 추가됨")
		acquired.accessibility_name = "%s 카드, 획득 완료" % card.display_name
		acquired.disabled = true
		acquired.add_theme_stylebox_override("disabled", _panel_style(Color(accent, 0.12), 18, accent, 3, 14, 10))
		row.add_child(acquired)
		_info_panel("현재 덱 · %d장" % run_coordinator.run.decks[local_slot].size(), "보상 선택은 자동 저장됐으며 다음 전투부터 드로우될 수 있습니다.", COLOR_CYAN)
		if cooperative_session == null:
			local_slot = 0
			_add_connection_action("⌁  맵에서 다음 노드 선택", _show_post_reward_destination, COLOR_CYAN)
		elif run_coordinator.run.pending_card_rewards.any(func(pending: bool) -> bool: return pending):
			_info_panel("대원 보상 대기", "상대 대원이 보상을 선택하면 다음 노드 선택이 열립니다.", COLOR_YELLOW)
		else:
			_add_connection_action("⌁  맵에서 다음 노드 선택", _show_post_reward_destination, COLOR_CYAN)

func _show_shop() -> void:
	if game_mode == "duel":
		_show_mode_locked_notice("상점", "상점과 크레딧은 협동 원정 전용입니다.")
		return
	_clear_overlay()
	_set_overlay_immersive()
	overlay_title.text = "ORBITAL BAZAAR · 궤도 상점"
	if not run_coordinator.run.shop_open[local_slot]:
		_set_overlay_compact(true, true)
		overlay_subtitle.text = "현재 항로에서는 상점을 이용할 수 없습니다."
		overlay_content.add_child(_game_status_line([
			["◈", "%d C" % run_coordinator.run.gold[local_slot], COLOR_ORANGE],
			["▤", "현재 덱 %d장" % run_coordinator.run.decks[local_slot].size(), COLOR_BLUE],
			["▣", "상점 노드에서 접근", COLOR_CYAN],
		]))
		_info_panel("상점 접근 조건", "항로에서 상점 노드를 선택한 플레이어만 구매할 수 있습니다. 다음 항로에서 ▣ 상점 아이콘을 선택하세요.", COLOR_ORANGE)
		return
	var inventory := run_coordinator.current_shop(local_slot)
	overlay_subtitle.text = "P%d 보유 크레딧 %d · 공용 카드는 희소성 때문에 10%% 할증" % [local_slot + 1, run_coordinator.run.gold[local_slot]]
	overlay_content.add_child(_game_status_line([
		["◈", "보유 %d C" % run_coordinator.run.gold[local_slot], COLOR_ORANGE],
		["▤", "카드 재고 %d장" % inventory.cards.size(), COLOR_CYAN],
		["✂", "덱 정비 %d C" % inventory.remove_card_cost, Color("#bc8cff")],
	]))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	overlay_content.add_child(row)
	for entry in inventory.cards:
		var card: CardData = catalog[StringName(entry.card_id)]
		var sold := run_coordinator.run.shop_purchases[local_slot].has("card:%s" % String(entry.card_id))
		var button := preload("res://src/ui/card_button.gd").new()
		button.custom_minimum_size = Vector2(200, 236)
		var accent := _scope_color(card.owner_scope)
		button.configure(card, "%s · %s" % [_rarity_label(card.rarity), _scope_label(card.owner_scope)], _effect_summary(card), accent, false, "✓ 판매 완료" if sold else "%d C  ·  구매" % entry.price)
		button.disabled = sold or run_coordinator.run.gold[local_slot] < int(entry.price)
		button.add_theme_stylebox_override("normal", _panel_style(COLOR_PANEL, 16, accent, 2, 12, 8))
		button.add_theme_stylebox_override("hover", _panel_style(Color(accent, 0.18), 16, accent, 3, 12, 8))
		button.add_theme_stylebox_override("disabled", _panel_style(Color("#101725"), 16, Color("#4d5a71"), 1, 12, 8))
		button.pressed.connect(_buy_shop_card.bind(entry))
		row.add_child(button)
	var item_row := HBoxContainer.new()
	item_row.alignment = BoxContainer.ALIGNMENT_CENTER
	item_row.add_theme_constant_override("separation", 10)
	var run_content := RunContentCatalog.build()
	for relic in inventory.relics:
		var relic_sold := run_coordinator.run.shop_purchases[local_slot].has("relic:%s" % String(relic.id))
		var relic_detail := _content_item_by_id(run_content.relics, relic.id)
		var relic_button := _shop_item_button("✦  유물 · %s\n%s\n%s" % [relic.name, _relic_effect_text(relic_detail), "✓ 판매 완료" if relic_sold else "%d C · 장착" % relic.price], COLOR_BLUE, relic_sold or run_coordinator.run.gold[local_slot] < int(relic.price))
		relic_button.pressed.connect(_buy_shop_relic.bind(relic))
		item_row.add_child(relic_button)
	for consumable in inventory.consumables:
		var consumable_sold := run_coordinator.run.shop_purchases[local_slot].has("consumable:%s" % String(consumable.id))
		var consumable_detail := _content_item_by_id(run_content.consumables, consumable.id)
		var consumable_button := _shop_item_button("◆  소비품 · %s\n%s\n%s" % [consumable.name, _consumable_effect_text(consumable_detail), "✓ 판매 완료" if consumable_sold else "%d C · 보관" % consumable.price], COLOR_ORANGE, consumable_sold or run_coordinator.run.gold[local_slot] < int(consumable.price))
		consumable_button.pressed.connect(_buy_shop_consumable.bind(consumable))
		item_row.add_child(consumable_button)
	overlay_content.add_child(item_row)
	var removal_sold := run_coordinator.run.shop_purchases[local_slot].has("service:remove_card")
	var removal_disabled := removal_sold or run_coordinator.run.gold[local_slot] < int(inventory.remove_card_cost) or run_coordinator.run.decks[local_slot].size() <= 5
	var removal_text := "✓ 카드 정비 완료" if removal_sold else "✂  덱에서 카드 1장 제거 · %d C" % inventory.remove_card_cost
	var removal_button := _action_button(removal_text, _show_remove_card_picker.bind(int(inventory.remove_card_cost)), Color("#bc8cff"), 58)
	removal_button.disabled = removal_disabled
	removal_button.custom_minimum_size.x = 620
	removal_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	overlay_content.add_child(removal_button)
	var service_hint := "방문당 1회 · 최소 덱 5장 · 소비 아이템 최대 3개"
	if not removal_sold and run_coordinator.run.gold[local_slot] < int(inventory.remove_card_cost):
		service_hint = "카드 제거에 %d C가 더 필요합니다 · %s" % [int(inventory.remove_card_cost) - run_coordinator.run.gold[local_slot], service_hint]
	_info_panel("정비 서비스", service_hint, Color("#bc8cff"))

func _show_remove_card_picker(cost: int) -> void:
	_clear_overlay()
	overlay_title.text = "덱 정비 · 제거할 카드 선택"
	overlay_subtitle.text = "P%d 덱 %d장 · 카드 1장 제거 %d C · 선택 후 한 번 더 확인합니다." % [local_slot + 1, run_coordinator.run.decks[local_slot].size(), cost]
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	overlay_content.add_child(grid)
	for index in run_coordinator.run.decks[local_slot].size():
		var card_id := StringName(run_coordinator.run.decks[local_slot][index])
		if not catalog.has(card_id):
			continue
		var card: CardData = catalog[card_id]
		var button := preload("res://src/ui/card_button.gd").new()
		button.custom_minimum_size = Vector2(245, 242)
		var accent := _scope_color(card.owner_scope)
		button.configure(card, "%s · %s" % [_rarity_label(card.rarity), _scope_label(card.owner_scope)], _effect_summary(card), accent, false, "제거 후보로 선택")
		button.pressed.connect(_show_remove_card_confirmation.bind(index, cost))
		grid.add_child(button)
	_add_connection_action("←  상점으로 돌아가기", _show_shop, COLOR_MUTED)

func _show_remove_card_confirmation(deck_index: int, cost: int) -> void:
	if deck_index < 0 or deck_index >= run_coordinator.run.decks[local_slot].size():
		_show_shop()
		return
	var card_id := StringName(run_coordinator.run.decks[local_slot][deck_index])
	var card: CardData = catalog[card_id]
	_clear_overlay()
	# A destructive confirmation must keep both the safe exit and the final
	# action visible together. Enlarged Android text needs the taller frame so
	# the warning does not push those choices below the fold.
	if _destructive_confirm_needs_tall_layout():
		_set_overlay_tall()
	else:
		_set_overlay_compact(true)
	overlay_title.text = "카드 제거 확인"
	overlay_subtitle.text = "%s을(를) 덱에서 영구 제거하고 %d C를 사용합니다." % [card.display_name, cost]
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay_content.add_child(row)
	var preview := preload("res://src/ui/card_button.gd").new()
	preview.custom_minimum_size = Vector2(280, 252)
	var accent := _scope_color(card.owner_scope)
	preview.configure(card, "%s · %s" % [_rarity_label(card.rarity), _scope_label(card.owner_scope)], _effect_summary(card), accent, true, "제거 예정")
	preview.disabled = true
	row.add_child(preview)
	_info_panel("되돌릴 수 없는 정비", "확정하면 현재 런의 덱에서 즉시 제거되고 체크포인트에 저장됩니다. 이번 상점에서는 한 번만 이용할 수 있습니다.", COLOR_RED)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	var cancel := _action_button("←  다른 카드 선택", _show_remove_card_picker.bind(cost), COLOR_MUTED, 64)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(cancel)
	var confirm := _action_button("✂  %d C 사용하고 제거" % cost, _remove_shop_card.bind(deck_index, cost), COLOR_RED, 64)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(confirm)
	overlay_content.add_child(actions)

func _remove_shop_card(deck_index: int, cost: int) -> void:
	if not run_coordinator.remove_card(local_slot, deck_index, cost):
		overlay_subtitle.text = "카드를 제거하지 못했습니다. 크레딧과 덱 상태를 다시 확인해 주세요."
		return
	_clear_overlay()
	_set_overlay_minimal()
	overlay_title.text = "덱 정비 완료"
	overlay_subtitle.text = "카드 1장을 제거했습니다. P%d 덱은 이제 %d장입니다." % [local_slot + 1, run_coordinator.run.decks[local_slot].size()]
	_info_panel("체크포인트 저장 완료", "보유 크레딧 %d C · 이번 상점의 카드 제거 서비스를 사용했습니다." % run_coordinator.run.gold[local_slot], Color("#bc8cff"))
	_add_connection_action("▣  상점으로 돌아가기", _show_shop, COLOR_ORANGE)

func _show_consumables() -> void:
	if game_mode == "duel":
		_show_mode_locked_notice("아이템", "유물과 소비 아이템은 결투 밸런스에서 제외됩니다.")
		return
	_clear_overlay()
	_set_overlay_immersive()
	overlay_title.text = "FIELD LOADOUT · 소지품"
	var relic_names: Array[String] = []
	for relic_id in run_coordinator.run.relics[local_slot]:
		for relic in RunContentCatalog.build().relics:
			if String(relic.id) == String(relic_id):
				relic_names.append(String(relic.name))
				break
	var content := RunContentCatalog.build()
	var can_use := active_route_combat and state.phase == CombatState.Phase.PLANNING
	var loadout := HBoxContainer.new()
	loadout.custom_minimum_size.y = 500
	loadout.alignment = BoxContainer.ALIGNMENT_CENTER
	loadout.add_theme_constant_override("separation", 56)
	var loadout_actor := _briefing_actor(_character_portrait(run_coordinator.run.characters[local_slot]), "P%d · %s" % [local_slot + 1, _character_name(run_coordinator.run.characters[local_slot])], "전술 장비 슬롯 3개", _character_color(run_coordinator.run.characters[local_slot]), Vector2(340, 420))
	loadout_actor.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	loadout.add_child(loadout_actor)
	var inventory_column := VBoxContainer.new()
	inventory_column.custom_minimum_size = Vector2(0, 420)
	inventory_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_column.alignment = BoxContainer.ALIGNMENT_CENTER
	inventory_column.add_theme_constant_override("separation", 18)
	var relic_status := Label.new()
	relic_status.text = "✦  활성 유물 %d개%s" % [relic_names.size(), "  ·  " + ", ".join(relic_names) if not relic_names.is_empty() else "  ·  아직 획득한 유물이 없습니다"]
	relic_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	relic_status.add_theme_font_size_override("font_size", 15)
	relic_status.add_theme_color_override("font_color", COLOR_CYAN)
	inventory_column.add_child(relic_status)
	inventory_column.add_child(_consumable_slot_row(content, can_use))
	var inventory_hint := Label.new()
	inventory_hint.text = "행동 선택 중 사용  ·  사용 즉시 소모  ·  유물은 조건 충족 시 자동 발동"
	inventory_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inventory_hint.add_theme_font_size_override("font_size", 13)
	inventory_hint.add_theme_color_override("font_color", COLOR_MUTED)
	inventory_column.add_child(inventory_hint)
	loadout.add_child(inventory_column)
	overlay_content.add_child(loadout)
	if not active_route_combat or state.phase != CombatState.Phase.PLANNING:
		overlay_subtitle.text = "현재 장비 점검 중 · 소비 아이템은 항로 전투의 행동 선택 단계에서 활성화됩니다."
		inventory_column.add_child(_game_status_line([["◆", "소지품 %d/3" % run_coordinator.run.consumables[local_slot].size(), Color("#bc8cff")], ["⌁", "다음 전투에서 사용 가능", COLOR_CYAN]]))
		return
	overlay_subtitle.text = "P%d 소지품 %d / 3 · 사용 즉시 소모되고 체크포인트에 저장됩니다." % [local_slot + 1, run_coordinator.run.consumables[local_slot].size()]
	if run_coordinator.run.consumables[local_slot].is_empty():
		_add_connection_notice("사용 가능한 소비 아이템이 없습니다.", COLOR_MUTED)
		return

func _consumable_slot_row(content: Dictionary, can_use: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inventory: Array = run_coordinator.run.consumables[local_slot]
	for slot in 3:
		var item: Dictionary = {}
		if slot < inventory.size():
			for candidate in content.consumables:
				if String(candidate.id) == String(inventory[slot]):
					item = candidate
					break
		if not item.is_empty() and can_use:
			var action := _action_button("◆ SLOT %d · %s\n%s" % [slot + 1, item.name, _consumable_effect_text(item)], _use_consumable.bind(slot), COLOR_ORANGE, 76)
			action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(action)
			continue
		var panel := PanelContainer.new()
		panel.custom_minimum_size.y = 136
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", _panel_style(Color("#ffffff05") if item.is_empty() else Color("#bc8cff12"), 44, Color.TRANSPARENT, 0, 14, 8))
		var label := Label.new()
		label.text = "○\nSLOT %d · 비어 있음" % (slot + 1) if item.is_empty() else "◆\nSLOT %d · %s\n%s" % [slot + 1, item.name, _consumable_effect_text(item)]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", COLOR_MUTED if item.is_empty() else COLOR_TEXT)
		label.accessibility_name = "소지품 슬롯 %d" % (slot + 1)
		label.accessibility_description = "비어 있음" if item.is_empty() else "%s. %s. 전투 행동 선택 단계에서 사용 가능" % [item.name, _consumable_effect_text(item)]
		panel.add_child(label)
		row.add_child(panel)
	return row

func _use_consumable(item_index: int) -> void:
	var is_guest := cooperative_session != null and cooperative_session.role == CooperativeSession.Role.GUEST
	var result := cooperative_session.use_consumable(local_slot, item_index) if cooperative_session != null else run_coordinator.use_consumable(state, local_slot, item_index, engine)
	if not result.ok:
		overlay_subtitle.text = "아이템을 사용할 수 없습니다: %s" % result.get("error", "unknown")
		return
	if is_guest:
		overlay_subtitle.text = "호스트의 사용 판정을 기다리는 중입니다."
		return
	_show_consumables()
	overlay_subtitle.text = "%s 사용 · %s" % [result.name, result.summary]
	_refresh()

func _consumable_effect_text(item: Dictionary) -> String:
	return {
		"block": "이번 턴 방어 +%d" % int(item.value),
		"energy": "이번 턴 에너지 +%d" % int(item.value),
		"heal": "팀 내구도 +%d" % int(item.value),
		"damage": "적에게 %d 피해" % int(item.value),
		"draw": "카드 %d장 드로우" % int(item.value),
		"duplicate": "첫 손패 1장 임시 복제",
		"escape": "회피 방벽 +20",
		"upgrade": "이번 전투 최대 에너지 +%d" % int(item.value),
	}.get(String(item.effect), String(item.effect))

func _content_item_by_id(items: Array, item_id: Variant) -> Dictionary:
	for item in items:
		if String(item.id) == String(item_id):
			return item
	return {}

func _relic_effect_text(item: Dictionary) -> String:
	if item.is_empty():
		return "자동 발동 장비"
	var trigger: String = {
		"combat_start": "전투 시작",
		"turn_start": "턴 시작",
		"card_played": "카드 사용",
		"support_played": "지원 사용",
		"damage_taken": "피해 받을 때",
		"combat_end": "전투 종료",
	}.get(String(item.trigger), String(item.trigger))
	var effect: String = {
		"block": "방어 +%d" % int(item.value),
		"energy": "에너지 +%d" % int(item.value),
		"damage": "피해 %d" % int(item.value),
		"heal": "내구도 +%d" % int(item.value),
	}.get(String(item.effect), String(item.effect))
	return "%s · %s" % [trigger, effect]

func _buy_shop_card(entry: Dictionary) -> void:
	if run_coordinator.buy_card(local_slot, entry):
		_show_shop()

func _buy_shop_relic(entry: Dictionary) -> void:
	if run_coordinator.buy_relic(local_slot, entry):
		_show_shop()

func _buy_shop_consumable(entry: Dictionary) -> void:
	if run_coordinator.buy_consumable(local_slot, entry):
		_show_shop()

func _shop_item_button(text: String, accent: Color, disabled: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(218, 86)
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.disabled = disabled
	_set_button_accessibility(button, _first_text_line(text), "%s. %s" % [_remaining_text_lines(text), "판매 완료 또는 구매 조건을 충족하지 못했습니다" if disabled else "두 번 탭하여 구매합니다"])
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_stylebox_override("normal", _main_menu_choice_style(accent, 0.07, 3))
	button.add_theme_stylebox_override("hover", _main_menu_choice_style(accent, 0.18, 4))
	button.add_theme_stylebox_override("disabled", _main_menu_choice_style(Color("#59647a"), 0.03, 2))
	button.add_theme_stylebox_override("focus", _main_menu_choice_style(accent, 0.16, 5))
	return button

func _show_mode_locked_notice(title: String, message: String) -> void:
	_clear_overlay()
	_set_overlay_minimal()
	overlay_title.text = title
	overlay_subtitle.text = message
	_add_connection_action("플레이 모드로 이동", _show_mode, COLOR_CYAN)

func _node_label(type: String) -> String:
	return {"combat": "전투", "event": "이벤트", "shop": "상점", "rest": "휴식", "elite": "엘리트", "key_challenge": "열쇠 도전"}.get(type, type)

func _node_icon(type: String) -> String:
	return {"combat": "⚔", "event": "?", "shop": "▣", "rest": "＋", "elite": "◆", "key_challenge": "✦", "boss": "☠", "true_boss": "☄"}.get(type, "·")

func _node_preview(type: String) -> String:
	return {
		"combat": "위험 보통 · 카드 보상",
		"event": "결과 변동 · 협동 선택",
		"shop": "안전 · 카드와 장비 구매",
		"rest": "안전 · 팀 내구도 회복",
		"elite": "위험 높음 · 강화 보상",
		"key_challenge": "위험 매우 높음 · 열쇠 획득",
	}.get(type, "경로 정보를 확인하세요")

func _refresh() -> void:
	_refresh_character_identity()
	_refresh_quick_chat_availability()
	if game_mode == "duel" and duel_state != null:
		_refresh_duel()
		return
	turn_label.text = "TURN %02d" % state.turn
	ready_button.text = "✓  행동 확정"
	team_health_label.text = "팀 내구도   %d / %d" % [state.team_health, state.team_max_health]
	team_health_bar.max_value = state.team_max_health
	team_health_bar.value = state.team_health
	var enemy: EnemyState = state.enemies[0]
	enemy_name_label.text = enemy.display_name
	encounter_label.text = "%s  ·  STAGE %d-%02d" % [_encounter_kind(), run_coordinator.run.stage, run_coordinator.run.step + 1]
	intent_label.text = "⚠  다음 행동 · 팀에 %d 피해" % enemy.intent_damage
	var danger_color := COLOR_RED if enemy.intent_damage >= 18 else COLOR_YELLOW
	intent_label.add_theme_color_override("font_color", danger_color)
	intent_panel.add_theme_stylebox_override("panel", _panel_style(Color("#241221df"), 18, Color(danger_color, 0.62), 2, 14, 7))
	enemy_health_label.text = "%d / %d" % [enemy.health, enemy.max_health]
	enemy_health_bar.max_value = enemy.max_health
	enemy_health_bar.value = enemy.health
	if enemy_art != null:
		_apply_enemy_visual(enemy)
		enemy_art.modulate = Color("#ffb8c5") if enemy.health <= ceili(enemy.max_health * 0.25) else Color.WHITE
	for slot in state.players.size():
		var player: CombatantState = state.players[slot]
		var remaining := player.energy - selected_energy if slot == local_slot else player.energy
		var readiness := "준비 완료" if player.ready else ("내 캐릭터" if slot == local_slot else "선택 중")
		player_detail_labels[slot].text = "에너지  %d / %d   ·   방어 %d   ·   유물 %d\n상태  %s" % [remaining, player.max_energy, player.block, state.relics[slot].size(), readiness]
		player_detail_labels[slot].add_theme_color_override("font_color", COLOR_YELLOW if slot == local_slot else COLOR_TEXT)
		_update_player_readiness(slot, player.ready, slot == local_slot, selected_plays.size() if slot == local_slot else 0)
	status_label.text = _plan_summary(false)
	energy_label.text = "⚡ %d" % maxi(0, state.players[local_slot].energy - selected_energy)
	ready_button.text = "✓  %d장 행동 확정" % selected_plays.size() if not selected_plays.is_empty() else "✓  행동 확정"
	ready_button.disabled = interaction_locked or selected_plays.is_empty() or state.phase != CombatState.Phase.PLANNING
	_set_button_accessibility(ready_button, "행동 확정", "선택한 카드 %d장, 예상 비용 %d. %s" % [selected_plays.size(), selected_energy, "카드를 먼저 선택해야 합니다" if selected_plays.is_empty() else "두 번 탭하여 실행을 확정합니다"])
	_rebuild_hand()
	_sync_android_accessibility.call_deferred()
	queue_redraw()

func _apply_enemy_visual(enemy: EnemyState) -> void:
	var profile: Dictionary = EnemyVisuals.identity_profile(enemy.id, active_route_types)
	var padding: Vector2 = profile["padding"]
	enemy_art.texture = load(String(profile["texture"]))
	enemy_art.offset_left = -padding.x
	enemy_art.offset_top = -padding.y
	enemy_art.offset_right = padding.x
	enemy_art.offset_bottom = padding.y
	enemy_art.accessibility_name = "%s · %s" % [enemy.display_name, _encounter_kind()]
	enemy_art.accessibility_description = String(profile["description"])
	enemy_name_label.accessibility_name = "전투 상대 · %s" % String(profile["identity_name"])
	if enemy_aura != null:
		enemy_aura.configure(profile)

func _refresh_duel() -> void:
	_refresh_quick_chat_availability()
	turn_label.text = "DUEL %02d" % duel_state.turn
	team_health_label.text = "내구도   P1 %d / %d   ·   P2 %d / %d" % [duel_state.health[0], duel_state.max_health[0], duel_state.health[1], duel_state.max_health[1]]
	team_health_bar.max_value = duel_state.max_health[local_slot]
	team_health_bar.value = duel_state.health[local_slot]
	encounter_label.text = "2인 대전  ·  동시 계획"
	enemy_name_label.text = "P1   VS   P2"
	enemy_health_label.text = "먼저 상대 내구도를 0으로 만드세요"
	enemy_health_bar.max_value = duel_state.max_health[1 - local_slot]
	enemy_health_bar.value = duel_state.health[1 - local_slot]
	intent_label.text = "상대 행동 비공개\n양쪽 확정 후 동시 공개"
	for slot in 2:
		var player: CombatantState = duel_state.players[slot]
		var remaining := player.energy - selected_energy if slot == local_slot else player.energy
		var readiness := "행동 확정" if player.ready else ("내 차례" if slot == local_slot else "선택 중")
		player_detail_labels[slot].text = "내구도 %d / %d   ·   에너지 %d / %d\n방어 %d   ·   상태 %s" % [duel_state.health[slot], duel_state.max_health[slot], remaining, player.max_energy, player.block, readiness]
		player_detail_labels[slot].add_theme_color_override("font_color", COLOR_YELLOW if slot == local_slot else COLOR_TEXT)
		_update_player_readiness(slot, player.ready, slot == local_slot, selected_plays.size() if slot == local_slot else 0)
	status_label.text = _plan_summary(true)
	ready_button.text = "✓  %d장 행동 확정" % selected_plays.size() if not selected_plays.is_empty() else "✓  행동 확정"
	_set_button_accessibility(ready_button, "행동 확정", "선택한 카드 %d장, 예상 비용 %d. %s" % [selected_plays.size(), selected_energy, "카드를 먼저 선택해야 합니다" if selected_plays.is_empty() else "상대에게 공개하지 않고 계획을 확정합니다"])
	energy_label.text = "⚡ %d" % maxi(0, duel_state.players[local_slot].energy - selected_energy)
	ready_button.disabled = interaction_locked or selected_plays.is_empty() or duel_state.phase != DuelState.Phase.PLANNING or duel_state.players[local_slot].ready
	if duel_state.phase == DuelState.Phase.FINISHED:
		ready_button.disabled = true
		status_label.text = "무승부" if duel_state.winner == -1 else "P%d 결투 승리" % (duel_state.winner + 1)
		if not overlay.visible:
			_show_duel_outcome.call_deferred()
	_rebuild_hand()
	_sync_android_accessibility.call_deferred()
	queue_redraw()

func _refresh_quick_chat_availability() -> void:
	if quick_chat_button != null:
		quick_chat_button.visible = cooperative_session != null

func _update_player_readiness(slot: int, is_ready: bool, is_local: bool, planned_cards: int) -> void:
	if player_status_visuals.size() <= slot or player_status_badges.size() <= slot:
		return
	var character_id: StringName = duel_state.players[slot].character_id if game_mode == "duel" and duel_state != null else run_coordinator.run.characters[slot]
	var accent := _character_color(character_id)
	var state_name := "ready" if is_ready else ("planning" if is_local and planned_cards > 0 else ("local" if is_local else "waiting"))
	var badge_text := "확정 완료" if is_ready else ("계획 %d장" % planned_cards if is_local and planned_cards > 0 else ("내 선택" if is_local else "상대 선택 중"))
	player_status_visuals[slot].configure(accent)
	player_status_visuals[slot].set_status(state_name)
	player_status_badges[slot].text = badge_text
	player_status_badges[slot].add_theme_stylebox_override("normal", _panel_style(Color("#07101fe8"), 14, accent if state_name != "waiting" else Color("#7d8ba8"), 3 if is_ready else 2, 8, 3))
	player_panels[slot].add_theme_stylebox_override("panel", _panel_style(Color("#07101f66"), 22, Color(accent, 0.88 if is_ready else 0.52), 3 if is_ready else 1, 14, 10))

func _show_duel_outcome() -> void:
	if game_mode != "duel" or duel_state == null or duel_state.phase != DuelState.Phase.FINISHED:
		return
	_clear_overlay()
	_set_overlay_immersive()
	overlay_title.text = "결투 종료 · 무승부" if duel_state.winner == -1 else "결투 종료 · P%d 승리" % (duel_state.winner + 1)
	overlay_subtitle.text = "최종 내구도 P1 %d / %d · P2 %d / %d · %d턴" % [duel_state.health[0], duel_state.max_health[0], duel_state.health[1], duel_state.max_health[1], duel_state.turn]
	var emblem := Label.new()
	emblem.text = "DRAW" if duel_state.winner == -1 else "P%d  VICTORY" % (duel_state.winner + 1)
	emblem.accessibility_name = "결투 결과"
	emblem.accessibility_description = "무승부" if duel_state.winner == -1 else "P%d 승리" % (duel_state.winner + 1)
	emblem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emblem.add_theme_font_size_override("font_size", 52)
	emblem.add_theme_color_override("font_color", COLOR_MUTED if duel_state.winner == -1 else (COLOR_BLUE if duel_state.winner == 0 else COLOR_ORANGE))
	overlay_content.add_child(emblem)
	overlay_content.add_child(_game_status_line([
		["♥", "P1 %d/%d" % [duel_state.health[0], duel_state.max_health[0]], COLOR_BLUE],
		["⌛", "%02d턴" % duel_state.turn, COLOR_CYAN],
		["♥", "P2 %d/%d" % [duel_state.health[1], duel_state.max_health[1]], COLOR_ORANGE],
	]))
	_info_panel("공정한 결투 기록", "원정 성장과 소비 아이템을 제외한 표준 덱 결과입니다. 재대결하면 같은 편성과 초기 조건으로 다시 시작합니다.", COLOR_CYAN)
	if cooperative_session == null or cooperative_session.role == CooperativeSession.Role.HOST:
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 12)
		var rematch := _action_button("↻  같은 편성으로 재대결", _activate_mode.bind("duel"), COLOR_RED, 64)
		rematch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(rematch)
		var expedition := _action_button("✦  협동 원정으로 전환", _activate_mode.bind("cooperative"), COLOR_CYAN, 64)
		expedition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(expedition)
		overlay_content.add_child(actions)
	else:
		_info_panel("호스트 선택 대기", "호스트가 재대결 또는 협동 원정 전환을 선택하면 자동으로 동기화됩니다.", COLOR_MUTED)

func _encounter_kind() -> String:
	if active_route_types.has("true_boss"): return "진 최종 보스"
	if active_route_types.has("key_challenge"): return "열쇠 도전"
	if active_route_types.has("boss"): return "보스 전투"
	if active_route_types.has("elite"): return "엘리트 전투"
	return "일반 전투" if active_route_combat else "훈련 전투"

func _rebuild_hand() -> void:
	for child in hand_container.get_children():
		child.queue_free()
	var active_player: CombatantState = duel_state.players[local_slot] if game_mode == "duel" and duel_state != null else state.players[local_slot]
	if draw_pile_badge != null:
		draw_pile_badge.configure(local_slot, active_player.draw_pile.size(), COLOR_BLUE if local_slot == 0 else COLOR_ORANGE)
	for hand_index in active_player.hand.size():
		var card_id: StringName = active_player.hand[hand_index]
		var card: CardData = catalog[card_id]
		var card_button := preload("res://src/ui/card_button.gd").new()
		var selected := selected_hand_indices.has(hand_index)
		var selection_order := selected_hand_indices.find(hand_index) + 1 if selected else 0
		var card_slot := Control.new()
		card_slot.custom_minimum_size = Vector2(174, 182)
		card_slot.mouse_filter = Control.MOUSE_FILTER_PASS
		card_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
		card_button.position = Vector2(0, 0 if selected else 12)
		card_button.size = Vector2(174, 168)
		var accent := _scope_color(card.owner_scope)
		card_button.configure(card, "%s · %s" % [_rarity_label(card.rarity), _scope_label(card.owner_scope)], _effect_summary(card), accent, selected, "", false, selection_order)
		var base_color := Color(accent, 0.22) if selected else COLOR_PANEL
		card_button.add_theme_stylebox_override("normal", _panel_style(base_color, 16, Color.TRANSPARENT, 0, 12, 8))
		card_button.add_theme_stylebox_override("hover", _panel_style(COLOR_PANEL_SOFT, 16, Color.TRANSPARENT, 0, 12, 8))
		card_button.add_theme_stylebox_override("pressed", _panel_style(Color(accent, 0.30), 16, Color.TRANSPARENT, 0, 12, 8))
		card_button.add_theme_color_override("font_color", COLOR_TEXT)
		card_button.pressed.connect(_on_card_pressed.bind(hand_index, card))
		card_slot.add_child(card_button)
		hand_container.add_child(card_slot)
	_apply_text_scale_tree.call_deferred(hand_container)

func _on_card_pressed(hand_index: int, card: CardData) -> void:
	if interaction_locked:
		return
	if selected_hand_indices.has(hand_index):
		var selected_position := selected_hand_indices.find(hand_index)
		selected_hand_indices.remove_at(selected_position)
		selected_plays.remove_at(selected_position)
		selected_energy -= card.energy_cost
		if haptics_enabled:
			Input.vibrate_handheld(20, 0.18)
		log_label.text = "%s 선택 취소 · %s" % [card.display_name, "행동 큐가 비었습니다." if selected_plays.is_empty() else "%d장 남음" % selected_plays.size()]
		_refresh()
		return
	if selected_plays.size() >= 3:
		_reject_card_selection("%s 선택 불가 · 이미 3장을 골랐습니다. 먼저 한 장을 취소하세요." % card.display_name)
		return
	var available_energy := duel_state.players[local_slot].energy if game_mode == "duel" and duel_state != null else state.players[local_slot].energy
	var remaining_energy := available_energy - selected_energy
	if card.energy_cost > remaining_energy:
		_reject_card_selection("%s 선택 불가 · 필요 에너지 %d / 남은 에너지 %d" % [card.display_name, card.energy_cost, maxi(0, remaining_energy)])
		return
	if card.is_support():
		for play in selected_plays:
			var selected_card: CardData = catalog[play.card_id]
			if selected_card.is_support():
				_reject_card_selection("%s 선택 불가 · 지원 카드는 턴당 1장입니다. 이미 %s 선택됨" % [card.display_name, selected_card.display_name])
				return
	selected_hand_indices.append(hand_index)
	selected_plays.append({"card_id": card.id, "target": 0})
	selected_energy += card.energy_cost
	if haptics_enabled:
		Input.vibrate_handheld(28, 0.22)
	log_label.text = "%d번 · %s · %s · %s · 속도 %d" % [selected_plays.size(), card.display_name, _card_target_label(card, game_mode == "duel"), _effect_summary(card), card.speed]
	_refresh()

func _reject_card_selection(message: String) -> void:
	log_label.text = "⚠  %s" % message
	_play_ui_sound("cancel")
	if haptics_enabled:
		Input.vibrate_handheld(52, 0.38)

func _plan_summary(duel: bool) -> String:
	if selected_plays.is_empty():
		return "P%d 비공개 행동을 선택하세요 · 상대 계획은 확정 전 공개되지 않음" % (local_slot + 1) if duel else "P%d 카드를 최대 3장 선택하세요 · ＋ 지원 0/1 (녹색 배지)" % (local_slot + 1)
	var entries: Array[String] = []
	var support_count := 0
	for index in selected_plays.size():
		var card: CardData = catalog[selected_plays[index].card_id]
		entries.append("%d. %s→%s" % [index + 1, card.display_name, _card_target_label(card, duel)])
		if card.is_support():
			support_count += 1
	var privacy := " · 상대에게 비공개" if duel else " · 지원 %d/1" % support_count
	return "행동 큐  %s · 비용 %d%s" % ["  →  ".join(entries), selected_energy, privacy]

func _card_target_label(card: CardData, duel: bool) -> String:
	if duel:
		return "상대" if card.target == CardData.Target.ENEMY else "나"
	return ["나", "동료", "적", "팀"][card.target]

func _on_ready_pressed() -> void:
	if interaction_locked:
		return
	if game_mode == "duel" and duel_state != null:
		_on_duel_ready_pressed()
		return
	var committed_cards := _cards_for_plays(selected_plays)
	var previous_turn := state.turn
	var previous_enemy_health := state.enemies[0].health
	var previous_team_health := state.team_health
	var previous_event_count := state.event_log.size()
	var local_result := cooperative_session.submit_plan(local_slot, selected_plays) if cooperative_session != null else engine.submit_plan(state, local_slot, selected_plays)
	if not local_result.ok:
		log_label.text = "행동을 확정할 수 없습니다: %s" % local_result.get("error", "unknown")
		return
	var committed_actions: Array[Dictionary] = []
	if cooperative_session == null and local_slot == 0:
		singleplayer_pending_cards.assign(committed_cards)
		selected_hand_indices.clear()
		selected_plays.clear()
		selected_energy = 0
		local_slot = 1
		log_label.text = "P1 왼쪽 대원 확정 · P2 오른쪽 대원의 카드를 선택하세요."
		_refresh()
		return
	if cooperative_session == null:
		for pending_card in singleplayer_pending_cards:
			committed_actions.append({"card": pending_card, "slot": 0})
		for current_card in committed_cards:
			committed_actions.append({"card": current_card, "slot": 1})
		singleplayer_pending_cards.clear()
		engine.resolve_if_ready(state)
		local_slot = 0
	else:
		for current_card in committed_cards:
			committed_actions.append({"card": current_card, "slot": local_slot})
	var resolved := state.turn != previous_turn
	selected_hand_indices.clear()
	selected_plays.clear()
	selected_energy = 0
	var result_label := "상대 준비 대기 중" if cooperative_session != null and state.turn == previous_turn else "턴 해결 완료"
	log_label.text = "%s · 상태 해시 %s…" % [result_label, StateHasher.hash_snapshot(state.to_snapshot()).left(8)]
	if resolved:
		committed_actions = _actions_resolved_since(committed_actions, previous_event_count)
		interaction_locked = true
		await _play_resolution_feedback(committed_actions, previous_enemy_health, previous_team_health)
		_refresh()
		await _play_draw_animation()
		interaction_locked = false
	_refresh()

func _on_duel_ready_pressed() -> void:
	if interaction_locked:
		return
	var committed_cards := _cards_for_plays(selected_plays)
	var acting_slot := local_slot
	var previous_health := duel_state.health.duplicate()
	var result := cooperative_session.submit_duel_plan(local_slot, selected_plays) if cooperative_session != null else duel_engine.submit_plan(duel_state, local_slot, selected_plays)
	if not result.ok:
		log_label.text = "결투 행동을 확정할 수 없습니다: %s" % result.get("error", "unknown")
		return
	if cooperative_session == null:
		duel_save_store.save(duel_state)
	selected_hand_indices.clear()
	selected_plays.clear()
	selected_energy = 0
	if cooperative_session == null:
		if duel_state.plans.size() == 1:
			local_slot = 1 - local_slot
			log_label.text = "기기를 상대에게 건네주세요 · P%d 행동 선택" % (local_slot + 1)
		else:
			duel_engine.resolve_if_ready(duel_state)
			duel_save_store.save(duel_state)
			local_slot = 0
			log_label.text = "동시 행동 해결 완료 · 상태 해시 %s…" % StateHasher.hash_snapshot(duel_state.to_snapshot()).left(8)
			interaction_locked = true
			var target_slot := 1 - acting_slot
			var committed_actions: Array[Dictionary] = []
			for card in committed_cards:
				committed_actions.append({"card": card, "slot": acting_slot})
			await _play_resolution_feedback(committed_actions, int(previous_health[target_slot]), int(previous_health[acting_slot]))
			_refresh()
			await _play_draw_animation()
			interaction_locked = false
	else:
		log_label.text = "상대 행동 확정을 기다리는 중입니다."
	_refresh()

func _cards_for_plays(plays: Array[Dictionary]) -> Array[CardData]:
	var result: Array[CardData] = []
	for play in plays:
		if catalog.has(play.card_id):
			result.append(catalog[play.card_id])
	return result

func _actions_resolved_since(candidate_actions: Array[Dictionary], event_start: int) -> Array[Dictionary]:
	var remaining: Array[Dictionary] = candidate_actions.duplicate()
	var resolved_actions: Array[Dictionary] = []
	for event_index in range(event_start, state.event_log.size()):
		var event: Dictionary = state.event_log[event_index]
		if String(event.get("type", "")) != "card_played":
			continue
		var event_slot := int(event.get("slot", -1))
		var event_card_id := StringName(event.get("card_id", ""))
		for candidate_index in remaining.size():
			var candidate: Dictionary = remaining[candidate_index]
			var candidate_card: CardData = candidate.card
			if int(candidate.slot) == event_slot and candidate_card.id == event_card_id:
				resolved_actions.append(candidate)
				remaining.remove_at(candidate_index)
				break
	return resolved_actions

func _play_resolution_feedback(actions: Array[Dictionary], previous_enemy_health: int, previous_team_health: int) -> void:
	if actions.is_empty() or battle_fx_layer == null:
		return
	actions.sort_custom(_sort_action_animation)
	var incremental_health := game_mode != "duel"
	var visual_enemy_health := previous_enemy_health
	var visual_team_health := previous_team_health
	var final_enemy_health := state.enemies[0].health if incremental_health else previous_enemy_health
	var final_team_health := state.team_health if incremental_health else previous_team_health
	var remaining_enemy_damage := maxi(0, previous_enemy_health - final_enemy_health)
	var remaining_damage_cards := 0
	for action in actions:
		if _card_effect_amount(action.card, "damage") > 0:
			remaining_damage_cards += 1
	if incremental_health:
		_set_cooperative_health_preview(visual_enemy_health, visual_team_health)
	battle_fx_layer.visible = true
	for action_index in actions.size():
		for child in battle_fx_layer.get_children():
			child.queue_free()
		await get_tree().process_frame
		var card: CardData = actions[action_index].card
		var source_slot := int(actions[action_index].slot)
		var spatial_effect: CombatEffectVisual = preload("res://src/ui/combat_effect_visual.gd").new()
		spatial_effect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var source_character: StringName = duel_state.players[source_slot].character_id if game_mode == "duel" and duel_state != null else run_coordinator.run.characters[source_slot]
		var single_card: Array[CardData] = [card]
		spatial_effect.configure(_primary_effect_type(single_card), source_slot, reduce_motion, source_character)
		battle_fx_layer.add_child(spatial_effect)
		var stack := VBoxContainer.new()
		stack.set_anchors_preset(Control.PRESET_CENTER)
		stack.offset_left = -220
		stack.offset_right = 220
		stack.offset_top = -140
		stack.offset_bottom = 20
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		battle_fx_layer.add_child(stack)
		var cue := Label.new()
		cue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cue.add_theme_font_size_override("font_size", 16)
		cue.add_theme_color_override("font_color", _character_color(source_character))
		cue.text = "P%d  ·  ACTION %d / %d" % [source_slot + 1, action_index + 1, actions.size()]
		stack.add_child(cue)
		var card_label := Label.new()
		card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_label.add_theme_font_size_override("font_size", 31)
		card_label.add_theme_color_override("font_color", _resolution_color(single_card))
		card_label.add_theme_stylebox_override("normal", _panel_style(Color("#07101ff2"), 22, _resolution_color(single_card), 3, 30, 15))
		card_label.text = "  %s  " % card.display_name
		stack.add_child(card_label)
		var result := Label.new()
		result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		result.add_theme_font_size_override("font_size", 20)
		result.add_theme_color_override("font_color", COLOR_TEXT)
		result.text = _card_resolution_text(card)
		stack.add_child(result)
		battle_fx_layer.accessibility_description = "%s. %s. %s" % [card.display_name, spatial_effect.effect_description(), result.text]
		_play_ui_sound("confirm")
		if reduce_motion:
			await get_tree().create_timer(0.42).timeout
		else:
			stack.modulate = Color(1, 1, 1, 0)
			stack.scale = Vector2(0.80, 0.80)
			stack.pivot_offset = Vector2(220, 80)
			var reveal := create_tween().set_parallel(true)
			reveal.tween_property(stack, "modulate", Color.WHITE, 0.14)
			reveal.tween_property(stack, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			create_tween().tween_property(spatial_effect, "progress", 1.0, 0.46).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
			await reveal.finished
			await get_tree().create_timer(0.18).timeout
		if incremental_health:
			var card_damage := _card_effect_amount(card, "damage")
			var card_heal := _card_effect_amount(card, "heal")
			if card_damage > 0:
				remaining_damage_cards -= 1
				var applied_damage := remaining_enemy_damage if remaining_damage_cards == 0 else mini(card_damage, remaining_enemy_damage)
				remaining_enemy_damage -= applied_damage
				visual_enemy_health -= applied_damage
				await _animate_health_preview(enemy_health_bar, visual_enemy_health)
				enemy_health_label.text = "%d / %d" % [visual_enemy_health, state.enemies[0].max_health]
				await _play_card_impact_feedback(spatial_effect, applied_damage, source_character, visual_enemy_health == 0)
			if card_heal > 0:
				visual_team_health = mini(state.team_max_health, visual_team_health + card_heal)
				await _animate_health_preview(team_health_bar, visual_team_health)
				team_health_label.text = "팀 내구도   %d / %d" % [visual_team_health, state.team_max_health]
		if reduce_motion:
			await get_tree().create_timer(0.18).timeout
		else:
			await get_tree().create_timer(0.14).timeout
			var dismiss := create_tween()
			dismiss.tween_property(stack, "modulate", Color(1, 1, 1, 0), 0.12)
			await dismiss.finished
	if incremental_health and visual_team_health != final_team_health:
		await _animate_health_preview(team_health_bar, final_team_health)
		team_health_label.text = "팀 내구도   %d / %d" % [final_team_health, state.team_max_health]
		await get_tree().create_timer(0.20 if reduce_motion else 0.32).timeout
	if incremental_health and final_enemy_health == 0:
		await _play_enemy_defeat_feedback()
	battle_fx_layer.visible = false

func _play_card_impact_feedback(effect_visual: CombatEffectVisual, amount: int, source_character: StringName, lethal: bool) -> void:
	if amount <= 0:
		return
	var impact := Label.new()
	impact.text = "-%d" % amount
	impact.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	impact.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	impact.position = Vector2(size.x * 0.5 - 70, size.y * 0.29)
	impact.size = Vector2(140, 90)
	impact.add_theme_font_size_override("font_size", 42 if lethal else 34)
	impact.add_theme_color_override("font_color", Color.WHITE)
	impact.add_theme_stylebox_override("normal", _panel_style(Color(_character_color(source_character), 0.32), 45, _character_color(source_character), 3, 12, 5))
	impact.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle_fx_layer.add_child(impact)
	if reduce_motion:
		await get_tree().create_timer(0.20).timeout
		return
	impact.scale = Vector2(0.45, 0.45)
	impact.pivot_offset = impact.size * 0.5
	var hit := create_tween().set_parallel(true)
	hit.tween_property(impact, "scale", Vector2(1.18, 1.18), 0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	hit.tween_property(impact, "modulate", Color.WHITE, 0.08)
	var original_enemy_position := enemy_art.position
	var shake := create_tween()
	shake.tween_property(enemy_art, "position", original_enemy_position + Vector2(-12, 3), 0.045)
	shake.tween_property(enemy_art, "position", original_enemy_position + Vector2(10, -2), 0.045)
	shake.tween_property(enemy_art, "position", original_enemy_position, 0.055)
	await hit.finished
	var fade := create_tween().set_parallel(true)
	fade.tween_property(impact, "scale", Vector2(1.42, 1.42), 0.16)
	fade.tween_property(impact, "modulate:a", 0.0, 0.16)
	await fade.finished

func _play_enemy_defeat_feedback() -> void:
	for child in battle_fx_layer.get_children():
		child.queue_free()
	await get_tree().process_frame
	var flash := ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color("#c9fff622")
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle_fx_layer.add_child(flash)
	var finish_label := Label.new()
	finish_label.text = "TARGET  DESTROYED\n전투 구역 확보"
	finish_label.accessibility_name = "적 격파"
	finish_label.accessibility_description = "마지막 카드 효과가 적용되어 전투에서 승리했습니다."
	finish_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	finish_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	finish_label.set_anchors_preset(Control.PRESET_CENTER)
	finish_label.offset_left = -280
	finish_label.offset_right = 280
	finish_label.offset_top = -82
	finish_label.offset_bottom = 82
	finish_label.add_theme_font_size_override("font_size", 30)
	finish_label.add_theme_color_override("font_color", COLOR_CYAN)
	finish_label.add_theme_stylebox_override("normal", _panel_style(Color("#07101fee"), 28, COLOR_CYAN, 3, 28, 18))
	battle_fx_layer.add_child(finish_label)
	battle_fx_layer.accessibility_description = "적 격파. 전투 구역 확보."
	_play_ui_sound("confirm")
	if reduce_motion:
		await get_tree().create_timer(0.65).timeout
		return
	finish_label.scale = Vector2(0.72, 0.72)
	finish_label.pivot_offset = Vector2(280, 82)
	var original_modulate := enemy_art.modulate
	var defeat := create_tween().set_parallel(true)
	defeat.tween_property(flash, "color:a", 0.0, 0.52)
	defeat.tween_property(finish_label, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	defeat.tween_property(enemy_art, "modulate", Color(1.7, 1.7, 1.7, 0.12), 0.48)
	await defeat.finished
	await get_tree().create_timer(0.38).timeout
	enemy_art.modulate = original_modulate

func _card_effect_amount(card: CardData, effect_type: String) -> int:
	var total := 0
	for effect in card.effects:
		if String(effect.get("type", "")) == effect_type:
			total += int(effect.get("amount", 0))
	return total

func _set_cooperative_health_preview(enemy_health: int, team_health: int) -> void:
	enemy_health_label.text = "%d / %d" % [enemy_health, state.enemies[0].max_health]
	enemy_health_bar.value = enemy_health
	team_health_label.text = "팀 내구도   %d / %d" % [team_health, state.team_max_health]
	team_health_bar.value = team_health

func _animate_health_preview(bar: ProgressBar, target_value: int) -> void:
	if reduce_motion:
		bar.value = target_value
		return
	var health_tween := create_tween()
	health_tween.tween_property(bar, "value", target_value, 0.18).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	await health_tween.finished

func _sort_action_animation(a: Dictionary, b: Dictionary) -> bool:
	var card_a: CardData = a.card
	var card_b: CardData = b.card
	if card_a.speed != card_b.speed:
		return card_a.speed < card_b.speed
	return int(a.slot) < int(b.slot)

func _card_resolution_text(card: CardData) -> String:
	var parts: Array[String] = []
	for effect in card.effects:
		match String(effect.get("type", "")):
			"damage": parts.append("피해 %d" % int(effect.amount))
			"block": parts.append("방어 %d" % int(effect.amount))
			"heal": parts.append("회복 %d" % int(effect.amount))
			"energy": parts.append("에너지 +%d" % int(effect.amount))
	return " · ".join(parts)

func _play_draw_animation() -> void:
	if reduce_motion or hand_container == null or hand_container.get_child_count() == 0:
		return
	await get_tree().process_frame
	var longest: Tween
	for card_index in hand_container.get_child_count():
		var card := hand_container.get_child(card_index) as Control
		var target_position := card.position
		var deck_origin := Vector2(-170 - card_index * 18, target_position.y)
		if draw_pile_badge != null:
			deck_origin = hand_container.to_local(draw_pile_badge.global_position + draw_pile_badge.size * 0.5) - card.size * 0.5
		card.position = deck_origin
		card.modulate = Color(1, 1, 1, 0)
		var draw := create_tween()
		draw.tween_interval(card_index * 0.055)
		draw.set_parallel(true)
		draw.tween_property(card, "position", target_position, 0.24).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		draw.tween_property(card, "modulate", Color.WHITE, 0.18)
		longest = draw
	if longest != null:
		_play_ui_sound("open")
		await longest.finished

func _primary_effect_type(cards: Array[CardData]) -> String:
	for priority in ["damage", "block", "heal", "energy"]:
		for card in cards:
			for effect in card.effects:
				if String(effect.get("type", "")) == priority:
					return priority
	return "damage"

func _resolution_color(cards: Array[CardData]) -> Color:
	for card in cards:
		for effect in card.effects:
			match String(effect.get("type", "")):
				"damage": return COLOR_RED
				"block": return COLOR_BLUE
				"heal": return COLOR_CYAN
	return COLOR_YELLOW

func _resolution_result_text(cards: Array[CardData], enemy_damage: int, team_delta: int) -> String:
	var parts: Array[String] = []
	if enemy_damage > 0:
		parts.append("적 내구도 −%d" % enemy_damage)
	if team_delta < 0:
		parts.append("팀 내구도 −%d" % abs(team_delta))
	elif team_delta > 0:
		parts.append("팀 내구도 +%d" % team_delta)
	var block_total := 0
	var energy_total := 0
	for card in cards:
		for effect in card.effects:
			if String(effect.get("type", "")) == "block": block_total += int(effect.amount)
			if String(effect.get("type", "")) == "energy": energy_total += int(effect.amount)
	if block_total > 0: parts.append("방어 +%d" % block_total)
	if energy_total > 0: parts.append("에너지 +%d" % energy_total)
	return "  ·  ".join(parts) if not parts.is_empty() else "행동 해결 완료"

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

func _scope_label(scope: CardData.Scope) -> String:
	return ["수호자", "기술자", "해커", "강습병", "공용", "의무관", "항법사"][scope]

func _scope_color(scope: CardData.Scope) -> Color:
	match scope:
		CardData.Scope.GUARDIAN: return COLOR_BLUE
		CardData.Scope.ENGINEER: return COLOR_ORANGE
		CardData.Scope.HACKER: return Color("#bc8cff")
		CardData.Scope.ASSAULT: return COLOR_RED
		CardData.Scope.MEDIC: return Color("#55d99a")
		CardData.Scope.NAVIGATOR: return Color("#42d7d7")
		_: return COLOR_CYAN

func _panel_style(color: Color, radius: int, border_color: Color = Color.TRANSPARENT, border_width: int = 0, horizontal_margin: int = 18, vertical_margin: int = 14) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	var subtle_border := 0
	style.border_width_left = subtle_border
	style.border_width_top = subtle_border
	style.border_width_right = subtle_border
	style.border_width_bottom = subtle_border
	style.border_color = Color(border_color, minf(border_color.a, 0.42))
	style.content_margin_left = horizontal_margin
	style.content_margin_right = horizontal_margin
	style.content_margin_top = vertical_margin
	style.content_margin_bottom = vertical_margin
	return style

func _focus_style(accent: Color, radius: int) -> StyleBoxFlat:
	var style := _panel_style(Color(accent, 0.22), radius, Color.WHITE, 0, 18, 14)
	style.set_border_width_all(3)
	style.border_color = Color.WHITE
	return style
