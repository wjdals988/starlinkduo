class_name StateHasher
extends RefCounted

static func hash_snapshot(snapshot: Dictionary) -> String:
	var canonical: Variant = _canonicalize(snapshot)
	return JSON.stringify(canonical).sha256_text()

static func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var source: Dictionary = value
		var keys := source.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		var result: Dictionary = {}
		for key in keys:
			result[str(key)] = _canonicalize(source[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_canonicalize(item))
		return result
	return value
