@tool
extends EditorPlugin

var export_plugin: StarlinkBluetoothExportPlugin

func _enter_tree() -> void:
	export_plugin = StarlinkBluetoothExportPlugin.new()
	add_export_plugin(export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(export_plugin)
	export_plugin = null

class StarlinkBluetoothExportPlugin extends EditorExportPlugin:
	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		return PackedStringArray([
			"starlink_bluetooth/StarlinkBluetooth.debug.aar" if debug
			else "starlink_bluetooth/StarlinkBluetooth.release.aar"
		])

	func _get_name() -> String:
		return "StarlinkBluetooth"
