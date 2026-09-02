class_name SessionTransport
extends RefCounted

signal state_changed(state: String)
signal message_received(message: String)
signal transport_error(code: String, detail: String)

func is_available() -> bool:
	return false

func get_state() -> String:
	return "unavailable"

func request_permissions() -> void:
	pass

func start_host(_service_uuid: String) -> bool:
	return false

func connect_to(_address: String, _service_uuid: String) -> bool:
	return false

func send_message(_message: String) -> bool:
	return false

func poll() -> void:
	pass

func close() -> void:
	pass

