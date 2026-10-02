extends GutTest
## Movement and fuel (docs/ARCHITECTURE.md section 20).

const U = preload("res://tests/core/sim_test_util.gd")


func _state() -> MatchState:
	return U.flat_state(2)  # tanks at x = 300 and 1300, ground at y = 600


func _slope(s: MatchState, x0: int, x1: int, base_y: int, per_col: int) -> void:
	for c: int in range(x0, x1 + 1):
		s.terrain.flatten(c, c, base_y + per_col * (c - x0 + 1))


func test_walking_costs_one_fuel_per_cell() -> void:
	var s: MatchState = _state()
	s.tanks[0].fuel = 10
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.move(0, 4))
	assert_eq(s.tanks[0].x, 304)
	assert_eq(s.tanks[0].fuel, 6)
	assert_eq(ev, [{"type": "tank_move", "tick": 0, "tank": 0, "from_x": 300, "to_x": 304, "fuel": 6}] as Array[Dictionary])
	var back: Array[Dictionary] = Simulation.apply_action(s, U.move(0, -3))
	assert_eq(s.tanks[0].x, 301)
	assert_eq(s.tanks[0].fuel, 3)
	assert_eq(back[0]["from_x"], 304)
	assert_eq(back[0]["to_x"], 301)


func test_move_does_not_end_the_turn() -> void:
	var s: MatchState = _state()
	s.tanks[0].fuel = 10
	var wind: int = s.wind
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.move(0, 5))
	assert_eq(s.current_tank, 0)
	assert_eq(s.turn_number, 0)
	assert_eq(s.wind, wind)
	for e: Dictionary in ev:
		assert_false(["turn", "wind", "round_end"].has(e["type"]))
	assert_eq(Simulation.validate_action(s, U.fire(0, 450, 500)), "", "still can fire")
	var ev2: Array[Dictionary] = Simulation.apply_action(s, U.fire(0, 450, 500))
	assert_eq(U.find(ev2, "fire").size(), 1)
	assert_eq(s.current_tank, 1)
	# several moves in one turn
	s.tanks[1].fuel = 20
	Simulation.apply_action(s, U.move(1, -3))
	Simulation.apply_action(s, U.move(1, -3))
	assert_eq(s.current_tank, 1)
	assert_eq(s.tanks[1].x, 1294)


func test_no_fuel_error_and_refusal() -> void:
	var s: MatchState = _state()
	assert_eq(s.tanks[0].fuel, 0)
	assert_eq(Simulation.validate_action(s, U.move(0, 5)), "no_fuel")
	var before: String = Simulation.fingerprint(s)
	assert_eq(Simulation.apply_action(s, U.move(0, 5)).size(), 0)
	assert_eq(Simulation.fingerprint(s), before)
	s.tanks[0].fuel = 1
	assert_eq(Simulation.validate_action(s, U.move(0, 5)), "")
	Simulation.apply_action(s, U.move(0, 5))
	assert_eq(s.tanks[0].x, 301, "ran dry after one cell")
	assert_eq(s.tanks[0].fuel, 0)
	assert_eq(Simulation.validate_action(s, U.move(0, 5)), "no_fuel")


func test_running_out_of_fuel_stops_the_walk() -> void:
	var s: MatchState = _state()
	s.tanks[0].fuel = 3
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.move(0, 50))
	assert_eq(s.tanks[0].x, 303)
	assert_eq(ev[0]["fuel"], 0)


func test_fuel_cell_is_drawn_automatically_when_fuel_hits_zero() -> void:
	var s: MatchState = _state()
	s.tanks[0].fuel = 2
	s.tanks[0].set_stock("fuel_cell", 2)
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.move(0, 10))
	assert_eq(s.tanks[0].x, 310, "walked the whole way")
	assert_eq(s.tanks[0].stock_of("fuel_cell"), 1, "one cell drawn")
	assert_eq(s.tanks[0].fuel, 2 + 100 - 10)
	assert_eq(ev[0]["fuel"], 92)


