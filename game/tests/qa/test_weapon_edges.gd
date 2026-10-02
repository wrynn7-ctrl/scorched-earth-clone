@warning_ignore_start("integer_division")
extends GutTest
## Adversarial weapon edge cases (docs/ARCHITECTURE.md section 21 and the M3-C2 resolutions in
## section 26). Every shot goes through _fire(), which also runs the independent economy audit,
## the timeline-order check, the state invariants and the show-layer terrain replay.

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M3 = preload("res://tests/qa/qa_m3.gd")


func _bug(ok: bool, desc: String) -> void:
	if ok:
		pass_test("bug no longer reproduces (remove the pending guard): %s" % desc)
	else:
		pending("BUG: %s" % desc)


# --- helpers --------------------------------------------------------------------------------------

func _flat(xs: Array[int], ground_y: int = 600) -> MatchState:
	var s: MatchState = QaUtil.flat_state(xs, ground_y)
	for t: TankState in s.tanks:
		t.money = 10000
	return s


## Terrain whose surface at column x is ground.call(x); pads under the tanks are levelled.
func _shaped(xs: Array[int], ground: Callable) -> MatchState:
	var s: MatchState = _flat(xs, 600)
	for x: int in range(SimConstants.WORLD_W):
		var y: int = ground.call(x)
		if y != 600:
			s.terrain.flatten(x, x, y)
	for t: TankState in s.tanks:
		_place(s, t.id, t.x)
	return s


func _place(state: MatchState, id: int, x: int) -> void:
	var t: TankState = state.tanks[id]
	t.x = x
	var half: int = SimConstants.TANK_W / 2
	state.terrain.flatten(x - half, x + half - 1, state.terrain.surface_y(x))
	t.y = TankState.rest_y(state.terrain, x)


func _set_solid(t: Terrain, x0: int, x1: int, y0: int, y1: int) -> void:
	for x: int in range(x0, x1):
		for y: int in range(y0, y1):
			t.cells[x * t.height + y] = 1


func _check(snap: Dictionary, before: Terrain, state: MatchState, action: Dictionary, ev: Array[Dictionary], tag: String) -> void:
	var errs: Array[String] = M3.audit(snap, state, action, ev)
	errs.append_array(M3.check_timeline(action, ev))
	errs.append_array(M3.check_state(state))
	assert_eq(errs, [] as Array[String], "%s: invariants" % tag)
	if before != null:
		assert_true(WeaponTestUtil.replay_matches(before, ev, state.terrain), "%s: show-layer terrain replay matches" % tag)


## Fires for the current tank (stock topped up) with all the checks. Returns the timeline.
func _fire(state: MatchState, weapon: String, angle: int, power: int, tag: String = "") -> Array[Dictionary]:
	var t: TankState = state.tanks[state.current_tank]
	var unlimited: bool = WeaponDefs.get_def(weapon).get("unlimited", false)
	if not unlimited:
		t.set_stock(weapon, maxi(1, t.stock_of(weapon)))
	var action: Dictionary = {"kind": "fire", "tank": t.id, "angle": angle, "power": power, "weapon": weapon}
	var snap: Dictionary = M3.snapshot(state)
	var before: Terrain = state.terrain.duplicate_terrain()
	var ev: Array[Dictionary] = Simulation.apply_action(state, action)
	assert_gt(ev.size(), 0, "%s: %s fired (%s)" % [tag, weapon, Simulation.validate_action(state, action)])
	if ev.is_empty():
		return ev
	_check(snap, before, state, action, ev, "%s %s a%d p%d" % [tag, weapon, angle, power])
	return ev


## Angle/power (angles x coarse power scan, then a fine scan) whose PLAIN shell (pulse_missile physics) ends with
## `reason` within `tol` columns of target_x, as close as possible. Returns Vector2i(angle, power) or (-1, -1).
func _find_shot(state: MatchState, shooter: int, angles: Array, target_x: int, tol: int, reason: String = "terrain") -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = tol + 1
	for a: int in angles:
		var coarse: int = -1
		var coarse_d: int = 1 << 30
		for p: int in range(20, 1001, 10):
			var d: int = _miss(state, shooter, a, p, target_x, reason)
			if d < coarse_d:
				coarse_d = d
				coarse = p
		if coarse < 0:
			continue
		for p: int in range(maxi(1, coarse - 10), mini(1000, coarse + 10) + 1):
			var d2: int = _miss(state, shooter, a, p, target_x, reason)
			if d2 < best_d:
				best_d = d2
				best = Vector2i(a, p)
		if best_d == 0:
			return best
	return best


func _miss(state: MatchState, shooter: int, angle: int, power: int, target_x: int, reason: String) -> int:
	var tr: Dictionary = Ballistics.trace(state, shooter, angle, power, "pulse_missile", SimConstants.WIND_USE_STATE,
			SimConstants.MAX_FLIGHT_TICKS)
	if tr["end_reason"] != reason:
		return 1 << 30
	return absi((tr["end_x"] as int) - target_x)


func _of_type(ev: Array[Dictionary], type: String) -> Array[Dictionary]:
	return QaUtil.find(ev, type)


func _solid(t: Terrain) -> int:
	return WeaponTestUtil.solid_count(t)


# --- splitter --------------------------------------------------------------------------------------

func test_splitter_apex_above_the_top_of_the_map() -> void:
	for weapon: String in ["prism_splitter", "prism_cascade"]:
		var s: MatchState = _flat([300, 1200] as Array[int])
		var children: int = WeaponDefs.get_def(weapon)["children"]
		var ev: Array[Dictionary] = _fire(s, weapon, 900, 1000, "apex above map")
		var ends: Array[Dictionary] = _of_type(ev, "projectile_end")
		assert_eq(ends.size(), children + 1, "%s: main shell + every child ends" % weapon)
		assert_eq(ends[0]["id"], 0)
		assert_eq(ends[0]["reason"], "split")
		assert_lt(ends[0]["y"], 0, "%s: the apex is above the top of the map (y < 0)" % weapon)
		var path: PackedInt32Array = _of_type(ev, "projectile")[0]["path"]
		var min_y: int = 0
		for i: int in range(1, path.size(), 2):
			min_y = mini(min_y, path[i])
		assert_lt(FixedMath.to_cell(min_y), -100, "%s: the shell really flew far above the map" % weapon)
		var ids: Array[int] = []
		for e: Dictionary in _of_type(ev, "projectile"):
			ids.append(e["id"])
		var want_ids: Array[int] = []
		for i: int in range(children + 1):
			want_ids.append(i)
		assert_eq(ids, want_ids, "%s: projectile ids in order" % weapon)
		var impacts: int = 0
		for e: Dictionary in ends.slice(1):
			assert_true(["terrain", "tank", "lost", "shield", "timeout"].has(e["reason"]))
			assert_gte(e["y"], 0, "%s: a child that landed is back on the map" % weapon)
			if e["reason"] != "lost" and e["reason"] != "timeout":
				impacts += 1
		assert_eq(_of_type(ev, "explosion").size(), impacts, "%s: one explosion per child that struck something" % weapon)


