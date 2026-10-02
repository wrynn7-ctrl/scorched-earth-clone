@warning_ignore_start("integer_division")
extends GutTest
## Glide Orb / Heavy Orb (docs/ARCHITECTURE.md section 21).

const U = preload("res://tests/core/sim_test_util.gd")
const WU = preload("res://tests/core/weapon_test_util.gd")


## A V-shaped valley (1 cell down per column) with its bottom at x = 800; plateaus at y = 250.
func _valley(num_tanks: int = 2) -> MatchState:
	var s: MatchState = WU.shaped_state(num_tanks, func(x: int) -> int: return clampi(820 - absi(x - 800), 250, 820))
	WU.place_tank(s, 0, 100)
	if num_tanks > 1:
		WU.place_tank(s, 1, 1500)
	return s


func _fire_at(s: MatchState, weapon: String, target_x: int, angle: int = 450) -> Array[Dictionary]:
	var p: int = WU.power_for_landing(s, angle, target_x)
	return WU.fire(s, weapon, angle, p)


func test_rolls_down_the_slope_and_stops_in_the_valley() -> void:
	var s: MatchState = _valley()
	var ev: Array[Dictionary] = _fire_at(s, "glide_orb", 500)
	var end: Dictionary = U.find(ev, "projectile_end")[0]
	var plain: Dictionary = WU.plain_trace(_valley(), 450, WU.power_for_landing(_valley(), 450, 500))
	assert_eq(plain["end_reason"], "terrain")
	assert_eq(end["reason"], "terrain")
	assert_eq(end["x"], 800, "the valley bottom")
	assert_eq(end["y"], 819, "one cell above the lowest ground")
	assert_gt(end["y"] as int, plain["end_y"] as int, "ends lower than the impact point")
	var ex: Dictionary = U.find(ev, "explosion")[0]
	assert_eq([ex["x"], ex["y"], ex["radius"]], [800, 819, 30])
	assert_eq(ex["tick"], end["tick"])
	assert_eq(ex["weapon"], "glide_orb")


func test_rolling_positions_are_appended_one_per_tick() -> void:
	var s: MatchState = _valley()
	var ev: Array[Dictionary] = _fire_at(s, "glide_orb", 500)
	var proj: Dictionary = U.find(ev, "projectile")[0]
	var end: Dictionary = U.find(ev, "projectile_end")[0]
	assert_eq(U.find(ev, "projectile").size(), 1, "one projectile for the whole trip")
	var path: PackedInt32Array = proj["path"]
	assert_eq(path.size() / 2, end["tick"], "projectile_end.tick = path length")
	assert_eq(path[path.size() - 2] >> 16, end["x"])
	assert_eq(path[path.size() - 1] >> 16, end["y"])
	var flight: Dictionary = WU.plain_trace(_valley(), 450, WU.power_for_landing(_valley(), 450, 500))
	var flight_ticks: int = flight["ticks"]
	# After the flight and the settling tick the roller moves exactly one cell per tick.
	for i: int in range(flight_ticks + 1, path.size() / 2):
		var dx: int = (path[2 * i] >> 16) - (path[2 * i - 2] >> 16)
		assert_eq(dx, 1, "tick %d moves one cell to the right" % i)
	assert_eq(path.size() / 2 - (flight_ticks + 1), 800 - (flight["end_x"] as int), "rolled from impact column to the valley")


func test_stops_in_a_valley_not_before() -> void:
	var s: MatchState = _valley()
	var ev: Array[Dictionary] = _fire_at(s, "glide_orb", 500)
	var end: Dictionary = U.find(ev, "projectile_end")[0]
	# Both neighbours of the stop column were higher or equal in the terrain before the blast.
	var pre: MatchState = _valley()
	var x: int = end["x"]
	var here: int = pre.terrain.surface_y(x)
	assert_true(pre.terrain.surface_y(x - 1) <= here and pre.terrain.surface_y(x + 1) <= here)


func test_max_roll_ends_the_roll() -> void:
	var s: MatchState = _valley()
	var ev: Array[Dictionary] = _fire_at(s, "glide_orb", 350)
	var end: Dictionary = U.find(ev, "projectile_end")[0]
	var flight: Dictionary = WU.plain_trace(_valley(), 450, WU.power_for_landing(_valley(), 450, 350))
	assert_eq(end["tick"], (flight["ticks"] as int) + 1 + 400, "settle tick + max_roll 400")
	assert_eq(end["x"], (flight["end_x"] as int) + 400)
	assert_lt(end["x"] as int, 800, "still on the slope")
	assert_eq(U.find(ev, "explosion")[0]["x"], end["x"])


func test_heavy_orb_rolls_two_cells_per_tick_with_its_own_blast() -> void:
	var s: MatchState = _valley()
	var ev: Array[Dictionary] = _fire_at(s, "heavy_orb", 500)
	var path: PackedInt32Array = U.find(ev, "projectile")[0]["path"]
	var flight: Dictionary = WU.plain_trace(_valley(), 450, WU.power_for_landing(_valley(), 450, 500))
	var first_roll: int = (flight["ticks"] as int) + 1
	for i: int in range(first_roll + 1, path.size() / 2 - 1):
		assert_eq((path[2 * i] >> 16) - (path[2 * i - 2] >> 16), 2, "tick %d" % i)
	assert_eq(U.find(ev, "projectile_end")[0]["x"], 800)
	var ex: Dictionary = U.find(ev, "explosion")[0]
	assert_eq(ex["radius"], 44)