func test_fuel_cell_allows_a_move_from_zero_fuel_and_stops_when_all_is_used() -> void:
	var s: MatchState = _state()
	s.tanks[0].set_stock("fuel_cell", 1)
	assert_eq(Simulation.validate_action(s, U.move(0, 1)), "", "a cell counts as fuel")
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.move(0, 200))
	assert_eq(s.tanks[0].x, 400, "100 fuel from one cell = 100 cells")
	assert_eq(s.tanks[0].fuel, 0)
	assert_eq(s.tanks[0].stock_of("fuel_cell"), 0)
	assert_eq(ev[0]["to_x"], 400)
	assert_eq(Simulation.validate_action(s, U.move(0, 1)), "no_fuel")


func test_two_cells_chain() -> void:
	var s: MatchState = _state()
	s.tanks[0].set_stock("fuel_cell", 2)
	Simulation.apply_action(s, U.move(0, 200))
	Simulation.apply_action(s, U.move(0, 200))
	Simulation.apply_action(s, U.move(0, 200))
	assert_eq(s.tanks[0].x, 300 + 200)
	assert_eq(s.tanks[0].stock_of("fuel_cell"), 0)
	assert_eq(s.tanks[0].fuel, 0)


func test_cell_is_not_drawn_for_a_blocked_step() -> void:
	var s: MatchState = _state()
	s.tanks[0].x = 12
	s.tanks[0].set_stock("fuel_cell", 1)
	Simulation.apply_action(s, U.move(0, -5))
	assert_eq(s.tanks[0].x, 12)
	assert_eq(s.tanks[0].stock_of("fuel_cell"), 1, "no step, no cell")
	assert_eq(s.tanks[0].fuel, 0)


func test_stops_at_a_climb_of_more_than_three() -> void:
	var s: MatchState = _state()
	s.terrain.flatten(330, 700, 596)  # a 4-cell wall starting at x = 330
	s.tanks[0].fuel = 100
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.move(0, 100))
	# the box [nx-12, nx+12) first touches column 330 at nx = 319
	assert_eq(s.tanks[0].x, 318)
	assert_eq(s.tanks[0].y, 600)
	assert_eq(s.tanks[0].fuel, 100 - 18)
	assert_eq(ev[0]["to_x"], 318)


func test_climbs_of_exactly_three_are_walked() -> void:
	var s: MatchState = _state()
	s.terrain.flatten(330, 700, 597)
	s.tanks[0].fuel = 100
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.move(0, 40))
	assert_eq(s.tanks[0].x, 340)
	assert_eq(s.tanks[0].y, 597, "stepped up onto the 3-cell rise")
	assert_eq(U.find(ev, "tank_fall").size(), 0)


func test_each_step_follows_the_ground() -> void:
	var s: MatchState = _state()
	_slope(s, 320, 399, 600, -1)  # gentle uphill, 1 cell per column
	s.tanks[0].fuel = 200
	Simulation.apply_action(s, U.move(0, 100))
	assert_eq(s.tanks[0].x, 400)
	assert_eq(s.tanks[0].y, TankState.rest_y(s.terrain, 400))
	assert_lt(s.tanks[0].y, 600, "climbed")


func test_stops_at_the_map_edge_with_the_tank_fully_on_map() -> void:
	var s: MatchState = _state()
	s.tanks[0].x = 15
	s.tanks[0].fuel = 50
	Simulation.apply_action(s, U.move(0, -50))
	assert_eq(s.tanks[0].x, 12, "box [0, 24)")
	assert_eq(s.tanks[0].fuel, 47)
	s.tanks[1].x = 1585
	s.tanks[1].fuel = 50
	s.current_tank = 1
	Simulation.apply_action(s, U.move(1, 50))
	assert_eq(s.tanks[1].x, 1588, "box [1576, 1600)")
	# at the edge: nothing happens and nothing is spent
	var fuel: int = s.tanks[1].fuel
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.move(1, 10))
	assert_eq(s.tanks[1].x, 1588)
	assert_eq(s.tanks[1].fuel, fuel)
	assert_eq(ev[0]["from_x"], ev[0]["to_x"])


func test_stops_next_to_another_tank() -> void:
	var s: MatchState = _state()
	s.tanks[1].x = 340  # box [328, 352)
	s.tanks[0].fuel = 100
	Simulation.apply_action(s, U.move(0, 100))
	assert_eq(s.tanks[0].x, 316, "boxes touch at 328 but never overlap")
	assert_eq(s.tanks[1].x - s.tanks[0].x, 24)
	# moving away is fine
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.move(0, -5))
	assert_eq(s.tanks[0].x, 311)
	assert_eq(ev[0]["fuel"], 100 - 16 - 5)