## Children spawned right next to a side wall: the ones that drift out are lost (no explosion).
func test_splitter_children_lost_near_the_side_walls() -> void:
	for side: int in [0, 1]:
		var x: int = 70 if side == 0 else 1530
		var angles: Array = range(1500, 1790, 25) if side == 0 else range(10, 300, 25)
		var s: MatchState = _flat([x, 800] as Array[int]) if side == 0 else _flat([800, x] as Array[int])
		var me: int = 0 if side == 0 else 1
		s.current_tank = me
		var found: Vector2i = Vector2i(-1, -1)
		var lost_children: int = 0
		for a: int in angles:
			for p: int in range(60, 1001, 20):
				var kids: Array[Dictionary] = Ballistics.trace_children(s, me, a, p, "prism_splitter", SimConstants.WIND_USE_STATE,
						SimConstants.MAX_FLIGHT_TICKS)
				if kids.is_empty():
					continue
				var lost: int = 0
				for k: Dictionary in kids:
					if k["end_reason"] == "lost":
						lost += 1
				if lost >= 1 and lost < kids.size():
					found = Vector2i(a, p)
					lost_children = lost
					break
			if found.x >= 0:
				break
		assert_ne(found.x, -1, "side %d: some shot leaves part of the children outside the map" % side)
		if found.x < 0:
			continue
		var ev: Array[Dictionary] = _fire(s, "prism_splitter", found.x, found.y, "wall side %d" % side)
		var lost_n: int = 0
		var impacts: int = 0
		for e: Dictionary in _of_type(ev, "projectile_end").slice(1):
			if e["reason"] == "lost":
				lost_n += 1
			elif e["reason"] == "terrain" or e["reason"] == "tank" or e["reason"] == "shield":
				impacts += 1
		# The preview (trace_children) flies every child against the CURRENT terrain; the real children
		# fly against the craters their siblings left (section 26), so more of them may leave the map.
		assert_gte(lost_n, lost_children, "side %d: the real shot loses at least the children the preview loses" % side)
		assert_eq(_of_type(ev, "explosion").size(), impacts, "side %d: lost children do not explode" % side)
		assert_gte(impacts, 1)


# --- roller ------------------------------------------------------------------------------------------

func test_roller_on_flat_ground_does_not_roll() -> void:
	for weapon: String in ["glide_orb", "heavy_orb"]:
		var s: MatchState = _flat([200, 1300] as Array[int])
		var p: int = WeaponTestUtil.power_for_landing(s, 450, 800)
		var tr: Dictionary = WeaponTestUtil.plain_trace(s, 450, p)
		assert_eq(tr["end_reason"], "terrain")
		var ev: Array[Dictionary] = _fire(s, weapon, 450, p, "flat roller")
		var proj: Dictionary = _of_type(ev, "projectile")[0]
		var end: Dictionary = _of_type(ev, "projectile_end")[0]
		assert_eq(end["x"], tr["end_x"], "%s stays in its impact column on level ground" % weapon)
		assert_eq((proj["path"] as PackedInt32Array).size(), (tr["path"] as PackedInt32Array).size() + 2,
				"%s: exactly one extra path point (it settles onto the surface)" % weapon)
		assert_eq(end["tick"], (tr["ticks"] as int) + 1)
		assert_eq(end["reason"], "terrain")


func test_roller_stops_at_max_roll_on_an_endless_gentle_slope() -> void:
	var s: MatchState = _shaped([100, 1500] as Array[int], func(x: int) -> int: return 200 + x / 3)
	var p: int = WeaponTestUtil.power_for_landing(s, 600, 330)
	var tr: Dictionary = WeaponTestUtil.plain_trace(s, 600, p)
	assert_eq(tr["end_reason"], "terrain")
	var ev: Array[Dictionary] = _fire(s, "glide_orb", 600, p, "slope roller")
	var end: Dictionary = _of_type(ev, "projectile_end")[0]
	var ticks_rolling: int = (end["tick"] as int) - (tr["ticks"] as int) - 1
	assert_eq(ticks_rolling, 400, "rolls exactly max_roll ticks and no longer")
	assert_eq((end["x"] as int) - (tr["end_x"] as int), 400, "glide orb moves 1 cell per tick")
	# Heavy orb: 2 cells per tick, same tick cap.
	var s2: MatchState = _shaped([100, 1500] as Array[int], func(x: int) -> int: return 200 + x / 3)
	var ev2: Array[Dictionary] = _fire(s2, "heavy_orb", 600, p, "slope heavy roller")
	var end2: Dictionary = _of_type(ev2, "projectile_end")[0]
	assert_eq((end2["tick"] as int) - (tr["ticks"] as int) - 1, 400)
	assert_eq((end2["x"] as int) - (tr["end_x"] as int), 800)


func test_roller_rolls_into_a_tank_and_explodes_on_contact() -> void:
	var ground: Callable = func(x: int) -> int:
		if x < 400:
			return 500
		if x < 800:
			return 500 + (x - 400) / 2
		return 700
	var s: MatchState = _shaped([100, 840] as Array[int], ground)
	var p: int = WeaponTestUtil.power_for_landing(s, 500, 450)
	var ev: Array[Dictionary] = _fire(s, "glide_orb", 500, p, "roller into tank")
	var end: Dictionary = _of_type(ev, "projectile_end")[0]
	assert_eq(end["reason"], "tank", "the roller ends on contact with the tank")
	assert_gte(end["x"], 828, "inside tank 1's hit box")
	assert_lt(end["x"], 852)
	var dmg: Array[Dictionary] = _of_type(ev, "damage").filter(func(e: Dictionary) -> bool: return e["tank"] == 1 and e["cause"] == "explosion")
	assert_eq(dmg.size(), 1, "tank 1 is hit by the orb's blast")
	assert_lt(s.tanks[1].health, 100)


# --- tunneler ------------------------------------------------------------------------------------------

func test_bore_end_straight_down_stops_at_the_bottom_edge() -> void:
	var s: MatchState = _flat([200, 1300] as Array[int], 850)
	var end: Vector2i = TunnelerBehavior.bore_end(s, 800 << 16, 850 << 16, 0, 8 << 16, 180)
	assert_eq(end, Vector2i(800, 899), "straight down: the last cell above the map bottom")
	var end0: Vector2i = TunnelerBehavior.bore_end(s, 800 << 16, 850 << 16, 0, 0, 180)
	assert_eq(end0, Vector2i(800, 850), "zero velocity: no tunnel")
	var up: Vector2i = TunnelerBehavior.bore_end(s, 800 << 16, 850 << 16, 0, -(8 << 16), 180)
	assert_eq(up, Vector2i(800, 670), "straight up: full length")
	var left: Vector2i = TunnelerBehavior.bore_end(s, 50 << 16, 850 << 16, -(8 << 16), 0, 180)
	assert_eq(left, Vector2i(0, 850), "toward the left wall: stops at the edge")
	var right: Vector2i = TunnelerBehavior.bore_end(s, 1550 << 16, 850 << 16, 8 << 16, 0, 180)
	assert_eq(right, Vector2i(1599, 850))


func test_tunneler_steeply_down_to_bedrock_keeps_everything_in_bounds() -> void:
	for weapon: String in ["bore_shell", "deep_bore"]:
		var s: MatchState = _flat([100, 1500] as Array[int], 850)
		s.wind = 100  # drifts the shell away from the shooter so it comes down nearly vertically
		var shot: Vector2i = _find_shot(s, 0, [880, 900], 300, 60)
		assert_ne(shot.x, -1, "found a steep arc")
		var ev: Array[Dictionary] = _fire(s, weapon, shot.x, shot.y, "bore to bedrock")
		var tun: Array[Dictionary] = _of_type(ev, "tunnel")
		assert_eq(tun.size(), 1)
		assert_lte(tun[0]["y1"], 899, "tunnel ends inside the map")
		assert_gt(tun[0]["y1"], tun[0]["y0"], "digs downward")
		assert_eq(s.terrain.cells.size(), SimConstants.WORLD_W * SimConstants.WORLD_H)
		assert_eq(s.terrain.get_cell(tun[0]["x1"], 900), Terrain.BEDROCK, "below the map is still bedrock")


func test_tunnel_horizontally_through_a_wall_stops_before_a_tank() -> void:
	var s: MatchState = _flat([100, 330] as Array[int])
	_set_solid(s.terrain, 200, 260, 500, 600)  # a wall in front of tank 1
	var ev: Array[Dictionary] = _fire(s, "deep_bore", 0, 1000, "bore through wall")
	var end: Dictionary = _of_type(ev, "projectile_end")[0]
	assert_eq(end["reason"], "terrain")
	var tun: Dictionary = _of_type(ev, "tunnel")[0]
	assert_lt(tun["x1"], 318, "the tunnel stops before tank 1's box [318, 342)")
	assert_gte(tun["x1"], 310, "...but right at it")
	var dmg: Array[Dictionary] = _of_type(ev, "damage").filter(func(e: Dictionary) -> bool: return e["tank"] == 1)
	assert_eq(dmg.size(), 1, "the end blast reaches the tank it stopped at")
	assert_eq(_of_type(ev, "explosion")[0]["x"], tun["x1"])
	# The tank is not carved out of its box by the tunnel.
	assert_true(s.tanks[1].alive or s.tanks[1].health == 0)
	# Direct function check with a horizontal line through the tank's box.
	var t: MatchState = _flat([100, 400] as Array[int])
	var end_cell: Vector2i = TunnelerBehavior.bore_end(t, 330 << 16, 595 << 16, 5 << 16, 0, 80)
	assert_eq(end_cell, Vector2i(387, 595), "stops on the last cell before the box [388, 412)")
	t.tanks[1].alive = false
	var through: Vector2i = TunnelerBehavior.bore_end(t, 330 << 16, 595 << 16, 5 << 16, 0, 80)
	assert_eq(through, Vector2i(410, 595), "a dead tank does not block")


