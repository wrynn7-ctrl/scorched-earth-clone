extends GutTest
## use_item, pass, shields, repulsor, repair (docs/ARCHITECTURE.md sections 19-20).

const U = preload("res://tests/core/sim_test_util.gd")


func _state() -> MatchState:
	return U.flat_state(2)


func _give(s: MatchState, tank: int, item: String, n: int = 1) -> void:
	s.tanks[tank].set_stock(item, n)


## Power that makes tank 0's 45 degree shot land on tank 1 (computed without any shield).
func _aim_at_tank_1(s: MatchState) -> int:
	return U.power_for_target(s, 450, s.tanks[1].x)


func _shield(s: MatchState, tank: int, id: String) -> void:
	var def: Dictionary = ItemDefs.get_def(id)
	s.tanks[tank].shield_type = Catalog.index_of(id)
	s.tanks[tank].shield_hp = def["hp"]


# --- pass --------------------------------------------------------------------------------

func test_pass_ends_the_turn() -> void:
	var s: MatchState = _state()
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.pass_turn(0))
	assert_eq(U.types(ev), ["wind", "turn"] as Array[String])
	assert_eq(s.current_tank, 1)
	assert_eq(s.turn_number, 1)
	assert_eq(ev[1]["tank"], 1)
	assert_eq(ev[0]["wind"], s.wind)


func test_pass_validation() -> void:
	var s: MatchState = _state()
	assert_eq(Simulation.validate_action(s, U.pass_turn(1)), "not_your_turn")
	assert_eq(Simulation.validate_action(s, U.pass_turn(3)), "bad_tank")
	assert_eq(Simulation.validate_action(s, {"kind": "pass"}), "bad_field")
	s.tanks[0].alive = false
	assert_eq(Simulation.validate_action(s, U.pass_turn(0)), "tank_dead")


func test_pass_skips_dead_tanks_and_wraps() -> void:
	var s: MatchState = U.flat_state(3)
	s.tanks[1].alive = false
	s.tanks[1].health = 0
	Simulation.apply_action(s, U.pass_turn(0))
	assert_eq(s.current_tank, 2)
	Simulation.apply_action(s, U.pass_turn(2))
	assert_eq(s.current_tank, 0)


# --- use_item validation -------------------------------------------------------------------

func test_use_item_errors() -> void:
	var s: MatchState = _state()
	assert_eq(Simulation.validate_action(s, U.use_item(0, "glow_shield")), "out_of_stock")
	assert_eq(Simulation.validate_action(s, U.use_item(0, "repulsor_field")), "out_of_stock")
	assert_eq(Simulation.validate_action(s, U.use_item(0, "nanorepair_kit")), "out_of_stock")
	assert_eq(Simulation.validate_action(s, U.use_item(0, "nope")), "unknown_item")
	for id: String in ["pulse_missile", "spark_dart", "drift_chute", "fuel_cell", "supernova"]:
		_give(s, 0, id, 3)
		assert_eq(Simulation.validate_action(s, U.use_item(0, id)), "not_usable", id)
	assert_eq(Simulation.validate_action(s, U.use_item(1, "glow_shield")), "not_your_turn")
	assert_eq(Simulation.validate_action(s, U.use_item(7, "glow_shield")), "bad_tank")
	assert_eq(Simulation.validate_action(s, {"kind": "use_item", "tank": 0}), "bad_field")
	assert_eq(Simulation.validate_action(s, {"kind": "use_item", "tank": 0, "item": 3}), "bad_field")
	s.tanks[0].alive = false
	_give(s, 0, "glow_shield")
	assert_eq(Simulation.validate_action(s, U.use_item(0, "glow_shield")), "tank_dead")


func test_rejected_use_item_changes_nothing() -> void:
	var s: MatchState = _state()
	var before: String = Simulation.fingerprint(s)
	for a: Dictionary in [U.use_item(0, "glow_shield"), U.use_item(0, "pulse_missile"), U.use_item(0, "nope")]:
		assert_eq(Simulation.apply_action(s, a).size(), 0)
		assert_eq(Simulation.fingerprint(s), before)


# --- shields -------------------------------------------------------------------------------

