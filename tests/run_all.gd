extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	_test_initial_state()
	_test_simultaneous_resolution()
	_test_support_limit()
	_test_deterministic_hash()
	if failures.is_empty():
		print("PASS: 4 combat core tests")
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

func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append("FAIL: %s" % label)

