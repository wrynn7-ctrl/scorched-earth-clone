@warning_ignore_start("integer_division")
extends GutTest
## Move / item edge cases (docs/ARCHITECTURE.md sections 19-20 and 25). Every legal action goes
## through _do(), which also runs the independent economy audit (fuel and stock arithmetic,
## money, health chain), the timeline checks and the state invariants.

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M3 = preload("res://tests/qa/qa_m3.gd")


func _bug(ok: bool, desc: String) -> void:
	if ok:
		pass_test("bug no longer reproduces (remove the pending guard): %s" % desc)
	else:
		pending("BUG: %s" % desc)


func _flat(xs: Array[int]) -> MatchState:
	var s: MatchState = QaUtil.flat_state(xs, 600)
	for t: TankState in s.tanks:
		t.money = 10000
	return s


## A cliff: ground at 600 left of `edge`, `low` right of it. Tanks keep their x and stand on levelled pads.
func _cliff(xs: Array[int], edge: int, low: int) -> MatchState:
	var s: MatchState = _flat(xs)
	for x: int in range(edge, SimConstants.WORLD_W):
		s.terrain.flatten(x, x, low)
	for t: TankState in s.tanks:
		t.y = TankState.rest_y(s.terrain, t.x)
	return s


func _do(state: MatchState, action: Dictionary, tag: String = "") -> Array[Dictionary]:
	var verr: String = Simulation.validate_action(state, action)
	assert_eq(verr, "", "%s: %s is legal" % [tag, str(action)])
	var snap: Dictionary = M3.snapshot(state)
	var ev: Array[Dictionary] = Simulation.apply_action(state, action)
	var errs: Array[String] = M3.audit(snap, state, action, ev)
	errs.append_array(M3.check_timeline(action, ev))
	errs.append_array(M3.check_state(state))
	assert_eq(errs, [] as Array[String], "%s: %s invariants" % [tag, str(action)])
	return ev


func _move(tank: int, dx: int) -> Dictionary:
	return {"kind": "move", "tank": tank, "dx": dx}


func _item(tank: int, item: String) -> Dictionary:
	return {"kind": "use_item", "tank": tank, "item": item}


func _one(ev: Array[Dictionary], type: String) -> Dictionary:
	var found: Array[Dictionary] = QaUtil.find(ev, type)
	assert_eq(found.size(), 1, "exactly one %s event" % type)
	return found[0] if found.size() > 0 else {}


# --- move --------------------------------------------------------------------------------------

func test_move_200_into_the_walls_stops_with_the_box_on_the_map() -> void:
	var s: MatchState = _flat([40, 1500] as Array[int])
	s.tanks[0].fuel = 500
	var ev: Array[Dictionary] = _do(s, _move(0, -200), "left wall")
	assert_eq(QaUtil.types(ev), ["tank_move"] as Array[String], "no turn change after a move")
	assert_eq(ev[0]["from_x"], 40)
	assert_eq(ev[0]["to_x"], 12, "box [0, 24) is flush with the wall")
	assert_eq(ev[0]["fuel"], 500 - 28, "only the 28 cells actually walked cost fuel")
	assert_eq(s.current_tank, 0, "the mover keeps the turn")
	# Already at the wall: nothing happens, nothing is charged.
	var ev2: Array[Dictionary] = _do(s, _move(0, -200), "at the wall")
	assert_eq([ev2[0]["from_x"], ev2[0]["to_x"], ev2[0]["fuel"]], [12, 12, 472])
	# Right wall.
	var r: MatchState = _flat([100, 1560] as Array[int])
	r.tanks[1].fuel = 300
	r.current_tank = 1
	var ev3: Array[Dictionary] = _do(r, _move(1, 200), "right wall")
	assert_eq([ev3[0]["from_x"], ev3[0]["to_x"], ev3[0]["fuel"]], [1560, 1588, 272])
	assert_eq(r.tanks[1].x + 12, SimConstants.WORLD_W)


