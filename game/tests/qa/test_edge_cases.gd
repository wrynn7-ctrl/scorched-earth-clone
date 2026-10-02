@warning_ignore_start("integer_division")
extends GutTest
## Adversarial edge cases for game/core. Tests that expose a defect call _bug() so the suite
## stays green (pending) while the lead decides; see the QA report.

const QaUtil = preload("res://tests/qa/qa_util.gd")
const W: int = SimConstants.WORLD_W
const H: int = SimConstants.WORLD_H


## Marks the test pending with the bug text when `ok` is false (the check failed).
func _bug(ok: bool, desc: String) -> void:
	if ok:
		pass_test("bug no longer reproduces (remove the pending guard): %s" % desc)
	else:
		pending("BUG: %s" % desc)


## Applies a legal action and runs the contract/invariant checks on the result.
func _fire_checked(state: MatchState, tank: int, angle: int, power: int, strict: bool = true) -> Array[Dictionary]:
	var action: Dictionary = QaUtil.fire(tank, angle, power)
	assert_eq(Simulation.validate_action(state, action), "", "action legal: %s" % str(action))
	var ev: Array[Dictionary] = Simulation.apply_action(state, action)
	assert_gt(ev.size(), 3, "timeline produced")
	assert_eq(QaUtil.check_event_fields(ev), [] as Array[String], "event fields")
	assert_eq(QaUtil.check_order(ev, false), [] as Array[String], "event order")
	assert_eq(QaUtil.check_invariants(state, strict, strict), [] as Array[String], "invariants")
	return ev


func _end_reason(ev: Array[Dictionary]) -> String:
	return QaUtil.find(ev, "projectile_end")[0]["reason"]


# --- horizontal shots from the map edges ------------------------------------------

func test_angle_0_and_1800_from_far_edges_are_lost_without_explosion() -> void:
	var s: MatchState = QaUtil.flat_state([12, 1587, 800])  # boxes [0,24) and [1575,1599)
	var before_cells: PackedByteArray = s.terrain.cells.duplicate()
	var ev: Array[Dictionary] = _fire_checked(s, 0, 1800, 1000)  # leftwards off the map
	assert_eq(_end_reason(ev), "lost")
	assert_eq(QaUtil.find(ev, "explosion").size(), 0)
	assert_eq(s.current_tank, 1, "turn passes after a lost shot")
	ev = _fire_checked(s, 1, 0, 1000)  # rightwards off the map
	assert_eq(_end_reason(ev), "lost")
	assert_eq(QaUtil.find(ev, "explosion").size(), 0)
	assert_true(s.terrain.cells == before_cells, "lost shots do not touch terrain")
	for t: TankState in s.tanks:
		assert_eq(t.health, 100)


func test_angle_0_and_1800_inward_from_edges_cross_the_map() -> void:
	var s: MatchState = QaUtil.flat_state([12, 1587])
	var ev: Array[Dictionary] = _fire_checked(s, 0, 0, 1000)
	assert_ne(_end_reason(ev), "timeout")
	var end: Dictionary = QaUtil.find(ev, "projectile_end")[0]
	assert_gt(end["x"] as int, 100, "flat horizontal shot travels right")
	ev = _fire_checked(s, 1, 1800, 1000)
	end = QaUtil.find(ev, "projectile_end")[0]
	assert_lt(end["x"] as int, 1500, "flat horizontal shot travels left")


func test_tanks_hanging_off_the_map_do_not_crash() -> void:
	# Hand-built: hit box partly outside the world (x=0 / x=1599). Must not crash.
	var s: MatchState = QaUtil.flat_state([0, 1599])
	var ev: Array[Dictionary] = _fire_checked(s, 0, 1800, 500, false)
	assert_eq(_end_reason(ev), "lost")
	ev = _fire_checked(s, 1, 0, 500, false)
	assert_eq(_end_reason(ev), "lost")
	s.wind = 0
	s.current_tank = 0
	ev = _fire_checked(s, 0, 900, 200, false)  # up and back down onto itself at the edge
	assert_eq(_end_reason(ev), "tank")


# --- vertical / extreme power ------------------------------------------------------

func test_angle_900_power_1_hits_own_tank() -> void:
	var s: MatchState = QaUtil.flat_state([400, 1200])
	var ev: Array[Dictionary] = _fire_checked(s, 0, 900, 1)
	assert_eq(_end_reason(ev), "tank")
	var d: Array[Dictionary] = QaUtil.find(ev, "damage")
	assert_gt(d.size(), 0)
	assert_eq(d[0]["tank"], 0)
	assert_eq(s.tanks[1].health, 100)


