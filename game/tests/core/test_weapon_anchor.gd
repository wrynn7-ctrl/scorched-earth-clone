@warning_ignore_start("integer_division")
extends GutTest
## Riptide Anchor (docs/ARCHITECTURE.md section 21).

const U = preload("res://tests/core/sim_test_util.gd")
const WU = preload("res://tests/core/weapon_test_util.gd")


## Flat ground, shooter (tank 0) at x = 100, tank 1 and 2 where the test puts them.
func _state(x1: int, x2: int = 1550) -> MatchState:
	var s: MatchState = U.flat_state(3)
	s.tanks[0].x = 100
	s.tanks[1].x = x1
	s.tanks[2].x = x2
	return s


## Fires the anchor so it lands on column `impact_x`.
func _fire_at(s: MatchState, impact_x: int, angle: int = 450) -> Array[Dictionary]:
	var p: int = WU.power_for_landing(s, angle, impact_x)
	return WU.fire(s, "riptide_anchor", angle, p)


func _drag_of(ev: Array[Dictionary], tank: int) -> Dictionary:
	for e: Dictionary in U.find(ev, "tank_drag"):
		if e["tank"] == tank:
			return e
	return {}


func test_pulls_toward_the_impact_but_not_past_it() -> void:
	var s: MatchState = _state(870)
	var ev: Array[Dictionary] = _fire_at(s, 800)
	var end: Dictionary = U.find(ev, "projectile_end")[0]
	assert_eq(end["reason"], "terrain")
	var impact: int = end["x"]
	var d: Dictionary = _drag_of(ev, 1)
	assert_eq([d["from_x"], d["to_x"]], [870, impact], "ends exactly on the impact column")
	assert_eq(s.tanks[1].x, impact)
	assert_eq(d["tick"], end["tick"])
	assert_eq(s.tanks[1].y, TankState.rest_y(s.terrain, impact))
	assert_eq(U.find(ev, "tank_fall").size(), 0)
	assert_eq(_drag_of(ev, 2), {}, "tank 2 is far away")
	assert_eq(_drag_of(ev, 0), {}, "so is the shooter")


func test_pull_is_limited_to_120_cells() -> void:
	var s: MatchState = _state(940)
	var ev: Array[Dictionary] = _fire_at(s, 800)
	var impact: int = U.find(ev, "projectile_end")[0]["x"]
	var d: Dictionary = _drag_of(ev, 1)
	assert_eq(d["from_x"], 940)
	assert_eq(d["to_x"], 940 - 120)
	assert_gt(d["to_x"] as int, impact)


func test_tanks_beyond_the_pull_radius_stay_put() -> void:
	var s: MatchState = _state(1000)  # 200 cells from the impact
	var ev: Array[Dictionary] = _fire_at(s, 800)
	assert_eq(U.find(ev, "tank_drag").size(), 0)
	assert_eq(s.tanks[1].x, 1000)
	var near: MatchState = _state(970)  # 170 away
	var ev2: Array[Dictionary] = _fire_at(near, 800)
	assert_eq(_drag_of(ev2, 1)["to_x"], 970 - 120)


func test_tanks_on_both_sides_are_pulled_in() -> void:
	var s: MatchState = _state(900, 1400)
	s.tanks[2].x = 700  # left of the impact
	var ev: Array[Dictionary] = _fire_at(s, 800)
	var impact: int = U.find(ev, "projectile_end")[0]["x"]
	assert_eq(_drag_of(ev, 1)["to_x"], impact, "tank 1 moves first and gets there")
	assert_eq(_drag_of(ev, 2)["to_x"], impact - 24, "tank 2 is pulled right until tank 1 blocks it")
	var order: Array[int] = []
	for e: Dictionary in U.find(ev, "tank_drag"):
		order.append(e["tank"])
	assert_eq(order, [1, 2] as Array[int], "id order")


