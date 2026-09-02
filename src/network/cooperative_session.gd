class_name CooperativeSession
extends RefCounted

enum Role { HOST, GUEST }

signal snapshot_received(snapshot: Dictionary, state_hash: String)
signal run_snapshot_received(snapshot: Dictionary)
signal duel_snapshot_received(snapshot: Dictionary, state_hash: String)
signal game_mode_changed(mode: String)
signal session_error(code: String, detail: String)
signal peer_ready(slot: int, ready: bool)

var role: Role
var transport: SessionTransport
var engine: CombatEngine
var combat_state: CombatState
var run_coordinator: RunCoordinator
var duel_engine: DuelEngine
var duel_state: DuelState
var duel_save_store := DuelSaveStore.new()
var game_mode := "cooperative"
var remote_snapshot: Dictionary = {}
var outgoing_sequence := 0
var incoming_sequence := 0

func _init(session_role: Role, session_transport: SessionTransport, combat_engine: CombatEngine = null, initial_state: CombatState = null, coordinator: RunCoordinator = null) -> void:
	role = session_role
	transport = session_transport
	engine = combat_engine
	combat_state = initial_state
	run_coordinator = coordinator
	transport.message_received.connect(_on_message)
	transport.transport_error.connect(func(code: String, detail: String) -> void: session_error.emit(code, detail))
	transport.state_changed.connect(_on_transport_state_changed)
	if role == Role.HOST and transport.get_state() == "connected":
		_publish_snapshot("session_started")
		_publish_run_snapshot("session_started")

func submit_plan(slot: int, plays: Array[Dictionary]) -> Dictionary:
	if game_mode != "cooperative":
		return _error("cooperative_mode_inactive")
	if role == Role.HOST:
		if engine == null or combat_state == null:
			return _error("host_state_missing")
		var result := engine.submit_plan(combat_state, slot, plays)
		if not result.ok:
			return result
		peer_ready.emit(slot, true)
		_publish_snapshot("plan_accepted")
		_resolve_if_ready()
		return result
	if slot != 1:
		return _error("guest_slot_forbidden")
	var sent := _send("plan", {"slot": slot, "turn": _known_turn(), "plays": plays})
	return {"ok": sent} if sent else _error("send_failed")

func request_resync() -> bool:
	return _send("resync_request", {"last_seq": incoming_sequence})

func set_game_mode(mode: String) -> Dictionary:
	if role != Role.HOST:
		return _error("host_only_mode")
	if not mode in ["cooperative", "duel"]:
		return _error("unknown_game_mode")
	game_mode = mode
	if mode == "duel":
		if run_coordinator == null or run_coordinator.run == null:
			return _error("host_run_missing")
		duel_engine = DuelEngine.new(FullCardCatalog.build())
		duel_state = duel_engine.create_duel(run_coordinator.run.characters, [
			run_coordinator.starter_deck_for(run_coordinator.run.characters[0]),
			run_coordinator.starter_deck_for(run_coordinator.run.characters[1]),
		])
		duel_save_store.save(duel_state)
	else:
		duel_state = null
		duel_engine = null
		duel_save_store.clear()
	game_mode_changed.emit(game_mode)
	_send("game_mode", {"mode": game_mode})
	if mode == "duel":
		_publish_duel_snapshot("duel_started")
	else:
		_publish_snapshot("cooperative_resumed")
	return {"ok": true, "mode": game_mode}

func submit_duel_plan(slot: int, plays: Array[Dictionary]) -> Dictionary:
	if game_mode != "duel":
		return _error("duel_not_active")
	if role == Role.HOST:
		if duel_engine == null or duel_state == null:
			return _error("host_duel_missing")
		var result := duel_engine.submit_plan(duel_state, slot, plays)
		if not result.ok:
			return result
		duel_save_store.save(duel_state)
		_publish_duel_snapshot("duel_plan_accepted")
		_resolve_duel_if_ready()
		return result
	if slot != 1:
		return _error("guest_slot_forbidden")
	return {"ok": _send("duel_plan", {"slot": slot, "turn": _known_duel_turn(), "plays": plays})}

func select_route(slot: int, node_id: String) -> Dictionary:
	if game_mode != "cooperative":
		return _error("cooperative_mode_inactive")
	if role == Role.HOST:
		if run_coordinator == null:
			return _error("host_run_missing")
		var result := run_coordinator.choose_route(slot, node_id)
		if result.ok:
			_publish_run_snapshot("route_selected")
		return result
	if slot != 1:
		return _error("guest_slot_forbidden")
	return {"ok": _send("route_select", {"slot": slot, "node_id": node_id})}

func select_character(slot: int, character_id: StringName) -> Dictionary:
	if game_mode != "cooperative":
		return _error("cooperative_mode_inactive")
	if role == Role.HOST:
		if run_coordinator == null:
			return _error("host_run_missing")
		var result := run_coordinator.select_character(slot, character_id)
		if result.ok:
			_publish_run_snapshot("character_selected")
		return result
	if slot != 1:
		return _error("guest_slot_forbidden")
	return {"ok": _send("character_select", {"slot": slot, "character_id": String(character_id)})}