func test_angle_900_power_1000_goes_off_the_top_and_returns() -> void:
	var s: MatchState = QaUtil.flat_state([400, 1200])
	var ev: Array[Dictionary] = _fire_checked(s, 0, 900, 1000)
	var path: PackedInt32Array = QaUtil.find(ev, "projectile")[0]["path"]
	var min_y: int = 1 << 40
	for i: int in range(path.size() / 2):
		min_y = mini(min_y, path[i * 2 + 1])
	assert_lt(min_y, 0, "path goes above y<0 (open sky)")
	assert_eq(_end_reason(ev), "tank", "comes straight back down on the shooter")
	assert_eq(path.size() % 2, 0)
	var end: Dictionary = QaUtil.find(ev, "projectile_end")[0]
	assert_true((end["y"] as int) >= 0, "impact is on the map")


func test_shot_above_the_map_with_wind_comes_back_and_lands() -> void:
	var s: MatchState = QaUtil.flat_state([400, 1200])
	s.wind = 60
	var ev: Array[Dictionary] = _fire_checked(s, 0, 820, 1000)
	var path: PackedInt32Array = QaUtil.find(ev, "projectile")[0]["path"]
	var went_above: bool = false
	var came_back: bool = false
	for i: int in range(path.size() / 2):
		if path[i * 2 + 1] < 0:
			went_above = true
		elif went_above:
			came_back = true
	assert_true(went_above and came_back, "left the top of the map and re-entered")
	for i: int in range(path.size()):
		assert_true(path[i] > -(1 << 30) and path[i] < (1 << 30), "path value fits comfortably in int32")


func test_wind_extremes_power_1() -> void:
	for w: int in [SimConstants.WIND_MAX, -SimConstants.WIND_MAX]:
		for angle: int in [0, 450, 900, 1350, 1800]:
			var s: MatchState = QaUtil.flat_state([800, 1500])
			s.wind = w
			var ev: Array[Dictionary] = _fire_checked(s, 0, angle, 1)
			assert_ne(_end_reason(ev), "timeout", "w=%d angle=%d" % [w, angle])
	# Direction check: straight up at modest power, wind pushes the landing point.
	var right: MatchState = QaUtil.flat_state([800, 1500])
	right.wind = SimConstants.WIND_MAX
	var left: MatchState = QaUtil.flat_state([800, 1500])
	left.wind = -SimConstants.WIND_MAX
	var tr_r: Dictionary = Ballistics.trace(right, 0, 900, 500, QaUtil.WEAPON, SimConstants.WIND_USE_STATE, 1500)
	var tr_l: Dictionary = Ballistics.trace(left, 0, 900, 500, QaUtil.WEAPON, SimConstants.WIND_USE_STATE, 1500)
	assert_gt(tr_r["end_x"] as int, 800 + 20, "+wind blows right")
	assert_lt(tr_l["end_x"] as int, 800 - 20, "-wind blows left")
	# override == state wind
	var tr_o: Dictionary = Ballistics.trace(left, 0, 900, 500, QaUtil.WEAPON, SimConstants.WIND_MAX, 1500)
	assert_eq(tr_o["end_x"], tr_r["end_x"], "wind_override=+max equals state wind +max")


func test_wind_drift_never_exceeds_wind_max_in_a_match() -> void:
	for wm: int in [0, 1, 7, 100]:
		var s: MatchState = QaUtil.started_match(QaUtil.settings(31 + wm, 4, 1, wm))
		var rng := Rng.new(5)
		for i: int in range(12):
			if QaUtil.play_bot_step(s, rng).is_empty():
				break
			assert_true(absi(s.wind) <= wm, "wind %d within +-%d" % [s.wind, wm])


# --- placement ---------------------------------------------------------------------

func test_placement_never_overlaps_and_stays_on_map() -> void:
	var failures: Array[String] = []
	for n: int in range(2, 9):
		for sd: int in range(0, 15):
			var s: MatchState = QaUtil.started_match(QaUtil.settings(sd * 7919 + n, n))
			assert_eq(s.tanks.size(), n)
			var prev_right: int = 0
			for t: TankState in s.tanks:
				var left: int = t.x - 12
				var right: int = t.x + 12
				if left < prev_right:
					failures.append("n=%d seed=%d tank %d overlaps previous (left %d < %d)" % [n, sd * 7919 + n, t.id, left, prev_right])
				if left < 0 or right > W or t.y < 0 or t.y > H:
					failures.append("n=%d seed=%d tank %d off map" % [n, sd * 7919 + n, t.id])
				prev_right = right
	assert_eq(failures.size(), 0, "\n".join(failures))


func test_placement_8_tanks_many_seeds_with_extreme_seed_values() -> void:
	for sd: int in [0, -1, 1, (1 << 62), -(1 << 62), 9223372036854775807, -9223372036854775807 - 1, 0xFFFFFFFF, 0x100000000]:
		var s: MatchState = QaUtil.started_match(QaUtil.settings(sd, 8))
		assert_eq(s.tanks.size(), 8, "seed %d" % sd)
		assert_eq(QaUtil.check_invariants(s), [] as Array[String], "seed %d" % sd)
		for i: int in range(1, 8):
			assert_true(s.tanks[i].x - s.tanks[i - 1].x >= 24, "seed %d tanks %d/%d" % [sd, i - 1, i])


