extends SceneTree

const EnemyVisuals := preload("res://src/ui/enemy_visual_catalog.gd")
const EnemyAura := preload("res://src/ui/enemy_visual.gd")
const CardFrames := preload("res://src/ui/card_frame_visual.gd")
const CardArt := preload("res://src/ui/card_art_catalog.gd")
const CardIdentity := preload("res://src/ui/card_identity_visual.gd")

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
	_test_host_authoritative_route_session()
	_test_session_rejects_stale_sequence()
	_test_session_rejects_incompatible_content()
	_test_combat_snapshot_round_trip()
	_test_full_card_catalog()
	_test_full_run_content_catalog()
	_test_route_selection_and_key_gate()
	_test_run_combat_completion_gate()
	_test_boss_and_run_completion_flow()
	_test_collaborative_event_resolution()
	_test_consumable_effects_and_sync()
	_test_relic_lifecycle_triggers()
	_test_character_selection_and_scope()
	_test_duel_resolution_and_snapshot()
	_test_host_authoritative_duel_session()
	_test_duel_save_round_trip()
	_test_duel_commitment_tamper_rejected()
	_test_duel_commitment_process_restart_recovery()
	_test_reduced_motion_effect_cues()
	_test_card_scope_frames()
	_test_character_card_art_profiles()
	if failures.is_empty():
		print("PASS: 31 core, content, run, character, duel, relic, item, event, boss, encounter, route, accessibility, save, economy, protocol, and transport tests")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _test_reduced_motion_effect_cues() -> void:
	var visual := CombatEffectVisual.new()
	var signatures := {}
	for character_id in [&"guardian", &"engineer", &"hacker", &"assault", &"medic", &"navigator"]:
		for effect_type in ["damage", "block", "heal", "energy"]:
			visual.configure(effect_type, 0, true, character_id)
			_expect(visual.static_mode and is_equal_approx(visual.progress, 0.82), "reduced motion keeps a stable spatial cue for %s %s" % [character_id, effect_type])
			_expect(visual.effect_description().contains(CombatEffectVisual.CHARACTER_PROFILES[character_id].name), "effect description names its source character")
			signatures[CombatEffectVisual.profile_signature(character_id, effect_type)] = true
	_expect(signatures.size() == 24, "six characters and four effects use twenty-four distinct combat effect profiles")
	visual.free()

func _test_card_scope_frames() -> void:
	var signatures := {}
	for scope in CardData.Scope.values():
		signatures[CardFrames.frame_signature(scope)] = true
	_expect(signatures.size() == 7, "seven card ownership scopes use seven distinct geometric frame signatures")

func _test_character_card_art_profiles() -> void:
	var profile_keys := {}
	var texture_paths := {}
	for scope in CardData.Scope.values():
		for effect_kind in CardArt.EFFECT_KINDS:
			profile_keys[CardArt.profile_key(scope, effect_kind)] = true
			var texture := CardArt.texture_for(scope, effect_kind)
			_expect(texture != null, "card art exists for scope %d and effect %s" % [scope, effect_kind])
			if texture != null:
				texture_paths[texture.resource_path] = true
	_expect(CardArt.profile_count() == 20, "five dedicated scope sets provide twenty card art profiles")
	_expect(profile_keys.size() == 28, "all twenty-eight card art profile keys are distinct")
	_expect(texture_paths.size() == 20, "all dedicated card art profiles use distinct texture resources")

func _test_initial_state() -> void:
	var engine := CombatEngine.new(DemoCardCatalog.build())
	var state := engine.create_demo_combat()
	_expect(state.players.size() == 2, "demo combat has two players")
	_expect(state.players[0].hand.size() == 5, "guardian draws five cards")
	_expect(state.team_health == 70, "team health starts full")
	var main_script: Variant = load("res://src/ui/main.gd").new()
	main_script.system_font_scale = 1.0
	main_script.large_text_enabled = false
	_expect(is_equal_approx(main_script._effective_text_scale(), 1.0), "default system text uses one hundred percent scale")
	main_script.large_text_enabled = true
	_expect(is_equal_approx(main_script._effective_text_scale(), 1.15), "app large text uses one hundred fifteen percent scale")
	main_script.system_font_scale = 2.0
	_expect(is_equal_approx(main_script._effective_text_scale(), 1.30), "two hundred percent Android text preference activates the safe one hundred thirty percent HUD")
	main_script.free()

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
	host.dispose()

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
	var reward_unique := {}
	for card_id in reward:
		reward_unique[card_id] = true
	_expect(reward_unique.size() == 3, "card reward choices are unique")
	_expect(catalog[reward[0]].owner_scope == CardData.Scope.GUARDIAN, "first reward matches character scope")
	_expect(catalog[reward[1]].owner_scope == CardData.Scope.GUARDIAN, "second reward matches character scope")
	_expect(catalog[reward[2]].owner_scope == CardData.Scope.NEUTRAL, "third reward is a neutral card")
	var unique_shop := generator.shop_inventory(90210, CardData.Scope.GUARDIAN)
	var shop_ids: Array[String] = []
	var shop_unique := {}
	for entry in unique_shop.cards:
		shop_ids.append(String(entry.card_id))
		shop_unique[String(entry.card_id)] = true
	_expect(shop_unique.size() == shop_ids.size(), "shop card offers are unique")
	var shop := generator.shop_inventory(777, CardData.Scope.GUARDIAN)
	_expect(shop.cards.size() == 5, "shop contains five cards")
	_expect(shop.relics.size() == 2 and shop.consumables.size() == 2, "shop contains relics and consumables")
	_expect(shop.relics[0].has("id") and shop.relics[0].has("price"), "shop relics are purchasable entries")
	_expect(shop.consumables[0].has("id") and shop.consumables[0].has("price"), "shop consumables are purchasable entries")