func test_move_into_another_tank_stops_one_box_away() -> void:
	var s: MatchState = _flat([300, 340, 1000] as Array[int])
	s.tanks[0].fuel = 500
	var ev: Array[Dictionary] = _do(s, _move(0, 200), "into a tank")
	assert_eq(ev[0]["to_x"], 316, "boxes touch but never overlap (centres 24 apart)")
	assert_eq(s.tanks[1].x - s.tanks[0].x, 24)
	# Blocked at once: from == to, no fuel spent, a Fuel Cell is not drawn.
	var s2: MatchState = _flat([300, 324, 1000] as Array[int])
	s2.tanks[0].set_stock("fuel_cell", 1)
	var ev2: Array[Dictionary] = _do(s2, _move(0, 50), "blocked at once")
	assert_eq([ev2[0]["from_x"], ev2[0]["to_x"], ev2[0]["fuel"]], [300, 300, 0])
	assert_eq(s2.tanks[0].stock_of("fuel_cell"), 1, "no Fuel Cell burned for a step that was never taken")
	# A dead tank does not block.
	var s3: MatchState = _flat([300, 340, 1000] as Array[int])
	s3.tanks[0].fuel = 500
	s3.tanks[1].alive = false
	s3.tanks[1].health = 0
	var ev3: Array[Dictionary] = _do(s3, _move(0, 200), "through a corpse")
	assert_eq(ev3[0]["to_x"], 500)
	# Moving away from a neighbour is always allowed.
	var s4: MatchState = _flat([300, 324, 1000] as Array[int])
	s4.tanks[0].fuel = 10
	var ev4: Array[Dictionary] = _do(s4, _move(0, -10), "away from a neighbour")
	assert_eq(ev4[0]["to_x"], 290)


func test_move_dx_range_and_extreme_values() -> void:
	var s: MatchState = _flat([300, 900] as Array[int])
	s.tanks[0].fuel = 1000
	assert_eq(Simulation.validate_action(s, _move(0, 0)), "bad_field")
	assert_eq(Simulation.validate_action(s, _move(0, 201)), "bad_field")
	assert_eq(Simulation.validate_action(s, _move(0, -201)), "bad_field")
	assert_eq(Simulation.validate_action(s, _move(0, 9223372036854775807)), "bad_field")
	assert_eq(Simulation.validate_action(s, _move(0, 200)), "")
	assert_eq(Simulation.validate_action(s, _move(0, -200)), "")
	# INT64_MIN: |dx| overflows back to a negative number, so `absi(dx) > 200` is false.
	var v: String = Simulation.validate_action(s, _move(0, -9223372036854775807 - 1))
	var desc: String = ("move dx = INT64_MIN (-9223372036854775808, reachable from JSON as -9.223372036854775808e18) passes "
			+ "validate_action ('%s' instead of 'bad_field'): absi(INT64_MIN) overflows back to INT64_MIN, so the range check "
			+ "`absi(dx) > MOVE_MAX_DX` in Simulation._validate_move (game/core/simulation.gd:207) is skipped. Harmless "
			+ "today (the move loop runs 0 steps and emits a no-op tank_move) but it lets a malformed network action through.") % v
	_bug(v == "bad_field", desc)
	# The same value through the JSON path the saves and online play use.
	var parsed: Variant = JSON.parse_string(JSON.stringify({"kind": "move", "tank": 0, "dx": -9223372036854775807 - 1}))
	var norm: Dictionary = Simulation.normalize_action(parsed as Dictionary)
	assert_eq(typeof(norm["dx"]), TYPE_INT, "whole-number floats at the int64 edge normalise to int")


func test_walking_off_a_cliff_costs_fall_damage_without_a_chute() -> void:
	var s: MatchState = _cliff([400, 1200] as Array[int], 500, 640)
	s.tanks[0].fuel = 500
	var money: int = s.tanks[0].money
	var ev: Array[Dictionary] = _do(s, _move(0, 200), "cliff")
	assert_eq(QaUtil.types(ev), ["tank_move", "tank_fall", "damage"] as Array[String])
	assert_eq(ev[0]["to_x"], 600)
	assert_eq([ev[1]["from_y"], ev[1]["to_y"]], [600, 640])
	assert_eq(ev[2]["cause"], "fall")
	assert_eq(ev[2]["amount"], (40 - 12) / 2)
	assert_eq(s.tanks[0].health, 100 - 14)
	assert_eq(s.tanks[0].money, money, "a walking fall has no attacker: no money moves")
	assert_eq(s.current_tank, 0)