func test_use_shield_sets_hp_consumes_stock_and_keeps_the_turn() -> void:
	var s: MatchState = _state()
	_give(s, 0, "glow_shield", 2)
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.use_item(0, "glow_shield"))
	var t: TankState = s.tanks[0]
	assert_eq(t.shield_type, Catalog.index_of("glow_shield"))
	assert_eq(t.shield_hp, 30)
	assert_eq(t.stock_of("glow_shield"), 1)
	assert_eq(ev, [{"type": "shield_on", "tick": 0, "tank": 0, "item": "glow_shield", "hp": 30}] as Array[Dictionary])
	assert_eq(s.current_tank, 0, "using a shield does not end the turn")
	assert_eq(s.turn_number, 0)
	assert_eq(Simulation.validate_action(s, U.fire(0, 450, 500)), "")


func test_each_shield_item_hp() -> void:
	for pair: Array in [["glow_shield", 30], ["ion_shield", 60], ["fortress_field", 100]]:
		var s: MatchState = _state()
		_give(s, 0, pair[0])
		Simulation.apply_action(s, U.use_item(0, pair[0]))
		assert_eq(s.tanks[0].shield_hp, pair[1], pair[0])
		assert_true(s.tanks[0].has_shield())


func test_a_new_shield_replaces_the_old_one() -> void:
	var s: MatchState = _state()
	_give(s, 0, "ion_shield")
	_give(s, 0, "glow_shield")
	Simulation.apply_action(s, U.use_item(0, "ion_shield"))
	s.tanks[0].shield_hp = 41
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.use_item(0, "glow_shield"))
	assert_eq(s.tanks[0].shield_type, Catalog.index_of("glow_shield"))
	assert_eq(s.tanks[0].shield_hp, 30, "replaced, not added: the old 41 HP is gone")
	assert_eq(ev[0]["item"], "glow_shield")
	assert_eq(s.tanks[0].stock_of("ion_shield"), 0)
	assert_eq(s.tanks[0].stock_of("glow_shield"), 0)


func test_direct_damage_is_absorbed_then_overflows_to_health() -> void:
	var s: MatchState = _state()
	_shield(s, 1, "glow_shield")
	var ev: Array[Dictionary] = []
	Simulation.apply_damage(s, 0, 1, 20, "explosion", 7, ev)
	assert_eq(s.tanks[1].shield_hp, 10)
	assert_eq(s.tanks[1].health, 100)
	assert_eq(ev, [{"type": "shield_hit", "tick": 7, "tank": 1, "absorbed": 20, "hp": 10}] as Array[Dictionary])
	ev.clear()
	Simulation.apply_damage(s, 0, 1, 25, "explosion", 7, ev)
	assert_eq(U.types(ev), ["shield_hit", "shield_down", "damage", "money"] as Array[String])
	assert_eq(ev[0], {"type": "shield_hit", "tick": 7, "tank": 1, "absorbed": 10, "hp": 0})
	assert_eq(ev[1], {"type": "shield_down", "tick": 7, "tank": 1})
	assert_eq(ev[2]["amount"], 15, "only the overflow reaches health")
	assert_eq(ev[2]["health"], 85)
	assert_eq(s.tanks[1].shield_type, -1)
	assert_eq(s.tanks[1].shield_hp, 0)
	assert_false(s.tanks[1].has_shield())
	ev.clear()
	Simulation.apply_damage(s, 0, 1, 10, "explosion", 7, ev)
	assert_eq(U.types(ev), ["damage", "money"] as Array[String], "shield is gone: damage goes straight to health")


func test_exact_absorption_brings_the_shield_down_without_damage() -> void:
	var s: MatchState = _state()
	_shield(s, 1, "glow_shield")
	var ev: Array[Dictionary] = []
	Simulation.apply_damage(s, 0, 1, 30, "explosion", 0, ev)
	assert_eq(U.types(ev), ["shield_hit", "shield_down"] as Array[String])
	assert_eq(s.tanks[1].health, 100)


func test_fall_damage_ignores_shields() -> void:
	var s: MatchState = _state()
	_shield(s, 1, "ion_shield")
	var ev: Array[Dictionary] = []
	Simulation.apply_damage(s, -1, 1, 17, "fall", 0, ev)
	assert_eq(s.tanks[1].health, 83)
	assert_eq(s.tanks[1].shield_hp, 60)
	assert_eq(U.types(ev), ["damage"] as Array[String])