func _test_run_save_round_trip() -> void:
	var store := RunSaveStore.new()
	store.clear()
	var original := RunState.new(314159)
	original.map = MapGenerator.new().generate_run(original.seed)
	original.stage = 2
	original.step = 4
	original.gold[0] = 143
	var selected_step: Dictionary = original.map.stages[1].steps[4]
	if selected_step.kind == "parallel":
		original.pending_routes = {0: selected_step.lanes[0].options[0].id, 1: selected_step.lanes[1].options[0].id}
	_expect(store.save(original, "test_checkpoint") == OK, "run checkpoint saves")
	var first_snapshot := original.to_snapshot()
	original.gold[0] += 1
	_expect(store.save(original, "newer_checkpoint") == OK, "newer run checkpoint rotates the prior valid save")
	var absolute_save := ProjectSettings.globalize_path(store.save_path)
	var absolute_temp := ProjectSettings.globalize_path(store.save_path + CheckedJsonStore.TEMP_SUFFIX)
	DirAccess.rename_absolute(absolute_save, absolute_temp)
	var staged_run := store.load_active()
	_expect(staged_run != null and staged_run.gold[0] == original.gold[0], "interrupted run promotion restores the newer staged checkpoint")
	DirAccess.rename_absolute(absolute_temp, absolute_save)
	var corrupt_file := FileAccess.open(store.save_path, FileAccess.WRITE)
	if corrupt_file != null:
		corrupt_file.store_string("{}")
		corrupt_file.close()
	var restored := store.load_active()
	_expect(restored != null, "saved run loads")
	if restored != null:
		_expect(restored.to_snapshot() == first_snapshot, "structurally incomplete run checkpoint falls back to the previous checksummed state")
		var restored_coordinator := RunCoordinator.new(FullCardCatalog.build(), store)
		restored_coordinator.run = restored
		_expect(restored.pending_routes.has(0) and restored.pending_routes.has(1) and restored_coordinator.selected_route_types().size() == 2, "restored route keys remain playable integer slots")
	store.clear()
	var legacy_file := FileAccess.open(store.save_path, FileAccess.WRITE)
	if legacy_file != null:
		legacy_file.store_string(JSON.stringify(first_snapshot))
		legacy_file.close()
	var legacy_restored := store.load_active()
	_expect(legacy_restored != null and legacy_restored.to_snapshot() == first_snapshot, "legacy unenveloped run snapshots remain readable")
	store.clear()

func _test_run_coordinator_economy() -> void:
	var store := RunSaveStore.new("user://coordinator_test.json")
	store.clear()
	var coordinator := RunCoordinator.new(DemoCardCatalog.build(), store)
	var run := coordinator.start_new(4242)
	_expect(coordinator.current_card_reward(0).is_empty(), "card reward is locked before combat victory")
	run.pending_card_rewards[0] = true
	var reward := coordinator.current_card_reward(0)
	var previous_deck_size: int = run.decks[0].size()
	_expect(coordinator.claim_card(0, reward[2]), "neutral reward can be claimed")
	_expect(run.decks[0].size() == previous_deck_size + 1, "claimed reward joins the player deck")
	_expect(not coordinator.claim_card(0, reward[0]), "claimed combat reward cannot be taken twice")
	var shop := coordinator.current_shop(0)
	var affordable: Dictionary = shop.cards[0]
	run.gold[0] = int(affordable.price)
	_expect(not coordinator.buy_card(0, affordable), "shop purchase is locked outside a shop node")
	run.shop_open[0] = true
	_expect(coordinator.buy_card(0, affordable), "affordable shop card can be purchased")
	_expect(run.gold[0] == 0, "shop purchase deducts exact gold")
	run.gold[0] = int(affordable.price)
	_expect(not coordinator.buy_card(0, affordable), "sold shop card cannot be purchased twice")
	run.gold[0] = 0
	_expect(not coordinator.buy_card(0, affordable), "shop rejects purchase without enough gold")
	var stocked := coordinator.current_shop(0)
	var relic: Dictionary = stocked.relics[0]
	run.gold[0] = int(relic.price)
	_expect(coordinator.buy_relic(0, relic), "relic purchase deducts gold and adds inventory")
	_expect(not coordinator.buy_relic(0, relic), "duplicate relic purchase is rejected")
	var consumable: Dictionary = stocked.consumables[0]
	run.gold[0] = int(consumable.price)
	_expect(coordinator.buy_consumable(0, consumable), "consumable purchase adds carried item")
	run.gold[0] = int(consumable.price)
	_expect(not coordinator.buy_consumable(0, consumable), "sold consumable cannot be purchased twice")
	var removal_cost := int(stocked.remove_card_cost)
	run.gold[0] = removal_cost
	var deck_size_before_removal: int = run.decks[0].size()
	_expect(coordinator.remove_card(0, 0, removal_cost), "shop removal service removes one selected card")
	_expect(run.decks[0].size() == deck_size_before_removal - 1 and run.gold[0] == 0, "card removal deducts exact gold and updates deck")
	run.gold[0] = removal_cost
	_expect(not coordinator.remove_card(0, 0, removal_cost), "card removal service can only be used once per shop visit")
	coordinator._set_shop_access(["shop", "rest"])
	_expect(run.shop_purchases[0].is_empty(), "a later shop visit receives a fresh inventory purchase state")
	coordinator.checkpoint("shop_reopened")
	var restored := store.load_active()
	_expect(restored != null and restored.decks[0] == run.decks[0] and restored.shop_purchases[0] == run.shop_purchases[0], "economy mutations persist at checkpoints")
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
	host.poll()
	guest.poll()
	var hashes: Array[String] = []
	var started_modes: Array[String] = []
	var host_messages: Array[String] = []
	var guest_messages: Array[String] = []
	guest.snapshot_received.connect(func(_snapshot: Dictionary, state_hash: String) -> void: hashes.append(state_hash))
	guest.game_started.connect(func(mode: String) -> void: started_modes.append(mode))
	host.macro_chat_received.connect(func(from_slot: int, macro_id: String) -> void: host_messages.append("%d:%s" % [from_slot, macro_id]))
	guest.macro_chat_received.connect(func(from_slot: int, macro_id: String) -> void: guest_messages.append("%d:%s" % [from_slot, macro_id]))
	_expect(host.start_game("cooperative").ok, "verified host can start the multiplayer lobby game")
	guest.poll()
	_expect(started_modes == ["cooperative"], "guest leaves the lobby only after the host start message")
	_expect(not guest.start_game("duel").ok, "guest cannot start the multiplayer lobby game")
	_expect(guest.send_macro_chat("wait").ok, "guest can send a whitelisted macro chat")
	host.poll()
	guest.poll()
	_expect(host_messages == ["1:wait"] and guest_messages == ["1:wait"], "host validates and echoes the guest macro chat")
	_expect(host.send_macro_chat("ready").ok, "host can send a whitelisted macro chat")
	guest.poll()
	_expect(host_messages == ["1:wait", "0:ready"] and guest_messages == ["1:wait", "0:ready"], "both peers receive the host macro chat")
	_expect(not host.send_macro_chat("custom text").ok, "free-form or unknown macro chat is rejected")
	_expect(guest.submit_plan(1, [{"card_id": "engineer_bolt", "target": 0}]).ok, "guest sends intent without mutating host directly")
	host.poll()
	_expect(state.players[1].ready, "host validates and accepts guest plan")
	_expect(host.submit_plan(0, [{"card_id": &"guardian_strike", "target": 0}]).ok, "host accepts local plan")
	guest.poll()
	_expect(state.turn == 2 and state.enemies[0].health == 31, "host alone resolves simultaneous turn")
	_expect(not hashes.is_empty() and hashes[-1] == StateHasher.hash_snapshot(state.to_snapshot()), "guest receives verified authoritative snapshot")
	host.close()
	guest.close()
	transports[0].dispose()