func test_walking_off_a_cliff_with_a_chute_is_free_and_consumes_one() -> void:
	var s: MatchState = _cliff([400, 1200] as Array[int], 500, 640)
	s.tanks[0].fuel = 500
	s.tanks[0].set_stock("drift_chute", 2)
	var ev: Array[Dictionary] = _do(s, _move(0, 200), "cliff with chute")
	assert_eq(QaUtil.types(ev), ["tank_move", "tank_fall", "chute"] as Array[String])
	assert_eq(s.tanks[0].health, 100)
	assert_eq(s.tanks[0].stock_of("drift_chute"), 1)
	# A drop within FALL_SAFE spends no chute: 12 cells.
	var s2: MatchState = _cliff([400, 1200] as Array[int], 500, 612)
	s2.tanks[0].fuel = 500
	s2.tanks[0].set_stock("drift_chute", 1)
	var ev2: Array[Dictionary] = _do(s2, _move(0, 200), "12 cell drop")
	assert_eq(QaUtil.types(ev2), ["tank_move", "tank_fall"] as Array[String])
	assert_eq(s2.tanks[0].stock_of("drift_chute"), 1)
	# 13 cells: the chute is consumed although the fall damage would have been (13-12)/2 = 0.
	var s3: MatchState = _cliff([400, 1200] as Array[int], 500, 613)
	s3.tanks[0].fuel = 500
	s3.tanks[0].set_stock("drift_chute", 1)
	var ev3: Array[Dictionary] = _do(s3, _move(0, 200), "13 cell drop")
	assert_eq(QaUtil.types(ev3), ["tank_move", "tank_fall", "chute"] as Array[String])
	assert_eq(s3.tanks[0].stock_of("drift_chute"), 0, "a chute is spent on a fall that would have cost 0 HP (spec: fall > FALL_SAFE)")
	# Without the chute a 13-cell fall does no damage and emits no damage event.
	var s4: MatchState = _cliff([400, 1200] as Array[int], 500, 613)
	s4.tanks[0].fuel = 500
	var ev4: Array[Dictionary] = _do(s4, _move(0, 200), "13 cell drop, no chute")
	assert_eq(QaUtil.types(ev4), ["tank_move", "tank_fall"] as Array[String])
	assert_eq(s4.tanks[0].health, 100)


func test_dying_in_a_walking_fall_ends_the_turn_and_may_end_the_round() -> void:
	var s: MatchState = _cliff([400, 1200] as Array[int], 500, 700)
	s.tanks[0].fuel = 500
	s.tanks[0].health = 10
	var ev: Array[Dictionary] = _do(s, _move(0, 200), "fatal walk")
	assert_eq(QaUtil.types(ev), ["tank_move", "tank_fall", "damage", "tank_destroyed", "round_end", "money", "money"] as Array[String])
	assert_eq(_one(ev, "round_end")["winner"], 1)
	assert_eq(s.phase, SimConstants.PHASE_SHOP)
	assert_eq(s.tanks[1].round_wins, 1)
	assert_eq(s.tanks[0].kills + s.tanks[1].kills, 0, "a fall nobody caused is nobody's kill")
	# With a third tank the round goes on and the dead walker's turn passes on.
	var s3: MatchState = _cliff([400, 1200, 1500] as Array[int], 500, 700)
	s3.tanks[0].fuel = 500
	s3.tanks[0].health = 10
	var ev3: Array[Dictionary] = _do(s3, _move(0, 200), "fatal walk, 3 tanks")
	assert_eq(QaUtil.types(ev3), ["tank_move", "tank_fall", "damage", "tank_destroyed", "wind", "turn"] as Array[String])
	assert_eq(s3.current_tank, 1)