func test_dead_tanks_do_not_block() -> void:
	var s: MatchState = _state()
	s.tanks[1].x = 340
	s.tanks[1].alive = false
	s.tanks[1].health = 0
	s.tanks[0].fuel = 100
	Simulation.apply_action(s, U.move(0, 60))
	assert_eq(s.tanks[0].x, 360)


func test_move_validation() -> void:
	var s: MatchState = _state()
	s.tanks[0].fuel = 500
	assert_eq(Simulation.validate_action(s, U.move(0, 200)), "")
	assert_eq(Simulation.validate_action(s, U.move(0, -200)), "")
	assert_eq(Simulation.validate_action(s, U.move(0, 201)), "bad_field")
	assert_eq(Simulation.validate_action(s, U.move(0, -201)), "bad_field")
	assert_eq(Simulation.validate_action(s, U.move(0, 0)), "bad_field")
	assert_eq(Simulation.validate_action(s, {"kind": "move", "tank": 0}), "bad_field")
	assert_eq(Simulation.validate_action(s, {"kind": "move", "tank": 0, "dx": 5.0}), "bad_field")
	assert_eq(Simulation.validate_action(s, {"kind": "move", "tank": 0, "dx": "5"}), "bad_field")
	assert_eq(Simulation.validate_action(s, U.move(1, 5)), "not_your_turn")
	assert_eq(Simulation.validate_action(s, U.move(4, 5)), "bad_tank")
	s.tanks[0].alive = false
	assert_eq(Simulation.validate_action(s, U.move(0, 5)), "tank_dead")


func test_move_leaves_the_terrain_alone_and_keeps_the_aim() -> void:
	var s: MatchState = _state()
	s.tanks[0].fuel = 30
	s.tanks[0].angle = 777
	s.tanks[0].power = 321
	var cells: PackedByteArray = s.terrain.cells.duplicate()
	Simulation.apply_action(s, U.move(0, 20))
	assert_true(s.terrain.cells == cells)
	assert_eq(s.tanks[0].angle, 777)
	assert_eq(s.tanks[0].power, 321)


# --- falling off ledges ---------------------------------------------------------------

func _ledge(s: MatchState, drop: int) -> void:
	s.terrain.flatten(330, 1599, 600 + drop)


func test_walking_off_a_ledge_causes_fall_damage() -> void:
	var s: MatchState = _state()
	_ledge(s, 40)
	s.tanks[0].fuel = 100
	s.tanks[0].money = 1000
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.move(0, 60))
	assert_eq(s.tanks[0].x, 360)
	assert_eq(s.tanks[0].y, 640)
	assert_eq(U.types(ev), ["tank_move", "tank_fall", "damage"] as Array[String])
	assert_eq(ev[1], {"type": "tank_fall", "tick": 0, "tank": 0, "from_y": 600, "to_y": 640})
	assert_eq(ev[2]["amount"], (40 - SimConstants.FALL_SAFE) / SimConstants.FALL_DMG_DIV)
	assert_eq(ev[2]["cause"], "fall")
	assert_eq(s.tanks[0].health, 100 - 14)
	assert_eq(s.tanks[0].money, 1000, "a fall caused by walking is nobody's shot: no penalty")
	assert_eq(s.current_tank, 0, "still the same turn")


func test_small_drops_are_free() -> void:
	var s: MatchState = _state()
	_ledge(s, 10)
	s.tanks[0].fuel = 100
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.move(0, 60))
	assert_eq(s.tanks[0].y, 610)
	assert_eq(U.types(ev), ["tank_move", "tank_fall"] as Array[String], "10 <= FALL_SAFE: no damage")
	assert_eq(s.tanks[0].health, 100)


