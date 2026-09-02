extends SceneTree

func _initialize() -> void:
	var scene := load("res://src/ui/main.tscn") as PackedScene
	var instance := scene.instantiate()
	root.add_child(instance)
	await process_frame
	await process_frame
	var image := root.get_viewport().get_texture().get_image()
	if image == null:
		push_error("UI capture requires a rendering backend; do not use --headless")
		quit(1)
		return
	var error := image.save_png("res://artifacts/combat-ui.png")
	if error != OK:
		push_error("UI capture failed: %s" % error_string(error))
		quit(1)
		return
	print("Saved artifacts/combat-ui.png")
	quit(0)