# --- dirt ---------------------------------------------------------------------------------------------

func test_dirt_on_a_tank_buries_it_then_it_bursts_at_the_muzzle_and_digs_out() -> void:
	var s: MatchState = _flat([200, 700] as Array[int])
	var p: int = WeaponTestUtil.power_for_landing(s, 450, 700)
	var ev: Array[Dictionary] = _fire(s, "landslide", 450, p, "bury")
	assert_eq(_of_type(ev, "terrain_add").size(), 1)
	var t1: TankState = s.tanks[1]
	assert_true(t1.alive, "burying does no damage")
	assert_eq(t1.y, 600, "the tank stays where it was")
	var cells: int = WeaponTestUtil.solid_in_box(s.terrain, t1)
	assert_gt(cells, 0, "dirt settled into the tank's box (%d cells)" % cells)
	assert_eq(s.current_tank, 1)
	assert_eq(M3.check_state(s), [] as Array[String], "a buried tank is a legal state")
	# It fires: the shell is born inside dirt and bursts at the muzzle.
	var burst: Array[Dictionary] = _fire(s, "pulse_missile", 1350, 500, "buried tank fires")
	var end: Dictionary = _of_type(burst, "projectile_end")[0]
	assert_eq(end["reason"], "terrain")
	assert_lte(end["tick"], 2, "bursts at the muzzle")
	assert_lt(absi((end["x"] as int) - t1.x), 20)
	assert_lt(absi((end["y"] as int) - (t1.y - 12)), 20)
	assert_lt(t1.health, 100, "its own burst hurts it")
	# Dig out over several turns (tank 0 passes in between).
	var turns: int = 0
	while WeaponTestUtil.solid_in_box(s.terrain, t1) > 0 and turns < 30 and s.phase == SimConstants.PHASE_AIM:
		turns += 1
		if s.current_tank == 0:
			Simulation.apply_action(s, {"kind": "pass", "tank": 0})
		var angle: int = 1350 if turns % 2 == 0 else 900
		t1.health = 100  # keep it alive: this test is about digging, not dying
		_fire(s, "hyperpulse" if turns % 3 == 0 else "pulse_missile", angle, 400 + 10 * turns, "dig %d" % turns)
	assert_eq(WeaponTestUtil.solid_in_box(s.terrain, t1), 0, "the tank dug itself out within %d turns" % turns)
	gut.p("buried tank freed after %d firing turns" % turns)


# --- sludge --------------------------------------------------------------------------------------------

func test_sludge_into_a_deep_narrow_pit_stays_in_the_pit() -> void:
	var s: MatchState = _shaped([100, 1400] as Array[int], func(x: int) -> int: return 800 if x >= 790 and x < 810 else 400)
	var shot: Vector2i = _find_shot(s, 0, range(500, 900, 25), 800, 12)
	assert_ne(shot.x, -1, "a shot that lands in the pit")
	var solid_before: int = _solid(s.terrain)
	var ev: Array[Dictionary] = _fire(s, "sludge_shell", shot.x, shot.y, "pit")
	var pour: Array[Dictionary] = _of_type(ev, "terrain_pour")
	assert_eq(pour.size(), 1)
	var cols: PackedInt32Array = pour[0]["cells"]
	assert_eq(cols.size(), 1800, "every cell of the 1800 landed")
	for c: int in cols:
		if c < 790 or c > 809:
			fail_test("sludge cell escaped the pit at column %d" % c)
			break
	assert_eq(_solid(s.terrain) - solid_before, 1800)
	assert_eq(s.terrain.surface_y(800), 800 - 90, "1800 cells over 20 columns fill 90 rows")
	assert_eq(s.terrain.surface_y(789), 400, "the rim is untouched")


func test_sludge_on_a_flat_map_spreads_a_film_of_at_most_300_columns_per_side() -> void:
	var s: MatchState = _flat([100, 1400] as Array[int])
	var shot: Vector2i = _find_shot(s, 0, range(450, 800, 25), 800, 12)
	assert_ne(shot.x, -1)
	var ev: Array[Dictionary] = _fire(s, "sludge_shell", shot.x, shot.y, "flat sludge")
	var pour: Dictionary = _of_type(ev, "terrain_pour")[0]
	var ex: int = _of_type(ev, "projectile_end")[0]["x"]
	var cols: PackedInt32Array = pour["cells"]
	var lo: int = 9999
	var hi: int = -1
	for c: int in cols:
		lo = mini(lo, c)
		hi = maxi(hi, c)
	assert_gte(lo, ex - 300, "never more than 300 columns to the left of the impact")
	assert_lte(hi, ex + 300, "never more than 300 columns to the right of the impact")
	assert_gt(hi - lo, 20, "it really spreads out on level ground (%d..%d around %d)" % [lo, hi, ex])
	assert_eq(cols.size(), 1800)
	assert_gt(600 - s.terrain.surface_y(ex), 0, "a film of sludge covers the impact column")
	assert_lt(600 - s.terrain.surface_y(ex), 60, "but it is a film, not a mound")


func test_sludge_at_the_map_edge_stays_inside_the_map() -> void:
	for side: int in [0, 1]:
		var xs: Array[int] = [160, 800]
		if side == 1:
			xs = [800, 1440]
		var s: MatchState = _flat(xs)
		s.current_tank = 0 if side == 0 else 1
		var target: int = 6 if side == 0 else 1593
		var angles: Array = range(1400, 1800, 20) if side == 0 else range(0, 400, 20)
		var shot: Vector2i = _find_shot(s, s.current_tank, angles, target, 12)
		assert_ne(shot.x, -1, "side %d: a shot that lands next to the wall" % side)
		if shot.x < 0:
			continue
		var before: int = _solid(s.terrain)
		var ev: Array[Dictionary] = _fire(s, "sludge_shell", shot.x, shot.y, "edge sludge %d" % side)
		var cols: PackedInt32Array = _of_type(ev, "terrain_pour")[0]["cells"]
		for c: int in cols:
			if c < 0 or c >= SimConstants.WORLD_W:
				fail_test("sludge cell outside the map: %d" % c)
				break
		assert_eq(_solid(s.terrain) - before, cols.size())


# --- fire ---------------------------------------------------------------------------------------------

func test_fire_flames_rest_on_the_surface_of_a_steep_slope() -> void:
	var s: MatchState = _shaped([100, 1000] as Array[int], func(x: int) -> int: return 300 if x < 200 else mini(880, 300 + (x - 200)))
	var shot: Vector2i = _find_shot(s, 0, range(300, 800, 25), 400, 10)
	assert_ne(shot.x, -1)
	var ev: Array[Dictionary] = _fire(s, "inferno_gel", shot.x, shot.y, "steep fire")
	var pts: PackedInt32Array = _of_type(ev, "flames")[0]["points"]
	assert_eq(pts.size(), 220, "110 points x (x, y)")
	var lowest: int = 0
	for i: int in range(0, pts.size(), 2):
		var x: int = pts[i]
		var y: int = pts[i + 1]
		assert_true(x >= 0 and x < SimConstants.WORLD_W, "flame x on the map")
		assert_false(s.terrain.is_solid(x, y), "flame cell (%d,%d) is in the air" % [x, y])
		assert_true(y + 1 >= SimConstants.WORLD_H or s.terrain.is_solid(x, y + 1), "...resting on the ground")
		lowest = maxi(lowest, y)
	assert_gt(lowest, 700, "flames ran far down the slope")
	assert_eq(_of_type(ev, "terrain_carve").size(), 0, "fire does not change the terrain")


