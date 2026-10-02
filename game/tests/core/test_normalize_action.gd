extends GutTest
## Simulation.normalize_action (docs/ARCHITECTURE.md section 19): JSON gives floats.

const U = preload("res://tests/core/sim_test_util.gd")


func _json_roundtrip(a: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(a))
	assert_eq(typeof(parsed), TYPE_DICTIONARY)
	return parsed


func _aim_actions() -> Array[Dictionary]:
	return [U.fire(0, 452, 610), U.move(0, -17), U.use_item(0, "glow_shield"), U.pass_turn(0)]


func _shop_actions() -> Array[Dictionary]:
	return [U.buy(0, "fuel_cell", 2), U.sell(0, "fuel_cell", 1), U.ready(0)]


func test_json_roundtrip_of_every_action_kind_validates_after_normalizing() -> void:
	var aim: MatchState = U.flat_state(2)
	aim.tanks[0].fuel = 50
	aim.tanks[0].set_stock("glow_shield", 2)
	for a: Dictionary in _aim_actions():
		var parsed: Dictionary = _json_roundtrip(a)
		assert_ne(Simulation.validate_action(aim, parsed), "", "raw JSON floats are rejected: %s" % str(a))
		var fixed: Dictionary = Simulation.normalize_action(parsed)
		assert_eq(Simulation.validate_action(aim, fixed), "", "normalized: %s" % str(a))
		assert_eq(fixed, a, "round trip is lossless")
	var shop: MatchState = U.shop_state(2)
	shop.tanks[0].set_stock("fuel_cell", 3)
	for a: Dictionary in _shop_actions():
		var parsed: Dictionary = _json_roundtrip(a)
		assert_ne(Simulation.validate_action(shop, parsed), "", "raw JSON floats are rejected: %s" % str(a))
		var fixed: Dictionary = Simulation.normalize_action(parsed)
		assert_eq(Simulation.validate_action(shop, fixed), "", "normalized: %s" % str(a))
		assert_eq(fixed, a)


func test_normalized_types_are_int() -> void:
	var fixed: Dictionary = Simulation.normalize_action({"kind": "fire", "tank": 1.0, "angle": 452.0, "power": 610.0,
			"weapon": "pulse_missile"})
	for k: String in ["tank", "angle", "power"]:
		assert_eq(typeof(fixed[k]), TYPE_INT, k)
	assert_eq(fixed["weapon"], "pulse_missile")
	assert_eq(typeof(fixed["weapon"]), TYPE_STRING)


func test_negative_zero_and_large_whole_floats() -> void:
	var fixed: Dictionary = Simulation.normalize_action({"dx": -17.0, "zero": 0.0, "big": 1048576.0, "neg0": -0.0})
	assert_eq(fixed["dx"], -17)
	assert_eq(typeof(fixed["dx"]), TYPE_INT)
	assert_eq(fixed["zero"], 0)
	assert_eq(typeof(fixed["zero"]), TYPE_INT)
	assert_eq(fixed["big"], 1048576)
	assert_eq(typeof(fixed["neg0"]), TYPE_INT)


func test_non_whole_floats_and_other_types_are_left_alone() -> void:
	var src: Dictionary = {"a": 45.5, "b": "450", "c": true, "d": null, "e": [1.0, 2], "f": {"x": 1.0}, "g": 7}
	var fixed: Dictionary = Simulation.normalize_action(src)
	assert_eq(typeof(fixed["a"]), TYPE_FLOAT)
	assert_eq(fixed["a"], 45.5)
	assert_eq(fixed["b"], "450")
	assert_eq(fixed["c"], true)
	assert_eq(fixed["d"], null)
	assert_eq(typeof((fixed["e"] as Array)[0]), TYPE_FLOAT, "nested values are untouched")
	assert_eq(typeof((fixed["f"] as Dictionary)["x"]), TYPE_FLOAT)
	assert_eq(fixed["g"], 7)
	var s: MatchState = U.flat_state(2)
	var frac: Dictionary = Simulation.normalize_action({"kind": "fire", "tank": 0, "angle": 45.5, "power": 500.0,
			"weapon": "pulse_missile"})
	assert_eq(Simulation.validate_action(s, frac), "bad_field", "a fractional angle stays invalid")


func test_does_not_mutate_the_input_and_handles_empty() -> void:
	var src: Dictionary = {"kind": "move", "tank": 0.0, "dx": 3.0}
	var copy: Dictionary = src.duplicate(true)
	var fixed: Dictionary = Simulation.normalize_action(src)
	assert_eq(src, copy)
	assert_eq(typeof(src["tank"]), TYPE_FLOAT)
	assert_eq(typeof(fixed["tank"]), TYPE_INT)
	assert_eq(Simulation.normalize_action({}), {})


func test_huge_floats_do_not_become_valid_ints() -> void:
	var fixed: Dictionary = Simulation.normalize_action(_json_roundtrip({"v": 1e300, "w": -1e300}))
	assert_ne(typeof(fixed["v"]), TYPE_STRING)
	var s: MatchState = U.flat_state(2)
	var a: Dictionary = U.fire(0, 450, 500)
	a["power"] = 1e300
	assert_ne(Simulation.validate_action(s, Simulation.normalize_action(a)), "")


func test_normalized_action_applies_like_the_original() -> void:
	var a_state: MatchState = U.flat_state(2)
	var b_state: MatchState = U.flat_state(2)
	var act: Dictionary = U.fire(0, 450, 700)
	var ev_a: Array[Dictionary] = Simulation.apply_action(a_state, act)
	var ev_b: Array[Dictionary] = Simulation.apply_action(b_state, Simulation.normalize_action(_json_roundtrip(act)))
	assert_eq(ev_a, ev_b)
	assert_eq(Simulation.fingerprint(a_state), Simulation.fingerprint(b_state))