func test_num_tanks_out_of_range_is_clamped() -> void:
	for n: int in [-3, 0, 1, 9, 100]:
		var s: MatchState = QaUtil.started_match(QaUtil.settings(3, n))
		var expect: int = clampi(n, 2, 8)
		assert_eq(s.tanks.size(), expect, "num_tanks=%d" % n)
		assert_eq(s.current_tank, 0)
		assert_eq(Simulation.fingerprint(s).length(), 16)


# --- Terrain API at the borders ----------------------------------------------------

func _flat_terrain(ground: int = 600) -> Terrain:
	return QaUtil.flat_terrain(ground)


func test_carve_at_left_and_right_border_clips_without_crash() -> void:
	var t: Terrain = _flat_terrain()
	var r0: Rect2i = t.carve_circle(0, 650, 28)
	assert_eq(r0.position.x, 0)
	assert_eq(r0.end.x, 29, "clipped to x in [0,28]")
	var r1: Rect2i = t.carve_circle(W - 1, 650, 28)
	assert_eq(r1.end.x, W, "clipped to the last column")
	assert_eq(r1.position.x, W - 1 - 28)
	assert_false(t.is_solid(0, 650))
	assert_false(t.is_solid(W - 1, 650))
	assert_true(t.is_solid(0, 700), "below the crater is intact")
	# the clipped half-disc equals the right half of an interior crater
	var u: Terrain = _flat_terrain()
	u.carve_circle(100, 650, 28)
	for dx: int in range(0, 29):
		assert_eq(t.surface_y(dx), u.surface_y(100 + dx), "column %d crater depth" % dx)
		assert_eq(t.surface_y(W - 1 - dx), u.surface_y(100 - dx), "mirror column %d" % dx)
	# fully outside / far outside
	assert_eq(t.carve_circle(-100, 650, 28).size.x, 0, "entirely left of the map")
	assert_eq(t.carve_circle(W + 100, 650, 28).size.x, 0, "entirely right of the map")
	assert_eq(t.carve_circle(-28, 650, 28).size.x, 1, "touches column 0 only")
	assert_eq(t.carve_circle(800, -100, 28).size.x, 0, "entirely above the map")
	assert_eq(t.carve_circle(800, H + 100, 28).size.x, 0, "entirely below the map")
	assert_eq(t.settle(0, 40).size() + t.settle(W - 41, W - 1).size() >= 0, true)


func test_explosion_in_the_corners_and_edges_of_the_map() -> void:
	var t: Terrain = _flat_terrain(100)
	for p: Vector2i in [Vector2i(0, 0), Vector2i(W - 1, 0), Vector2i(0, H - 1), Vector2i(W - 1, H - 1),
			Vector2i(0, 100), Vector2i(W - 1, 100), Vector2i(800, 0), Vector2i(800, H - 1)]:
		var rect: Rect2i = t.carve_circle(p.x, p.y, 28)
		if rect.size.x > 0:
			t.settle(rect.position.x, rect.end.x - 1)
		t.add_circle(p.x, p.y, 28, 3)
	assert_eq(t.cells.size(), W * H, "buffer size unchanged")


func test_carve_radius_zero_and_negative() -> void:
	var t: Terrain = _flat_terrain()
	var r: Rect2i = t.carve_circle(100, 650, 0)
	assert_eq(r, Rect2i(100, 650, 1, 1), "radius 0 clears exactly the centre cell")
	assert_false(t.is_solid(100, 650))
	assert_true(t.is_solid(99, 650))
	assert_true(t.is_solid(101, 650))
	assert_true(t.is_solid(100, 649) and t.is_solid(100, 651), "cells above/below the centre are untouched")
	assert_eq(t.carve_circle(100, 300, 0), Rect2i(100, 300, 1, 1), "radius 0 on air is a harmless no-op")
	assert_eq(t.carve_circle(100, 650, -1), Rect2i(), "negative radius: empty rect")
	var a: Rect2i = t.add_circle(100, 650, 0, 5)
	assert_eq(a, Rect2i(100, 650, 1, 1))
	assert_eq(t.get_cell(100, 650), 5, "add_circle radius 0 fills the single air cell")
	assert_eq(Damage.amount(0, 0, 55), 0, "radius-0 explosion deals no damage")
	assert_eq(Damage.compute(QaUtil.flat_state([100, 300]), 100, 590, 0, 55).size(), 0)


