extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	_test_initial_state()
	_test_simultaneous_resolution()
	_test_support_limit()
	_test_deterministic_hash()
	_test_loopback_transport()
	_test_run_map_generation()
	_test_reward_and_shop_generation()
	_test_run_save_round_trip()
	_test_run_coordinator_economy()
	_test_host_authoritative_session()
	_test_session_rejects_stale_sequence()
	_test_combat_snapshot_round_trip()
	_test_full_card_catalog()
	_test_full_run_content_catalog()
	_test_route_selection_and_key_gate()
	if failures.is_empty():
		print("PASS: 15 core, content, run, route, save, economy, protocol, and transport tests")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _test_initial_state() -> void:
	var engine := CombatEngine.new(DemoCardCatalog.build())
	var state := engine.create_demo_combat()
	_expect(state.players.size() == 2, "demo combat has two players")
	_expect(state.players[0].hand.size() == 5, "guardian draws five cards")
	_expect(state.team_health == 70, "team health starts full")

func _test_simultaneous_resolution() -> void:
	var engine := CombatEngine.new(DemoCardCatalog.build())
	var state := engine.create_demo_combat()
	var result_a := engine.submit_plan(state, 0, [{"card_id": &"guardian_strike", "target": 0}])
	var result_b := engine.submit_plan(state, 1, [{"card_id": &"engineer_bolt", "target": 0}])
	_expect(result_a.ok and result_b.ok, "both valid plans are accepted")
	var result := engine.resolve_if_ready(state)
	_expect(result.ok, "ready plans resolve")
	_expect(state.enemies[0].health == 31, "both player attacks resolve")
	_expect(state.team_health == 61, "enemy intent damages shared health")
	_expect(state.turn == 2, "combat advances to turn two")

func _test_support_limit() -> void:
	var engine := CombatEngine.new(DemoCardCatalog.build())
	var state := engine.create_demo_combat()
	state.players[0].hand.assign([&"guardian_cover", &"guardian_cover"])
	var result := engine.submit_plan(state, 0, [
		{"card_id": &"guardian_cover"},
		{"card_id": &"guardian_cover"},
	])
	_expect(not result.ok and result.error == "support_limit", "only one support card is allowed per turn")

func _test_deterministic_hash() -> void:
	var engine := CombatEngine.new(DemoCardCatalog.build())
	var first := engine.create_demo_combat()
	var second := engine.create_demo_combat()
	_expect(
		StateHasher.hash_snapshot(first.to_snapshot()) == StateHasher.hash_snapshot(second.to_snapshot()),
		"equivalent combat states have matching hashes"
	)

func _test_loopback_transport() -> void:
	var transports := LoopbackTransport.pair()
	var host: LoopbackTransport = transports[0]
	var guest: LoopbackTransport = transports[1]
	var received: Array[String] = []
	guest.message_received.connect(func(message: String) -> void: received.append(message))
	host.start_host("test")
	guest.connect_to("loopback", "test")
	_expect(host.send_message("{\"type\":\"ready\"}"), "connected loopback sends a message")
	guest.poll()
	_expect(received == ["{\"type\":\"ready\"}"], "loopback delivers the exact payload")

func _test_run_map_generation() -> void:
	var generator := MapGenerator.new()
	var first := generator.generate_run(20260902)
	var second := generator.generate_run(20260902)
	_expect(first == second, "run map generation is deterministic")
	_expect(first.stages.size() == 3, "run contains three stages")
	for stage in first.stages:
		_expect(stage.steps.size() == MapGenerator.TRAVERSAL_STEPS, "stage contains eight traversal steps")
		_expect(stage.boss.type == "boss", "stage ends with a boss")
		for slot in 2:
			var found: Dictionary = {"shop": false, "rest": false, "elite": false, "key_challenge": false}
			for step in stage.steps:
				if step.kind != "parallel":
					continue
				for option in step.lanes[slot].options:
					if found.has(option.type):
						found[option.type] = true
			_expect(found.values().all(func(value: bool) -> bool: return value), "each lane guarantees shop, rest, elite, and key")
	var run := RunState.new(20260902)
	run.unlock_key(1)
	run.unlock_key(2)
	_expect(not run.can_enter_true_boss(), "two keys do not unlock the true boss")
	run.unlock_key(3)
	_expect(run.can_enter_true_boss(), "three stage keys unlock the true boss")
	var invalid_seed_count := 0
	for seed in 10_000:
		var generated := generator.generate_run(seed + 1)
		for stage in generated.stages:
			for slot in 2:
				var required := {"shop": false, "rest": false, "elite": false, "key_challenge": false}
				for step in stage.steps:
					if step.kind == "parallel":
						for option in step.lanes[slot].options:
							if required.has(option.type):
								required[option.type] = true
				if not required.values().all(func(value: bool) -> bool: return value):
					invalid_seed_count += 1
	_expect(invalid_seed_count == 0, "10,000 map seeds preserve every lane guarantee")

