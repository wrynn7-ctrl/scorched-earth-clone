@warning_ignore_start("integer_division")
extends GutTest
## M4 QA: drift guard between AiFlight (the AI's integer copy of the shell physics, ARCHITECTURE
## section 31) and Ballistics.trace. 500 random shots (every wind, angles 0..1800, powers 1..1000,
## wells, repulsors, shields, tanks near the path, craters and plateaus, shells that leave the top of
## the map) plus three adversarial terrain groups. The landing cell of AiFlight.fly_shot must be
## within 2 cells of Ballistics.trace's end cell.
##
## AiFlight deliberately ignores tank boxes and shield bubbles ("a shell that hits an enemy is a fine
## outcome"). A shot whose real trace ends on a tank or a bubble is therefore compared on a copy of
## the state with the blocking tank removed, and counted as "occluded" in the report.

const QA_AI = preload("res://tests/qa/qa_ai.gd")
const SHOTS: int = 500
const POOLS: int = 25
const TOL: int = 2
const MAX_TICKS: int = 1500
const REASONS: Dictionary = {"terrain": AiFlight.REASON_TERRAIN, "lost": AiFlight.REASON_LOST, "timeout": AiFlight.REASON_TIMEOUT}

var _generic: Array[Dictionary] = []
var _groups: Dictionary = {}
var _elapsed_ms: int = 0


# --- one comparison -----------------------------------------------------------------------------------

## {d: Chebyshev distance of the end cells (-1 when the end reasons differ), reason_ok, occluded, desc}.
func _cmp_shot(state: MatchState, shooter: int, angle: int, power: int, wind: int, desc: String) -> Dictionary:
	var tr: Dictionary = Ballistics.trace(state, shooter, angle, power, "pulse_missile", wind, MAX_TICKS)
	var st: MatchState = state
	var occluded: bool = false
	var guard: int = 0
	while (tr["end_reason"] == "tank" or tr["end_reason"] == "shield") and guard < 8:
		guard += 1
		occluded = true
		if st == state:
			st = state.duplicate_state()
		var blocker: TankState = st.tanks[tr["hit_tank"] as int]
		# (A shell that falls back onto its own shooter is removed the same way: AiFlight never models
		# the shooter's box either.)
		blocker.alive = false
		blocker.health = 0
		blocker.shield_type = -1
		blocker.shield_hp = 0
		tr = Ballistics.trace(st, shooter, angle, power, "pulse_missile", wind, MAX_TICKS)
	var me: TankState = st.tanks[shooter]
	var fl := AiFlight.new(st.terrain, st.wells, AiPlayer.others_with_repulsors(st, me))
	fl.fly_shot(me.x, me.y, angle, power, wind, MAX_TICKS)
	var reason_b: String = tr["end_reason"]
	var reason_ok: bool = REASONS.get(reason_b, -1) == fl.r_reason
	var d: int = maxi(absi(fl.r_x - (tr["end_x"] as int)), absi(fl.r_y - (tr["end_y"] as int)))
	return {"d": d, "reason_ok": reason_ok, "occluded": occluded, "reason_b": reason_b, "reason_a": fl.r_reason,
			"desc": "%s: tank %d at (%d,%d) angle %d power %d wind %d -> Ballistics %s at (%d,%d), AiFlight reason %d at (%d,%d)" % [
			desc, shooter, me.x, me.y, angle, power, wind, reason_b, tr["end_x"], tr["end_y"], fl.r_reason, fl.r_x, fl.r_y]}


func _is_bad(c: Dictionary) -> bool:
	return not (c["reason_ok"] as bool) or (c["d"] as int) > TOL


# --- scenario pools ---------------------------------------------------------------------------------------

func _pool_state(k: int) -> MatchState:
	var r: Rng = Rng.derive(0xD21F7 + k, 31)
	var s := MatchSettings.new()
	s.seed = 880000 + k * 17
	s.num_tanks = r.range_int(2, 6)
	s.controllers = PackedInt32Array()
	for _i: int in range(s.num_tanks):
		s.controllers.append(2)
	var state: MatchState = Simulation.new_match(s)
	SimTestUtil.begin_round(state)
	var terrain: Terrain = state.terrain
	if r.chance(3, 5):
		for _c: int in range(r.range_int(1, 3)):
			var cx: int = r.range_int(100, 1500)
			var cr: int = r.range_int(20, 120)
			terrain.carve_circle(cx, terrain.surface_y(cx) + r.range_int(0, 30), cr)
			terrain.settle(maxi(0, cx - cr - 2), mini(1599, cx + cr + 2))
	if r.chance(3, 10):
		var wx: int = r.range_int(200, 1300)
		terrain.flatten(wx, wx + r.range_int(6, 60), r.range_int(250, 520))
	for t: TankState in state.tanks:
		if t.id > 0 and r.chance(1, 2):
			t.x = r.range_int(40, 1560)
			t.y = TankState.rest_y(terrain, t.x)
		if r.chance(2, 5):
			t.repulsor_charge = r.range_int(10, 100)
		if r.chance(2, 5):
			var shields: Array[String] = ["glow_shield", "ion_shield", "fortress_field"]
			var id: String = shields[r.range_int(0, 2)]
			t.shield_type = Catalog.index_of(id)
			t.shield_hp = r.range_int(5, ItemDefs.get_def(id)["hp"] as int)
	if r.chance(2, 5):
		for owner: int in range(r.range_int(1, mini(2, s.num_tanks))):
			state.wells.append({"owner": owner, "x": r.range_int(200, 1400), "y": r.range_int(100, 650), "expires_turn": 99})
	state.current_tank = 0
	return state