func test_explodes_on_contact_with_a_tank_box_while_rolling() -> void:
	var s: MatchState = _valley()
	WU.place_tank(s, 1, 700)
	var ev: Array[Dictionary] = _fire_at(s, "glide_orb", 500)
	var end: Dictionary = U.find(ev, "projectile_end")[0]
	assert_eq(end["reason"], "tank")
	assert_eq(end["x"], 688, "touches the left edge of the box")
	assert_true(s.tanks[1].health < 100 or s.tanks[1].y > 720 or not s.tanks[1].alive, "the blast hurt it")
	var dmg: Dictionary = WU.damage_by_tank(ev)
	assert_true(dmg.has(1))
	assert_eq(s.tanks[0].damage_dealt, 100 - s.tanks[1].health)


func test_a_shell_that_hits_a_tank_explodes_there_without_rolling() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[1].x = 800
	var p: int = WU.power_for_landing(s, 450, 800)
	var plain: Dictionary = WU.plain_trace(s, 450, p)
	var ev: Array[Dictionary] = WU.fire(s, "glide_orb", 450, p)
	assert_eq(plain["end_reason"], "tank")
	var end: Dictionary = U.find(ev, "projectile_end")[0]
	assert_eq(end["reason"], plain["end_reason"])
	assert_eq(end["tick"], plain["ticks"], "no rolling ticks were added")
	assert_eq([end["x"], end["y"]], [plain["end_x"], plain["end_y"]])


func test_a_shell_that_hits_a_shield_bubble_ends_there() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[1].x = 800
	s.tanks[1].shield_type = Catalog.index_of("glow_shield")
	s.tanks[1].shield_hp = 30
	var p: int = WU.power_for_landing(s, 450, 800)
	var plain: Dictionary = WU.plain_trace(s, 450, p)
	assert_eq(plain["end_reason"], "shield")
	var ev: Array[Dictionary] = WU.fire(s, "glide_orb", 450, p)
	var end: Dictionary = U.find(ev, "projectile_end")[0]
	assert_eq(end["reason"], "shield")
	assert_eq(end["tick"], plain["ticks"])
	assert_eq(U.find(ev, "explosion")[0]["x"], plain["end_x"])


func test_flat_ground_stops_at_once_one_cell_above_the_surface() -> void:
	var s: MatchState = U.flat_state(2)
	var p: int = WU.power_for_landing(s, 450, 700)
	var flight: Dictionary = WU.plain_trace(U.flat_state(2), 450, p)
	var ev: Array[Dictionary] = WU.fire(s, "glide_orb", 450, p)
	var end: Dictionary = U.find(ev, "projectile_end")[0]
	assert_eq(end["tick"], (flight["ticks"] as int) + 1, "only the settling tick")
	assert_eq(end["x"], flight["end_x"])
	assert_eq(end["y"], U.GROUND_Y - 1)


func test_gentle_slopes_with_level_steps_do_not_stop_the_roller() -> void:
	# Half a cell per column: every second neighbour is level. The roller keeps its direction.
	var s: MatchState = WU.shaped_state(2, func(x: int) -> int: return clampi(820 - absi(x - 800) / 2, 250, 820))
	WU.place_tank(s, 0, 100)
	WU.place_tank(s, 1, 1500)
	var p: int = WU.power_for_landing(s, 450, 500)
	var ev: Array[Dictionary] = WU.fire(s, "glide_orb", 450, p)
	var end: Dictionary = U.find(ev, "projectile_end")[0]
	assert_true(absi((end["x"] as int) - 800) <= 1, "reached the valley, not a terrace: %d" % end["x"])


func test_stops_at_the_map_wall() -> void:
	# Ground falls toward the left wall (y = 700 at x = 0, rising to 100).
	var s: MatchState = WU.shaped_state(2, func(x: int) -> int: return clampi(700 - x, 100, 700))
	WU.place_tank(s, 0, 1000)
	WU.place_tank(s, 1, 1500)
	var p: int = WU.power_for_landing(s, 1350, 300)
	var ev: Array[Dictionary] = WU.fire(s, "glide_orb", 1350, p)
	var end: Dictionary = U.find(ev, "projectile_end")[0]
	assert_eq(end["reason"], "terrain")
	assert_eq(end["x"], 0, "rolled to the wall")
	assert_eq(end["y"], 699)
	assert_eq(U.find(ev, "explosion")[0]["x"], 0)


func test_lost_shell_does_not_roll() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[0].x = 20
	var ev: Array[Dictionary] = WU.fire(s, "glide_orb", 1750, 900)
	assert_eq(U.find(ev, "projectile_end")[0]["reason"], "lost")
	assert_eq(U.find(ev, "explosion").size(), 0)


func test_roll_function_unit() -> void:
	var s: MatchState = _valley()
	var r: Dictionary = RollerBehavior.roll(s, 500, 1, 400, PackedInt32Array())
	assert_true(r["started"])
	assert_eq(r["x"], 800)
	assert_eq(r["ticks"], 1 + 300)
	assert_false(r["contact"])
	var p: PackedInt32Array = r["path"]
	assert_eq(p.size() / 2, 301)
	var short: Dictionary = RollerBehavior.roll(s, 500, 1, 10, PackedInt32Array())
	assert_eq(short["x"], 510)
	assert_eq(short["ticks"], 11)