func test_fall_after_an_explosion_ignores_the_shield() -> void:
	var s: MatchState = _state()
	var victim: TankState = s.tanks[1]
	_shield(s, 1, "fortress_field")
	s.terrain.carve_circle(victim.x, 600, 24)  # pit under the victim: it hovers 20 cells up
	var p: int = U.power_for_target(s, 450, victim.x + 24)
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.fire(0, 450, p))
	var fall_damage: Array[Dictionary] = []
	for d: Dictionary in U.find(ev, "damage"):
		if d["cause"] == "fall":
			fall_damage.append(d)
	assert_eq(fall_damage.size(), 1, "the victim fell")
	var absorbed: int = 0
	for h: Dictionary in U.find(ev, "shield_hit"):
		absorbed += h["absorbed"] as int
	assert_eq(victim.shield_hp, 100 - absorbed, "only the blast touched the shield; the fall ignored it")
	assert_eq(victim.health, 100 - (fall_damage[0]["amount"] as int), "fall damage went to health in full")
	var types: Array[String] = U.types(ev)
	assert_true(types.find("shield_hit") < types.find("tank_fall"))


func test_a_shell_stops_at_the_bubble() -> void:
	var s: MatchState = _state()
	var p: int = _aim_at_tank_1(s)
	var plain: Dictionary = Ballistics.trace(s, 0, 450, p, "pulse_missile", 0, SimConstants.MAX_FLIGHT_TICKS)
	assert_eq(plain["end_reason"], "tank", "test setup: the shot hits tank 1")
	_shield(s, 1, "glow_shield")
	var tr: Dictionary = Ballistics.trace(s, 0, 450, p, "pulse_missile", 0, SimConstants.MAX_FLIGHT_TICKS)
	assert_eq(tr["end_reason"], "shield")
	assert_eq(tr["hit_tank"], 1)
	var t1: TankState = s.tanks[1]
	var cx: int = tr["end_x"]
	var cy: int = tr["end_y"]
	var r2: int = (cx - t1.x) * (cx - t1.x) + (cy - (t1.y - 6)) * (cy - (t1.y - 6))
	assert_true(r2 <= 24 * 24, "ended inside the bubble (r = 24 around (x, y - 6))")
	assert_gt(r2, 21 * 21, "...right at its rim")
	assert_lt(tr["ticks"] as int, plain["ticks"] as int, "stopped earlier than the unshielded shell")
	var path: PackedInt32Array = tr["path"]
	var px: int = path[path.size() - 4] >> 16
	var py: int = path[path.size() - 3] >> 16
	var pr2: int = (px - t1.x) * (px - t1.x) + (py - (t1.y - 6)) * (py - (t1.y - 6))
	assert_gt(pr2, 24 * 24, "the previous tick's cell was outside")


func test_shielded_tank_in_a_fire_timeline() -> void:
	var s: MatchState = _state()
	var p: int = _aim_at_tank_1(s)
	_shield(s, 1, "ion_shield")
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.fire(0, 450, p))
	var end: Dictionary = U.find(ev, "projectile_end")[0]
	assert_eq(end["reason"], "shield")
	var expl: Dictionary = U.find(ev, "explosion")[0]
	assert_eq([expl["x"], expl["y"], expl["tick"]], [end["x"], end["y"], end["tick"]], "the blast happens at the bubble")
	var hits: Array[Dictionary] = U.find(ev, "shield_hit")
	assert_eq(hits.size(), 1)
	assert_eq(hits[0]["tank"], 1)
	assert_eq(hits[0]["hp"], s.tanks[1].shield_hp)
	assert_eq(s.tanks[1].shield_hp, 60 - (hits[0]["absorbed"] as int))
	assert_eq(s.tanks[1].health, 100, "the shield took it all")
	assert_eq(s.tanks[0].money, 0, "no health removed, no credit")


