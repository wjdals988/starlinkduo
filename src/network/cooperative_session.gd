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
var duel_save_store: DuelSaveStore
var game_mode := "cooperative"
var remote_snapshot: Dictionary = {}
var guest_pending_duel_plays: Array[Dictionary] = []
var guest_duel_nonce := ""
var guest_duel_commit_turn := -1
var host_guest_duel_commitment: Dictionary = {}
var outgoing_sequence := 0
var incoming_sequence := 0

func _init(session_role: Role, session_transport: SessionTransport, combat_engine: CombatEngine = null, initial_state: CombatState = null, coordinator: RunCoordinator = null, session_duel_store: DuelSaveStore = null) -> void:
	role = session_role
	transport = session_transport
	engine = combat_engine
	combat_state = initial_state
	run_coordinator = coordinator
	duel_save_store = session_duel_store if session_duel_store != null else DuelSaveStore.new()
	transport.message_received.connect(_on_message)
	transport.transport_error.connect(_on_transport_error)
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
	if mode == "duel" and (run_coordinator == null or run_coordinator.run == null):
		return _error("host_run_missing")
	host_guest_duel_commitment.clear()
	guest_pending_duel_plays.clear()
	guest_duel_nonce = ""
	guest_duel_commit_turn = -1
	duel_save_store.clear_pending()
	game_mode = mode
	if mode == "duel":
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
		_request_duel_reveal_if_ready()
		return result
	if slot != 1:
		return _error("guest_slot_forbidden")
	if not guest_pending_duel_plays.is_empty():
		return _error("duel_plan_already_committed")
	guest_pending_duel_plays = plays.duplicate(true)
	guest_duel_nonce = Crypto.new().generate_random_bytes(16).hex_encode()
	var turn := _known_duel_turn()
	guest_duel_commit_turn = turn
	var commitment := _duel_plan_commitment(turn, guest_pending_duel_plays, guest_duel_nonce)
	var pending_error := duel_save_store.save_pending_commitment({
		"role": "guest",
		"duel_id": String(duel_state.duel_id),
		"turn": turn,
		"commitment": commitment,
		"plays": guest_pending_duel_plays,
		"nonce": guest_duel_nonce,
	})
	if pending_error != OK:
		_clear_guest_duel_commitment()
		return _error("duel_commitment_persist_failed")
	if not _send("duel_commit", {"slot": slot, "turn": turn, "commitment": commitment}):
		_clear_guest_duel_commitment()
		return _error("send_failed")
	return {"ok": true, "commitment": commitment}

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
	if transport == null:
		return
	if transport.message_received.is_connected(_on_message):
		transport.message_received.disconnect(_on_message)
	if transport.transport_error.is_connected(_on_transport_error):
		transport.transport_error.disconnect(_on_transport_error)
	if transport.state_changed.is_connected(_on_transport_state_changed):
		transport.state_changed.disconnect(_on_transport_state_changed)
	transport.close()
	transport = null

func _on_transport_error(code: String, detail: String) -> void:
	session_error.emit(code, detail)

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
		_restore_duel_commitment_if_matching()
		_send("game_mode", {"mode": game_mode})
		if game_mode == "duel" and duel_state != null:
			_publish_duel_snapshot("session_started")
			_request_duel_reveal_if_ready()
		else:
			_publish_snapshot("session_started")
			_publish_run_snapshot("session_started")