func submit_event_choice(slot: int, choice_index: int) -> Dictionary:
	if game_mode != "cooperative":
		return _error("cooperative_mode_inactive")
	if role == Role.HOST:
		if run_coordinator == null:
			return _error("host_run_missing")
		var result := run_coordinator.submit_event_choice(slot, choice_index)
		if result.ok:
			_publish_run_snapshot("event_choice")
		return result
	if slot != 1:
		return _error("guest_slot_forbidden")
	return {"ok": _send("event_choice", {"slot": slot, "choice": choice_index})}

func use_consumable(slot: int, item_index: int) -> Dictionary:
	if game_mode != "cooperative":
		return _error("cooperative_mode_inactive")
	if role == Role.HOST:
		if run_coordinator == null or engine == null or combat_state == null:
			return _error("host_state_missing")
		var result := run_coordinator.use_consumable(combat_state, slot, item_index, engine)
		if result.ok:
			_publish_snapshot("consumable_used")
			_publish_run_snapshot("consumable_used")
		return result
	if slot != 1:
		return _error("guest_slot_forbidden")
	return {"ok": _send("use_consumable", {"slot": slot, "index": item_index})}

func replace_combat_state(next_state: CombatState) -> void:
	combat_state = next_state
	if role == Role.HOST:
		_publish_snapshot("encounter_started")

func publish_run_state(reason: String) -> bool:
	return _publish_run_snapshot(reason)

func poll() -> void:
	transport.poll()

func close() -> void:
	transport.close()

func _on_message(raw: String) -> void:
	var message := SessionProtocol.decode(raw)
	if not message.ok:
		session_error.emit(message.error, "message rejected")
		return
	if int(message.seq) <= incoming_sequence:
		session_error.emit("stale_sequence", str(message.seq))
		return
	incoming_sequence = int(message.seq)
	if role == Role.HOST:
		_handle_host_message(message.type, message.payload)
	else:
		_handle_guest_message(message.type, message.payload)

func _on_transport_state_changed(next_state: String) -> void:
	if next_state in ["disconnected", "closed", "error"]:
		session_error.emit("peer_disconnected", next_state)
		return
	if next_state == "connected" and role == Role.HOST:
		_send("game_mode", {"mode": game_mode})
		if game_mode == "duel" and duel_state != null:
			_publish_duel_snapshot("session_started")
		else:
			_publish_snapshot("session_started")
			_publish_run_snapshot("session_started")

func _handle_host_message(message_type: String, payload: Dictionary) -> void:
	if game_mode == "duel" and message_type not in ["duel_plan", "resync_request"]:
		_send_rejection("cooperative_mode_inactive")
		return
	match message_type:
		"duel_plan":
			if game_mode != "duel" or duel_state == null or int(payload.get("slot", -1)) != 1:
				_send_rejection("guest_duel_forbidden")
				return
			if int(payload.get("turn", -1)) != duel_state.turn:
				_send_rejection("duel_turn_mismatch")
				_publish_duel_snapshot("duel_resync")
				return
			var duel_plays: Array[Dictionary] = []
			for play in payload.get("plays", []):
				if play is Dictionary:
					duel_plays.append(play)
			var duel_result := duel_engine.submit_plan(duel_state, 1, duel_plays)
			if not duel_result.ok:
				_send_rejection(duel_result.error)
				return
			duel_save_store.save(duel_state)
			_publish_duel_snapshot("duel_plan_accepted")
			_resolve_duel_if_ready()
		"character_select":
			if run_coordinator == null or int(payload.get("slot", -1)) != 1:
				_send_rejection("guest_character_forbidden")
				return
			var character_result := run_coordinator.select_character(1, StringName(payload.get("character_id", "")))
			if not character_result.ok:
				_send_rejection(character_result.error)
				return
			_publish_run_snapshot("character_selected")
		"use_consumable":
			if run_coordinator == null or int(payload.get("slot", -1)) != 1:
				_send_rejection("guest_consumable_forbidden")
				return
			var item_result := run_coordinator.use_consumable(combat_state, 1, int(payload.get("index", -1)), engine)
			if not item_result.ok:
				_send_rejection(item_result.error)
				return
			_publish_snapshot("consumable_used")
			_publish_run_snapshot("consumable_used")
		"event_choice":
			if run_coordinator == null or int(payload.get("slot", -1)) != 1:
				_send_rejection("guest_event_forbidden")
				return
			var event_result := run_coordinator.submit_event_choice(1, int(payload.get("choice", -1)))
			if not event_result.ok:
				_send_rejection(event_result.error)
				return
			_publish_run_snapshot("event_choice")
		"route_select":
			if run_coordinator == null or int(payload.get("slot", -1)) != 1:
				_send_rejection("guest_route_forbidden")
				return
			var result := run_coordinator.choose_route(1, String(payload.get("node_id", "")))
			if not result.ok:
				_send_rejection(result.error)
				return
			_publish_run_snapshot("route_selected")
		"plan":
			if int(payload.get("slot", -1)) != 1:
				_send_rejection("guest_slot_forbidden")
				return
			if int(payload.get("turn", -1)) != combat_state.turn:
				_send_rejection("turn_mismatch")
				_publish_snapshot("resync")
				return
			var plays: Array[Dictionary] = []
			for play in payload.get("plays", []):
				if play is Dictionary:
					plays.append(play)
			var result := engine.submit_plan(combat_state, 1, plays)
			if not result.ok:
				_send_rejection(result.error)
				return
			peer_ready.emit(1, true)
			_publish_snapshot("plan_accepted")
			_resolve_if_ready()
		"resync_request":
			if game_mode == "duel":
				_publish_duel_snapshot("resync")
			else:
				_publish_snapshot("resync")
				_publish_run_snapshot("resync")
		_:
			_send_rejection("host_message_forbidden")