func test_shield_overflow_in_a_fire_timeline() -> void:
	var s: MatchState = _state()
	var p: int = _aim_at_tank_1(s)
	_shield(s, 1, "glow_shield")
	s.tanks[1].shield_hp = 1
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.fire(0, 450, p))
	var types: Array[String] = U.types(ev)
	assert_true(types.find("shield_hit") < types.find("shield_down"))
	assert_true(types.find("shield_down") < types.find("damage"))
	assert_false(s.tanks[1].has_shield())
	var d: Dictionary = U.find(ev, "damage")[0]
	assert_eq(d["tank"], 1)
	assert_eq(s.tanks[1].health, d["health"])
	assert_eq(s.tanks[0].money, (100 - (d["health"] as int)) * 15)


func test_own_shield_does_not_stop_your_own_shell() -> void:
	var s: MatchState = _state()
	_shield(s, 0, "ion_shield")
	var tr: Dictionary = Ballistics.trace(s, 0, 450, 700, "pulse_missile", 0, SimConstants.MAX_FLIGHT_TICKS)
	assert_ne(tr["end_reason"], "shield")
	var plain: MatchState = _state()
	var tr2: Dictionary = Ballistics.trace(plain, 0, 450, 700, "pulse_missile", 0, SimConstants.MAX_FLIGHT_TICKS)
	assert_eq(tr["path"], tr2["path"], "the shell leaves the own bubble and flies the same arc")


func test_own_shield_stops_a_shell_that_falls_back_on_you() -> void:
	var s: MatchState = _state()
	_shield(s, 0, "ion_shield")
	var tr: Dictionary = Ballistics.trace(s, 0, 900, 300, "pulse_missile", 0, SimConstants.MAX_FLIGHT_TICKS)
	assert_eq(tr["end_reason"], "shield")
	assert_eq(tr["hit_tank"], 0)
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.fire(0, 900, 300))
	assert_gt(U.find(ev, "shield_hit").size(), 0)
	assert_lt(s.tanks[0].shield_hp, 60)


func test_dead_tanks_have_no_bubble() -> void:
	var s: MatchState = _state()
	var p: int = _aim_at_tank_1(s)
	_shield(s, 1, "ion_shield")
	s.tanks[1].alive = false
	s.tanks[1].health = 0
	var tr: Dictionary = Ballistics.trace(s, 0, 450, p, "pulse_missile", 0, SimConstants.MAX_FLIGHT_TICKS)
	assert_ne(tr["end_reason"], "shield")


func test_shield_is_cleared_at_the_next_round() -> void:
	var s: MatchState = _state()
	_shield(s, 0, "ion_shield")
	U.kill_all_but(s, 0)
	Simulation.apply_action(s, U.pass_turn(0))
	assert_eq(s.phase, "shop")
	assert_true(s.tanks[0].has_shield(), "still there in the shop")
	U.begin_round(s)
	assert_false(s.tanks[0].has_shield())
	assert_eq(s.tanks[0].shield_type, -1)


func test_blast_next_to_a_shielded_tank_is_absorbed() -> void:
	var s: MatchState = _state()
	_shield(s, 1, "ion_shield")
	var p: int = U.power_for_target(s, 450, s.tanks[1].x - 40)
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.fire(0, 450, p))
	assert_eq(U.find(ev, "damage").size(), 0, "any damage went into the shield")
	assert_eq(s.tanks[1].health, 100)


# --- repulsor ------------------------------------------------------------------------------

func test_use_repulsor_sets_charge_independently_of_shields() -> void:
	var s: MatchState = _state()
	_give(s, 0, "repulsor_field", 2)
	_shield(s, 0, "glow_shield")
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.use_item(0, "repulsor_field"))
	assert_eq(s.tanks[0].repulsor_charge, 100)
	assert_eq(s.tanks[0].shield_hp, 30, "the shield stays")
	assert_eq(s.tanks[0].stock_of("repulsor_field"), 1)
	assert_eq(ev, [{"type": "repulsor_on", "tick": 0, "tank": 0, "charge": 100}] as Array[Dictionary])
	assert_eq(s.current_tank, 0, "no turn end")
	s.tanks[0].repulsor_charge = 20
	Simulation.apply_action(s, U.use_item(0, "repulsor_field"))
	assert_eq(s.tanks[0].repulsor_charge, 100, "recharged to 100, not added")