func test_fire_on_flat_ground_caps_damage_per_tank() -> void:
	for weapon: String in ["ember_rain", "inferno_gel"]:
		var cap: int = WeaponDefs.get_def(weapon)["cap"]
		var s: MatchState = _flat([100, 700] as Array[int])
		var p: int = WeaponTestUtil.power_for_landing(s, 450, 700)
		var ev: Array[Dictionary] = _fire(s, weapon, 450, p, "flat fire")
		var burn: Array[Dictionary] = _of_type(ev, "damage").filter(func(e: Dictionary) -> bool: return e["cause"] == "burn")
		assert_eq(burn.size(), 1, "%s: one damage event for the tank under it" % weapon)
		assert_eq(burn[0]["amount"], cap, "%s: capped at %d" % [weapon, cap])
		assert_eq(s.tanks[1].health, 100 - cap)
		assert_eq(s.tanks[0].money, 10000 + cap * 15, "%s: credit for the capped HP" % weapon)


func test_fire_cluster_of_tanks_each_capped_once() -> void:
	var s: MatchState = _flat([100, 700, 724, 748, 772] as Array[int])
	var p: int = WeaponTestUtil.power_for_landing(s, 450, 736)
	var ev: Array[Dictionary] = _fire(s, "inferno_gel", 450, p, "cluster fire")
	var seen: Dictionary = {}
	for e: Dictionary in _of_type(ev, "damage"):
		if e["cause"] != "burn":
			continue
		assert_false(seen.has(e["tank"]), "tank %d got more than one burn event" % e["tank"])
		seen[e["tank"]] = e["amount"]
		assert_lte(e["amount"], 70, "per-tank cap of Inferno Gel")
	assert_gte(seen.size(), 2, "several clustered tanks burn")
	assert_eq(_of_type(ev, "flames").size(), 1)
	var capped: int = 0
	for k: int in seen:
		if seen[k] == 70:
			capped += 1
	assert_gte(capped, 1, "at least one tank hit the cap exactly (%s)" % str(seen))
	# A second helping from the next shooter finishes weakened tanks: credits stay at 15 per HP actually removed
	# (the audit inside _fire checks this).
	s.current_tank = 0
	_fire(s, "inferno_gel", 450, p, "cluster fire 2")


# --- seeker ----------------------------------------------------------------------------------------------

func test_seeker_with_no_living_enemy_flies_like_a_plain_shell() -> void:
	var s: MatchState = _flat([300, 900] as Array[int])
	s.tanks[1].alive = false
	s.tanks[1].health = 0
	var plain: Dictionary = Ballistics.trace(s, 0, 1200, 700, "pulse_missile", SimConstants.WIND_USE_STATE, 1500)
	var seek: Dictionary = Ballistics.trace(s, 0, 1200, 700, "seeker", SimConstants.WIND_USE_STATE, 1500)
	assert_eq(seek["path"], plain["path"], "no target: no homing")
	assert_eq(seek["end_reason"], plain["end_reason"])
	var ev: Array[Dictionary] = _fire(s, "seeker", 1200, 700, "seeker without enemies")
	assert_eq(_of_type(ev, "round_end").size(), 1, "the lone survivor wins")


func test_seeker_ignores_teammates_and_itself() -> void:
	# All tanks on the shooter's team: nobody to home on (team == id today, so this is hand-built).
	var s: MatchState = _flat([300, 650, 1200] as Array[int])
	for t: TankState in s.tanks:
		t.team = 0
	var plain: Dictionary = Ballistics.trace(s, 0, 450, 600, "pulse_missile", SimConstants.WIND_USE_STATE, 1500)
	var seek: Dictionary = Ballistics.trace(s, 0, 450, 600, "seeker", SimConstants.WIND_USE_STATE, 1500)
	assert_eq(seek["path"], plain["path"], "all teammates: no homing")
	# Teammate nearest, enemy farther: it homes on the enemy only (path differs from plain, bends toward x=1200).
	s.tanks[2].team = 2
	var seek2: Dictionary = Ballistics.trace(s, 0, 450, 600, "seeker", SimConstants.WIND_USE_STATE, 1500)
	assert_ne(seek2["path"], plain["path"], "it homes on the enemy")
	assert_gt(seek2["end_x"], plain["end_x"] - 1, "pulled toward the enemy on the right")
	var ev: Array[Dictionary] = _fire(s, "seeker", 450, 600, "seeker with a teammate")
	assert_eq(_of_type(ev, "projectile").size(), 1)


func test_team_damage_counts_as_self_damage() -> void:
	var s: MatchState = _flat([300, 700, 1200] as Array[int])
	s.tanks[1].team = 0
	s.tanks[1].health = 1
	var kills: int = s.tanks[0].kills
	var money: int = s.tanks[0].money
	var p: int = WeaponTestUtil.power_for_landing(s, 450, 700)
	var ev: Array[Dictionary] = _fire(s, "pulse_missile", 450, p, "friendly fire")
	assert_false(s.tanks[1].alive, "the teammate died")
	assert_eq(s.tanks[0].kills, kills, "killing a teammate is not a kill")
	assert_eq(s.tanks[0].damage_dealt, 0, "nor damage dealt")
	for e: Dictionary in _of_type(ev, "money"):
		if e["tank"] == 0:
			assert_eq(e["reason"], "self_damage")
	assert_lt(s.tanks[0].money, money)


# --- beam -----------------------------------------------------------------------------------------------

func test_beam_straight_up_leaves_the_map() -> void:
	var s: MatchState = _flat([300, 900] as Array[int])
	var ev: Array[Dictionary] = _fire(s, "photon_lance", 900, 500, "beam up")
	var beam: Dictionary = _of_type(ev, "beam")[0]
	assert_eq(beam["x0"], 300)
	assert_eq(beam["x1"], 300)
	assert_eq(beam["y0"], 588 - 14)
	assert_eq(beam["y1"], -1, "ends at the first cell above the top")
	for type: String in ["tunnel", "damage", "explosion", "terrain_settle", "projectile"]:
		assert_eq(_of_type(ev, type).size(), 0, "straight up: no %s" % type)
	assert_eq(QaUtil.types(ev), ["fire", "beam", "wind", "turn"] as Array[String])


func test_beam_along_the_ground_hits_a_tank_in_range_and_misses_one_beyond() -> void:
	# Angle 0 from a tank on flat ground: the muzzle row is the top row of every tank box.
	var s: MatchState = _flat([300, 900] as Array[int])
	var ev: Array[Dictionary] = _fire(s, "photon_lance", 0, 1, "beam along ground")
	var dmg: Array[Dictionary] = _of_type(ev, "damage")
	assert_eq(dmg.size(), 1)
	assert_eq(dmg[0]["tank"], 1)
	assert_eq(dmg[0]["amount"], 35)
	assert_eq(dmg[0]["cause"], "beam")
	assert_eq(_of_type(ev, "beam")[0]["x1"], 888, "stops at the box edge")
	assert_eq(_of_type(ev, "tunnel").size(), 0, "no ground crossed")
	var s2: MatchState = _flat([300, 1500] as Array[int])
	var ev2: Array[Dictionary] = _fire(s2, "photon_lance", 0, 1, "beam short of tank")
	assert_eq(_of_type(ev2, "damage").size(), 0, "tank 1 is beyond the 900-cell reach")
	assert_eq(_of_type(ev2, "beam")[0]["x1"], 314 + 900)
	var left: MatchState = _flat([100, 900] as Array[int])
	var ev3: Array[Dictionary] = _fire(left, "photon_lance", 1800, 1, "beam left off the map")
	assert_eq(_of_type(ev3, "beam")[0]["x1"], -1)
	assert_eq(_of_type(ev3, "damage").size(), 0)