func _handle_guest_message(message_type: String, payload: Dictionary) -> void:
	match message_type:
		"game_mode":
			var next_mode := String(payload.get("mode", ""))
			if not next_mode in ["cooperative", "duel"]:
				session_error.emit("invalid_game_mode", next_mode)
				return
			game_mode = next_mode
			if next_mode == "cooperative":
				duel_state = null
			game_mode_changed.emit(game_mode)
		"duel_snapshot":
			var duel_snapshot: Variant = payload.get("state", null)
			var duel_hash := String(payload.get("state_hash", ""))
			if not duel_snapshot is Dictionary or duel_hash.is_empty() or StateHasher.hash_snapshot(duel_snapshot) != duel_hash:
				session_error.emit("invalid_duel_snapshot", "missing or mismatched state")
				return
			duel_state = DuelState.from_snapshot(duel_snapshot)
			game_mode = "duel"
			duel_snapshot_received.emit(duel_state.to_snapshot(), duel_hash)
		"run_snapshot":
			var run_snapshot: Variant = payload.get("state", null)
			if not run_snapshot is Dictionary:
				session_error.emit("invalid_run_snapshot", "missing state")
				return
			run_snapshot_received.emit(RunState._normalize_json_numbers(run_snapshot))
		"snapshot":
			var snapshot: Variant = payload.get("state", null)
			var expected_hash := String(payload.get("state_hash", ""))
			if not snapshot is Dictionary or expected_hash.is_empty():
				session_error.emit("invalid_snapshot", "missing state or hash")
				return
			var actual_hash := StateHasher.hash_snapshot(snapshot)
			if actual_hash != expected_hash:
				session_error.emit("hash_mismatch", "%s!=%s" % [actual_hash, expected_hash])
				request_resync()
				return
			remote_snapshot = RunState._normalize_json_numbers(snapshot)
			snapshot_received.emit(remote_snapshot, expected_hash)
		"reject":
			session_error.emit(String(payload.get("code", "rejected")), "host rejected command")
		_:
			session_error.emit("guest_message_forbidden", message_type)

func _resolve_if_ready() -> void:
	if combat_state.plans.size() != combat_state.players.size():
		return
	var result := engine.resolve_if_ready(combat_state)
	if result.ok:
		_publish_snapshot("turn_resolved")

func _resolve_duel_if_ready() -> void:
	if duel_state == null or duel_state.plans.size() != 2:
		return
	var result := duel_engine.resolve_if_ready(duel_state)
	if result.ok:
		duel_save_store.save(duel_state)
		_publish_duel_snapshot("duel_turn_resolved")

func _publish_duel_snapshot(reason: String) -> bool:
	if role != Role.HOST or duel_state == null:
		return false
	var snapshot := duel_state.to_snapshot()
	return _send("duel_snapshot", {"reason": reason, "state": snapshot, "state_hash": StateHasher.hash_snapshot(snapshot)})

func _publish_snapshot(reason: String) -> bool:
	if role != Role.HOST or combat_state == null:
		return false
	var snapshot := combat_state.to_snapshot()
	return _send("snapshot", {
		"reason": reason,
		"state": snapshot,
		"state_hash": StateHasher.hash_snapshot(snapshot),
	})

func _publish_run_snapshot(reason: String) -> bool:
	if role != Role.HOST or run_coordinator == null or run_coordinator.run == null:
		return false
	return _send("run_snapshot", {"reason": reason, "state": run_coordinator.run.to_snapshot()})

func _send_rejection(code: String) -> void:
	_send("reject", {"code": code})

func _send(message_type: String, payload: Dictionary) -> bool:
	outgoing_sequence += 1
	return transport.send_message(SessionProtocol.encode(message_type, outgoing_sequence, payload))

func _known_turn() -> int:
	if combat_state != null:
		return combat_state.turn
	return int(remote_snapshot.get("turn", 1))

func _known_duel_turn() -> int:
	return duel_state.turn if duel_state != null else 1

static func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code}
