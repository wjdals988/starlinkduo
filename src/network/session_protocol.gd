class_name SessionProtocol
extends RefCounted

const VERSION := 1

static func encode(message_type: String, sequence: int, payload: Dictionary) -> String:
	return JSON.stringify({
		"v": VERSION,
		"type": message_type,
		"seq": sequence,
		"payload": payload,
	})

static func decode(raw: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		return _error("invalid_json")
	if int(parsed.get("v", -1)) != VERSION:
		return _error("unsupported_version")
	if not parsed.get("type", null) is String or String(parsed.type).is_empty():
		return _error("invalid_type")
	if not parsed.get("seq", null) is float and not parsed.get("seq", null) is int:
		return _error("invalid_sequence")
	if int(parsed.seq) < 1 or not parsed.get("payload", null) is Dictionary:
		return _error("invalid_envelope")
	return {
		"ok": true,
		"type": String(parsed.type),
		"seq": int(parsed.seq),
		"payload": parsed.payload,
	}

static func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code}