func test_the_shooter_is_pulled_too() -> void:
	var s: MatchState = U.flat_state(2)
	var p: int = WU.power_for_landing(s, 450, 420)
	var ev: Array[Dictionary] = WU.fire(s, "riptide_anchor", 450, p)
	var impact: int = U.find(ev, "projectile_end")[0]["x"]
	var d: Dictionary = _drag_of(ev, 0)
	assert_eq([d["from_x"], d["to_x"]], [300, impact])
	assert_eq(s.tanks[0].x, impact)


func test_fortress_field_halves_the_pull() -> void:
	var s: MatchState = _state(940)
	s.tanks[1].shield_type = Catalog.index_of("fortress_field")
	s.tanks[1].shield_hp = 100
	var ev: Array[Dictionary] = _fire_at(s, 800)
	assert_eq(_drag_of(ev, 1)["to_x"], 940 - 60)
	var other: MatchState = _state(940)
	other.tanks[1].shield_type = Catalog.index_of("glow_shield")
	other.tanks[1].shield_hp = 30
	var ev2: Array[Dictionary] = _fire_at(other, 800)
	assert_eq(_drag_of(ev2, 1)["to_x"], 940 - 120, "other shields do not resist")


func test_a_tank_blocked_by_another_stops_next_to_it() -> void:
	var s: MatchState = _state(900, 860)
	var ev: Array[Dictionary] = _fire_at(s, 800)
	var impact: int = U.find(ev, "projectile_end")[0]["x"]
	assert_eq(_drag_of(ev, 1)["to_x"], 860 + 24, "stops where the boxes touch")
	assert_eq(_drag_of(ev, 2)["to_x"], impact, "tank 2 then moves in")


func test_a_tank_dragged_off_a_ledge_takes_fall_damage_and_the_shooter_is_credited() -> void:
	var s: MatchState = _pit_state()
	var ev: Array[Dictionary] = _fire_at_pit(s)
	var d: Dictionary = _drag_of(ev, 1)
	assert_eq(d["from_x"], 800)
	assert_eq(d["to_x"], 680, "120 cells: the box is entirely over the pit")
	var fall: Dictionary = U.find(ev, "tank_fall")[0]
	assert_eq([fall["tank"], fall["from_y"], fall["to_y"]], [1, 600, 640])
	var dmg: Dictionary = U.find(ev, "damage")[0]
	assert_eq([dmg["tank"], dmg["amount"], dmg["cause"]], [1, 14, "fall"], "(40 - 12) / 2")
	assert_eq(s.tanks[1].health, 86)
	assert_eq(s.tanks[1].y, 640)
	assert_eq(s.tanks[0].money, 15 * 14, "fall damage caused by the anchor pays the shooter")
	assert_eq(s.tanks[0].damage_dealt, 14)
	var types: Array[String] = U.types(ev)
	assert_true(types.find("tank_drag") < types.find("tank_fall"))
	assert_true(types.find("tank_fall") < types.find("damage"))


func test_a_drift_chute_negates_the_drag_fall() -> void:
	var s: MatchState = _pit_state()
	s.tanks[1].set_stock("drift_chute", 1)
	var ev: Array[Dictionary] = _fire_at_pit(s)
	var types: Array[String] = U.types(ev)
	assert_eq(types.count("chute"), 1)
	assert_true(types.find("tank_fall") < types.find("chute"))
	assert_eq(U.find(ev, "damage").size(), 0)
	assert_eq(s.tanks[1].health, 100)
	assert_eq(s.tanks[1].stock_of("drift_chute"), 0, "consumed")
	assert_eq(s.tanks[0].money, 0)


func test_a_fall_that_kills_is_credited_with_the_kill() -> void:
	var s: MatchState = _pit_state()
	s.tanks[1].health = 10
	var ev: Array[Dictionary] = _fire_at_pit(s)
	assert_false(s.tanks[1].alive)
	assert_eq(U.find(ev, "tank_destroyed").size(), 1)
	assert_eq(s.tanks[0].kills, 1)
	assert_eq(s.tanks[0].money, 15 * 10 + 1500)


