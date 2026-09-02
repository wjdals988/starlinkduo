class_name AndroidAccessibilityBridge
extends RefCounted

const PLUGIN_NAME := "StarlinkBluetooth"

var _plugin: Object
var _controls: Dictionary = {}
var _next_id := 1

func _init() -> void:
	if Engine.has_singleton(PLUGIN_NAME):
		_plugin = Engine.get_singleton(PLUGIN_NAME)

func is_available() -> bool:
	return _plugin != null

func sync(root: Control) -> void:
	if not is_available():
		return
	_controls.clear()
	var elements: Array[Dictionary] = []
	_collect_elements(root, elements)
	var viewport_size := root.get_viewport_rect().size
	_plugin.setAccessibilityElementsJson(JSON.stringify({
		"width": roundi(viewport_size.x),
		"height": roundi(viewport_size.y),
		"elements": elements,
	}))

func poll_action() -> void:
	if not is_available():
		return
	while true:
		var action_id := int(_plugin.pollAccessibilityAction())
		if action_id < 0:
			return
		var control: BaseButton = _controls.get(action_id)
		if is_instance_valid(control) and control.is_visible_in_tree() and not control.disabled:
			control.pressed.emit()

func _collect_elements(node: Node, elements: Array[Dictionary]) -> void:
	if node is BaseButton:
		var button := node as BaseButton
		if button.is_visible_in_tree() and not button.is_queued_for_deletion() and button.focus_mode != Control.FOCUS_NONE:
			var rect := button.get_global_rect()
			if rect.size.x > 0 and rect.size.y > 0:
				var action_id := _id_for(button)
				_controls[action_id] = button
				elements.append({
					"id": action_id,
					"name": button.accessibility_name if not button.accessibility_name.is_empty() else _fallback_name(button),
					"description": button.accessibility_description,
					"enabled": not button.disabled,
					"role": "button",
					"left": floori(rect.position.x),
					"top": floori(rect.position.y),
					"right": ceili(rect.end.x),
					"bottom": ceili(rect.end.y),
				})
	elif node is Label:
		var label := node as Label
		if label.is_visible_in_tree() and not label.is_queued_for_deletion() and not label.accessibility_name.is_empty():
			var rect := label.get_global_rect()
			if rect.size.x > 0 and rect.size.y > 0:
				elements.append({
					"id": _id_for(label),
					"name": label.accessibility_name,
					"description": label.text,
					"enabled": true,
					"role": "text",
					"left": floori(rect.position.x),
					"top": floori(rect.position.y),
					"right": ceili(rect.end.x),
					"bottom": ceili(rect.end.y),
				})
	for child in node.get_children():
		_collect_elements(child, elements)

func _id_for(control: Control) -> int:
	if control.has_meta("android_accessibility_id"):
		return int(control.get_meta("android_accessibility_id"))
	var result := _next_id
	_next_id += 1
	control.set_meta("android_accessibility_id", result)
	return result

func _fallback_name(button: BaseButton) -> String:
	for line in button.text.split("\n"):
		var cleaned := String(line).strip_edges()
		if not cleaned.is_empty():
			return cleaned
	return "버튼"
