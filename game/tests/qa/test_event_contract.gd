@warning_ignore_start("integer_division")
extends GutTest
## Event contract (docs/ARCHITECTURE.md section 10) checked over many bot-played matches.

const QaUtil = preload("res://tests/qa/qa_util.gd")


func _bug(ok: bool, desc: String) -> void:
	if ok:
		pass_test("bug no longer reproduces (remove the pending guard): %s" % desc)
	else:
		pending("BUG: %s" % desc)


## Plays `steps` bot steps of a match, calling `check` (Callable(state_before, events, state_after))
## for every fire timeline.
func _play(settings: MatchSettings, bot_seed: int, steps: int, check: Callable) -> int:
	var state: MatchState = Simulation.new_match(settings)
	var rng := Rng.new(bot_seed)
	var fires: int = 0
	for i: int in range(steps):
		if state.phase == SimConstants.PHASE_MATCH_OVER:
			break
		if state.phase == SimConstants.PHASE_ROUND_OVER:
			var sr: Array[Dictionary] = Simulation.start_round(state)
			check_start_round(sr, state)
			continue
		var before: MatchState = state.duplicate_state()
		var action: Dictionary = QaUtil.bot_action(state, rng)
		var ev: Array[Dictionary] = Simulation.apply_action(state, action)
		fires += 1
		check.call(before, ev, state)
	return fires


func check_start_round(ev: Array[Dictionary], state: MatchState) -> void:
	assert_eq(QaUtil.check_event_fields(ev), [] as Array[String])
	assert_eq(QaUtil.types(ev), ["round_start", "wind", "turn"] as Array[String])
	for e: Dictionary in ev:
		assert_eq(e["tick"], 0)
	assert_eq(ev[0]["round"], state.round_index)
	assert_eq(ev[1]["wind"], state.wind)
	assert_eq(ev[2]["tank"], state.current_tank)
	assert_true(state.tanks[state.current_tank].alive, "round starts with an alive tank")


func _matches() -> Array[MatchSettings]:
	var out: Array[MatchSettings] = []
	var seed_value: int = 100
	for n: int in range(2, 9):
		out.append(QaUtil.settings(seed_value, n, 2))
		seed_value += 17
	out.append(QaUtil.settings(-5, 4, 3, 0))
	out.append(QaUtil.settings(9, 5, 3, 100))
	return out