func test_settle_full_width_conserves_dirt_and_leaves_nothing_floating() -> void:
	var rng := Rng.new(99)
	var h: int = 300  # full 1600-column width, shorter columns keep the per-cell checks fast
	var t: Terrain = Terrain.generate(W, h, rng)
	for i: int in range(120):  # swiss cheese
		t.carve_circle(rng.range_int(-20, W + 20), rng.range_int(60, h + 20), rng.range_int(0, 40))
	var solid_before: int = 0
	var mats_before: Dictionary = {}
	for c: int in range(t.cells.size()):
		if t.cells[c] != 0:
			solid_before += 1
			mats_before[t.cells[c]] = (mats_before.get(t.cells[c], 0) as int) + 1
	var falls: Array[Dictionary] = t.settle(0, W - 1)
	assert_gt(falls.size(), 0, "carved cheese had floating dirt")
	var solid_after: int = 0
	var mats_after: Dictionary = {}
	for x: int in range(W):
		var seen_air: bool = false
		for y: int in range(h - 1, -1, -1):
			var c: int = t.cells[x * h + y]
			if c == 0:
				seen_air = true
			else:
				solid_after += 1
				mats_after[c] = (mats_after.get(c, 0) as int) + 1
				if seen_air:
					fail_test("column %d: solid cell above an air gap at y=%d" % [x, y])
					return
	assert_eq(solid_after, solid_before, "settle conserves the number of dirt cells")
	assert_eq(mats_after, mats_before, "settle conserves materials")
	assert_eq(t.settle(0, W - 1).size(), 0, "second settle is a no-op")
	# clipping of silly ranges
	assert_eq(t.settle(-500, 5000).size(), 0)
	assert_eq(t.settle(10, 5).size(), 0, "reversed range is a no-op")
	assert_eq(t.settle(W + 5, W + 9).size(), 0)


func test_settle_on_empty_and_full_columns() -> void:
	var t := Terrain.new(W, H)
	assert_eq(t.settle(0, W - 1).size(), 0, "empty world")
	t.cells.fill(1)
	assert_eq(t.settle(0, W - 1).size(), 0, "full world")
	t.carve_circle(0, 0, 5)
	assert_eq(t.settle(0, W - 1).size(), 0, "a bite out of the top leaves nothing floating")
	t.carve_circle(800, H - 1, 5)
	assert_eq(t.settle(0, W - 1).size(), 11, "a bite at the very bottom: each of the 11 columns above it drops")


func test_repeated_explosions_dig_to_the_bottom() -> void:
	var t: Terrain = _flat_terrain(600)
	var guard: int = 0
	while t.surface_y(800) < H and guard < 200:
		guard += 1
		var sy: int = t.surface_y(800)
		var rect: Rect2i = t.carve_circle(800, sy, 28)
		t.settle(rect.position.x, rect.end.x - 1)
	assert_eq(t.surface_y(800), H, "column 800 dug out completely")
	assert_lt(guard, 200)
	assert_true(t.is_solid(800, H), "y >= height is bedrock")
	assert_true(t.is_solid(800, H + 500))
	assert_eq(t.carve_circle(800, H, 28).size.x > 0, true, "an explosion on bedrock still carves the upper half-disc")
	assert_eq(t.carve_circle(800, H + 40, 28).size.x, 0, "an explosion fully below the map is a no-op")
	assert_eq(t.cells.size(), W * H)
	assert_eq(t.get_cell(800, H), Terrain.BEDROCK, "get_cell below the map reports bedrock")
	assert_true(t.is_solid(800, H), "is_solid below the map agrees with get_cell")


func test_dig_to_bottom_via_simulation_shots() -> void:
	# Tank 1 stays far away; tank 0 keeps shooting its own spot (straight up) until the ground is gone
	# under it. Exercises fall-to-bedrock through the real action pipeline.
	var s: MatchState = QaUtil.flat_state([400, 1500, 1000], 860)
	s.settings.rounds = 50
	for t: TankState in s.tanks:
		t.health = 100
	var shots: int = 0
	while s.phase == SimConstants.PHASE_AIM and shots < 60:
		shots += 1
		var me: int = s.current_tank
		# keep everyone healthy so the dig goes on, shoot straight up (self hit digs under oneself)
		for t: TankState in s.tanks:
			t.health = 100
			t.alive = true
		var ev: Array[Dictionary] = _fire_checked(s, me, 900, 300)
		assert_true(QaUtil.find(ev, "explosion").size() == 1)
	assert_gt(shots, 5)
	for t: TankState in s.tanks:
		assert_true(t.y <= H, "tank %d never below bedrock" % t.id)


# --- kills --------------------------------------------------------------------------

func test_one_explosion_kills_the_last_two_tanks_draw() -> void:
	var s: MatchState = QaUtil.flat_state([800, 824])  # boxes touch: [788,812) and [812,836)
	s.tanks[0].health = 10
	s.tanks[1].health = 10
	var ev: Array[Dictionary] = _fire_checked(s, 0, 900, 300)  # straight up, lands on itself
	assert_false(s.tanks[0].alive)
	assert_false(s.tanks[1].alive)
	var end: Dictionary = QaUtil.find(ev, "round_end")[0]
	assert_eq(end["winner"], -1, "draw")
	assert_eq(ev[ev.size() - 1]["type"], "round_end")
	assert_eq(QaUtil.find(ev, "turn").size(), 0)
	assert_eq(QaUtil.find(ev, "wind").size(), 0)
	assert_eq(QaUtil.find(ev, "tank_destroyed").size(), 2)
	assert_eq(s.phase, SimConstants.PHASE_SHOP)
	# health reported by damage events is clamped at 0, never negative
	for d: Dictionary in QaUtil.find(ev, "damage"):
		assert_true((d["health"] as int) >= 0)
	assert_eq(Simulation.apply_action(s, QaUtil.fire(0, 450, 500)).size(), 0, "no fire in the shop")
	assert_eq(Simulation.validate_action(s, QaUtil.fire(0, 450, 500)), "bad_phase")


