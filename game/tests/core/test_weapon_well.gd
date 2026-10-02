@warning_ignore_start("integer_division")
extends GutTest
## Singularity Seed (docs/ARCHITECTURE.md section 21).

const U = preload("res://tests/core/sim_test_util.gd")
const WU = preload("res://tests/core/weapon_test_util.gd")


func _fire_seed(s: MatchState, angle: int = 450, power: int = 600) -> Array[Dictionary]:
	return WU.fire(s, "singularity_seed", angle, power)


func _apex(path: PackedInt32Array) -> Vector2i:
	var best: int = 0
	for i: int in range(0, path.size(), 2):
		if path[i + 1] < path[best + 1]:
			best = i
	return Vector2i(path[best] >> 16, path[best + 1] >> 16)


func test_impact_creates_a_well_with_the_expected_expiry() -> void:
	var s: MatchState = U.flat_state(2)
	var ev: Array[Dictionary] = _fire_seed(s)
	var on: Array[Dictionary] = U.find(ev, "well_on")
	assert_eq(on.size(), 1)
	var end: Dictionary = U.find(ev, "projectile_end")[0]
	assert_eq([on[0]["owner"], on[0]["x"], on[0]["y"], on[0]["expires_turn"]], [0, end["x"], end["y"], 4])
	assert_eq(on[0]["tick"], end["tick"])
	assert_eq(s.wells.size(), 1)
	assert_eq(s.wells[0], {"owner": 0, "x": end["x"], "y": end["y"], "expires_turn": 4})
	assert_eq(U.types(ev), ["fire", "projectile", "projectile_end", "well_on", "wind", "turn"] as Array[String])
	assert_eq(U.find(ev, "explosion").size(), 0)


func test_expiry_counts_only_alive_tanks() -> void:
	var s: MatchState = U.flat_state(4)
	s.tanks[3].alive = false
	s.tanks[3].health = 0
	s.turn_number = 5
	var ev: Array[Dictionary] = _fire_seed(s)
	assert_eq(U.find(ev, "well_on")[0]["expires_turn"], 5 + 2 * 3)


func test_same_owner_replaces_its_old_well() -> void:
	var s: MatchState = U.flat_state(2)
	_fire_seed(s, 450, 600)
	var first: Dictionary = s.wells[0].duplicate()
	s.current_tank = 0
	var ev: Array[Dictionary] = _fire_seed(s, 450, 700)
	assert_eq(s.wells.size(), 1)
	assert_ne(s.wells[0]["x"], first["x"])
	var types: Array[String] = U.types(ev)
	assert_true(types.find("well_off") >= 0 and types.find("well_off") < types.find("well_on"))
	assert_eq(U.find(ev, "well_off")[0]["owner"], 0)
	assert_eq(s.wells[0]["expires_turn"], s.turn_number - 1 + 4, "measured from the second shot's turn")


func test_wells_stay_in_owner_order() -> void:
	var s: MatchState = U.flat_state(3)
	s.current_tank = 2
	_fire_seed(s, 1350, 600)
	s.current_tank = 0
	_fire_seed(s, 450, 700)
	s.current_tank = 1
	_fire_seed(s, 450, 450)
	var owners: Array[int] = []
	for w: Dictionary in s.wells:
		owners.append(w["owner"])
	assert_eq(owners, [0, 1, 2] as Array[int])
	s.current_tank = 1
	var ev: Array[Dictionary] = _fire_seed(s, 450, 400)
	assert_eq(U.find(ev, "well_off")[0]["owner"], 1)
	owners.clear()
	for w: Dictionary in s.wells:
		owners.append(w["owner"])
	assert_eq(owners, [0, 1, 2] as Array[int], "replacing keeps the slot")


func test_the_well_lasts_two_full_turn_cycles() -> void:
	var s: MatchState = U.flat_state(2)
	_fire_seed(s)
	assert_eq(s.turn_number, 1)
	assert_eq(s.wells[0]["expires_turn"], 4)
	for i: int in range(2):  # turns 1 and 2 are passed: turn_number 2, 3
		var ev: Array[Dictionary] = Simulation.apply_action(s, U.pass_turn(s.current_tank))
		assert_eq(U.find(ev, "well_off").size(), 0)
		assert_eq(s.wells.size(), 1, "still there at turn %d" % s.turn_number)
	assert_eq(s.turn_number, 3)
	var last: Array[Dictionary] = Simulation.apply_action(s, U.pass_turn(s.current_tank))
	assert_eq(s.turn_number, 4)
	var off: Array[Dictionary] = U.find(last, "well_off")
	assert_eq(off.size(), 1)
	assert_eq(off[0]["owner"], 0)
	assert_eq(s.wells.size(), 0)


func test_three_tanks_keep_it_for_six_turns() -> void:
	var s: MatchState = U.flat_state(3)
	_fire_seed(s)
	assert_eq(s.wells[0]["expires_turn"], 6)
	while s.turn_number < 5:
		Simulation.apply_action(s, U.pass_turn(s.current_tank))
	assert_eq(s.wells.size(), 1)
	Simulation.apply_action(s, U.pass_turn(s.current_tank))
	assert_eq(s.wells.size(), 0)


func test_the_well_changes_later_shots() -> void:
	var s: MatchState = U.flat_state(2)
	var before: Dictionary = WU.plain_trace(s, 450, 600)
	var apex: Vector2i = _apex(before["path"])
	s.wells = [{"owner": 1, "x": apex.x, "y": apex.y + 120, "expires_turn": 99}]
	var after: Dictionary = WU.plain_trace(s, 450, 600)
	assert_ne(after["path"], before["path"])
	assert_ne(after["end_x"], before["end_x"])
	s.wells.clear()
	assert_eq(WU.plain_trace(s, 450, 600)["path"], before["path"], "no wells: the original flight")