func _test_host_authoritative_route_session() -> void:
	var transports := LoopbackTransport.pair()
	transports[0].start_host("test")
	transports[1].connect_to("loopback", "test")
	var host_store := RunSaveStore.new("user://host_route_session.json")
	host_store.clear()
	var coordinator := RunCoordinator.new(FullCardCatalog.build(), host_store)
	var run := coordinator.start_new(20260902)
	var engine := CombatEngine.new(DemoCardCatalog.build())
	var host := CooperativeSession.new(CooperativeSession.Role.HOST, transports[0], engine, engine.create_demo_combat(), coordinator)
	var guest := CooperativeSession.new(CooperativeSession.Role.GUEST, transports[1])
	host.poll()
	guest.poll()
	var received_runs: Array[Dictionary] = []
	guest.run_snapshot_received.connect(func(snapshot: Dictionary) -> void: received_runs.append(snapshot))
	_expect(guest.select_character(1, &"hacker").ok, "guest sends character selection intent")
	host.poll()
	guest.poll()
	_expect(run.characters[1] == &"hacker" and run.decks[1].has("hacker_card_01"), "host validates guest character and rebuilds its starter deck")
	_expect(not received_runs.is_empty() and received_runs[-1].characters[1] == "hacker", "guest receives authoritative character selection snapshot")
	var guest_node := String(run.map.stages[0].steps[0].lanes[1].options[0].id)
	_expect(guest.select_route(1, guest_node).ok, "guest sends route intent without mutating run")
	host.poll()
	guest.poll()
	_expect(run.pending_routes.get(1, "") == guest_node, "host validates and records guest route")
	_expect(not received_runs.is_empty() and received_runs[-1].pending_routes.get("1", "") == guest_node, "guest receives authoritative run snapshot")
	run.pending_routes = {0: "event-a", 1: "rest-b"}
	coordinator.begin_event(["event", "rest"])
	_expect(guest.submit_event_choice(1, 1).ok, "guest sends event choice without resolving locally")
	host.poll()
	_expect(run.pending_event.votes.size() == 1, "host records guest event vote")
	_expect(host.submit_event_choice(0, 0).ready, "host vote resolves two-player event")
	guest.poll()
	_expect(received_runs[-1].pending_event.is_empty() and received_runs[-1].last_event_result.outcome == "compromise", "guest receives resolved event result in run snapshot")
	run.consumables[1].append("consumable_01")
	_expect(guest.use_consumable(1, 0).ok, "guest sends consumable intent without mutating combat directly")
	host.poll()
	guest.poll()
	_expect(run.consumables[1].is_empty() and host.combat_state.players[1].block == 12, "host applies and consumes guest item authoritatively")
	host.close()
	guest.close()
	transports[0].dispose()
	host_store.clear()