func test_drops_of_three_or_less_per_step_are_just_walking() -> void:
	var s: MatchState = _state()
	_ledge(s, 3)
	s.tanks[0].fuel = 100
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.move(0, 60))
	assert_eq(s.tanks[0].y, 603)
	assert_eq(U.types(ev), ["tank_move"] as Array[String], "no tank_fall for a 3 cell step down")
	var s2: MatchState = _state()
	_ledge(s2, 4)
	s2.tanks[0].fuel = 100
	var ev2: Array[Dictionary] = Simulation.apply_action(s2, U.move(0, 60))
	assert_eq(U.types(ev2), ["tank_move", "tank_fall"] as Array[String], "a 4 cell step is a fall")


func test_drift_chute_negates_walking_fall_damage() -> void:
	var s: MatchState = _state()
	_ledge(s, 40)
	s.tanks[0].fuel = 100
	s.tanks[0].set_stock("drift_chute", 2)
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.move(0, 60))
	assert_eq(U.types(ev), ["tank_move", "tank_fall", "chute"] as Array[String])
	assert_eq(ev[2], {"type": "chute", "tick": 0, "tank": 0})
	assert_eq(s.tanks[0].health, 100)
	assert_eq(s.tanks[0].stock_of("drift_chute"), 1, "one chute consumed")


func test_a_steep_slope_is_one_accumulated_fall() -> void:
	var s: MatchState = _state()
	_slope(s, 330, 1500, 600, 5)  # every column 5 lower than its left neighbour
	s.tanks[0].fuel = 100
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.move(0, 60))
	var falls: Array[Dictionary] = U.find(ev, "tank_fall")
	assert_eq(falls.size(), 1, "consecutive steep steps accumulate into one fall")
	assert_eq(falls[0]["from_y"], 600)
	assert_eq(falls[0]["to_y"], s.tanks[0].y)
	var total: int = s.tanks[0].y - 600
	assert_gt(total, 12)
	assert_eq(U.find(ev, "damage")[0]["amount"], (total - 12) / 2)


func test_chute_is_per_fall_not_per_step() -> void:
	var s: MatchState = _state()
	_slope(s, 330, 1500, 600, 5)
	s.tanks[0].fuel = 100
	s.tanks[0].set_stock("drift_chute", 5)
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.move(0, 60))
	assert_eq(U.find(ev, "chute").size(), 1)
	assert_eq(s.tanks[0].stock_of("drift_chute"), 4)
	assert_eq(s.tanks[0].health, 100)


func test_fall_damage_ignores_shields_when_walking() -> void:
	var s: MatchState = _state()
	_ledge(s, 40)
	s.tanks[0].fuel = 100
	s.tanks[0].shield_type = Catalog.index_of("ion_shield")
	s.tanks[0].shield_hp = 60
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.move(0, 60))
	assert_eq(s.tanks[0].shield_hp, 60, "shield untouched")
	assert_eq(s.tanks[0].health, 86)
	assert_eq(U.find(ev, "shield_hit").size(), 0)


func test_walking_to_death_ends_the_turn() -> void:
	var s: MatchState = U.flat_state(3)
	_ledge(s, 40)
	s.tanks[0].fuel = 100
	s.tanks[0].health = 10
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.move(0, 60))
	assert_false(s.tanks[0].alive)
	assert_eq(U.types(ev), ["tank_move", "tank_fall", "damage", "tank_destroyed", "wind", "turn"] as Array[String])
	assert_eq(s.current_tank, 1)


func test_walking_to_death_with_one_enemy_left_ends_the_round() -> void:
	var s: MatchState = _state()
	_ledge(s, 40)
	s.tanks[0].fuel = 100
	s.tanks[0].health = 10
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.move(0, 60))
	var types: Array[String] = U.types(ev)
	assert_true(types.has("round_end"))
	assert_eq(U.find(ev, "round_end")[0]["winner"], 1)
	assert_eq(s.phase, "shop")
	assert_eq(s.tanks[1].round_wins, 1)


func test_move_events_are_deterministic() -> void:
	var a: MatchState = _state()
	var b: MatchState = _state()
	for s: MatchState in [a, b]:
		_ledge(s, 25)
		s.tanks[0].fuel = 60
	var ea: Array[Dictionary] = Simulation.apply_action(a, U.move(0, 50))
	var eb: Array[Dictionary] = Simulation.apply_action(b, U.move(0, 50))
	assert_eq(ea, eb)
	assert_eq(Simulation.fingerprint(a), Simulation.fingerprint(b))