func _test_reward_and_shop_generation() -> void:
	var catalog := DemoCardCatalog.build()
	var generator := RewardGenerator.new(catalog)
	var reward := generator.card_reward(90210, CardData.Scope.GUARDIAN, "combat")
	_expect(reward.size() == 3, "card reward contains three choices")
	_expect(catalog[reward[0]].owner_scope == CardData.Scope.GUARDIAN, "first reward matches character scope")
	_expect(catalog[reward[1]].owner_scope == CardData.Scope.GUARDIAN, "second reward matches character scope")
	_expect(catalog[reward[2]].owner_scope == CardData.Scope.NEUTRAL, "third reward is a neutral card")
	var shop := generator.shop_inventory(777, CardData.Scope.GUARDIAN)
	_expect(shop.cards.size() == 5, "shop contains five cards")
	_expect(shop.relics.size() == 2 and shop.consumables.size() == 2, "shop contains relics and consumables")

func _test_run_save_round_trip() -> void:
	var store := RunSaveStore.new()
	store.clear()
	var original := RunState.new(314159)
	original.map = MapGenerator.new().generate_run(original.seed)
	original.stage = 2
	original.step = 4
	original.gold[0] = 143
	_expect(store.save(original, "test_checkpoint") == OK, "run checkpoint saves")
	var restored := store.load_active()
	_expect(restored != null, "saved run loads")
	if restored != null:
		_expect(restored.to_snapshot() == original.to_snapshot(), "run save round trip preserves state")
	store.clear()

func _test_run_coordinator_economy() -> void:
	var store := RunSaveStore.new("user://coordinator_test.json")
	store.clear()
	var coordinator := RunCoordinator.new(DemoCardCatalog.build(), store)
	var run := coordinator.start_new(4242)
	var reward := coordinator.current_card_reward(0)
	var previous_deck_size: int = run.decks[0].size()
	_expect(coordinator.claim_card(0, reward[2]), "neutral reward can be claimed")
	_expect(run.decks[0].size() == previous_deck_size + 1, "claimed reward joins the player deck")
	var shop := coordinator.current_shop(0)
	var affordable: Dictionary = shop.cards[0]
	run.gold[0] = int(affordable.price)
	_expect(coordinator.buy_card(0, affordable), "affordable shop card can be purchased")
	_expect(run.gold[0] == 0, "shop purchase deducts exact gold")
	_expect(not coordinator.buy_card(0, affordable), "shop rejects purchase without enough gold")
	var restored := store.load_active()
	_expect(restored != null and restored.decks[0] == run.decks[0], "economy mutations persist at checkpoints")
	store.clear()

func _test_host_authoritative_session() -> void:
	var transports := LoopbackTransport.pair()
	transports[0].start_host("test")
	transports[1].connect_to("loopback", "test")
	var catalog := DemoCardCatalog.build()
	var engine := CombatEngine.new(catalog)
	var state := engine.create_demo_combat()
	var host := CooperativeSession.new(CooperativeSession.Role.HOST, transports[0], engine, state)
	var guest := CooperativeSession.new(CooperativeSession.Role.GUEST, transports[1])
	var hashes: Array[String] = []
	guest.snapshot_received.connect(func(_snapshot: Dictionary, state_hash: String) -> void: hashes.append(state_hash))
	_expect(guest.submit_plan(1, [{"card_id": "engineer_bolt", "target": 0}]).ok, "guest sends intent without mutating host directly")
	host.poll()
	_expect(state.players[1].ready, "host validates and accepts guest plan")
	_expect(host.submit_plan(0, [{"card_id": &"guardian_strike", "target": 0}]).ok, "host accepts local plan")
	guest.poll()
	_expect(state.turn == 2 and state.enemies[0].health == 31, "host alone resolves simultaneous turn")
	_expect(not hashes.is_empty() and hashes[-1] == StateHasher.hash_snapshot(state.to_snapshot()), "guest receives verified authoritative snapshot")