func test_draw_on_last_round_is_match_over() -> void:
	var s: MatchState = QaUtil.flat_state([800, 824], 600, 1)
	s.tanks[0].health = 10
	s.tanks[1].health = 10
	var ev: Array[Dictionary] = _fire_checked(s, 0, 900, 300)
	assert_eq(QaUtil.find(ev, "round_end")[0]["winner"], -1)
	assert_eq(s.phase, SimConstants.PHASE_MATCH_OVER)
	assert_eq(Simulation.start_round(s).size(), 0)


func test_kill_of_two_with_a_third_alive_continues_the_round() -> void:
	var s: MatchState = QaUtil.flat_state([800, 824, 1200, 1500])
	s.tanks[0].health = 10
	s.tanks[1].health = 10
	var ev: Array[Dictionary] = _fire_checked(s, 0, 900, 300)
	assert_eq(QaUtil.find(ev, "tank_destroyed").size(), 2)
	assert_eq(QaUtil.find(ev, "round_end").size(), 0)
	assert_eq(s.current_tank, 2, "turn skips the two dead tanks")
	assert_eq(QaUtil.find(ev, "turn")[0]["tank"], 2)
	assert_eq(s.phase, SimConstants.PHASE_AIM)


func test_tank_killed_by_its_own_shot() -> void:
	var s: MatchState = QaUtil.flat_state([400, 1200])
	s.tanks[0].health = 30
	var ev: Array[Dictionary] = _fire_checked(s, 0, 900, 300)
	assert_false(s.tanks[0].alive)
	assert_eq(s.tanks[0].health, 0)
	assert_eq(QaUtil.find(ev, "tank_destroyed")[0]["tank"], 0)
	var end: Dictionary = QaUtil.find(ev, "round_end")[0]
	assert_eq(end["winner"], 1, "the survivor wins")
	assert_eq(s.phase, SimConstants.PHASE_SHOP)


func test_dead_tanks_are_ignored_by_shells_and_by_turn_order() -> void:
	var s: MatchState = QaUtil.flat_state([200, 600, 1000, 1400])
	s.tanks[1].alive = false
	s.tanks[1].health = 0
	# flat shot from tank 0 at the dead tank's position: aim a ballistic arc landing on x=600
	var p: int = 1
	var best: int = 1 << 30
	for q: int in range(1, 1001, 4):
		var tr: Dictionary = Ballistics.trace(s, 0, 450, q, QaUtil.WEAPON, 0, 1500)
		var d: int = absi((tr["end_x"] as int) - 600)
		if d < best:
			best = d
			p = q
	var tr2: Dictionary = Ballistics.trace(s, 0, 450, p, QaUtil.WEAPON, 0, 1500)
	assert_eq(tr2["hit_tank"], -1, "shell does not hit the dead tank")
	var ev: Array[Dictionary] = _fire_checked(s, 0, 450, p)
	assert_eq(s.current_tank, 2, "turn skips the dead tank")
	assert_eq(QaUtil.find(ev, "turn")[0]["tank"], 2)
	assert_eq(Simulation.validate_action(s, QaUtil.fire(1, 450, 500)), "not_your_turn")
	s.current_tank = 1
	assert_eq(Simulation.validate_action(s, QaUtil.fire(1, 450, 500)), "tank_dead")


func test_fall_through_the_floor_onto_bedrock() -> void:
	# A one-cell-thick sheet is all that holds the tank up; destroying it drops the tank onto bedrock.
	var s: MatchState = QaUtil.flat_state([800, 300])
	for x: int in range(W):
		for y: int in range(601, H):
			s.terrain.cells[x * H + y] = 0  # leave only the y=600 sheet
	s.current_tank = 0
	var ev: Array[Dictionary] = _fire_checked(s, 0, 900, 300, false)
	var falls: Array[Dictionary] = QaUtil.find(ev, "tank_fall")
	assert_eq(falls.size(), 1)
	assert_eq(falls[0]["tank"], 0)
	assert_eq(falls[0]["from_y"], 600)
	assert_eq(falls[0]["to_y"], H, "empty column: lands on bedrock at y = height")
	assert_eq(s.tanks[0].y, H)
	assert_false(s.tanks[0].alive, "300-cell fall is fatal")
	assert_eq(s.tanks[0].health, 0)
	var kinds: Array[String] = []
	for d: Dictionary in QaUtil.find(ev, "damage"):
		kinds.append(d["cause"])
		assert_true((d["health"] as int) >= 0)
	assert_eq(kinds, ["explosion", "fall"] as Array[String])
	assert_eq(QaUtil.find(ev, "tank_destroyed").size(), 1)