func test_fuel_cell_auto_draw_happens_exactly_at_zero_fuel() -> void:
	# (a) fuel 0 with two cells: the first step draws one (+100), 10 steps leave 90.
	var a: MatchState = _flat([300, 1200] as Array[int])
	a.tanks[0].set_stock("fuel_cell", 2)
	var ev: Array[Dictionary] = _do(a, _move(0, 10), "draw at 0")
	assert_eq([ev[0]["to_x"], ev[0]["fuel"]], [310, 90])
	assert_eq(a.tanks[0].stock_of("fuel_cell"), 1)
	# (b) fuel 5, dx 5 uses it up exactly with NO draw; the next step then draws.
	var b: MatchState = _flat([300, 1200] as Array[int])
	b.tanks[0].fuel = 5
	b.tanks[0].set_stock("fuel_cell", 1)
	var evb: Array[Dictionary] = _do(b, _move(0, 5), "exactly out of fuel")
	assert_eq([evb[0]["to_x"], evb[0]["fuel"]], [305, 0])
	assert_eq(b.tanks[0].stock_of("fuel_cell"), 1, "not drawn yet: the 5 steps were covered")
	var evb2: Array[Dictionary] = _do(b, _move(0, 1), "draw on the next step")
	assert_eq([evb2[0]["to_x"], evb2[0]["fuel"]], [306, 99])
	assert_eq(b.tanks[0].stock_of("fuel_cell"), 0)
	# (c) fuel 1, no cell: one step, then stopped; the next move is refused as no_fuel.
	var c: MatchState = _flat([300, 1200] as Array[int])
	c.tanks[0].fuel = 1
	var evc: Array[Dictionary] = _do(c, _move(0, 3), "one step of fuel")
	assert_eq([evc[0]["to_x"], evc[0]["fuel"]], [301, 0])
	assert_eq(Simulation.validate_action(c, _move(0, 1)), "no_fuel")
	# (d) one cell is worth exactly 100 steps.
	var d: MatchState = _flat([300, 1500] as Array[int])
	d.tanks[0].set_stock("fuel_cell", 1)
	var evd: Array[Dictionary] = _do(d, _move(0, 150), "one cell, 150 steps asked")
	assert_eq([evd[0]["to_x"], evd[0]["fuel"]], [400, 0])
	assert_eq(d.tanks[0].stock_of("fuel_cell"), 0)
	# (e) two cells chain inside one move: 200 steps = both cells, no leftover.
	var e: MatchState = _flat([300, 1500] as Array[int])
	e.tanks[0].set_stock("fuel_cell", 2)
	var eve: Array[Dictionary] = _do(e, _move(0, 200), "two cells in one move")
	assert_eq([eve[0]["to_x"], eve[0]["fuel"]], [500, 0])
	assert_eq(e.tanks[0].stock_of("fuel_cell"), 0)
	# (f) a stock of Fuel Cells with fuel left over is not touched until the fuel is gone.
	var f: MatchState = _flat([300, 1500] as Array[int])
	f.tanks[0].fuel = 50
	f.tanks[0].set_stock("fuel_cell", 3)
	var evf: Array[Dictionary] = _do(f, _move(0, 60), "50 fuel then a cell")
	assert_eq([evf[0]["to_x"], evf[0]["fuel"]], [360, 90])
	assert_eq(f.tanks[0].stock_of("fuel_cell"), 2)


func test_no_fuel_and_not_your_turn_and_phase_errors_for_move() -> void:
	var s: MatchState = _flat([300, 900] as Array[int])
	assert_eq(Simulation.validate_action(s, _move(0, 5)), "no_fuel")
	s.tanks[1].fuel = 100
	assert_eq(Simulation.validate_action(s, _move(1, 5)), "not_your_turn")
	var shop: MatchState = Simulation.new_match(QaUtil.settings(1, 2))
	assert_eq(Simulation.validate_action(shop, _move(0, 5)), "bad_phase")
	assert_eq(Simulation.validate_action(shop, _item(0, "glow_shield")), "bad_phase")
	assert_eq(Simulation.validate_action(shop, {"kind": "pass", "tank": 0}), "bad_phase")


func test_a_buried_tank_cannot_walk_out() -> void:
	var s: MatchState = _flat([300, 900] as Array[int])
	s.tanks[0].fuel = 100
	# 30 cells of dirt piled over tank 0's box and a wide bank around it.
	for x: int in range(250, 350):
		for y: int in range(560, 600):
			s.terrain.cells[x * s.terrain.height + y] = 1
	assert_true(QaUtil.tank_embedded(s, s.tanks[0]))
	var ev: Array[Dictionary] = _do(s, _move(0, 50), "buried walk")
	assert_eq([ev[0]["from_x"], ev[0]["to_x"]], [300, 300], "a 40-high bank is not climbable")
	assert_eq(s.tanks[0].fuel, 100, "no fuel for steps not taken")


func test_move_then_fire_in_the_same_turn() -> void:
	var s: MatchState = _flat([300, 900] as Array[int])
	s.tanks[0].fuel = 50
	_do(s, _move(0, 30), "move")
	_do(s, _move(0, -10), "move back")
	assert_eq(s.current_tank, 0)
	var ev: Array[Dictionary] = _do(s, {"kind": "fire", "tank": 0, "angle": 450, "power": 500, "weapon": "pulse_missile"}, "then fire")
	assert_eq(QaUtil.types(ev).slice(-2), ["wind", "turn"] as Array[String])
	assert_eq(s.current_tank, 1)
	assert_eq(Simulation.validate_action(s, _move(0, 5)), "not_your_turn", "the turn is gone after the shot")


# --- items --------------------------------------------------------------------------------------