func test_a_well_near_the_arc_bends_the_landing_by_at_least_40_cells() -> void:
	for angle: int in [300, 450]:
		var s: MatchState = U.flat_state(2)
		var base: Dictionary = WU.plain_trace(s, angle, 600)
		var apex: Vector2i = _apex(base["path"])
		for off: Vector2i in [Vector2i(0, 150), Vector2i(0, -150), Vector2i(150, 0), Vector2i(-150, 0)]:
			s.wells = [{"owner": 1, "x": apex.x + off.x, "y": apex.y + off.y, "expires_turn": 99}]
			var tr: Dictionary = WU.plain_trace(s, angle, 600)
			var shift: int = absi((tr["end_x"] as int) - (base["end_x"] as int))
			assert_true(shift >= 40, "angle %d, well %s from the apex: shift %d" % [angle, str(off), shift])


func test_the_pull_points_toward_the_well() -> void:
	var s: MatchState = U.flat_state(2)
	var base: Dictionary = WU.plain_trace(s, 450, 600)
	var apex: Vector2i = _apex(base["path"])
	s.wells = [{"owner": 1, "x": apex.x, "y": apex.y - 150, "expires_turn": 99}]
	assert_gt(WU.plain_trace(s, 450, 600)["end_x"] as int, base["end_x"] as int, "a well above holds the shell up: it flies on")
	s.wells = [{"owner": 1, "x": apex.x, "y": apex.y + 150, "expires_turn": 99}]
	assert_lt(WU.plain_trace(s, 450, 600)["end_x"] as int, base["end_x"] as int, "a well below pulls it down short")


func test_well_range_and_the_close_up_dead_zone() -> void:
	var s: MatchState = U.flat_state(2)
	var base: Dictionary = WU.plain_trace(s, 450, 600)
	var path: PackedInt32Array = base["path"]
	# Out of range (the shell never comes within 300 cells): identical flight.
	s.wells = [{"owner": 1, "x": 1500, "y": 100, "expires_turn": 99}]
	assert_eq(WU.plain_trace(s, 450, 600)["path"], path)
	# A well sitting exactly on the path: no division by zero, a finished flight.
	var mid: int = path.size() / 4 * 2
	s.wells = [{"owner": 1, "x": path[mid] >> 16, "y": path[mid + 1] >> 16, "expires_turn": 99}]
	var tr: Dictionary = WU.plain_trace(s, 450, 600)
	assert_eq(tr["end_reason"], "terrain")


func test_wells_pull_every_weapon_including_the_owners_shells() -> void:
	var s: MatchState = U.flat_state(2)
	var base: Dictionary = WU.plain_trace(s, 450, 600)
	var apex: Vector2i = _apex(base["path"])
	s.wells = [{"owner": 0, "x": apex.x, "y": apex.y + 100, "expires_turn": 99}]
	assert_ne(WU.plain_trace(s, 450, 600, 0)["end_x"], base["end_x"])
	var ev: Array[Dictionary] = WU.fire(s, "pulse_missile", 450, 600)
	assert_ne(U.find(ev, "projectile_end")[0]["x"], base["end_x"], "a real shot is bent as well")


func test_wells_are_part_of_the_fingerprint_and_the_save() -> void:
	var s: MatchState = U.flat_state(2)
	var plain_fp: String = Simulation.fingerprint(s)
	_fire_seed(s)
	var with_well: String = Simulation.fingerprint(s)
	assert_ne(with_well, plain_fp)
	var t: MatchState = s.duplicate_state()
	t.wells[0]["x"] = (t.wells[0]["x"] as int) + 1
	assert_ne(Simulation.fingerprint(t), with_well, "the well position matters")
	var u: MatchState = s.duplicate_state()
	u.wells[0]["expires_turn"] = 17
	assert_ne(Simulation.fingerprint(u), with_well, "so does the expiry")
	var bytes: PackedByteArray = SaveCodec.encode(s, [] as Array[Dictionary])
	var dec: Dictionary = SaveCodec.decode(bytes)
	assert_true(dec["ok"], str(dec.get("error", "")))
	var back: MatchState = dec["state"]
	assert_eq(back.wells, s.wells)
	assert_eq(Simulation.fingerprint(back), with_well)


func test_wells_are_cleared_at_round_start() -> void:
	var s: MatchState = U.shop_state(2, 3, 5)
	s.wells = [{"owner": 0, "x": 100, "y": 100, "expires_turn": 50}]
	U.begin_round(s)
	assert_eq(s.wells.size(), 0)


func test_a_lost_shell_makes_no_well() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[0].x = 20
	var ev: Array[Dictionary] = _fire_seed(s, 1750, 900)
	assert_eq(U.find(ev, "well_on").size(), 0)
	assert_eq(s.wells.size(), 0)


func test_a_well_appears_where_the_shell_hit_a_tank_or_shield() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[1].x = 800
	var p: int = WU.power_for_landing(s, 450, 800)
	var ev: Array[Dictionary] = WU.fire(s, "singularity_seed", 450, p)
	var end: Dictionary = U.find(ev, "projectile_end")[0]
	assert_eq(end["reason"], "tank")
	assert_eq(s.wells[0]["x"], end["x"])
	assert_eq(s.wells[0]["y"], end["y"])
	assert_eq(s.tanks[1].health, 100, "the seed is harmless by itself")