func _test_session_rejects_stale_sequence() -> void:
	var transports := LoopbackTransport.pair()
	transports[0].start_host("test")
	transports[1].connect_to("loopback", "test")
	var engine := CombatEngine.new(DemoCardCatalog.build())
	var host := CooperativeSession.new(CooperativeSession.Role.HOST, transports[0], engine, engine.create_demo_combat())
	var errors: Array[String] = []
	host.session_error.connect(func(code: String, _detail: String) -> void: errors.append(code))
	transports[1].send_message(SessionProtocol.encode("hello", 1, {"role": "guest", "fingerprint": GameCompatibility.fingerprint(), "ruleset": GameCompatibility.RULESET_VERSION}))
	var repeated := SessionProtocol.encode("resync_request", 2, {})
	transports[1].send_message(repeated)
	transports[1].send_message(repeated)
	host.poll()
	_expect(errors == ["stale_sequence"], "duplicate sequence is rejected exactly once")
	host.close()
	transports[0].dispose()

func _test_session_rejects_incompatible_content() -> void:
	var transports := LoopbackTransport.pair()
	transports[0].start_host("incompatible")
	transports[1].connect_to("loopback", "incompatible")
	var engine := CombatEngine.new(DemoCardCatalog.build())
	var host := CooperativeSession.new(CooperativeSession.Role.HOST, transports[0], engine, engine.create_demo_combat(), null, null, "host-content")
	var guest := CooperativeSession.new(CooperativeSession.Role.GUEST, transports[1], null, null, null, null, "guest-content")
	var host_errors: Array[String] = []
	var guest_errors: Array[String] = []
	host.session_error.connect(func(code: String, _detail: String) -> void: host_errors.append(code))
	guest.session_error.connect(func(code: String, _detail: String) -> void: guest_errors.append(code))
	host.poll()
	guest.poll()
	_expect(not host.handshake_complete and not guest.handshake_complete and host_errors.has("incompatible_content") and guest_errors.has("incompatible_content"), "different content fingerprints fail the multiplayer handshake on both devices")
	var blocked := guest.submit_plan(1, [{"card_id": "engineer_bolt"}])
	_expect(not blocked.ok and blocked.error == "handshake_required", "guest game commands remain blocked after an incompatible handshake")
	host.close()
	guest.close()
	transports[0].dispose()

func _test_combat_snapshot_round_trip() -> void:
	var engine := CombatEngine.new(DemoCardCatalog.build())
	var original := engine.create_demo_combat()
	engine.submit_plan(original, 0, [{"card_id": &"guardian_strike", "target": 0}])
	var restored := CombatState.from_snapshot(JSON.parse_string(JSON.stringify(original.to_snapshot())))
	_expect(restored.to_snapshot() == original.to_snapshot(), "combat snapshot survives JSON reconstruction")
	_expect(StateHasher.hash_snapshot(restored.to_snapshot()) == StateHasher.hash_snapshot(original.to_snapshot()), "reconstructed combat preserves state hash")

func _test_full_card_catalog() -> void:
	var catalog := FullCardCatalog.build()
	_expect(catalog.size() == 192, "full catalog contains exactly 192 cards")
	var identity_signatures := {}
	for card in catalog.values():
		identity_signatures[CardIdentity.geometry_signature(card.id)] = true
	_expect(identity_signatures.size() == 192, "all 192 cards use distinct deterministic visual identity signatures")
	var fingerprint := GameCompatibility.fingerprint()
	_expect(fingerprint.length() == 64 and fingerprint == GameCompatibility.fingerprint(), "complete game content produces one stable SHA-256 compatibility fingerprint")
	_expect(GameCompatibility.code().length() == 12 and fingerprint.begins_with(GameCompatibility.code().to_lower()), "connection screen exposes a stable 12-character compatibility code")
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
	var visual_tiers: Array[String] = []
	visual_tiers.append(EnemyVisuals.profile(&"training_drone", []).tier)
	visual_tiers.append(EnemyVisuals.profile(&"s1_normal_1", ["combat"]).tier)
	visual_tiers.append(EnemyVisuals.profile(&"s1_elite_1", ["elite"]).tier)
	visual_tiers.append(EnemyVisuals.profile(&"s1_boss", ["boss"]).tier)
	visual_tiers.append(EnemyVisuals.profile(&"true_boss_star_eater", ["true_boss"]).tier)
	_expect(visual_tiers == ["training", "standard", "elite", "boss", "true_boss"], "five encounter tiers map to five distinct enemy visual profiles")
	var visual_textures := {}
	for profile in [EnemyVisuals.TRAINING, EnemyVisuals.STANDARD, EnemyVisuals.ELITE, EnemyVisuals.BOSS, EnemyVisuals.TRUE_BOSS]:
		visual_textures[profile.texture] = true
	_expect(visual_textures.size() == 5, "each encounter tier uses a distinct enemy texture")
	var identity_signatures := {}
	var encounter_count := 0
	for stage in content.stages:
		for enemy in stage.normal_formations:
			var identity := EnemyVisuals.identity_profile(StringName(enemy.id), ["combat"])
			identity_signatures[EnemyAura.geometry_signature(identity)] = true
			_expect(String(identity.description).contains(String(identity.identity_name)), "enemy description includes its non-color identity marker")
			encounter_count += 1
		for enemy in stage.elites:
			var identity := EnemyVisuals.identity_profile(StringName(enemy.id), ["elite"])
			identity_signatures[EnemyAura.geometry_signature(identity)] = true
			encounter_count += 1
		var boss_identity := EnemyVisuals.identity_profile(StringName(stage.boss.id), ["boss"])
		identity_signatures[EnemyAura.geometry_signature(boss_identity)] = true
		encounter_count += 1
	for special in [[&"training_drone", []], [&"true_boss_star_eater", ["true_boss"]]]:
		var special_routes: Array[String] = []
		special_routes.assign(special[1])
		var identity := EnemyVisuals.identity_profile(special[0], special_routes)
		identity_signatures[EnemyAura.geometry_signature(identity)] = true
		encounter_count += 1
	_expect(encounter_count == 23, "run content exposes twenty-three enemy identities")
	_expect(identity_signatures.size() == 23, "all twenty-three enemies use distinct stage, tier, and formation identity signatures")

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
	_expect(run.stage == 1 and run.step == MapGenerator.TRAVERSAL_STEPS and run.phase == "stage_boss" and not run.keys[0], "stage traversal ends at boss without granting a free key")
	run.phase = "traversal"
	run.step = 0
	run.stage = 1
	run.pending_routes = {0: "a", 1: "b"}
	coordinator.complete_routes(["key_challenge", "combat"])
	_expect(run.keys[0], "completed key challenge unlocks only its stage key")
	store.clear()