func test_beam_cuts_at_most_120_cells_through_a_wall() -> void:
	var s: MatchState = _flat([100, 700] as Array[int])
	_set_solid(s.terrain, 200, 500, 500, 600)  # 300 cells thick
	var ev: Array[Dictionary] = _fire(s, "photon_lance", 0, 1, "beam through wall")
	var tun: Dictionary = _of_type(ev, "tunnel")[0]
	assert_eq(tun["x0"], 200)
	assert_eq(tun["x1"], 200 + 119, "120 solid cells, then it stops")
	assert_eq(_of_type(ev, "damage").size(), 0, "the tank behind the wall is safe")
	assert_eq(_of_type(ev, "beam")[0]["x1"], 319)


func test_beam_into_a_shield() -> void:
	# Glow Shield (30 hp) absorbs 30 of the 35; 5 reach health.
	var s: MatchState = _flat([300, 700] as Array[int])
	s.tanks[1].shield_type = Catalog.index_of("glow_shield")
	s.tanks[1].shield_hp = 30
	var money: int = s.tanks[0].money
	var ev: Array[Dictionary] = _fire(s, "photon_lance", 0, 1, "beam glow")
	assert_eq(QaUtil.types(ev), ["fire", "beam", "shield_hit", "shield_down", "damage", "money", "wind", "turn"] as Array[String])
	assert_eq(_of_type(ev, "shield_hit")[0]["absorbed"], 30)
	assert_eq(_of_type(ev, "damage")[0]["amount"], 5)
	assert_eq(s.tanks[1].health, 95)
	assert_eq(s.tanks[0].money, money + 5 * 15)
	assert_lt(_of_type(ev, "beam")[0]["x1"], 700 - 12, "stopped by the bubble, outside the tank box")
	# Ion Shield (60 hp) absorbs all 35: no damage, no money.
	var s2: MatchState = _flat([300, 700] as Array[int])
	s2.tanks[1].shield_type = Catalog.index_of("ion_shield")
	s2.tanks[1].shield_hp = 60
	var ev2: Array[Dictionary] = _fire(s2, "photon_lance", 0, 1, "beam ion")
	assert_eq(QaUtil.types(ev2), ["fire", "beam", "shield_hit", "wind", "turn"] as Array[String])
	assert_eq(s2.tanks[1].shield_hp, 25)
	assert_eq(s2.tanks[1].health, 100)
	assert_eq(s2.tanks[0].money, 10000, "absorbed damage earns nothing")
	assert_eq(QaUtil.find(ev2, "money").size(), 0)


# --- static --------------------------------------------------------------------------------------------

func test_static_on_a_tank_with_shield_and_repulsor_strips_both_before_damage() -> void:
	var base: MatchState = _flat([300, 800] as Array[int])
	base.tanks[1].shield_type = Catalog.index_of("glow_shield")
	base.tanks[1].shield_hp = 30
	base.tanks[1].repulsor_charge = 100
	var found: Vector2i = Vector2i(-1, -1)
	for a: int in range(300, 900, 50):
		for p: int in range(100, 1001, 25):
			var trial: MatchState = base.duplicate_state()
			trial.tanks[0].set_stock("static_burst", 1)
			var ev: Array[Dictionary] = Simulation.apply_action(trial, {"kind": "fire", "tank": 0, "angle": a, "power": p, "weapon": "static_burst"})
			var ts: Array[String] = QaUtil.types(ev)
			if ts.has("shield_down") and trial.tanks[1].repulsor_charge == 0 and not ts.has("round_end"):
				found = Vector2i(a, p)
				break
		if found.x >= 0:
			break
	assert_ne(found.x, -1, "a static burst that reaches a shielded, repulsing tank")
	if found.x < 0:
		return
	var s: MatchState = base.duplicate_state()
	var ev2: Array[Dictionary] = _fire(s, "static_burst", found.x, found.y, "static")
	var ts2: Array[String] = QaUtil.types(ev2)
	assert_eq(s.tanks[1].shield_hp, 0)
	assert_eq(s.tanks[1].shield_type, -1)
	assert_eq(s.tanks[1].repulsor_charge, 0)
	var explosion_at: int = ts2.find("explosion")
	var down_at: int = ts2.find("shield_down")
	var damage_at: int = ts2.find("damage")
	assert_lt(explosion_at, down_at)
	if damage_at >= 0:
		assert_lt(down_at, damage_at, "shields are stripped before damage is dealt")
	var hits: Array[Dictionary] = _of_type(ev2, "shield_hit")
	assert_eq(hits.size(), 0, "stripped, not damaged")


# --- wells -----------------------------------------------------------------------------------------------

func _pass_turn(s: MatchState) -> Array[Dictionary]:
	var ev: Array[Dictionary] = Simulation.apply_action(s, {"kind": "pass", "tank": s.current_tank})
	assert_gt(ev.size(), 0)
	return ev


func test_two_wells_from_two_owners_coexist_and_each_expires_after_two_cycles() -> void:
	var s: MatchState = _flat([200, 600, 1000] as Array[int])
	var fp_none: String = Simulation.fingerprint(s)
	var plain: Dictionary = Ballistics.trace(s, 2, 1350, 600, "pulse_missile", SimConstants.WIND_USE_STATE, 1500)
	_fire(s, "singularity_seed", 600, 450, "well A")
	assert_eq(s.wells.size(), 1)
	_fire(s, "singularity_seed", 600, 450, "well B")
	assert_eq(s.wells.size(), 2, "two owners, two wells")
	assert_eq([s.wells[0]["owner"], s.wells[1]["owner"]], [0, 1])
	assert_eq(s.wells[0]["expires_turn"], 0 + 2 * 3)
	assert_eq(s.wells[1]["expires_turn"], 1 + 2 * 3)
	assert_ne(Simulation.fingerprint(s), fp_none)
	assert_eq(M3.check_state(s), [] as Array[String])
	var bent: Dictionary = Ballistics.trace(s, 2, 1350, 600, "pulse_missile", SimConstants.WIND_USE_STATE, 1500)
	assert_ne(bent["path"], plain["path"], "the wells bend everyone's shells")
	# Tank 2 is next. Pass until each well goes; each must disappear exactly when turn_number reaches its expiry.
	var removed: Array[int] = []
	for i: int in range(12):
		if s.wells.is_empty():
			break
		var wells_before: Array[Dictionary] = s.wells.duplicate()
		var ev: Array[Dictionary] = _pass_turn(s)
		for e: Dictionary in _of_type(ev, "well_off"):
			removed.append(e["owner"])
			var w: Dictionary = wells_before.filter(func(d: Dictionary) -> bool: return d["owner"] == e["owner"])[0]
			assert_eq(s.turn_number, w["expires_turn"], "owner %d's well ends exactly at its expires_turn" % e["owner"])
		for w2: Dictionary in s.wells:
			assert_lt(s.turn_number, w2["expires_turn"], "a live well has not reached its expiry")
	assert_eq(removed, [0, 1] as Array[int], "A (created first) expires first, B one turn later")
	assert_eq(s.wells.size(), 0)


func test_well_expiry_is_fixed_at_creation_even_when_tanks_die_mid_cycle() -> void:
	var s: MatchState = _flat([200, 600, 1000] as Array[int])
	_fire(s, "singularity_seed", 600, 450, "well")
	var expires: int = s.wells[0]["expires_turn"]
	assert_eq(expires, 6)
	# Tanks 0 (the owner) and 2 die mid-cycle; tank 1 stays alive... only one alive ends the round, so keep 2 alive.
	s.tanks[2].alive = false
	s.tanks[2].health = 0
	var gone_at: int = -1
	for i: int in range(10):
		if s.wells.is_empty():
			gone_at = s.turn_number
			break
		_pass_turn(s)
	assert_eq(gone_at, expires, "the well is removed when turn_number reaches 6, whatever the survivors")
	# The owner dying does not remove the well either.
	var s2: MatchState = _flat([200, 600, 1000] as Array[int])
	_fire(s2, "singularity_seed", 600, 450, "well 2")
	s2.tanks[0].alive = false
	s2.tanks[0].health = 0
	_pass_turn(s2)
	assert_eq(s2.wells.size(), 1, "an owner's death does not cancel the well")