func _check_everything(before: MatchState, ev: Array[Dictionary], after: MatchState) -> void:
	# 1. field names / types, ticks
	var field_errs: Array[String] = QaUtil.check_event_fields(ev)
	assert_eq(field_errs.size(), 0, "event fields: %s" % "; ".join(field_errs))
	# 2. section 10 ordering (tank_fall/fall-damage interleaving is tested separately)
	var order_errs: Array[String] = QaUtil.check_order(ev, false)
	assert_eq(order_errs.size(), 0, "ordering: %s in %s" % ["; ".join(order_errs), ",".join(QaUtil.types(ev))])
	if ev.is_empty():
		return
	# 3. fire echoes the action; first two ticks are 0
	assert_eq(ev[0]["tick"], 0)
	assert_eq(ev[1]["type"], "projectile")
	assert_eq(ev[1]["tick"], 0)
	assert_eq(ev[0]["tank"], before.current_tank)
	# 4. projectile / projectile_end consistency
	var path: PackedInt32Array = ev[1]["path"]
	var pend: Dictionary = QaUtil.find(ev, "projectile_end")[0]
	assert_eq(path.size() % 2, 0, "path is x,y pairs")
	assert_eq(path.size() / 2, pend["tick"], "one path point per tick, projectile_end.tick == path length")
	assert_true(["terrain", "tank", "lost", "timeout"].has(pend["reason"]))
	var explosions: Array[Dictionary] = QaUtil.find(ev, "explosion")
	if pend["reason"] == "terrain" or pend["reason"] == "tank":
		assert_eq(explosions.size(), 1)
		assert_eq(explosions[0]["x"], pend["x"])
		assert_eq(explosions[0]["y"], pend["y"])
		assert_eq(explosions[0]["tick"], pend["tick"])
		var carve: Dictionary = QaUtil.find(ev, "terrain_carve")[0]
		assert_eq([carve["x"], carve["y"], carve["radius"]], [pend["x"], pend["y"], explosions[0]["radius"]])
	else:
		assert_eq(explosions.size(), 0, "no explosion for %s" % pend["reason"])
		assert_eq(QaUtil.find(ev, "damage").size(), 0)
		assert_eq(QaUtil.find(ev, "terrain_carve").size(), 0)
	if path.size() >= 2 and pend["reason"] != "timeout":
		assert_eq(path[path.size() - 2] >> 16, pend["x"], "last path point is the end cell (x)")
		assert_eq(path[path.size() - 1] >> 16, pend["y"], "last path point is the end cell (y)")
	# 5. terrain_settle shape
	for st: Dictionary in QaUtil.find(ev, "terrain_settle"):
		assert_true((st["x0"] as int) >= 0 and (st["x1"] as int) < SimConstants.WORLD_W and st["x0"] <= st["x1"])
		for f: Dictionary in (st["falls"] as Array):
			assert_eq(f.keys().size(), 4)
			for k: String in ["x", "from_y", "to_y", "length"]:
				assert_eq(typeof(f[k]), TYPE_INT)
			assert_true((f["x"] as int) >= st["x0"] and (f["x"] as int) <= st["x1"])
			assert_gt(f["to_y"] as int, f["from_y"] as int)
	# 6. damage.health == tank health after the action; amounts add up; cause values
	var last_health: Dictionary = {}
	var total: Dictionary = {}
	for d: Dictionary in QaUtil.find(ev, "damage"):
		var tid: int = d["tank"]
		assert_true(["explosion", "fall"].has(d["cause"]))
		assert_gt(d["amount"] as int, 0)
		last_health[tid] = d["health"]
		total[tid] = (total.get(tid, 0) as int) + (d["amount"] as int)
	for tid: int in last_health:
		assert_eq(last_health[tid], after.tanks[tid].health, "damage.health of tank %d equals its final health" % tid)
	for t: TankState in before.tanks:
		# `amount` is the nominal (un-clamped) damage, health is clamped at 0 (overkill is reported as-is).
		var expect_health: int = maxi(0, t.health - (total.get(t.id, 0) as int))
		assert_eq(after.tanks[t.id].health, expect_health, "tank %d: final health = max(0, health - sum of damage)" % t.id)
	# 7. tank_destroyed == exactly the tanks that died, once each, after damage
	var destroyed: Array[int] = []
	for e: Dictionary in QaUtil.find(ev, "tank_destroyed"):
		destroyed.append(e["tank"])
	var expect_dead: Array[int] = []
	for t: TankState in before.tanks:
		if t.alive and not after.tanks[t.id].alive:
			expect_dead.append(t.id)
	destroyed.sort()
	assert_eq(destroyed, expect_dead, "tank_destroyed lists exactly the new casualties")
	# 8. tank_fall matches the state
	for e: Dictionary in QaUtil.find(ev, "tank_fall"):
		assert_eq(e["to_y"], after.tanks[e["tank"] as int].y)
		assert_gt(e["to_y"] as int, e["from_y"] as int)
	# 9. end of timeline: round_end XOR (wind, turn), consistent with the state
	var ends: Array[Dictionary] = QaUtil.find(ev, "round_end")
	if ends.is_empty():
		assert_eq(after.phase, SimConstants.PHASE_AIM)
		var turn: Dictionary = QaUtil.find(ev, "turn")[0]
		assert_true(after.tanks[turn["tank"] as int].alive, "turn names an alive tank")
		assert_eq(turn["tank"], after.current_tank)
		assert_eq(QaUtil.find(ev, "wind")[0]["wind"], after.wind)
		assert_gt(QaUtil.alive_count(after), 1)
		assert_eq(after.turn_number, before.turn_number + 1)
	else:
		assert_ne(after.phase, SimConstants.PHASE_AIM)
		var winner: int = ends[0]["winner"]
		var alive: Array[int] = []
		for t: TankState in after.tanks:
			if t.alive:
				alive.append(t.id)
		assert_true(alive.size() <= 1)
		assert_eq(winner, alive[0] if alive.size() == 1 else -1)
		assert_eq(after.turn_number, before.turn_number, "no turn advance on round end")


func test_contract_over_many_matches() -> void:
	var total_fires: int = 0
	var bot_seed: int = 1
	for s: MatchSettings in _matches():
		total_fires += _play(s, bot_seed, 40, _check_everything)
		bot_seed += 1
	assert_gt(total_fires, 150, "enough timelines were checked")


