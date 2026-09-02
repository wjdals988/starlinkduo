class_name MapGenerator
extends RefCounted

const TRAVERSAL_STEPS := 8
const COMMON_STEPS := [2, 5]
const PERSONAL_TYPES := ["combat", "combat", "event", "shop", "rest", "elite"]

func generate_run(seed: int) -> Dictionary:
	var stages: Array[Dictionary] = []
	for stage_number in range(1, 4):
		stages.append(generate_stage(seed, stage_number))
	return {"seed": seed, "stages": stages}

func generate_stage(seed: int, stage_number: int) -> Dictionary:
	var rng := SeededRng.new(seed + stage_number * 104_729)
	var steps: Array[Dictionary] = []
	var guarantees := {
		0: ["shop", "rest", "elite", "key_challenge"],
		1: ["shop", "rest", "elite", "key_challenge"],
	}
	for step_index in TRAVERSAL_STEPS:
		if step_index in COMMON_STEPS:
			steps.append({
				"index": step_index,
				"kind": "common",
				"options": [{"id": _node_id(stage_number, step_index, -1, 0), "type": "combat"}],
			})
			continue
		var lanes: Array[Dictionary] = []
		for slot in 2:
			var options: Array[Dictionary] = []
			for option_index in 2:
				var node_type: String = rng.pick(PERSONAL_TYPES)
				options.append({
					"id": _node_id(stage_number, step_index, slot, option_index),
					"type": node_type,
				})
			lanes.append({"slot": slot, "options": options})
		steps.append({"index": step_index, "kind": "parallel", "lanes": lanes})
	_apply_guarantees(steps, guarantees, rng)
	return {
		"stage": stage_number,
		"steps": steps,
		"boss": {"id": "s%d-boss" % stage_number, "type": "boss"},
	}

func _apply_guarantees(steps: Array[Dictionary], guarantees: Dictionary, rng: SeededRng) -> void:
	var parallel_indices: Array[int] = []
	for index in steps.size():
		if steps[index].kind == "parallel":
			parallel_indices.append(index)
	for slot in 2:
		var targets := rng.shuffled(parallel_indices)
		var types: Array = guarantees[slot]
		for guarantee_index in types.size():
			var step_index: int = targets[guarantee_index]
			var option_index := guarantee_index % 2
			steps[step_index].lanes[slot].options[option_index].type = types[guarantee_index]

func _node_id(stage_number: int, step_index: int, slot: int, option_index: int) -> String:
	return "s%d-r%d-p%d-o%d" % [stage_number, step_index, slot, option_index]