func test_survivable_fall_damage_formula() -> void:
	# Ground 20 cells thick: the crater under the tank leaves 6 cells -> fall 14 -> (14-12)/2 = 1 damage.
	var s: MatchState = QaUtil.flat_state([800, 300], 880)
	var ev: Array[Dictionary] = _fire_checked(s, 0, 900, 300)
	var falls: Array[Dictionary] = QaUtil.find(ev, "tank_fall")
	assert_eq(falls.size(), 1)
	var fall: int = (falls[0]["to_y"] as int) - (falls[0]["from_y"] as int)
	var fall_damage: int = 0
	for d: Dictionary in QaUtil.find(ev, "damage"):
		if d["cause"] == "fall":
			fall_damage += d["amount"] as int
	assert_eq(fall_damage, maxi(0, (fall - SimConstants.FALL_SAFE) / SimConstants.FALL_DMG_DIV))
	assert_eq(s.tanks[0].health, 100 - 55 - fall_damage)


# --- Ballistics.trace ---------------------------------------------------------------

func test_trace_max_ticks_zero_one_and_negative() -> void:
	var s: MatchState = QaUtil.flat_state([800, 1500])
	var before: String = Simulation.fingerprint(s)
	var t0: Dictionary = Ballistics.trace(s, 0, 450, 500, QaUtil.WEAPON, 0, 0)
	assert_eq(t0["ticks"], 0)
	assert_eq((t0["path"] as PackedInt32Array).size(), 0)
	assert_eq(t0["end_reason"], "timeout")
	assert_eq(t0["hit_tank"], -1)
	var t1: Dictionary = Ballistics.trace(s, 0, 450, 500, QaUtil.WEAPON, 0, 1)
	assert_eq(t1["ticks"], 1)
	assert_eq((t1["path"] as PackedInt32Array).size(), 2)
	assert_eq(t1["end_reason"], "timeout")
	var tn: Dictionary = Ballistics.trace(s, 0, 450, 500, QaUtil.WEAPON, 0, -5)
	assert_eq(tn["ticks"], 0, "negative max_ticks behaves like 0")
	# a shot that ends on its very first tick
	var edge: MatchState = QaUtil.flat_state([12, 1500])
	var te: Dictionary = Ballistics.trace(edge, 0, 1800, 500, QaUtil.WEAPON, 0, 1)
	assert_eq(te["end_reason"], "lost")
	assert_eq(te["ticks"], 1)
	# the full trace is a prefix-consistent extension of the 1-tick trace
	var full: Dictionary = Ballistics.trace(s, 0, 450, 500, QaUtil.WEAPON, 0, SimConstants.MAX_FLIGHT_TICKS)
	var fp: PackedInt32Array = full["path"]
	assert_eq(fp[0], (t1["path"] as PackedInt32Array)[0])
	assert_eq(fp[1], (t1["path"] as PackedInt32Array)[1])
	assert_eq(Simulation.fingerprint(s), before, "trace never mutates state")


func test_trace_is_pure_and_repeatable_across_angles_and_powers() -> void:
	var s: MatchState = QaUtil.started_match(QaUtil.settings(8, 8))
	var before: String = Simulation.fingerprint(s)
	for angle: int in [0, 1, 899, 900, 901, 1799, 1800]:
		for power: int in [1, 2, 500, 999, 1000]:
			var a: Dictionary = Ballistics.trace(s, 3, angle, power, QaUtil.WEAPON, 0, 1500)
			var b: Dictionary = Ballistics.trace(s, 3, angle, power, QaUtil.WEAPON, 0, 1500)
			assert_eq(a["path"], b["path"])
			assert_eq(a["end_reason"], b["end_reason"])
			assert_eq((a["path"] as PackedInt32Array).size(), 2 * (a["ticks"] as int))
	assert_eq(Simulation.fingerprint(s), before)


# --- whole matches ------------------------------------------------------------------

