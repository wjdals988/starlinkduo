extends SceneTree

const OUTPUT_PATH := "/tmp/starlink-duo-event-run.json"

func _init() -> void:
	var store := RunSaveStore.new(OUTPUT_PATH)
	store.clear()
	var coordinator := RunCoordinator.new(FullCardCatalog.build(), store)
	var run := coordinator.start_new(20260904)
	run.stage = 1
	run.step = 3
	run.team_health = 66
	run.pending_routes = {0: "event-preview", 1: "rest-preview"}
	var result := coordinator.begin_event(["event", "rest"])
	if not result.ok:
		push_error("event visual fixture failed: %s" % result.get("error", "unknown"))
		quit(1)
		return
	print("EVENT_VISUAL_FIXTURE=%s" % OUTPUT_PATH)
	quit(0)
