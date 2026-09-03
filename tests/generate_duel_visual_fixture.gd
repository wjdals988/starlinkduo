extends SceneTree

const OUTPUT_PATH := "/tmp/starlink-duo-finished-duel.json"

func _init() -> void:
	var catalog := FullCardCatalog.build()
	var engine := DuelEngine.new(catalog)
	var coordinator := RunCoordinator.new(catalog, RunSaveStore.new("user://duel_visual_fixture_run.json"))
	coordinator.start_new(20260903)
	var duel := engine.create_duel(coordinator.run.characters, [
		coordinator.starter_deck_for(coordinator.run.characters[0]),
		coordinator.starter_deck_for(coordinator.run.characters[1]),
	])
	duel.turn = 8
	duel.phase = DuelState.Phase.FINISHED
	duel.health = [0, 11]
	duel.winner = 1
	duel.event_log.append({"type": "duel_finished", "winner": 1})
	var error := DuelSaveStore.new(OUTPUT_PATH).save(duel)
	RunSaveStore.new("user://duel_visual_fixture_run.json").clear()
	if error != OK:
		push_error("duel visual fixture save failed: %s" % error_string(error))
		quit(1)
		return
	print("DUEL_VISUAL_FIXTURE=%s" % OUTPUT_PATH)
	quit(0)
