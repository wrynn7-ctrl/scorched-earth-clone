extends GutTest
## Settle helper (shared fall / chute logic) and gravity-well expiry at turn change.

const U = preload("res://tests/core/sim_test_util.gd")


func test_apply_fall_up_to_safe_height_is_free_and_keeps_the_chute() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[0].set_stock("drift_chute", 1)
	var ev: Array[Dictionary] = []
	Settle.apply_fall(s, 0, 600, 612, 1, 3, ev)
	assert_eq(ev, [{"type": "tank_fall", "tick": 3, "tank": 0, "from_y": 600, "to_y": 612}] as Array[Dictionary])
	assert_eq(s.tanks[0].stock_of("drift_chute"), 1, "a fall of exactly FALL_SAFE does not use the chute")
	assert_eq(s.tanks[0].health, 100)


func test_apply_fall_damage_formula() -> void:
	var s: MatchState = U.flat_state(2)
	var ev: Array[Dictionary] = []
	Settle.apply_fall(s, 0, 600, 626, -1, 0, ev)
	assert_eq(U.types(ev), ["tank_fall", "damage"] as Array[String])
	assert_eq(ev[1]["amount"], 7, "(26 - 12) / 2")
	assert_eq(ev[1]["cause"], "fall")
	assert_eq(s.tanks[0].health, 93)


func test_fall_of_thirteen_gives_no_damage_and_does_not_emit_damage() -> void:
	var s: MatchState = U.flat_state(2)
	var ev: Array[Dictionary] = []
	Settle.apply_fall(s, 0, 600, 613, -1, 0, ev)
	assert_eq(U.types(ev), ["tank_fall"] as Array[String], "(13 - 12) / 2 = 0")


func test_a_chute_is_used_for_any_fall_above_the_safe_height() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[0].set_stock("drift_chute", 2)
	var ev: Array[Dictionary] = []
	Settle.apply_fall(s, 0, 600, 613, -1, 4, ev)
	assert_eq(U.types(ev), ["tank_fall", "chute"] as Array[String], "chute sits between tank_fall and the damage")
	assert_eq(ev[1], {"type": "chute", "tick": 4, "tank": 0})
	assert_eq(s.tanks[0].stock_of("drift_chute"), 1)
	Settle.apply_fall(s, 0, 600, 700, -1, 4, ev)
	assert_eq(s.tanks[0].stock_of("drift_chute"), 0)
	assert_eq(s.tanks[0].health, 100)
	Settle.apply_fall(s, 0, 600, 700, -1, 4, ev)
	assert_eq(s.tanks[0].health, 100 - 44, "no chute left: (100 - 12) / 2")


func test_fall_damage_credit_goes_to_the_attacker() -> void:
	var s: MatchState = U.flat_state(2)
	var ev: Array[Dictionary] = []
	Settle.apply_fall(s, 0, 600, 640, 0, 0, ev)  # tank 0 falls, attributed to itself
	assert_eq(s.tanks[0].money, 0, "self penalty on 0 money stays 0")
	Settle.apply_fall(s, 1, 600, 640, 0, 0, ev)
	assert_eq(s.tanks[0].money, 14 * 15)


func test_settle_region_emits_settle_then_drops_overlapping_tanks() -> void:
	var s: MatchState = U.flat_state(3)
	s.terrain.carve_circle(s.tanks[1].x, 600, 30)
	var ev: Array[Dictionary] = []
	Settle.settle_region(s, s.tanks[1].x - 40, s.tanks[1].x + 40, 0, 9, ev)
	assert_eq(ev[0]["type"], "terrain_settle")
	assert_eq(ev[0]["tick"], 9)
	assert_eq(ev[1]["type"], "tank_fall")
	assert_eq(ev[1]["tank"], 1)
	assert_eq(s.tanks[1].y, TankState.rest_y(s.terrain, s.tanks[1].x))
	assert_eq(s.tanks[0].y, 600, "tank 0 is far away")
	for e: Dictionary in ev:
		if e["type"] == "tank_fall" or e["type"] == "damage":
			assert_ne(e["tank"], 0)


func test_settle_region_ignores_dead_tanks_and_tanks_outside_the_range() -> void:
	var s: MatchState = U.flat_state(2)
	s.terrain.carve_circle(s.tanks[1].x, 600, 30)
	s.tanks[1].alive = false
	s.tanks[1].health = 0
	var y: int = s.tanks[1].y
	var ev: Array[Dictionary] = []
	Settle.settle_region(s, s.tanks[1].x - 40, s.tanks[1].x + 40, 0, 0, ev)
	assert_eq(s.tanks[1].y, y, "dead tanks do not fall")
	assert_eq(U.types(ev), ["terrain_settle"] as Array[String])
	s.tanks[1].alive = true
	s.tanks[1].health = 100
	var ev2: Array[Dictionary] = []
	Settle.drop_tanks(s, 0, 100, 0, 0, ev2)
	assert_eq(ev2.size(), 0, "range does not reach the tank")
	assert_eq(s.tanks[1].y, y)


func test_drop_tanks_requires_actual_drop() -> void:
	var s: MatchState = U.flat_state(2)
	var ev: Array[Dictionary] = []
	Settle.drop_tanks(s, 0, 1599, 0, 0, ev)
	assert_eq(ev.size(), 0, "tanks already resting do nothing")


# --- wells (state field maintained by the core, filled by M3-C2 behaviours) ------------------

func test_wells_expire_at_turn_change_in_owner_order() -> void:
	var s: MatchState = U.flat_state(3)
	s.wells.append({"owner": 0, "x": 10, "y": 20, "expires_turn": 2})
	s.wells.append({"owner": 1, "x": 11, "y": 21, "expires_turn": 4})
	s.wells.append({"owner": 2, "x": 12, "y": 22, "expires_turn": 2})
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.pass_turn(0))  # turn_number -> 1
	assert_eq(s.wells.size(), 3)
	assert_eq(U.find(ev, "well_off").size(), 0)
	ev = Simulation.apply_action(s, U.pass_turn(1))  # turn_number -> 2: owners 0 and 2 expire
	var off: Array[Dictionary] = U.find(ev, "well_off")
	assert_eq(off.size(), 2)
	assert_eq([off[0]["owner"], off[1]["owner"]], [0, 2])
	assert_eq(s.wells.size(), 1)
	assert_eq(s.wells[0]["owner"], 1)
	var types: Array[String] = U.types(ev)
	assert_eq(types.slice(types.size() - 2), ["wind", "turn"] as Array[String])
	Simulation.apply_action(s, U.pass_turn(2))
	ev = Simulation.apply_action(s, U.pass_turn(0))  # turn_number -> 4
	assert_eq(s.wells.size(), 0)
	assert_eq(U.find(ev, "well_off")[0]["owner"], 1)


func test_wells_are_hashed_and_duplicated_deeply() -> void:
	var s: MatchState = U.flat_state(2)
	s.wells.append({"owner": 0, "x": 10, "y": 20, "expires_turn": 7})
	var copy: MatchState = s.duplicate_state()
	copy.wells[0]["x"] = 99
	assert_eq(s.wells[0]["x"], 10, "deep copy")
	assert_ne(Simulation.fingerprint(copy), Simulation.fingerprint(s))