func test_wells_are_cleared_by_start_round_and_survive_into_the_shop() -> void:
	var s: MatchState = _flat([200, 600, 1000] as Array[int])
	_fire(s, "singularity_seed", 600, 450, "well")
	assert_eq(s.wells.size(), 1)
	s.tanks[1].alive = false
	s.tanks[1].health = 0
	s.tanks[2].alive = false
	s.tanks[2].health = 0
	s.current_tank = 0  # the survivor passes: the round ends
	_pass_turn(s)
	assert_eq(s.phase, SimConstants.PHASE_SHOP)
	assert_eq(s.wells.size(), 1, "wells linger (fingerprinted) until the next round starts")
	for t: TankState in s.tanks:
		Simulation.apply_action(s, {"kind": "ready", "tank": t.id})
	var start: Array[Dictionary] = Simulation.start_round(s)
	assert_eq(start.size(), 3)
	assert_eq(s.wells.size(), 0, "start_round clears the wells")


# --- anchor -----------------------------------------------------------------------------------------------

func test_anchor_drags_the_shooter_too() -> void:
	var s: MatchState = _flat([300, 1300] as Array[int])
	var shot: Vector2i = _find_shot(s, 0, range(300, 700, 25), 420, 3)
	assert_ne(shot.x, -1)
	var ev: Array[Dictionary] = _fire(s, "riptide_anchor", shot.x, shot.y, "anchor self")
	var drags: Array[Dictionary] = _of_type(ev, "tank_drag")
	assert_eq(drags.size(), 1, "only the shooter is near enough")
	assert_eq(drags[0]["tank"], 0)
	assert_eq(drags[0]["from_x"], 300)
	var ex: int = _of_type(ev, "projectile_end")[0]["x"]
	assert_eq(drags[0]["to_x"], mini(ex, 300 + 120), "dragged to the impact column, never past it, at most 120 cells")
	assert_eq(s.tanks[0].x, drags[0]["to_x"])
	assert_eq(_of_type(ev, "terrain_carve").size(), 0, "the anchor does not change terrain")


func test_anchor_on_a_fortress_shielded_tank_pulls_half_as_far() -> void:
	var result: Array[int] = []
	for variant: int in range(3):  # 0 = bare, 1 = fortress, 2 = glow (no resistance)
		var s: MatchState = _flat([100, 640] as Array[int])
		if variant == 1:
			s.tanks[1].shield_type = Catalog.index_of("fortress_field")
			s.tanks[1].shield_hp = 100
		elif variant == 2:
			s.tanks[1].shield_type = Catalog.index_of("glow_shield")
			s.tanks[1].shield_hp = 30
		var shot: Vector2i = _find_shot(s, 0, range(300, 700, 25), 480, 2)
		assert_ne(shot.x, -1)
		var ev: Array[Dictionary] = _fire(s, "riptide_anchor", shot.x, shot.y, "anchor variant %d" % variant)
		var drags: Array[Dictionary] = _of_type(ev, "tank_drag").filter(func(e: Dictionary) -> bool: return e["tank"] == 1)
		assert_eq(drags.size(), 1)
		result.append((drags[0]["from_x"] as int) - (drags[0]["to_x"] as int))
		if variant == 1:
			assert_eq(s.tanks[1].shield_hp, 100, "the pull does not damage the shield")
	assert_eq(result[0], 120, "bare tank: full 120-cell pull (160 cells away)")
	assert_eq(result[1], 60, "Fortress Field halves it")
	assert_eq(result[2], 120, "a Glow Shield gives no resistance")


func test_anchor_drags_two_tanks_toward_each_other_without_overlap() -> void:
	var s: MatchState = _flat([400, 440, 1000] as Array[int])
	s.current_tank = 2
	var shot: Vector2i = _find_shot(s, 2, range(1100, 1700, 20), 420, 5)
	assert_ne(shot.x, -1, "a shell that falls into the 16-cell gap between the two tanks")
	if shot.x < 0:
		return
	var ev: Array[Dictionary] = _fire(s, "riptide_anchor", shot.x, shot.y, "anchor squeeze")
	assert_gte(absi(s.tanks[0].x - s.tanks[1].x), SimConstants.TANK_W, "boxes never overlap")
	for d: Dictionary in _of_type(ev, "tank_drag"):
		assert_eq(s.tanks[d["tank"]].x, d["to_x"])
	# Lower id moves first and takes the space: tank 1 is then blocked by it.
	var ids: Array[int] = []
	for d: Dictionary in _of_type(ev, "tank_drag"):
		ids.append(d["tank"])
	assert_true(ids.has(0), "tank 0 (processed first) moves")


func test_anchor_drag_stops_at_a_step_taller_than_6_cells() -> void:
	var s: MatchState = _flat([100, 640] as Array[int])
	_set_solid(s.terrain, 560, 570, 590, 600)  # a 10-high step between the tank and the impact
	var shot: Vector2i = _find_shot(s, 0, range(300, 700, 25), 480, 2)
	assert_ne(shot.x, -1)
	var ev: Array[Dictionary] = _fire(s, "riptide_anchor", shot.x, shot.y, "anchor step")
	var drags: Array[Dictionary] = _of_type(ev, "tank_drag").filter(func(e: Dictionary) -> bool: return e["tank"] == 1)
	assert_eq(drags.size(), 1)
	assert_eq(drags[0]["to_x"], 582, "stops right before the box would climb the 10-cell step")
	assert_eq(s.tanks[1].y, 600)


# --- supernova at the corners ----------------------------------------------------------------------------

func test_supernova_next_to_the_side_walls() -> void:
	for side: int in [0, 1]:
		var xs: Array[int] = [300, 12]
		if side == 1:
			xs = [1300, 1588]
		var s: MatchState = _flat(xs)
		var target: int = 14 if side == 0 else 1585
		var angles: Array = [1800, 1700, 1600] if side == 0 else [0, 100, 200]
		var shot: Vector2i = _find_shot(s, 0, angles, target, 12, "tank")
		if shot.x < 0:
			shot = _find_shot(s, 0, angles, target, 12, "terrain")
		assert_ne(shot.x, -1, "side %d: a shell that lands at the wall" % side)
		if shot.x < 0:
			continue
		var ev: Array[Dictionary] = _fire(s, "supernova", shot.x, shot.y, "supernova wall %d" % side)
		assert_false(s.tanks[1].alive, "the tank in the corner is vaporised")
		var settle: Array[Dictionary] = _of_type(ev, "terrain_settle")
		assert_eq(settle.size(), 1)
		assert_gte(settle[0]["x0"], 0, "settle range clipped to the map")
		assert_lt(settle[0]["x1"], SimConstants.WORLD_W)
		assert_eq(s.terrain.cells.size(), SimConstants.WORLD_W * SimConstants.WORLD_H)


func test_blasts_at_the_corners_and_outside_the_map_do_not_crash() -> void:
	var spots: Array[Vector2i] = [Vector2i(0, 899), Vector2i(1599, 899), Vector2i(0, 0), Vector2i(1599, 0),
			Vector2i(-10, 450), Vector2i(1700, 450), Vector2i(800, 950), Vector2i(800, -300), Vector2i(-300, -300),
			Vector2i(0, 600), Vector2i(1599, 600), Vector2i(800, 900)]
	for spot: Vector2i in spots:
		var s: MatchState = _flat([12, 700, 1588] as Array[int])
		var before: Terrain = s.terrain.duplicate_terrain()
		var ev: Array[Dictionary] = []
		WeaponResolver.blast(s, 1, spot.x, spot.y, 160, 100, "supernova", 0, ev)
		s.phase = SimConstants.PHASE_SHOP  # a direct blast leaves no turn bookkeeping to check
		var errs: Array[String] = M3.check_state(s)
		assert_eq(errs, [] as Array[String], "blast at %s" % str(spot))
		assert_eq(s.terrain.cells.size(), SimConstants.WORLD_W * SimConstants.WORLD_H)
		assert_true(WeaponTestUtil.replay_matches(before, ev, s.terrain), "replay at %s" % str(spot))


# --- the whole catalog at the extremes ----------------------------------------------------------------------

