class_name AndroidBluetoothTransport
extends SessionTransport

const PLUGIN_NAME := "StarlinkBluetooth"

var _plugin: Object
var _last_state := "unavailable"

func _init() -> void:
	if Engine.has_singleton(PLUGIN_NAME):
		_plugin = Engine.get_singleton(PLUGIN_NAME)
		_last_state = _plugin.getState()

func is_available() -> bool:
	return _plugin != null and _plugin.isBluetoothAvailable()

func get_state() -> String:
	return _last_state

func request_permissions() -> void:
	if _plugin != null:
		_plugin.requestBluetoothPermissions()

func start_host(service_uuid: String) -> bool:
	return _plugin != null and _plugin.startHost(service_uuid)

func connect_to(address: String, service_uuid: String) -> bool:
	return _plugin != null and _plugin.connectToDevice(address, service_uuid)

func send_message(message: String) -> bool:
	return _plugin != null and _plugin.sendMessage(message)

func poll() -> void:
	if _plugin == null:
		return
	var next_state: String = _plugin.getState()
	if next_state != _last_state:
		_last_state = next_state
		state_changed.emit(next_state)
	while true:
		var message: String = _plugin.pollMessage()
		if message.is_empty():
			break
		message_received.emit(message)
	var error: String = _plugin.pollError()
	if not error.is_empty():
		transport_error.emit("bluetooth", error)

func close() -> void:
	if _plugin != null:
		_plugin.closeConnection()