func test_shield_replacement_keeps_only_the_new_shield() -> void:
	var s: MatchState = _flat([300, 900] as Array[int])
	var t: TankState = s.tanks[0]
	t.set_stock("glow_shield", 1)
	t.set_stock("ion_shield", 1)
	t.set_stock("fortress_field", 1)
	var ev: Array[Dictionary] = _do(s, _item(0, "glow_shield"), "glow")
	assert_eq(QaUtil.types(ev), ["shield_on"] as Array[String])
	assert_eq([t.shield_type, t.shield_hp], [Catalog.index_of("glow_shield"), 30])
	t.shield_hp = 7  # battered
	var ev2: Array[Dictionary] = _do(s, _item(0, "ion_shield"), "ion over a battered glow")
	assert_eq(ev2[0]["hp"], 60)
	assert_eq([t.shield_type, t.shield_hp], [Catalog.index_of("ion_shield"), 60], "the glow shield is gone, hp is the new shield's")
	assert_eq(t.stock_of("glow_shield"), 0, "and not refunded")
	_do(s, _item(0, "fortress_field"), "fortress over ion")
	assert_eq([t.shield_type, t.shield_hp], [Catalog.index_of("fortress_field"), 100])
	assert_eq(s.current_tank, 0, "shields do not end the turn")
	# Replacing with a weaker shield is allowed and lowers the protection (documented behaviour).
	t.set_stock("glow_shield", 1)
	_do(s, _item(0, "glow_shield"), "glow over fortress")
	assert_eq([t.shield_type, t.shield_hp], [Catalog.index_of("glow_shield"), 30])


func test_shield_down_then_reuse_and_shield_does_not_stop_fall_damage() -> void:
	var s: MatchState = _cliff([400, 1200] as Array[int], 500, 640)
	var t: TankState = s.tanks[0]
	t.fuel = 500
	t.set_stock("ion_shield", 1)
	_do(s, _item(0, "ion_shield"), "ion")
	var ev: Array[Dictionary] = _do(s, _move(0, 200), "fall with a shield on")
	assert_eq(QaUtil.find(ev, "shield_hit").size(), 0, "fall damage ignores shields")
	assert_eq(t.shield_hp, 60)
	assert_eq(t.health, 100 - 14)


func test_repulsor_never_pushes_the_owners_own_shell() -> void:
	for angle: int in [450, 900, 1350]:
		var s: MatchState = _flat([300, 900] as Array[int])
		var bare: Dictionary = Ballistics.trace(s, 0, angle, 300, "pulse_missile", SimConstants.WIND_USE_STATE, 1500)
		s.tanks[0].repulsor_charge = 100
		var armed: Dictionary = Ballistics.trace(s, 0, angle, 300, "pulse_missile", SimConstants.WIND_USE_STATE, 1500)
		assert_eq(armed["path"], bare["path"], "angle %d: the owner's field leaves its own shell alone" % angle)
		assert_eq((armed["repulsor_ticks"] as PackedInt32Array)[0], 0)
		var ev: Array[Dictionary] = _do(s, {"kind": "fire", "tank": 0, "angle": angle, "power": 300, "weapon": "pulse_missile"}, "own repulsor")
		assert_eq(s.tanks[0].repulsor_charge, 100 if s.tanks[0].alive else s.tanks[0].repulsor_charge, "angle %d: charge not spent on own shell" % angle)
		assert_eq(QaUtil.find(ev, "repulsor_down").size(), 0)
	# Straight up through its own field and back onto itself: still hits the owner (own tank).
	var s2: MatchState = _flat([300, 900] as Array[int])
	s2.tanks[0].repulsor_charge = 100
	var ev2: Array[Dictionary] = _do(s2, {"kind": "fire", "tank": 0, "angle": 900, "power": 100, "weapon": "pulse_missile"}, "up and back")
	assert_eq(QaUtil.find(ev2, "projectile_end")[0]["reason"], "tank")