func _test_run_combat_completion_gate() -> void:
	var store := RunSaveStore.new("user://encounter_test.json")
	store.clear()
	var catalog := FullCardCatalog.build()
	var coordinator := RunCoordinator.new(catalog, store)
	var run := coordinator.start_new(8080)
	run.team_health = 50
	run.pending_routes = {0: "a", 1: "b"}
	var engine := CombatEngine.new(catalog)
	var combat := engine.create_run_combat(run, ["key_challenge", "rest"], RunContentCatalog.build())
	_expect(combat.team_health == run.team_health and combat.enemies[0].display_name.begins_with("열쇠 수호자"), "route type creates matching run encounter")
	_expect(not coordinator.complete_combat(combat, ["key_challenge", "rest"]).ok, "unfinished combat cannot advance route")
	combat.phase = CombatState.Phase.WON
	var before_gold := run.gold[0]
	var completion := coordinator.complete_combat(combat, ["key_challenge", "rest"])
	_expect(completion.ok and completion.gold == 45, "key challenge victory grants elite reward")
	_expect(run.keys[0] and run.gold[0] == before_gold + 45 and run.step == 1, "victory updates key gold and route exactly once")
	_expect(run.team_health == 62 and completion.summary == ["팀 내구도 +12"], "mixed rest benefit resolves after combat victory")
	_expect(run.pending_card_rewards == [true, true] and not run.shop_open[0] and not run.shop_open[1], "combat unlocks one reward per player without opening shop")
	store.clear()

func _test_boss_and_run_completion_flow() -> void:
	var store := RunSaveStore.new("user://boss_flow_test.json")
	store.clear()
	var catalog := FullCardCatalog.build()
	var coordinator := RunCoordinator.new(catalog, store)
	var run := coordinator.start_new(7007)
	var engine := CombatEngine.new(catalog)
	run.step = MapGenerator.TRAVERSAL_STEPS
	run.phase = "stage_boss"
	var stage_boss := engine.create_run_combat(run, ["boss"], RunContentCatalog.build())
	_expect(not coordinator.complete_boss_combat(stage_boss).ok, "unfinished stage boss cannot advance")
	stage_boss.phase = CombatState.Phase.WON
	var stage_result := coordinator.complete_boss_combat(stage_boss)
	_expect(stage_result.stage_advanced and run.stage == 2 and run.step == 0 and run.phase == "traversal", "stage boss victory advances to next traversal")
	run.stage = 3
	run.step = MapGenerator.TRAVERSAL_STEPS
	run.phase = "stage_boss"
	run.keys = [true, true, true]
	var final_stage_boss := engine.create_run_combat(run, ["boss"], RunContentCatalog.build())
	final_stage_boss.phase = CombatState.Phase.WON
	var unlock := coordinator.complete_boss_combat(final_stage_boss)
	_expect(unlock.true_boss_unlocked and run.phase == "true_boss", "three keys unlock true boss after stage three boss")
	var true_boss := engine.create_run_combat(run, ["true_boss"], RunContentCatalog.build())
	_expect(true_boss.enemies[0].id == &"true_boss_star_eater", "true boss encounter uses final catalog enemy")
	true_boss.phase = CombatState.Phase.WON
	var finish := coordinator.complete_boss_combat(true_boss, true)
	_expect(finish.run_completed and run.phase == "completed" and run.checkpoint_reason == "run_completed", "true boss victory completes and saves the run")
	store.clear()

func _test_collaborative_event_resolution() -> void:
	var store := RunSaveStore.new("user://event_flow_test.json")
	store.clear()
	var coordinator := RunCoordinator.new(FullCardCatalog.build(), store)
	var run := coordinator.start_new(5150)
	run.pending_routes = {0: "event-a", 1: "rest-b"}
	run.team_health = 50
	var started := coordinator.resolve_noncombat(["event", "rest"])
	_expect(started.event_pending and run.step == 0 and run.team_health == 62, "event node waits after applying paired rest benefit")
	var first := coordinator.submit_event_choice(0, 0)
	_expect(first.ok and not first.ready and run.step == 0, "first event vote waits for teammate")
	_expect(not coordinator.submit_event_choice(0, 1).ok, "player cannot vote twice in one event")
	var second := coordinator.submit_event_choice(1, 1)
	_expect(second.ok and second.ready and second.outcome == "compromise", "different choices resolve to deterministic compromise")
	_expect(run.step == 1 and run.gold == [108, 108] and run.pending_event.is_empty(), "resolved event rewards both players and advances once")
	store.clear()