func test_every_weapon_at_power_1_and_1000_and_angles_0_900_1800() -> void:
	var shots: int = 0
	var weapons: Array[String] = []
	for id: String in Catalog.IDS:
		if Catalog.is_weapon(id):
			weapons.append(id)
	assert_eq(weapons.size(), 21)
	var bases: Array[MatchState] = [_flat([100, 800, 1500] as Array[int]), _flat([12, 700, 1588] as Array[int])]
	for bi: int in range(bases.size()):
		for weapon: String in weapons:
			for power: int in [1, 1000]:
				for angle: int in [0, 900, 1800]:
					var s: MatchState = bases[bi].duplicate_state()
					var ev: Array[Dictionary] = _fire(s, weapon, angle, power, "matrix base %d" % bi)
					shots += 1
					assert_true(ev.size() >= 3 and ev[0]["type"] == "fire", "%s a%d p%d produced a timeline" % [weapon, angle, power])
	assert_eq(shots, 2 * 21 * 6)


# --- degenerate terrains --------------------------------------------------------------------------------

func _terrain_variant(kind: String) -> MatchState:
	var xs: Array[int] = [200, 800, 1400]
	match kind:
		"bedrock_floor":
			return _place_all(_flat(xs, 899), xs)
		"empty":
			return _place_all(_flat(xs, 900), xs)
		"full":
			return _place_all(_flat(xs, 0), xs)
		"almost_full":
			return _place_all(_flat(xs, 1), xs)
		"comb":
			var s: MatchState = _flat(xs, 600)
			for x: int in range(SimConstants.WORLD_W):
				s.terrain.flatten(x, x, 300 if x % 2 == 0 else 800)
			return _place_all(s, xs)
		"spikes":
			var s2: MatchState = _flat(xs, 600)
			for x: int in range(SimConstants.WORLD_W):
				s2.terrain.flatten(x, x, 100 if x % 40 < 3 else 700)
			return _place_all(s2, xs)
	return _flat(xs)


func _place_all(s: MatchState, xs: Array[int]) -> MatchState:
	for i: int in range(xs.size()):
		_place(s, i, xs[i])
	return s


func test_every_weapon_on_degenerate_terrains() -> void:
	var shots: int = 0
	for kind: String in ["bedrock_floor", "empty", "full", "almost_full", "comb", "spikes"]:
		var base: MatchState = _terrain_variant(kind)
		assert_eq(M3.check_state(base), [] as Array[String], "%s: the base state is legal" % kind)
		for id: String in Catalog.IDS:
			if not Catalog.is_weapon(id):
				continue
			for pa: Array in [[450, 1000], [1350, 300]]:
				var s: MatchState = base.duplicate_state()
				var ev: Array[Dictionary] = _fire(s, id, pa[0], pa[1], "terrain %s" % kind)
				shots += 1
				assert_true(ev.size() >= 3, "%s on %s produced a timeline" % [id, kind])
	assert_eq(shots, 6 * 21 * 2)


# --- the contract between preview, timeline and tick convention ---------------------------------------------

## Path / tick convention (section 26): projectile.path[i] is the position at tick event.tick + i + 1 and
## projectile_end.tick = event.tick + path.size() / 2, for every projectile id.
func _check_tick_convention(ev: Array[Dictionary], tag: String) -> void:
	var starts: Dictionary = {}
	for e: Dictionary in ev:
		if e["type"] == "projectile":
			starts[e["id"]] = [e["tick"], (e["path"] as PackedInt32Array).size() / 2]
		elif e["type"] == "projectile_end":
			assert_true(starts.has(e["id"]), "%s: projectile_end %d has a projectile" % [tag, e["id"]])
			if starts.has(e["id"]):
				assert_eq(e["tick"], (starts[e["id"]][0] as int) + (starts[e["id"]][1] as int), "%s: end tick of shell %d" % [tag, e["id"]])


func test_preview_trace_matches_the_real_flight_for_every_weapon() -> void:
	var checked: int = 0
	for scenario: int in range(3):
		var s: MatchState = _flat([300, 900, 1300] as Array[int])
		match scenario:
			1:
				s.wind = 100
				s.tanks[1].shield_type = Catalog.index_of("ion_shield")
				s.tanks[1].shield_hp = 60
				s.tanks[2].repulsor_charge = 100
			2:
				s.wind = -73
				s.wells.append({"owner": 1, "x": 700, "y": 400, "expires_turn": 99})
		for id: String in Catalog.IDS:
			if not Catalog.is_weapon(id):
				continue
			for pa: Array in [[450, 600], [1100, 800], [700, 300]]:
				var tr: Dictionary = Ballistics.trace(s, 0, pa[0], pa[1], id, SimConstants.WIND_USE_STATE, SimConstants.MAX_FLIGHT_TICKS)
				var fp_before: String = Simulation.fingerprint(s)
				var s2: MatchState = s.duplicate_state()
				var ev: Array[Dictionary] = _fire(s2, id, pa[0], pa[1], "preview s%d" % scenario)
				assert_eq(Simulation.fingerprint(s), fp_before, "%s: trace() does not touch the state" % id)
				_check_tick_convention(ev, "%s s%d" % [id, scenario])
				checked += 1
				if Catalog.get_def(id)["behavior"] == "beam":
					var beam: Dictionary = QaUtil.find(ev, "beam")[0]
					assert_eq([beam["x0"], beam["y0"], beam["x1"], beam["y1"]], [tr["start_x"], tr["start_y"], tr["end_x"], tr["end_y"]], "%s: beam preview" % id)
					continue
				var first: Dictionary = QaUtil.find(ev, "projectile")[0]
				var real: PackedInt32Array = first["path"]
				var prev: PackedInt32Array = tr["path"]
				assert_gte(real.size(), prev.size(), "%s s%d: the real path covers the preview" % [id, scenario])
				assert_eq(real.slice(0, prev.size()), prev, "%s s%d a%d p%d: the preview path is the real flight (prefix; rollers continue)" % [id, scenario, pa[0], pa[1]])
				if Catalog.get_def(id)["behavior"] == "splitter" and tr["end_reason"] == "apex":
					var kids: Array[Dictionary] = Ballistics.trace_children(s, 0, pa[0], pa[1], id, SimConstants.WIND_USE_STATE, SimConstants.MAX_FLIGHT_TICKS)
					var projs: Array[Dictionary] = QaUtil.find(ev, "projectile")
					assert_eq(projs.size(), kids.size() + 1)
					assert_eq(projs[1]["path"], kids[0]["path"], "%s: the first child is not affected by earlier craters" % id)
	assert_eq(checked, 3 * 21 * 3)


func test_terrain_event_payload_shapes() -> void:
	# Fields inside the nested payloads that QaUtil.check_event_fields does not look into.
	var s: MatchState = _flat([300, 800] as Array[int])
	var ev: Array[Dictionary] = _fire(s, "hyperpulse", 450, WeaponTestUtil.power_for_landing(s, 450, 800), "payload")
	for e: Dictionary in QaUtil.find(ev, "terrain_settle"):
		for f: Variant in (e["falls"] as Array):
			var fall: Dictionary = f as Dictionary
			for k: String in ["x", "from_y", "to_y", "length"]:
				assert_true(fall.has(k) and typeof(fall[k]) == TYPE_INT, "settle fall has int '%s'" % k)
	var s2: MatchState = _flat([300, 800] as Array[int])
	var ev2: Array[Dictionary] = _fire(s2, "mound_mortar", 450, WeaponTestUtil.power_for_landing(s2, 450, 800), "payload dirt")
	var add: Dictionary = QaUtil.find(ev2, "terrain_add")[0]
	assert_eq((add["skip"] as PackedInt32Array).size() % 4, 0, "skip boxes are x0,y0,x1,y1 quadruples")
	var s3: MatchState = _flat([300, 800] as Array[int])
	var ev3: Array[Dictionary] = _fire(s3, "ember_rain", 450, WeaponTestUtil.power_for_landing(s3, 450, 800), "payload fire")
	assert_eq((QaUtil.find(ev3, "flames")[0]["points"] as PackedInt32Array).size(), 120)


