class_name SeededRng
extends RefCounted

const MODULUS := 2_147_483_647
const MULTIPLIER := 48_271

var state: int

func _init(seed_value: int = 1) -> void:
	state = absi(seed_value) % MODULUS
	if state == 0:
		state = 1

func next_int() -> int:
	state = (state * MULTIPLIER) % MODULUS
	return state

func range_int(minimum: int, maximum_exclusive: int) -> int:
	assert(maximum_exclusive > minimum)
	return minimum + next_int() % (maximum_exclusive - minimum)

func chance(percent: int) -> bool:
	return range_int(0, 100) < percent

func pick(values: Array) -> Variant:
	assert(not values.is_empty())
	return values[range_int(0, values.size())]

func shuffled(values: Array) -> Array:
	var result := values.duplicate()
	for index in range(result.size() - 1, 0, -1):
		var target := range_int(0, index + 1)
		var temporary: Variant = result[index]
		result[index] = result[target]
		result[target] = temporary
	return result