func _test_consumable_effects_and_sync() -> void:
	var store := RunSaveStore.new("user://consumable_test.json")
	store.clear()
	var catalog := FullCardCatalog.build()
	var coordinator := RunCoordinator.new(catalog, store)
	var content := RunContentCatalog.build()
	for item in content.consumables:
		var run := coordinator.start_new(9000 + int(String(item.id).trim_prefix("consumable_")))
		run.consumables[0] = [String(item.id)]
		var engine := CombatEngine.new(catalog)
		var combat := engine.create_run_combat(run, ["combat"], content)
		var result := coordinator.use_consumable(combat, 0, 0, engine)
		_expect(result.ok and run.consumables[0].is_empty(), "%s applies once and is consumed" % item.id)
	_expect(not coordinator.use_consumable(CombatEngine.new(catalog).create_demo_combat(), 0, 0, CombatEngine.new(catalog)).ok, "missing consumable is rejected")
	store.clear()

func _test_relic_lifecycle_triggers() -> void:
	var catalog := FullCardCatalog.build()
	var engine := CombatEngine.new(catalog)
	var run := RunCoordinator.new(catalog, RunSaveStore.new("user://relic_test.json")).start_new(6060)
	run.team_health = 50
	run.relics[0] = ["relic_01", "relic_02", "relic_03", "relic_04", "relic_05"]
	var combat := engine.create_run_combat(run, ["combat"], RunContentCatalog.build())
	_expect(combat.players[0].block == 1 and combat.players[0].energy == 4, "combat and turn start relics apply to their owner")
	_expect(combat.relics[0].size() == 5 and CombatState.from_snapshot(combat.to_snapshot()).relics[0].size() == 5, "relic ownership survives combat snapshot round trip")
	var guardian_card: StringName = &"guardian_cover" if combat.players[0].hand.has(&"guardian_cover") else combat.players[0].hand[0]
	engine.submit_plan(combat, 0, [{"card_id": guardian_card, "target": 0}])
	engine.submit_plan(combat, 1, [{"card_id": combat.players[1].hand[0], "target": 0}])
	engine.resolve_if_ready(combat)
	var triggers: Array[String] = []
	for entry in combat.event_log:
		if entry.type == "relic_triggered":
			triggers.append(String(entry.trigger))
	_expect(triggers.has("card_played") and triggers.has("damage_taken"), "card and incoming damage relic triggers execute during resolution")
	var finish_run := RunCoordinator.new(catalog, RunSaveStore.new("user://relic_finish_test.json")).start_new(6061)
	finish_run.team_health = 40
	finish_run.relics[0] = ["relic_06"]
	var finishing := engine.create_run_combat(finish_run, ["combat"], RunContentCatalog.build())
	finishing.enemies[0].health = 1
	engine.submit_plan(finishing, 0, [{"card_id": finishing.players[0].hand[0], "target": 0}])
	engine.submit_plan(finishing, 1, [{"card_id": finishing.players[1].hand[0], "target": 0}])
	engine.resolve_if_ready(finishing)
	_expect(finishing.phase == CombatState.Phase.WON and finishing.team_health == 41, "combat end relic heals after victory")
	RunSaveStore.new("user://relic_test.json").clear()
	RunSaveStore.new("user://relic_finish_test.json").clear()

func _test_character_selection_and_scope() -> void:
	var catalog := FullCardCatalog.build()
	var store := RunSaveStore.new("user://character_selection_test.json")
	store.clear()
	var coordinator := RunCoordinator.new(catalog, store)
	var run := coordinator.start_new(7788)
	_expect(coordinator.select_character(1, &"hacker").ok, "second player can select hacker before route choice")
	_expect(run.characters[1] == &"hacker" and run.decks[1].has("hacker_card_04"), "hacker selection installs hacker starter deck")
	_expect(not coordinator.select_character(0, &"hacker").ok, "same character cannot be selected by both players")
	_expect(coordinator.select_character(0, &"medic").ok and run.decks[0].has("medic_card_04"), "medic selection installs its healing starter deck")
	_expect(coordinator.select_character(1, &"navigator").ok and run.decks[1].has("navigator_card_04"), "navigator selection installs its navigation starter deck")
	run.pending_card_rewards[1] = true
	var rewards := coordinator.current_card_reward(1)
	_expect(rewards.size() == 3 and catalog[rewards[0]].owner_scope == CardData.Scope.NAVIGATOR and catalog[rewards[1]].owner_scope == CardData.Scope.NAVIGATOR and catalog[rewards[2]].owner_scope == CardData.Scope.NEUTRAL, "character reward contains two class cards and one neutral card")
	var route_id := String(run.map.stages[0].steps[0].lanes[0].options[0].id)
	_expect(coordinator.choose_route(0, route_id).ok and not coordinator.select_character(0, &"assault").ok, "character selection closes after route commitment")
	store.clear()

func _test_duel_resolution_and_snapshot() -> void:
	var catalog := FullCardCatalog.build()
	var engine := DuelEngine.new(catalog)
	var decks := [
		["guardian_strike", "guardian_guard", "guardian_cover", "neutral_pulse", "neutral_barrier"],
		["engineer_bolt", "engineer_charge", "engineer_patch", "neutral_pulse", "neutral_barrier"],
	]
	var duel := engine.create_duel(["guardian", "engineer"], decks)
	_expect(engine.submit_plan(duel, 0, [{"card_id": &"guardian_strike"}]).ok and engine.submit_plan(duel, 1, [{"card_id": &"engineer_bolt"}]).ok, "both duel plans are accepted")
	_expect(engine.resolve_if_ready(duel).ok and duel.health == [30, 29] and duel.turn == 2, "duel resolves simultaneous damage against opposing players")
	var restored := DuelState.from_snapshot(duel.to_snapshot())
	_expect(restored.health == duel.health and restored.turn == duel.turn and restored.players[0].character_id == &"guardian", "duel snapshot round trip preserves authoritative state")
	var draw_duel := engine.create_duel(["guardian", "engineer"], decks)
	draw_duel.health = [5, 5]
	engine.submit_plan(draw_duel, 0, [{"card_id": &"guardian_strike"}])
	engine.submit_plan(draw_duel, 1, [{"card_id": &"engineer_bolt"}])
	engine.resolve_if_ready(draw_duel)
	_expect(draw_duel.phase == DuelState.Phase.FINISHED and draw_duel.winner == -1, "simultaneous lethal damage produces a draw")