func test_repulsor_deflects_a_shell_that_would_otherwise_hit() -> void:
	var s: MatchState = _state()
	var p: int = _aim_at_tank_1(s)
	var plain: Dictionary = Ballistics.trace(s, 0, 450, p, "pulse_missile", 0, SimConstants.MAX_FLIGHT_TICKS)
	assert_eq(plain["end_reason"], "tank", "test setup")
	assert_eq((plain["repulsor_ticks"] as PackedInt32Array)[1], 0)
	s.tanks[1].repulsor_charge = 100
	var tr: Dictionary = Ballistics.trace(s, 0, 450, p, "pulse_missile", 0, SimConstants.MAX_FLIGHT_TICKS)
	assert_true(tr["path"] != plain["path"], "the shell flies a different arc")
	assert_gt((tr["repulsor_ticks"] as PackedInt32Array)[1], 0)
	assert_eq((tr["repulsor_ticks"] as PackedInt32Array)[0], 0)
	assert_eq(s.tanks[1].repulsor_charge, 100, "trace is pure")
	# The push is small (0.10 cell/tick^2 at most, a shell spends 4-8 ticks in the field), so the
	# end point moves by a cell or two: look for shots whose impact differs.
	var shifted: int = 0
	for power: int in range(p - 12, p + 13):
		s.tanks[1].repulsor_charge = 0
		var without: Dictionary = Ballistics.trace(s, 0, 450, power, "pulse_missile", 0, SimConstants.MAX_FLIGHT_TICKS)
		s.tanks[1].repulsor_charge = 100
		var with_field: Dictionary = Ballistics.trace(s, 0, 450, power, "pulse_missile", 0, SimConstants.MAX_FLIGHT_TICKS)
		assert_true(with_field["path"] != without["path"], "power %d: field changes the arc" % power)
		if with_field["end_x"] != without["end_x"] or with_field["end_y"] != without["end_y"]:
			shifted += 1
	assert_gt(shifted, 3, "the field visibly moves the impact point of several shots")


func test_repulsor_does_not_push_its_owners_shell() -> void:
	var s: MatchState = _state()
	var plain: Dictionary = Ballistics.trace(s, 0, 450, 700, "pulse_missile", 0, SimConstants.MAX_FLIGHT_TICKS)
	s.tanks[0].repulsor_charge = 100
	var own: Dictionary = Ballistics.trace(s, 0, 450, 700, "pulse_missile", 0, SimConstants.MAX_FLIGHT_TICKS)
	assert_eq(own["path"], plain["path"])
	assert_eq((own["repulsor_ticks"] as PackedInt32Array)[0], 0)


func test_repulsor_is_inert_outside_its_radius_and_when_empty() -> void:
	var s: MatchState = _state()
	var plain: Dictionary = Ballistics.trace(s, 0, 450, 700, "pulse_missile", 0, SimConstants.MAX_FLIGHT_TICKS)
	s.tanks[1].x = 1500  # far from the flight
	s.tanks[1].repulsor_charge = 100
	var far: Dictionary = Ballistics.trace(s, 0, 450, 700, "pulse_missile", 0, SimConstants.MAX_FLIGHT_TICKS)
	if (plain["end_x"] as int) < 1400:
		assert_eq(far["path"], plain["path"])
	var s2: MatchState = _state()
	var p: int = _aim_at_tank_1(s2)
	var base: Dictionary = Ballistics.trace(s2, 0, 450, p, "pulse_missile", 0, SimConstants.MAX_FLIGHT_TICKS)
	s2.tanks[1].repulsor_charge = 0
	var empty: Dictionary = Ballistics.trace(s2, 0, 450, p, "pulse_missile", 0, SimConstants.MAX_FLIGHT_TICKS)
	assert_eq(empty["path"], base["path"])