func test_twenty_round_match_runs_to_match_over() -> void:
	var s: MatchState = QaUtil.started_match(QaUtil.settings(2026, 3, 20))
	var rng := Rng.new(12)
	var starts: int = 0
	var steps: int = 0
	var round_winners: Array[int] = []
	while s.phase != SimConstants.PHASE_MATCH_OVER and steps < 4000:
		steps += 1
		if s.phase == SimConstants.PHASE_SHOP:
			var ev: Array[Dictionary] = QaUtil.enter_round(s)
			starts += 1
			assert_eq(QaUtil.types(ev), ["round_start", "wind", "turn"] as Array[String])
			assert_eq(s.round_index, starts)
			assert_eq(s.current_tank, s.round_index % 3, "round r starts with tank r %% n")
			assert_eq(QaUtil.alive_count(s), 3, "all tanks restored")
			for t: TankState in s.tanks:
				assert_eq(t.health, 100)
				t.health = 1  # glass cannons: any near miss ends the round, keeps this test fast
			assert_eq(QaUtil.check_invariants(s), [] as Array[String])
			# start_round mid-round must be a no-op
			var f0: String = Simulation.fingerprint(s)
			assert_eq(Simulation.start_round(s).size(), 0)
			assert_eq(Simulation.fingerprint(s), f0)
			continue
		var action: Dictionary = QaUtil.bot_action(s, rng)
		var ev2: Array[Dictionary] = Simulation.apply_action(s, action)
		assert_gt(ev2.size(), 3)
		var ends: Array[Dictionary] = QaUtil.find(ev2, "round_end")
		if not ends.is_empty():
			round_winners.append(ends[0]["winner"])
		var errs: Array[String] = QaUtil.check_invariants(s)
		if not errs.is_empty():
			fail_test("invariants broken at step %d: %s" % [steps, "; ".join(errs)])
			return
	gut.p("20-round match took %d bot steps" % steps)
	assert_eq(s.phase, SimConstants.PHASE_MATCH_OVER)
	assert_eq(s.round_index, 19)
	assert_eq(round_winners.size(), 20, "one round_end per round")
	assert_eq(Simulation.start_round(s).size(), 0)
	assert_eq(Simulation.apply_action(s, QaUtil.fire(0, 450, 500)).size(), 0)


func test_rounds_zero_or_negative_means_single_round() -> void:
	for r: int in [0, -4]:
		var s: MatchState = QaUtil.started_match(QaUtil.settings(77, 2, r))
		var rng := Rng.new(3)
		var n: int = 0
		while s.phase != SimConstants.PHASE_MATCH_OVER and n < 300:
			n += 1
			QaUtil.play_bot_step(s, rng)
		assert_eq(s.phase, SimConstants.PHASE_MATCH_OVER, "rounds=%d ends after the first round" % r)
		assert_eq(s.round_index, 0)


func test_wind_max_zero_keeps_wind_at_zero() -> void:
	var s: MatchState = QaUtil.started_match(QaUtil.settings(5, 3, 1, 0))
	assert_eq(s.wind, 0)
	var rng := Rng.new(3)
	for i: int in range(10):
		QaUtil.play_bot_step(s, rng)
		assert_eq(s.wind, 0)


# --- invalid inputs -------------------------------------------------------------------

func _unchanged_and_rejected(s: MatchState, a: Dictionary, expect: String) -> void:
	var before: String = Simulation.fingerprint(s)
	assert_eq(Simulation.validate_action(s, a), expect, "validate %s" % str(a))
	assert_eq(Simulation.apply_action(s, a).size(), 0, "apply returns no events for %s" % str(a))
	assert_eq(Simulation.fingerprint(s), before, "state unchanged by %s" % str(a))


func test_invalid_action_shapes() -> void:
	var s: MatchState = QaUtil.flat_state([400, 1200])
	_unchanged_and_rejected(s, {}, "bad_action")
	_unchanged_and_rejected(s, {"tank": 0, "angle": 1, "power": 1, "weapon": QaUtil.WEAPON}, "bad_action")
	_unchanged_and_rejected(s, {"kind": 5}, "bad_action")
	_unchanged_and_rejected(s, {"kind": null}, "bad_action")
	_unchanged_and_rejected(s, {"kind": &"fire", "tank": 0, "angle": 1, "power": 1, "weapon": QaUtil.WEAPON}, "bad_action")
	_unchanged_and_rejected(s, {"kind": "FIRE", "tank": 0, "angle": 1, "power": 1, "weapon": QaUtil.WEAPON}, "unknown_kind")
	_unchanged_and_rejected(s, {"kind": "", "tank": 0}, "unknown_kind")
	_unchanged_and_rejected(s, {"kind": "dance", "tank": 0, "dx": 3}, "unknown_kind")
	_unchanged_and_rejected(s, {"kind": "fire"}, "bad_field")
	_unchanged_and_rejected(s, {"kind": "fire", "tank": 0, "angle": 1, "power": 1}, "bad_field")


func test_float_string_bool_null_fields_are_rejected() -> void:
	var s: MatchState = QaUtil.flat_state([400, 1200])
	var base: Dictionary = QaUtil.fire(0, 450, 500)
	for key: String in ["tank", "angle", "power"]:
		for bad: Variant in [45.0, 0.0, "450", "", true, null, [450], {"v": 1}, Vector2i(1, 2)]:
			var a: Dictionary = base.duplicate()
			a[key] = bad
			_unchanged_and_rejected(s, a, "bad_field")
	var w: Dictionary = base.duplicate()
	w["weapon"] = 5
	_unchanged_and_rejected(s, w, "bad_field")
	w["weapon"] = null
	_unchanged_and_rejected(s, w, "bad_field")
	w["weapon"] = &"pulse_missile"
	_unchanged_and_rejected(s, w, "bad_field")
	w["weapon"] = ""
	_unchanged_and_rejected(s, w, "unknown_weapon")
	w["weapon"] = "Pulse_Missile"
	_unchanged_and_rejected(s, w, "unknown_weapon")


