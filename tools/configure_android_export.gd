@tool
extends SceneTree

func _initialize() -> void:
	if not Engine.is_editor_hint():
		push_error("Run with --editor")
		quit(1)
		return
	var settings := EditorInterface.get_editor_settings()
	settings.set_setting("export/android/java_sdk_path", "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home")
	settings.set_setting("export/android/android_sdk_path", "/Users/user/Library/Android/sdk")
	print("Configured Godot Android SDK and Java SDK paths")
	quit(0)