func _test_session_rejects_stale_sequence() -> void:
	var transports := LoopbackTransport.pair()
	transports[0].start_host("test")
	transports[1].connect_to("loopback", "test")
	var engine := CombatEngine.new(DemoCardCatalog.build())
	var host := CooperativeSession.new(CooperativeSession.Role.HOST, transports[0], engine, engine.create_demo_combat())
	var errors: Array[String] = []
	host.session_error.connect(func(code: String, _detail: String) -> void: errors.append(code))
	var repeated := SessionProtocol.encode("resync_request", 1, {})
	transports[1].send_message(repeated)
	transports[1].send_message(repeated)
	host.poll()
	_expect(errors == ["stale_sequence"], "duplicate sequence is rejected exactly once")

func _test_combat_snapshot_round_trip() -> void:
	var engine := CombatEngine.new(DemoCardCatalog.build())
	var original := engine.create_demo_combat()
	engine.submit_plan(original, 0, [{"card_id": &"guardian_strike", "target": 0}])
	var restored := CombatState.from_snapshot(JSON.parse_string(JSON.stringify(original.to_snapshot())))
	_expect(restored.to_snapshot() == original.to_snapshot(), "combat snapshot survives JSON reconstruction")
	_expect(StateHasher.hash_snapshot(restored.to_snapshot()) == StateHasher.hash_snapshot(original.to_snapshot()), "reconstructed combat preserves state hash")

func _test_full_card_catalog() -> void:
	var catalog := FullCardCatalog.build()
	_expect(catalog.size() == 144, "full catalog contains exactly 144 cards")
	for scope in CardData.Scope.values():
		var count := 0
		for card in catalog.values():
			if card.owner_scope == scope:
				count += 1
			_expect(not card.display_name.is_empty() and not card.effects.is_empty(), "every card has visible content and effects")
		var expected := 48 if scope == CardData.Scope.NEUTRAL else 24
		_expect(count == expected, "scope %d has its exact card target" % scope)

func _test_full_run_content_catalog() -> void:
	var content := RunContentCatalog.build()
	_expect(content.relics.size() == 24, "run content contains 24 relics")
	_expect(content.consumables.size() == 8, "run content contains 8 consumables")
	_expect(content.events.size() == 18, "run content contains 18 events")
	_expect(content.stages.size() == 3, "enemy content covers three stages")
	for stage in content.stages:
		_expect(stage.normal_formations.size() == 4, "each stage has four normal formations")
		_expect(stage.elites.size() == 2, "each stage has two elites")
		_expect(not stage.boss.id.is_empty(), "each stage has one boss")
	_expect(content.true_boss.health > content.stages[-1].boss.health, "true boss exceeds final stage boss health")

func _test_route_selection_and_key_gate() -> void:
	var store := RunSaveStore.new("user://route_test.json")
	store.clear()
	var coordinator := RunCoordinator.new(FullCardCatalog.build(), store)
	var run := coordinator.start_new(99)
	var step: Dictionary = run.map.stages[0].steps[0]
	var first := coordinator.choose_route(0, step.lanes[0].options[0].id)
	_expect(first.ok and not first.ready, "first personal route waits for teammate")
	_expect(not coordinator.complete_routes(["combat"]).ok, "routes cannot complete before both choices")
	var second := coordinator.choose_route(1, step.lanes[1].options[0].id)
	_expect(second.ok and second.ready, "second personal route makes the pair ready")
	_expect(coordinator.complete_routes([first.node_type, second.node_type]).ok and run.step == 1, "completed pair advances exactly one step")
	run.step = MapGenerator.TRAVERSAL_STEPS - 1
	run.pending_routes = {0: "a", 1: "b"}
	coordinator.complete_routes(["combat", "combat"])
	_expect(run.stage == 2 and not run.keys[0], "stage completion does not grant a free key")
	run.stage = 1
	run.pending_routes = {0: "a", 1: "b"}
	coordinator.complete_routes(["key_challenge", "combat"])
	_expect(run.keys[0], "completed key challenge unlocks only its stage key")
	store.clear()

func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append("FAIL: %s" % label)