func _handle_host_message(message_type: String, payload: Dictionary) -> void:
	if game_mode == "duel" and message_type not in ["duel_commit", "duel_reveal", "resync_request"]:
		_send_rejection("cooperative_mode_inactive")
		return
	match message_type:
		"duel_commit":
			if game_mode != "duel" or duel_state == null or int(payload.get("slot", -1)) != 1:
				_send_rejection("guest_duel_forbidden")
				return
			if int(payload.get("turn", -1)) != duel_state.turn:
				_send_rejection("duel_turn_mismatch")
				_publish_duel_snapshot("duel_resync")
				return
			var commitment := String(payload.get("commitment", ""))
			if commitment.length() != 64 or not host_guest_duel_commitment.is_empty():
				_send_rejection("invalid_duel_commitment")
				return
			host_guest_duel_commitment = {"turn": duel_state.turn, "hash": commitment}
			if duel_save_store.save_pending_commitment({"role": "host", "duel_id": String(duel_state.duel_id), "turn": duel_state.turn, "commitment": commitment}) != OK:
				host_guest_duel_commitment.clear()
				_send_rejection("duel_commitment_persist_failed")
				return
			peer_ready.emit(1, true)
			_request_duel_reveal_if_ready()
		"duel_reveal":
			if host_guest_duel_commitment.is_empty() or int(payload.get("turn", -1)) != int(host_guest_duel_commitment.turn):
				_send_rejection("duel_reveal_without_commitment")
				return
			var duel_plays: Array[Dictionary] = []
			for play in payload.get("plays", []):
				if play is Dictionary:
					duel_plays.append(play)
			var revealed_hash := _duel_plan_commitment(int(payload.turn), duel_plays, String(payload.get("nonce", "")))
			if revealed_hash != String(host_guest_duel_commitment.hash):
				host_guest_duel_commitment.clear()
				duel_save_store.clear_pending()
				_send_rejection("duel_commitment_mismatch")
				return
			var duel_result := duel_engine.submit_plan(duel_state, 1, duel_plays)
			if not duel_result.ok:
				host_guest_duel_commitment.clear()
				duel_save_store.clear_pending()
				_send_rejection(duel_result.error)
				return
			host_guest_duel_commitment.clear()
			duel_save_store.save(duel_state)
			duel_save_store.clear_pending()
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
		"duel_reveal_request":
			if guest_pending_duel_plays.is_empty() or guest_duel_nonce.is_empty() or int(payload.get("turn", -1)) != _known_duel_turn():
				session_error.emit("invalid_duel_reveal_request", "no matching commitment")
				return
			_send("duel_reveal", {"slot": 1, "turn": _known_duel_turn(), "plays": guest_pending_duel_plays, "nonce": guest_duel_nonce})
		"game_mode":
			var next_mode := String(payload.get("mode", ""))
			if not next_mode in ["cooperative", "duel"]:
				session_error.emit("invalid_game_mode", next_mode)
				return
			game_mode = next_mode
			if next_mode == "cooperative":
				duel_state = null
				_clear_guest_duel_commitment()
			game_mode_changed.emit(game_mode)
		"duel_snapshot":
			var duel_snapshot: Variant = payload.get("state", null)
			var duel_hash := String(payload.get("state_hash", ""))
			if not duel_snapshot is Dictionary or duel_hash.is_empty() or StateHasher.hash_snapshot(duel_snapshot) != duel_hash:
				session_error.emit("invalid_duel_snapshot", "missing or mismatched state")
				return
			duel_state = DuelState.from_snapshot(duel_snapshot)
			_restore_duel_commitment_if_matching()
			if guest_duel_commit_turn >= 0 and (duel_state.phase == DuelState.Phase.FINISHED or duel_state.turn != guest_duel_commit_turn or duel_state.players[1].ready):
				_clear_guest_duel_commitment()
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
			var rejection_code := String(payload.get("code", "rejected"))
			if rejection_code in ["duel_commitment_mismatch", "invalid_duel_commitment", "duel_reveal_without_commitment", "duel_commitment_persist_failed", "duel_turn_mismatch"]:
				_clear_guest_duel_commitment()
			session_error.emit(rejection_code, "host rejected command")
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

func _request_duel_reveal_if_ready() -> void:
	if role == Role.HOST and duel_state != null and duel_state.players[0].ready and not host_guest_duel_commitment.is_empty():
		_send("duel_reveal_request", {"turn": duel_state.turn})

static func _duel_plan_commitment(turn: int, plays: Array[Dictionary], nonce: String) -> String:
	return StateHasher.hash_snapshot({"turn": turn, "plays": plays, "nonce": nonce})

func _restore_duel_commitment_if_matching() -> void:
	if duel_state == null or duel_state.phase != DuelState.Phase.PLANNING:
		return
	var pending := duel_save_store.load_pending_commitment()
	var expected_role := "host" if role == Role.HOST else "guest"
	if String(pending.get("role", "")) != expected_role or String(pending.get("duel_id", "")) != String(duel_state.duel_id) or int(pending.get("turn", -1)) != duel_state.turn:
		if not pending.is_empty():
			duel_save_store.clear_pending()
		return
	if role == Role.HOST:
		if duel_state.players[1].ready:
			duel_save_store.clear_pending()
			return
		var commitment := String(pending.get("commitment", ""))
		if commitment.length() == 64:
			host_guest_duel_commitment = {"turn": duel_state.turn, "hash": commitment}
		return
	var restored_plays: Array[Dictionary] = []
	for play in pending.get("plays", []):
		if play is Dictionary:
			var restored_play: Dictionary = play.duplicate(true)
			if restored_play.has("card_id"):
				restored_play.card_id = StringName(restored_play.card_id)
			restored_plays.append(restored_play)
	var nonce := String(pending.get("nonce", ""))
	var stored_hash := String(pending.get("commitment", ""))
	if restored_plays.is_empty() or nonce.is_empty() or stored_hash != _duel_plan_commitment(duel_state.turn, restored_plays, nonce):
		duel_save_store.clear_pending()
		return
	guest_pending_duel_plays = restored_plays
	guest_duel_nonce = nonce
	guest_duel_commit_turn = duel_state.turn

func _clear_guest_duel_commitment() -> void:
	guest_pending_duel_plays.clear()
	guest_duel_nonce = ""
	guest_duel_commit_turn = -1
	duel_save_store.clear_pending()

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