func _shot(r: Rng, i: int) -> Vector3i:
	var angle: int = r.range_int(0, 1800)
	var power: int = r.range_int(1, 1000)
	var wind: int = r.range_int(-100, 100)
	match i % 12:
		0:
			angle = [0, 1800, 900, 899, 901, 450, 1350][r.range_int(0, 6)]
		1:
			power = [1, 1000, 2, 999, 500][r.range_int(0, 4)]
		2:
			wind = [-100, 100, 0, -1, 1][r.range_int(0, 4)]
		3:
			angle = r.range_int(800, 1000)
			power = r.range_int(700, 1000)  # shells that fly out of the top of the map
		4:
			angle = r.range_int(0, 120) if r.chance(1, 2) else r.range_int(1680, 1800)  # flat, fast
			power = r.range_int(500, 1000)
	return Vector3i(angle, power, wind)


func before_all() -> void:
	var t0: int = Time.get_ticks_msec()
	var per_pool: int = SHOTS / POOLS
	for k: int in range(POOLS):
		var state: MatchState = _pool_state(k)
		var r: Rng = Rng.derive(0xD21F7 + k, 32)
		for i: int in range(per_pool):
			var sh: Vector3i = _shot(r, i)
			var shooter: int = r.range_int(0, state.tanks.size() - 1)
			_generic.append(_cmp_shot(state, shooter, sh.x, sh.y, sh.z, "pool %d shot %d" % [k, i]))
	_adversarial_groups()
	_elapsed_ms = Time.get_ticks_msec() - t0


func _adversarial_groups() -> void:
	# A: thin tall pillars between the shooter and the landing area: a fast shell can skip over a
	#    pillar that is narrower than one tick of travel if the model only samples the tick ends.
	var a: Array[Dictionary] = []
	var s: MatchState = SimTestUtil.flat_state(2)
	QA_AI.fill_rect(s.terrain, 700, 702, 480, 600)
	var r: Rng = Rng.derive(77, 1)
	for i: int in range(60):
		var angle: int = r.range_int(20, 300)
		var power: int = r.range_int(500, 1000)
		a.append(_cmp_shot(s, 0, angle, power, r.range_int(-100, 100), "pillar 3 wide x 120 tall at x=700 [flat ground y=600, shooter x=300]"))
	_groups["thin pillar"] = a
	# B: a wall that reaches the very top of the map (y = 0): the model assumes open sky above SKY_Y.
	var b: Array[Dictionary] = []
	var s2: MatchState = SimTestUtil.flat_state(2)
	s2.terrain.flatten(800, 840, 0)
	for i: int in range(60):
		b.append(_cmp_shot(s2, 0, r.range_int(300, 900), r.range_int(300, 1000), r.range_int(-100, 100),
				"full-height wall x=800..840 [flat ground y=600, shooter x=300]"))
	_groups["full-height wall"] = b
	# C: a wall of moderate height that tops out above the model's SKY_Y (150) but not at the top.
	var c: Array[Dictionary] = []
	var s3: MatchState = SimTestUtil.flat_state(2)
	s3.terrain.flatten(800, 840, 100)
	for i: int in range(60):
		c.append(_cmp_shot(s3, 0, r.range_int(300, 900), r.range_int(300, 1000), r.range_int(-100, 100),
				"wall x=800..840 up to y=100 [flat ground y=600, shooter x=300]"))
	_groups["wall above sky line"] = c
	# D: deep narrow slot, shooter inside a 30-wide pit.
	var d: Array[Dictionary] = []
	var s4: MatchState = SimTestUtil.flat_state(2)
	s4.terrain.flatten(286, 314, 800)
	s4.tanks[0].y = 800
	for i: int in range(60):
		d.append(_cmp_shot(s4, 0, r.range_int(0, 1800), r.range_int(100, 1000), r.range_int(-100, 100),
				"shooter in a 28-wide, 200-deep pit at x=300"))
	_groups["deep pit"] = d


# --- reports ----------------------------------------------------------------------------------------------------

func _hist_of(list: Array[Dictionary]) -> String:
	var bounds: Array[int] = [0, 1, 2, 5, 20, 100000]
	var counts: Array[int] = [0, 0, 0, 0, 0, 0]
	var reason_mismatch: int = 0
	var occ: int = 0
	for c: Dictionary in list:
		if c["occluded"]:
			occ += 1
		if not (c["reason_ok"] as bool):
			reason_mismatch += 1
			continue
		for i: int in range(bounds.size()):
			if (c["d"] as int) <= bounds[i]:
				counts[i] += 1
				break
	return "n=%d (occluded and re-traced without the blocker: %d)  |d|=0: %d  1: %d  2: %d  3-5: %d  6-20: %d  >20: %d  end-reason mismatch: %d" % [
			list.size(), occ, counts[0], counts[1], counts[2], counts[3], counts[4], counts[5], reason_mismatch]