func _test_host_authoritative_duel_session() -> void:
	var transports := LoopbackTransport.pair()
	transports[0].start_host("duel")
	transports[1].connect_to("loopback", "duel")
	var catalog := FullCardCatalog.build()
	var store := RunSaveStore.new("user://duel_session_test.json")
	store.clear()
	DuelSaveStore.new().clear()
	var coordinator := RunCoordinator.new(catalog, store)
	coordinator.start_new(9090)
	var combat_engine := CombatEngine.new(catalog)
	var host := CooperativeSession.new(CooperativeSession.Role.HOST, transports[0], combat_engine, combat_engine.create_demo_combat(), coordinator)
	var guest := CooperativeSession.new(CooperativeSession.Role.GUEST, transports[1])
	var received_duels: Array[Dictionary] = []
	guest.duel_snapshot_received.connect(func(snapshot: Dictionary, _hash: String) -> void: received_duels.append(snapshot))
	host.poll()
	guest.poll()
	_expect(host.set_game_mode("duel").ok, "host starts duel mode on the shared session")
	_expect(not host.select_route(0, "forbidden").ok and not host.submit_plan(0, []).ok, "duel mode rejects cooperative route and combat commands")
	guest.poll()
	_expect(guest.game_mode == "duel" and guest.duel_state != null, "guest receives duel mode and initial authoritative snapshot")
	var guest_card: StringName = guest.duel_state.players[1].hand[0]
	_expect(guest.submit_duel_plan(1, [{"card_id": guest_card}]).ok, "guest sends duel plan without resolving locally")
	host.poll()
	var host_card: StringName = host.duel_state.players[0].hand[0]
	_expect(host.submit_duel_plan(0, [{"card_id": host_card}]).ok, "host accepts its duel plan and resolves when both are ready")
	guest.poll()
	host.poll()
	guest.poll()
	_expect(host.duel_state.turn == 2 and not received_duels.is_empty() and int(received_duels[-1].turn) == 2, "guest receives resolved authoritative duel turn")
	var preserved_duel_id := host.duel_state.duel_id
	transports[1].close()
	transports[0].start_host("duel")
	transports[1].connect_to("loopback", "duel")
	guest.poll()
	_expect(guest.duel_state != null and guest.duel_state.duel_id == preserved_duel_id and guest.duel_state.turn == 2, "reconnecting transport restores the existing authoritative duel")
	host.close()
	guest.close()
	transports[0].dispose()
	store.clear()
	DuelSaveStore.new().clear()

func _test_duel_save_round_trip() -> void:
	var store := DuelSaveStore.new("user://duel_round_trip_test.json")
	store.clear()
	var engine := DuelEngine.new(FullCardCatalog.build())
	var duel := engine.create_duel(["guardian", "engineer"], [
		["guardian_strike", "guardian_guard", "neutral_pulse"],
		["engineer_bolt", "engineer_charge", "neutral_barrier"],
	])
	engine.submit_plan(duel, 0, [{"card_id": duel.players[0].hand[0]}])
	_expect(store.save(duel) == OK, "duel checkpoint saves after one hidden plan")
	var backed_up_health := duel.health[0]
	duel.health[0] -= 1
	_expect(store.save(duel) == OK, "second duel checkpoint rotates the previous valid save to backup")
	var absolute_save := ProjectSettings.globalize_path(store.save_path)
	var absolute_temp := ProjectSettings.globalize_path(store.save_path + DuelSaveStore.TEMP_SUFFIX)
	_expect(DirAccess.rename_absolute(absolute_save, absolute_temp) == OK, "test simulates interruption after staging but before promotion")
	var staged_restore := store.load_active()
	_expect(staged_restore != null and staged_restore.health[0] == duel.health[0], "valid staged checkpoint takes priority over the older backup")
	DirAccess.rename_absolute(absolute_temp, absolute_save)
	var corrupt_file := FileAccess.open(store.save_path, FileAccess.WRITE)
	if corrupt_file != null:
		corrupt_file.store_string("{interrupted")
		corrupt_file.close()
	var restored := store.load_active()
	_expect(restored != null and restored.duel_id == duel.duel_id and restored.plans.has(0) and restored.players[0].ready, "duel checkpoint restores id, plan, and readiness")
	_expect(restored != null and restored.health[0] == backed_up_health, "corrupt primary duel checkpoint falls back to the previous checksummed backup")
	var first_pending := {"role": "guest", "duel_id": String(duel.duel_id), "turn": 1, "commitment": "a".repeat(64)}
	var second_pending := {"role": "guest", "duel_id": String(duel.duel_id), "turn": 2, "commitment": "b".repeat(64)}
	store.save_pending_commitment(first_pending)
	store.save_pending_commitment(second_pending)
	var corrupt_pending := FileAccess.open(store.save_path + DuelSaveStore.PENDING_SUFFIX, FileAccess.WRITE)
	if corrupt_pending != null:
		corrupt_pending.store_string("corrupt")
		corrupt_pending.close()
	_expect(store.load_pending_commitment().get("commitment", "") == first_pending.commitment, "corrupt pending commitment falls back to its checksummed backup")
	store.clear()