func test_climbing_up_to_six_cells_per_step_is_allowed_more_stops_the_drag() -> void:
	# A wall to the right of tank 1's start: ground rises by 5 (passable) or 8 (blocks).
	for rise: Array in [[5, true], [8, false]]:
		var s: MatchState = U.flat_state(3)
		s.tanks[0].x = 100
		s.tanks[1].x = 700
		s.tanks[2].x = 1550
		for x: int in range(760, 1000):
			s.terrain.flatten(x, x, U.GROUND_Y - (rise[0] as int))
		var p: int = WU.power_for_landing(s, 450, 800)
		var ev: Array[Dictionary] = WU.fire(s, "riptide_anchor", 450, p)
		var impact: int = U.find(ev, "projectile_end")[0]["x"]
		if rise[1]:
			assert_eq(s.tanks[1].x, impact, "rise %d: climbs the wall" % rise[0])
			assert_eq(s.tanks[1].y, U.GROUND_Y - 5)
		else:
			assert_eq(s.tanks[1].x, 748, "rise %d: stops where the box meets the wall" % rise[0])
			assert_eq(s.tanks[1].y, U.GROUND_Y)


func test_dead_tanks_are_not_dragged() -> void:
	var s: MatchState = _state(870)
	s.tanks[1].alive = false
	var ev: Array[Dictionary] = _fire_at(s, 800)
	assert_eq(U.find(ev, "tank_drag").size(), 0)
	assert_eq(s.tanks[1].x, 870)


func test_a_lost_shell_drags_nobody() -> void:
	var s: MatchState = _state(300)
	s.tanks[0].x = 20
	var ev: Array[Dictionary] = WU.fire(s, "riptide_anchor", 1750, 900)
	assert_eq(U.find(ev, "tank_drag").size(), 0)


func test_the_map_edge_stops_the_drag() -> void:
	var s: MatchState = U.flat_state(3)
	s.tanks[0].x = 700
	s.tanks[1].x = 40
	s.tanks[2].x = 1550
	# The impact is 120+ cells to the right of tank 1: it walks right, never off the map.
	var p: int = WU.power_for_landing(s, 1350, 20)  # lands left of tank 1
	var ev: Array[Dictionary] = WU.fire(s, "riptide_anchor", 1350, p)
	assert_true(s.tanks[1].x >= 12, "box stays on the map")


func test_the_anchor_does_not_touch_the_terrain_and_is_deterministic() -> void:
	var a: MatchState = _state(870)
	var b: MatchState = _state(870)
	var before: PackedByteArray = a.terrain.cells.duplicate()
	var ea: Array[Dictionary] = _fire_at(a, 800)
	var eb: Array[Dictionary] = _fire_at(b, 800)
	assert_eq(a.terrain.cells, before)
	assert_eq(WU.events_digest(ea), WU.events_digest(eb))
	assert_eq(Simulation.fingerprint(a), Simulation.fingerprint(b))
	assert_eq(U.types(ea), ["fire", "projectile", "projectile_end", "tank_drag", "wind", "turn"] as Array[String])


## A 50 wide, 40 deep pit at x 650..699; tank 1 stands on the flat at x = 800.
func _pit_state() -> MatchState:
	var s: MatchState = U.flat_state(3)
	s.tanks[0].x = 100
	s.tanks[1].x = 800
	s.tanks[2].x = 1550
	for x: int in range(650, 700):
		s.terrain.flatten(x, x, U.GROUND_Y + 40)
	return s


func _fire_at_pit(s: MatchState) -> Array[Dictionary]:
	var p: int = WU.power_for_landing(s, 800, 675)
	var plain: Dictionary = WU.plain_trace(s, 800, p)
	assert_eq(plain["end_reason"], "terrain")
	assert_true((plain["end_x"] as int) >= 664 and (plain["end_x"] as int) <= 686, "lands in the pit: %d" % plain["end_x"])
	return WU.fire(s, "riptide_anchor", 800, p)