# --- more interplay ---------------------------------------------------------------------------------------

func test_a_second_well_by_the_same_owner_replaces_the_first() -> void:
	var s: MatchState = _flat([200, 600, 1000] as Array[int])
	_fire(s, "singularity_seed", 600, 450, "first well")
	var first: Dictionary = s.wells[0].duplicate()
	_pass_turn(s)
	_pass_turn(s)
	assert_eq(s.current_tank, 0)
	var ev: Array[Dictionary] = _fire(s, "singularity_seed", 500, 700, "replacement well")
	assert_eq(s.wells.size(), 1, "still one well for owner 0")
	assert_ne(s.wells[0]["x"], first["x"], "it moved")
	var types: Array[String] = QaUtil.types(ev)
	assert_lt(types.find("well_off"), types.find("well_on"), "well_off then well_on")
	assert_eq(QaUtil.find(ev, "well_off")[0]["owner"], 0)
	assert_eq(s.wells[0]["expires_turn"], s.turn_number - 1 + 2 * 3, "the new well gets a fresh 2-cycle lifetime")


func test_beam_through_a_thin_wall_still_hits_the_tank_behind_it() -> void:
	var s: MatchState = _flat([100, 700] as Array[int])
	_set_solid(s.terrain, 300, 350, 500, 600)  # 50 cells thick: well under the 120-cell cut limit
	var ev: Array[Dictionary] = _fire(s, "photon_lance", 0, 1, "beam thin wall")
	var tun: Dictionary = QaUtil.find(ev, "tunnel")[0]
	assert_eq([tun["x0"], tun["x1"]], [300, 349])
	var dmg: Array[Dictionary] = _of_type(ev, "damage")
	assert_eq(dmg.size(), 1)
	assert_eq(dmg[0]["tank"], 1)
	assert_eq(dmg[0]["cause"], "beam")
	assert_gt(s.terrain.surface_y(325), 500, "the dirt above the tunnel settled down into it (the wall got shorter)")


func test_anchor_drag_off_a_cliff_credits_the_fall_to_the_shooter() -> void:
	var s: MatchState = _flat([100, 560, 1400] as Array[int])
	for x: int in range(600, SimConstants.WORLD_W):
		s.terrain.flatten(x, x, 700)
	s.tanks[2].y = TankState.rest_y(s.terrain, 1400)
	s.tanks[1].health = 5
	var shot: Vector2i = _find_shot(s, 0, range(300, 700, 25), 690, 3)
	assert_ne(shot.x, -1)
	var money: int = s.tanks[0].money
	var ev: Array[Dictionary] = _fire(s, "riptide_anchor", shot.x, shot.y, "anchor off a cliff")
	assert_false(s.tanks[1].alive, "the drop killed it")
	var falls: Array[Dictionary] = _of_type(ev, "damage").filter(func(e: Dictionary) -> bool: return e["tank"] == 1)
	assert_eq(falls[0]["cause"], "fall")
	assert_eq(s.tanks[1].health, 0)
	assert_eq(s.tanks[0].kills, 1, "a kill by a fall your shot caused counts")
	assert_eq(s.tanks[0].money, money + 5 * 15 + 1500, "15 per HP actually removed (5), plus the kill bonus")


func test_shield_absorbs_burn_and_only_the_remainder_pays() -> void:
	var s: MatchState = _flat([100, 700] as Array[int])
	s.tanks[1].shield_type = Catalog.index_of("glow_shield")
	s.tanks[1].shield_hp = 30
	var p: int = WeaponTestUtil.power_for_landing(s, 450, 700)
	var ev: Array[Dictionary] = _fire(s, "inferno_gel", 450, p, "burn into shield")
	# The shell may end on the bubble first; either way the shield takes the burn before health does.
	assert_gte(_of_type(ev, "shield_hit").size(), 1)
	assert_lt(s.tanks[1].shield_hp, 30)


func test_every_ground_weapon_at_the_side_walls() -> void:
	var shots: int = 0
	for side: int in [0, 1]:
		var xs: Array[int] = [300, 1300]
		var target: int = 6 if side == 0 else 1593
		var angles: Array = [1800, 1700, 1600, 1500] if side == 0 else [0, 100, 200, 300]
		var base: MatchState = _flat(xs)
		var shot: Vector2i = _find_shot(base, side, angles, target, 20)
		assert_ne(shot.x, -1, "side %d: a shell that lands within 20 cells of the wall" % side)
		if shot.x < 0:
			continue
		base.current_tank = side
		for id: String in Catalog.IDS:
			if not Catalog.is_weapon(id) or Catalog.get_def(id)["behavior"] == "beam":
				continue
			var s: MatchState = base.duplicate_state()
			_fire(s, id, shot.x, shot.y, "wall %d" % side)
			shots += 1
	assert_eq(shots, 2 * 20)


## Preview == reality, fuzzed: on generated terrain with random wind, wells, repulsors and shields, the pure trace()
## the AI and the aiming preview use must predict the first shell of the real shot exactly.
func test_preview_equals_reality_fuzz_on_generated_terrain() -> void:
	var rng := Rng.new(0xAB1E)
	var weapons: Array[String] = []
	for id: String in Catalog.IDS:
		if Catalog.is_weapon(id):
			weapons.append(id)
	var shots: int = 0
	var failures: Array[String] = []
	for m: int in range(6):
		var settings: MatchSettings = QaUtil.settings(5000 + m * 17, 2 + m % 5, 1)
		var base: MatchState = QaUtil.started_match(settings)
		for t: TankState in base.tanks:
			t.money = 10000
		for k: int in range(15):
			var s: MatchState = base.duplicate_state()
			s.wind = rng.range_int(-100, 100)
			if rng.range_int(0, 2) == 0:
				s.wells.append({"owner": 0, "x": rng.range_int(100, 1500), "y": rng.range_int(100, 700), "expires_turn": 99})
			for t: TankState in s.tanks:
				if t.id != s.current_tank and rng.range_int(0, 3) == 0:
					t.repulsor_charge = 100
				if rng.range_int(0, 3) == 0:
					t.shield_type = Catalog.index_of("ion_shield")
					t.shield_hp = 60
			var me: int = s.current_tank
			var weapon: String = weapons[rng.range_int(0, weapons.size() - 1)]
			var angle: int = rng.range_int(0, 1800)
			var power: int = rng.range_int(1, 1000)
			var tr: Dictionary = Ballistics.trace(s, me, angle, power, weapon, SimConstants.WIND_USE_STATE, SimConstants.MAX_FLIGHT_TICKS)
			var fp: String = Simulation.fingerprint(s)
			var ev: Array[Dictionary] = _fire(s, weapon, angle, power, "fuzz %d.%d" % [m, k])
			shots += 1
			var tag: String = "match %d shot %d (%s a%d p%d wind %d)" % [m, k, weapon, angle, power, base.wind]
			if Catalog.get_def(weapon)["behavior"] == "beam":
				var b: Dictionary = QaUtil.find(ev, "beam")[0]
				if [b["x1"], b["y1"]] != [tr["end_x"], tr["end_y"]]:
					failures.append("%s: beam end differs from the preview" % tag)
				continue
			var proj: Dictionary = QaUtil.find(ev, "projectile")[0]
			var path: PackedInt32Array = proj["path"]
			var tpath: PackedInt32Array = tr["path"]
			if path.size() < tpath.size() or path.slice(0, tpath.size()) != tpath:
				failures.append("%s: first shell's path differs from trace()" % tag)
			var behavior: String = Catalog.get_def(weapon)["behavior"]
			if behavior != "roller":
				var end: Dictionary = QaUtil.find(ev, "projectile_end")[0]
				var want: String = "split" if tr["end_reason"] == "apex" else tr["end_reason"]
				if end["reason"] != want or end["x"] != tr["end_x"] or end["y"] != tr["end_y"]:
					failures.append("%s: end %s@%s,%s vs preview %s@%s,%s" % [tag, end["reason"], end["x"], end["y"], want, tr["end_x"], tr["end_y"]])
	assert_eq(failures, [] as Array[String])
	assert_eq(shots, 90)
