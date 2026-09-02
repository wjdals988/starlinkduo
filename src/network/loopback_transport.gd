class_name LoopbackTransport
extends SessionTransport

var peer: LoopbackTransport
var inbox: Array[String] = []
var current_state := "idle"

static func pair() -> Array[LoopbackTransport]:
	var first := LoopbackTransport.new()
	var second := LoopbackTransport.new()
	first.peer = second
	second.peer = first
	return [first, second]

func is_available() -> bool:
	return true

func has_permissions() -> bool:
	return true

func is_enabled() -> bool:
	return true

func get_state() -> String:
	return current_state

func start_host(_service_uuid: String) -> bool:
	_set_state("listening")
	return true

func connect_to(_address: String, _service_uuid: String) -> bool:
	if peer == null:
		return false
	_set_state("connected")
	peer._set_state("connected")
	return true

func send_message(message: String) -> bool:
	if current_state != "connected" or peer == null:
		return false
	peer.inbox.append(message)
	return true

func poll() -> void:
	while not inbox.is_empty():
		message_received.emit(inbox.pop_front())

func close() -> void:
	_set_state("closed")
	if peer != null and peer.current_state != "closed":
		peer._set_state("closed")

func _set_state(value: String) -> void:
	current_state = value
	state_changed.emit(value)