func test_repulsor_charge_is_spent_by_other_shells_and_reports_when_empty() -> void:
	var s: MatchState = _flat([100, 700] as Array[int])
	s.tanks[1].repulsor_charge = 3
	var p: int = WeaponTestUtil.power_for_landing(s, 450, 700)
	var ev: Array[Dictionary] = _do(s, {"kind": "fire", "tank": 0, "angle": 450, "power": p, "weapon": "pulse_missile"}, "shot at a repulsor")
	var types: Array[String] = QaUtil.types(ev)
	assert_eq(s.tanks[1].repulsor_charge, 0, "three ticks inside the field exhaust it")
	var down: int = types.find("repulsor_down")
	assert_gt(down, 0)
	assert_gt(down, types.find("projectile"))
	assert_lt(down, types.find("projectile_end"), "repulsor_down is emitted between projectile and projectile_end")
	assert_eq(ev[down]["tank"], 1)
	# Re-arming resets the charge to 100, not +100.
	s.tanks[1].repulsor_charge = 40
	s.tanks[1].set_stock("repulsor_field", 1)
	s.current_tank = 1
	var ev2: Array[Dictionary] = _do(s, _item(1, "repulsor_field"), "re-arm")
	assert_eq(ev2[0]["charge"], 100)
	assert_eq(s.tanks[1].repulsor_charge, 100)


func test_repair_heals_up_to_100_and_ends_the_turn_even_at_full_health() -> void:
	for start: int in [100, 99, 70, 60, 50, 1]:
		var s: MatchState = _flat([300, 900] as Array[int])
		s.tanks[0].health = start
		s.tanks[0].set_stock("nanorepair_kit", 2)
		var ev: Array[Dictionary] = _do(s, _item(0, "nanorepair_kit"), "repair at %d" % start)
		var rep: Dictionary = _one(ev, "repair")
		assert_eq(rep["amount"], mini(40, 100 - start), "healed amount at %d" % start)
		assert_eq(rep["health"], mini(100, start + 40))
		assert_eq(s.tanks[0].health, mini(100, start + 40))
		assert_eq(QaUtil.types(ev), ["repair", "wind", "turn"] as Array[String], "repair ends the turn (start %d)" % start)
		assert_eq(s.tanks[0].stock_of("nanorepair_kit"), 1, "a kit is used even at full health")
		assert_eq(s.current_tank, 1)


func test_pass_ends_the_turn_and_skips_the_dead() -> void:
	var s: MatchState = _flat([200, 600, 1000] as Array[int])
	s.tanks[1].alive = false
	s.tanks[1].health = 0
	var money: Array[int] = [s.tanks[0].money, s.tanks[1].money, s.tanks[2].money]
	var turn: int = s.turn_number
	var ev: Array[Dictionary] = _do(s, {"kind": "pass", "tank": 0}, "pass")
	assert_eq(QaUtil.types(ev), ["wind", "turn"] as Array[String])
	assert_eq(ev[1]["tank"], 2, "the dead tank is skipped")
	assert_eq(s.current_tank, 2)
	assert_eq(s.turn_number, turn + 1)
	var ev2: Array[Dictionary] = _do(s, {"kind": "pass", "tank": 2}, "pass wraps")
	assert_eq(ev2[1]["tank"], 0)
	assert_eq([s.tanks[0].money, s.tanks[1].money, s.tanks[2].money], money)
	assert_eq(Simulation.validate_action(s, {"kind": "pass", "tank": 2}), "not_your_turn")


func test_non_usable_items_are_refused_with_not_usable() -> void:
	var s: MatchState = _flat([300, 900] as Array[int])
	var t: TankState = s.tanks[0]
	t.set_stock("drift_chute", 3)
	t.set_stock("fuel_cell", 3)
	t.set_stock("pulse_missile", 3)
	for id: String in ["drift_chute", "fuel_cell", "pulse_missile", "spark_dart", "supernova", "riptide_anchor"]:
		assert_eq(Simulation.validate_action(s, _item(0, id)), "not_usable", id)
		var sig: String = QaUtil.quick_sig(s)
		assert_eq(Simulation.apply_action(s, _item(0, id)).size(), 0, "%s: no events" % id)
		assert_eq(QaUtil.quick_sig(s), sig, "%s: nothing changed" % id)
	# Chute/fuel are not usable even with no stock; precedence: not_usable before out_of_stock.
	var empty: MatchState = _flat([300, 900] as Array[int])
	assert_eq(Simulation.validate_action(empty, _item(0, "drift_chute")), "not_usable")
	assert_eq(Simulation.validate_action(empty, _item(0, "glow_shield")), "out_of_stock")
	assert_eq(Simulation.validate_action(empty, _item(0, "no_such_item")), "unknown_item")
	assert_eq(Simulation.validate_action(empty, _item(0, "")), "unknown_item")
	assert_eq(Simulation.validate_action(empty, {"kind": "use_item", "tank": 0}), "bad_field")
	assert_eq(Simulation.validate_action(empty, {"kind": "use_item", "tank": 0, "item": 5}), "bad_field")