func test_wild_shots_contract() -> void:
	# Random angle/power incl. lots of lost shots, shots off the top and self hits.
	var rng := Rng.new(2024)
	var state: MatchState = Simulation.new_match(QaUtil.settings(31, 6, 3))
	var n: int = 0
	while n < 60 and state.phase != SimConstants.PHASE_MATCH_OVER:
		if state.phase == SimConstants.PHASE_ROUND_OVER:
			Simulation.start_round(state)
		var before: MatchState = state.duplicate_state()
		var a: Dictionary = QaUtil.fire(state.current_tank, rng.range_int(0, 1800), rng.range_int(1, 1000))
		var ev: Array[Dictionary] = Simulation.apply_action(state, a)
		_check_everything(before, ev, state)
		n += 1


func test_ticks_non_decreasing_and_projectile_end_tick_is_flight_time() -> void:
	var s: MatchState = QaUtil.flat_state([400, 1200])
	var ev: Array[Dictionary] = Simulation.apply_action(s, QaUtil.fire(0, 450, 600))
	var last: int = 0
	for e: Dictionary in ev:
		assert_true((e["tick"] as int) >= last)
		last = e["tick"]
	assert_eq(ev[ev.size() - 1]["tick"], QaUtil.find(ev, "projectile_end")[0]["tick"],
			"post-impact events all carry the impact tick")


func test_lost_shot_timeline_shape() -> void:
	var s: MatchState = QaUtil.flat_state([12, 1200])
	var ev: Array[Dictionary] = Simulation.apply_action(s, QaUtil.fire(0, 1800, 500))
	assert_eq(QaUtil.types(ev), ["fire", "projectile", "projectile_end", "wind", "turn"] as Array[String])


## Spec section 10: "... terrain_settle -> tank_fall* -> damage(fall)* -> tank_destroyed*".
## The simulation interleaves them per tank (tank_fall A, damage A, tank_fall B, damage B).
func test_literal_order_all_tank_falls_before_fall_damage() -> void:
	# Two tanks standing side by side on a 2-cell sheet; one shell removes the sheet under both.
	var base: MatchState = QaUtil.flat_state([200, 790, 814, 1500])
	for x: int in range(base.terrain.width):
		for y: int in range(602, base.terrain.height):
			base.terrain.cells[x * base.terrain.height + y] = 0
	var found: Array[Dictionary] = []
	var hit: Vector2i = Vector2i(-1, -1)
	for angle: int in [450, 520, 600, 380]:
		for power: int in range(1, 1001):
			var tr: Dictionary = Ballistics.trace(base, 0, angle, power, QaUtil.WEAPON, 0, 1500)
			var ex: int = tr["end_x"]
			if ex < 797 or ex > 807 or tr["end_reason"] != "tank":
				continue
			var trial: MatchState = base.duplicate_state()
			var ev: Array[Dictionary] = Simulation.apply_action(trial, QaUtil.fire(0, angle, power))
			var fall_damage: int = 0
			for d: Dictionary in QaUtil.find(ev, "damage"):
				if d["cause"] == "fall":
					fall_damage += 1
			if fall_damage >= 2:
				found = ev
				hit = Vector2i(angle, power)
				break
		if not found.is_empty():
			break
	assert_false(found.is_empty(), "scenario search found a shot dropping two tanks (test setup)")
	if found.is_empty():
		return
	assert_eq(QaUtil.check_order(found, false).size(), 0, "relaxed order is fine")
	var errs: Array[String] = QaUtil.check_order(found, true)
	_bug(errs.is_empty(), (
			"Timeline interleaves tank_fall and damage(fall) per tank (tank_fall A, damage A, tank_fall B, damage B, ...) "
			+ "but docs/ARCHITECTURE.md section 10 says 'terrain_settle -> tank_fall* -> damage(fall)* -> tank_destroyed*' "
			+ "(and game/tests/core/test_simulation.gd RANK expects the same). Repro: flat ground y=600 reduced to a 2-cell "
			+ "sheet, tanks at x=790 and 814, shooter at x=200 fires angle %d power %d. Seen: %s. "
			+ "Cause: game/core/simulation.gd _resolve_explosion loop emits _damage_tank inside the per-tank tank_fall loop. "
			+ "Low severity; fix either the code or the doc.") % [hit.x, hit.y, ",".join(QaUtil.types(found).slice(5))])