func test_repulsor_charge_depletes_during_a_shot() -> void:
	var s: MatchState = _state()
	var p: int = _aim_at_tank_1(s)
	s.tanks[1].repulsor_charge = 100
	var tr: Dictionary = Ballistics.trace(s, 0, 450, p, "pulse_missile", SimConstants.WIND_USE_STATE,
			SimConstants.MAX_FLIGHT_TICKS)
	var used: int = (tr["repulsor_ticks"] as PackedInt32Array)[1]
	assert_gt(used, 0)
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.fire(0, 450, p))
	assert_eq(s.tanks[1].repulsor_charge, 100 - used, "-1 charge per tick a shell is inside")
	assert_eq(U.find(ev, "repulsor_down").size(), 0)


func test_repulsor_runs_out_and_reports_repulsor_down() -> void:
	var s: MatchState = _state()
	var p: int = _aim_at_tank_1(s)
	s.tanks[1].repulsor_charge = 2
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.fire(0, 450, p))
	assert_eq(s.tanks[1].repulsor_charge, 0)
	var down: Array[Dictionary] = U.find(ev, "repulsor_down")
	assert_eq(down.size(), 1)
	assert_eq(down[0]["tank"], 1)
	var end_tick: int = U.find(ev, "projectile_end")[0]["tick"]
	assert_true((down[0]["tick"] as int) <= end_tick)
	var types: Array[String] = U.types(ev)
	assert_true(types.find("repulsor_down") > types.find("projectile"))
	assert_true(types.find("repulsor_down") < types.find("projectile_end"))
	# a second shot: the empty field no longer deflects and emits nothing
	s.current_tank = 0
	var ev2: Array[Dictionary] = Simulation.apply_action(s, U.fire(0, 450, p))
	assert_eq(U.find(ev2, "repulsor_down").size(), 0)


func test_repulsor_pushes_exactly_the_charged_ticks() -> void:
	var s: MatchState = _state()
	var p: int = _aim_at_tank_1(s)
	s.tanks[1].repulsor_charge = 3
	var tr: Dictionary = Ballistics.trace(s, 0, 450, p, "pulse_missile", 0, SimConstants.MAX_FLIGHT_TICKS)
	assert_eq((tr["repulsor_ticks"] as PackedInt32Array)[1], 3)
	assert_gt((tr["repulsor_down_tick"] as PackedInt32Array)[1], 0)
	assert_eq((tr["repulsor_down_tick"] as PackedInt32Array)[0], -1)


# --- repair --------------------------------------------------------------------------------

func test_repair_heals_and_ends_the_turn() -> void:
	var s: MatchState = _state()
	s.tanks[0].health = 50
	_give(s, 0, "nanorepair_kit", 2)
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.use_item(0, "nanorepair_kit"))
	assert_eq(s.tanks[0].health, 90)
	assert_eq(s.tanks[0].stock_of("nanorepair_kit"), 1)
	assert_eq(U.types(ev), ["repair", "wind", "turn"] as Array[String])
	assert_eq(ev[0], {"type": "repair", "tick": 0, "tank": 0, "amount": 40, "health": 90})
	assert_eq(s.current_tank, 1, "repair ends the turn")
	assert_eq(s.turn_number, 1)


func test_repair_is_capped_at_max_health() -> void:
	var s: MatchState = _state()
	s.tanks[0].health = 80
	_give(s, 0, "nanorepair_kit")
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.use_item(0, "nanorepair_kit"))
	assert_eq(s.tanks[0].health, 100)
	assert_eq(ev[0]["amount"], 20, "reports the HP actually restored")
	assert_eq(ev[0]["health"], 100)


func test_repair_at_full_health_is_allowed_and_wasted() -> void:
	var s: MatchState = _state()
	_give(s, 0, "nanorepair_kit")
	assert_eq(Simulation.validate_action(s, U.use_item(0, "nanorepair_kit")), "")
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.use_item(0, "nanorepair_kit"))
	assert_eq(ev[0]["amount"], 0)
	assert_eq(s.tanks[0].health, 100)


func test_repair_does_not_touch_shields() -> void:
	var s: MatchState = _state()
	s.tanks[0].health = 10
	_shield(s, 0, "glow_shield")
	s.tanks[0].shield_hp = 5
	_give(s, 0, "nanorepair_kit")
	Simulation.apply_action(s, U.use_item(0, "nanorepair_kit"))
	assert_eq(s.tanks[0].shield_hp, 5)
	assert_eq(s.tanks[0].health, 50)