func test_numeric_ranges_and_negative_ids() -> void:
	var s: MatchState = QaUtil.flat_state([400, 1200])
	for tid: int in [-1, -2, -(1 << 40), 2, 8, 1 << 40, 9223372036854775807, -9223372036854775807 - 1]:
		_unchanged_and_rejected(s, QaUtil.fire(tid, 450, 500), "bad_tank")
	_unchanged_and_rejected(s, QaUtil.fire(1, 450, 500), "not_your_turn")
	for angle: int in [-1, 1801, -3600, 3600, 1 << 40, -(1 << 40), 9223372036854775807]:
		_unchanged_and_rejected(s, QaUtil.fire(0, angle, 500), "bad_angle")
	for power: int in [0, -1, 1001, 1 << 40, -(1 << 40), 9223372036854775807]:
		_unchanged_and_rejected(s, QaUtil.fire(0, 450, power), "bad_power")
	# boundaries accepted
	for pair: Vector2i in [Vector2i(0, 1), Vector2i(1800, 1000), Vector2i(0, 1000), Vector2i(1800, 1)]:
		var c: MatchState = QaUtil.flat_state([400, 1200])
		assert_eq(Simulation.validate_action(c, QaUtil.fire(0, pair.x, pair.y)), "")
		assert_gt(Simulation.apply_action(c, QaUtil.fire(0, pair.x, pair.y)).size(), 3)


func test_extra_unknown_keys_are_accepted_and_ignored() -> void:
	# Observed behaviour (not specified in ARCHITECTURE.md): unknown keys do not invalidate an action,
	# and they do not influence the outcome.
	var a: MatchState = QaUtil.flat_state([400, 1200])
	var b: MatchState = QaUtil.flat_state([400, 1200])
	var act: Dictionary = QaUtil.fire(0, 450, 700)
	var act2: Dictionary = act.duplicate()
	act2["note"] = "hello"
	act2["extra"] = [1, 2, 3]
	act2["power2"] = 5
	assert_eq(Simulation.validate_action(a, act2), "")
	var ev_a: Array[Dictionary] = Simulation.apply_action(a, act)
	var ev_b: Array[Dictionary] = Simulation.apply_action(b, act2)
	assert_eq(QaUtil.events_digest(ev_a), QaUtil.events_digest(ev_b))
	assert_eq(Simulation.fingerprint(a), Simulation.fingerprint(b))
	assert_false((ev_b[0] as Dictionary).has("note"), "extras are not echoed into events")


func test_json_roundtripped_actions_are_rejected_documented_behaviour() -> void:
	# JSON has one number type: Godot parses 452 back as float 452.0, which validate_action rejects
	# (bad_field). Anything that loads actions from JSON (saves, Firebase) must convert to int first.
	var s: MatchState = QaUtil.flat_state([400, 1200])
	var parsed: Variant = JSON.parse_string(JSON.stringify(QaUtil.fire(0, 452, 610)))
	assert_eq(typeof(parsed), TYPE_DICTIONARY)
	var d: Dictionary = parsed
	assert_eq(typeof(d["angle"]), TYPE_FLOAT, "JSON gives floats")
	assert_eq(Simulation.validate_action(s, d), "bad_field")
	assert_eq(Simulation.validate_action(s, Simulation.normalize_action(d)), "", "normalize_action (M3) fixes it")
	var fixed: Dictionary = {"kind": d["kind"], "tank": int(d["tank"]), "angle": int(d["angle"]),
			"power": int(d["power"]), "weapon": d["weapon"]}
	assert_eq(Simulation.validate_action(s, fixed), "")


func test_validate_does_not_mutate_the_action_or_state() -> void:
	var s: MatchState = QaUtil.flat_state([400, 1200])
	var a: Dictionary = QaUtil.fire(0, 450, 500)
	a["x"] = 1
	var copy: Dictionary = a.duplicate(true)
	var before: String = Simulation.fingerprint(s)
	Simulation.validate_action(s, a)
	assert_eq(a, copy)
	assert_eq(Simulation.fingerprint(s), before)
	Simulation.apply_action(s, a)
	assert_eq(a, copy, "apply_action does not modify the caller's dictionary")


func test_error_precedence() -> void:
	var s: MatchState = QaUtil.flat_state([400, 1200])
	# not_your_turn is reported before range errors; bad_tank before not_your_turn
	assert_eq(Simulation.validate_action(s, QaUtil.fire(1, -5, 5000)), "not_your_turn")
	assert_eq(Simulation.validate_action(s, QaUtil.fire(-1, -5, 5000)), "bad_tank")
	s.phase = SimConstants.PHASE_MATCH_OVER
	assert_eq(Simulation.validate_action(s, {"kind": "fire"}), "bad_phase", "phase is checked before fields")
	assert_eq(Simulation.validate_action(s, {"kind": "dance"}), "unknown_kind", "kind is checked before phase")