func _test_duel_commitment_tamper_rejected() -> void:
	var transports := LoopbackTransport.pair()
	transports[0].start_host("duel-tamper")
	transports[1].connect_to("loopback", "duel-tamper")
	var catalog := FullCardCatalog.build()
	var run_store := RunSaveStore.new("user://duel_tamper_run.json")
	run_store.clear()
	var coordinator := RunCoordinator.new(catalog, run_store)
	coordinator.start_new(9191)
	var combat_engine := CombatEngine.new(catalog)
	var host := CooperativeSession.new(CooperativeSession.Role.HOST, transports[0], combat_engine, combat_engine.create_demo_combat(), coordinator)
	var guest := CooperativeSession.new(CooperativeSession.Role.GUEST, transports[1])
	var errors: Array[String] = []
	guest.session_error.connect(func(code: String, _detail: String) -> void: errors.append(code))
	host.poll()
	guest.poll()
	host.set_game_mode("duel")
	guest.poll()
	var committed_card: StringName = guest.duel_state.players[1].hand[0]
	var commit_result := guest.submit_duel_plan(1, [{"card_id": committed_card}])
	_expect(commit_result.ok, "guest duel plan creates a commitment")
	var duplicate_result := guest.submit_duel_plan(1, [{"card_id": committed_card}])
	_expect(not duplicate_result.ok and duplicate_result.error == "duel_plan_already_committed", "guest cannot replace a pending committed plan")
	guest.guest_pending_duel_plays = [{"card_id": &"tampered_card"}]
	host.poll()
	host.submit_duel_plan(0, [{"card_id": host.duel_state.players[0].hand[0]}])
	guest.poll()
	host.poll()
	guest.poll()
	_expect(host.duel_state.turn == 1 and host.duel_state.plans.size() == 1 and errors.has("duel_commitment_mismatch"), "tampered duel reveal is rejected before guest plan validation")
	_expect(guest.guest_pending_duel_plays.is_empty(), "guest clears rejected commitment and can choose again")
	_expect(guest.submit_duel_plan(1, [{"card_id": committed_card}]).ok, "guest can recommit after a rejected reveal")
	host.close()
	guest.close()
	transports[0].dispose()
	run_store.clear()
	DuelSaveStore.new().clear()

func _test_duel_commitment_process_restart_recovery() -> void:
	var host_store := DuelSaveStore.new("user://duel_restart_host.json")
	var guest_store := DuelSaveStore.new("user://duel_restart_guest.json")
	host_store.clear()
	guest_store.clear()
	var first_transports := LoopbackTransport.pair()
	first_transports[0].start_host("duel-restart")
	first_transports[1].connect_to("loopback", "duel-restart")
	var catalog := FullCardCatalog.build()
	var run_store := RunSaveStore.new("user://duel_restart_run.json")
	run_store.clear()
	var coordinator := RunCoordinator.new(catalog, run_store)
	coordinator.start_new(9292)
	var combat_engine := CombatEngine.new(catalog)
	var host := CooperativeSession.new(CooperativeSession.Role.HOST, first_transports[0], combat_engine, combat_engine.create_demo_combat(), coordinator, host_store)
	var guest := CooperativeSession.new(CooperativeSession.Role.GUEST, first_transports[1], null, null, null, guest_store)
	host.poll()
	guest.poll()
	host.set_game_mode("duel")
	guest.poll()
	var guest_card: StringName = guest.duel_state.players[1].hand[0]
	_expect(guest.submit_duel_plan(1, [{"card_id": guest_card}]).ok, "guest persists a commitment before sending it")
	host.poll()
	var host_card: StringName = host.duel_state.players[0].hand[0]
	_expect(host.submit_duel_plan(0, [{"card_id": host_card}]).ok, "host persists its ready plan while waiting for reveal")
	_expect(not host_store.load_pending_commitment().is_empty() and not guest_store.load_pending_commitment().is_empty(), "both devices checkpoint their side of the pending reveal")

	var restarted_transports := LoopbackTransport.pair()
	restarted_transports[0].start_host("duel-restart")
	var restarted_host := CooperativeSession.new(CooperativeSession.Role.HOST, restarted_transports[0], combat_engine, combat_engine.create_demo_combat(), coordinator, host_store)
	restarted_host.game_mode = "duel"
	restarted_host.duel_engine = DuelEngine.new(catalog)
	restarted_host.duel_state = host_store.load_active()
	var restarted_guest := CooperativeSession.new(CooperativeSession.Role.GUEST, restarted_transports[1], null, null, null, guest_store)
	restarted_transports[1].connect_to("loopback", "duel-restart")
	restarted_host.poll()
	restarted_guest.poll()
	restarted_host.poll()
	restarted_guest.poll()
	_expect(restarted_host.duel_state.turn == 2 and restarted_guest.duel_state.turn == 2, "both app processes resume commit reveal and resolve the interrupted turn")
	_expect(host_store.load_pending_commitment().is_empty() and guest_store.load_pending_commitment().is_empty(), "resolved restarted turn clears both pending checkpoints")
	host.close()
	guest.close()
	restarted_host.close()
	restarted_guest.close()
	first_transports[0].dispose()
	restarted_transports[0].dispose()
	host_store.clear()
	guest_store.clear()
	run_store.clear()

func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append("FAIL: %s" % label)