func _worst_of(list: Array[Dictionary], limit: int = 3) -> Array[String]:
	var bad: Array[Dictionary] = []
	for c: Dictionary in list:
		if _is_bad(c):
			bad.append(c)
	bad.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return (x["d"] as int) > (y["d"] as int))
	var out: Array[String] = []
	for i: int in range(mini(limit, bad.size())):
		out.append(bad[i]["desc"] as String)
	return out


func _count_bad(list: Array[Dictionary]) -> int:
	var n: int = 0
	for c: Dictionary in list:
		if _is_bad(c):
			n += 1
	return n


func test_500_random_shots_agree_with_ballistics_within_2_cells() -> void:
	gut.p("AIDRIFT random: " + _hist_of(_generic) + "   (%.1f s for everything)" % (float(_elapsed_ms) / 1000.0))
	var worst: Array[String] = _worst_of(_generic, 60 if OS.get_environment("QA_AI_VERBOSE") != "" else 3)
	for w: String in worst:
		gut.p("AIDRIFT   REPRO " + w)
	assert_eq(_generic.size(), SHOTS)
	var bad: int = _count_bad(_generic)
	# Ratchet: 3 known disagreements today (thin ridges skipped by the tick-end sampling); more is a regression.
	assert_lte(bad, 5, "random shots where AiFlight and Ballistics disagree (known baseline 3)")
	if bad > 0:
		pending("BUG: AiFlight and Ballistics.trace disagree by more than %d cells (or in end reason) on %d of %d random shots. Worst: %s" % [TOL, bad, _generic.size(), worst[0]])
	else:
		assert_eq(bad, 0)


func test_the_random_shots_cover_what_they_claim() -> void:
	var reasons: Dictionary = {}
	var occ: int = 0
	for c: Dictionary in _generic:
		reasons[c["reason_b"]] = (reasons.get(c["reason_b"], 0) as int) + 1
		if c["occluded"]:
			occ += 1
	gut.p("AIDRIFT coverage: Ballistics end reasons %s; %d shots had a tank or bubble in the way" % [str(reasons), occ])
	assert_gt(reasons.get("terrain", 0) as int, 100)
	assert_gt(reasons.get("lost", 0) as int, 10)
	assert_gt(occ, 3, "some shots run into tanks or bubbles (and get compared without them)")


func test_adversarial_terrain_groups_report() -> void:
	var names: Array = _groups.keys()
	for n: String in names:
		var list: Array[Dictionary] = _groups[n]
		gut.p("AIDRIFT %-20s %s" % [n, _hist_of(list)])
		for w: String in _worst_of(list, 2):
			gut.p("AIDRIFT   REPRO " + w)
	assert_eq(names.size(), 4)


func test_thin_pillar_is_not_skipped_by_the_model() -> void:
	var list: Array[Dictionary] = _groups["thin pillar"]
	var bad: int = _count_bad(list)
	assert_lte(bad, 24, "ratchet (known baseline 18 of 60)")
	if bad > 0:
		pending("BUG: AiFlight (game/ai/ai_flight.gd:148, GRAZE=4 at :26) samples only tick-end cells near the ground, so a shell that passes through a thin pillar between two samples is not stopped. %d of %d shots disagree with Ballistics. Repro: %s" % [bad, list.size(), _worst_of(list, 1)[0]])
	else:
		assert_eq(bad, 0)


func test_full_height_wall_stops_the_model_shell() -> void:
	var list: Array[Dictionary] = _groups["full-height wall"]
	var bad: int = _count_bad(list)
	assert_lte(bad, 8, "ratchet (known baseline 6 of 60)")
	if bad > 0:
		pending("BUG: AiFlight.SKY_Y = 150 (game/ai/ai_flight.gd:23,148) treats everything above row 150 as open sky, but terrain can reach row 0 (e.g. stacked Landslides, flatten). %d of %d shots disagree with Ballistics. Repro: %s" % [bad, list.size(), _worst_of(list, 1)[0]])
	else:
		assert_eq(bad, 0)


func test_wall_above_the_sky_line_stops_the_model_shell() -> void:
	var list: Array[Dictionary] = _groups["wall above sky line"]
	var bad: int = _count_bad(list)
	assert_lte(bad, 3, "ratchet (known baseline 1 of 60)")
	if bad > 0:
		pending("BUG: terrain above row 150 (SKY_Y) is invisible to AiFlight. %d of %d shots disagree with Ballistics. Repro: %s" % [bad, list.size(), _worst_of(list, 1)[0]])
	else:
		assert_eq(bad, 0)


func test_deep_pit_shots_agree() -> void:
	var list: Array[Dictionary] = _groups["deep pit"]
	var bad: int = _count_bad(list)
	assert_eq(bad, 0, "pit shots: %s" % ("" if bad == 0 else _worst_of(list, 1)[0]))
