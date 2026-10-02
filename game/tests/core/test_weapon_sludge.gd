@warning_ignore_start("integer_division")
extends GutTest
## Sludge Shell (docs/ARCHITECTURE.md section 21).

const U = preload("res://tests/core/sim_test_util.gd")
const WU = preload("res://tests/core/weapon_test_util.gd")


func _valley() -> MatchState:
	var s: MatchState = WU.shaped_state(2, func(x: int) -> int: return clampi(820 - absi(x - 800), 250, 820))
	WU.place_tank(s, 0, 100)
	WU.place_tank(s, 1, 1500)
	return s


## Reference walk: every cell starts at the impact column and walks the full path again.
func _naive_plan(terrain: Terrain, start: int, volume: int) -> PackedInt32Array:
	var cache := SurfaceCache.new(terrain)
	var out: PackedInt32Array = PackedInt32Array()
	for _k: int in range(volume):
		var c: int = start
		var dir: int = 0
		var steps: int = 0
		while steps < SludgeBehavior.MAX_STEPS:
			var d: int = cache.flow_dir(c, dir, true)
			if d == 0:
				break
			dir = d
			c += d
			steps += 1
		if cache.top(c) <= 0:
			continue
		out.append(c)
		cache.bump(c)
	return out


func test_pours_exactly_the_volume_and_reports_the_columns() -> void:
	var s: MatchState = _valley()
	var p: int = WU.power_for_landing(s, 450, 500)
	var before: int = WU.solid_count(s.terrain)
	var ev: Array[Dictionary] = WU.fire(s, "sludge_shell", 450, p)
	var pour: Array[Dictionary] = U.find(ev, "terrain_pour")
	assert_eq(pour.size(), 1)
	var end: Dictionary = U.find(ev, "projectile_end")[0]
	assert_eq(pour[0]["x"], end["x"], "x is the impact column")
	assert_eq(pour[0]["tick"], end["tick"])
	assert_eq((pour[0]["cells"] as PackedInt32Array).size(), 1800)
	assert_eq(WU.solid_count(s.terrain) - before, 1800, "volume is conserved")
	assert_eq(U.types(ev), ["fire", "projectile", "projectile_end", "terrain_pour", "wind", "turn"] as Array[String])
	assert_eq(U.find(ev, "explosion").size(), 0)


func test_fills_the_valley_level() -> void:
	var s: MatchState = _valley()
	var p: int = WU.power_for_landing(s, 450, 600)
	var depth_before: int = 820 - s.terrain.surface_y(800)
	assert_eq(depth_before, 0)
	var ev: Array[Dictionary] = WU.fire(s, "sludge_shell", 450, p)
	var cols: PackedInt32Array = U.find(ev, "terrain_pour")[0]["cells"]
	var lo: int = 1 << 30
	var hi: int = -1
	for c: int in cols:
		lo = mini(lo, c)
		hi = maxi(hi, c)
	# A V-shaped valley with 45 degree walls holds 1800 cells up to a level of about 42.
	assert_true(lo >= 750 and hi <= 850, "poured between %d and %d" % [lo, hi])
	var top_min: int = 1 << 30
	var top_max: int = -1
	for x: int in range(770, 831):
		top_min = mini(top_min, s.terrain.surface_y(x))
		top_max = maxi(top_max, s.terrain.surface_y(x))
	assert_true(top_max - top_min <= 2, "the sludge settled to a level surface (%d..%d)" % [top_min, top_max])
	assert_true(top_min >= 770 and top_min <= 785, "about 42 cells deep: surface at %d" % top_min)


func test_sludge_flows_to_a_valley_on_generated_terrain() -> void:
	var s: MatchState = WU.random_match(31, 2)
	var impact: int = 700
	var cols: PackedInt32Array = SludgeBehavior.plan(s.terrain, impact, 600)
	assert_eq(cols.size(), 600)
	# The lowest reachable point of the hill is where most of it lands.
	var counts: Dictionary = {}
	for c: int in cols:
		counts[c] = (counts.get(c, 0) as int) + 1
	assert_gt(counts.size(), 1)
	var span: int = 0
	var cache := SurfaceCache.new(s.terrain)
	for c: int in cols:
		span = maxi(span, absi(c - impact))
		assert_true(c >= 0 and c < SimConstants.WORLD_W)
		cache.top(c)
	assert_lte(span, SludgeBehavior.MAX_STEPS + 1)


func test_memoised_plan_equals_the_naive_walk() -> void:
	for seed_value: int in [3, 8, 21]:
		var s: MatchState = WU.random_match(seed_value, 2)
		for start: int in [0, 1, 400, 800, 1200, 1598, 1599]:
			var fast: PackedInt32Array = SludgeBehavior.plan(s.terrain, start, 150)
			var slow: PackedInt32Array = _naive_plan(s.terrain, start, 150)
			assert_eq(fast, slow, "seed %d start %d" % [seed_value, start])


func test_memoised_plan_equals_the_naive_walk_on_a_valley_and_flat_ground() -> void:
	var v: MatchState = _valley()
	assert_eq(SludgeBehavior.plan(v.terrain, 500, 400), _naive_plan(v.terrain, 500, 400))
	assert_eq(SludgeBehavior.plan(v.terrain, 800, 400), _naive_plan(v.terrain, 800, 400))
	var f: MatchState = U.flat_state(2)
	assert_eq(SludgeBehavior.plan(f.terrain, 800, 300), _naive_plan(f.terrain, 800, 300))


func test_plan_does_not_touch_the_terrain_and_handles_bad_input() -> void:
	var s: MatchState = _valley()
	var before: PackedByteArray = s.terrain.cells.duplicate()
	assert_eq(SludgeBehavior.plan(s.terrain, 500, 100).size(), 100)
	assert_eq(s.terrain.cells, before)
	assert_eq(SludgeBehavior.plan(s.terrain, -1, 100).size(), 0)
	assert_eq(SludgeBehavior.plan(s.terrain, 1600, 100).size(), 0)
	assert_eq(SludgeBehavior.plan(s.terrain, 500, 0).size(), 0)
	assert_eq(SludgeBehavior.plan(s.terrain, 500, -5).size(), 0)


func test_flat_ground_spreads_into_a_film_that_alternates_sides() -> void:
	var s: MatchState = U.flat_state(2)
	var cols: PackedInt32Array = SludgeBehavior.plan(s.terrain, 800, 601)
	assert_eq(cols.size(), 601)
	assert_eq(cols[0], 500, "even column: flows left, 300 steps")
	assert_eq(cols[1], 501, "the next cell stops at the edge of the first")
	var left: int = 0
	var right: int = 0
	for c: int in cols:
		assert_true(c >= 500 and c <= 1100, "within reach")
		if c < 800:
			left += 1
		elif c > 800:
			right += 1
	assert_eq(left, 300, "one layer on the left")
	assert_eq(right, 300, "then one layer on the right")
	assert_eq(cols[600], 800, "the impact column itself comes last")


func test_at_the_map_edge_the_walls_hold_the_sludge_in() -> void:
	var s: MatchState = U.flat_state(2)
	var cols: PackedInt32Array = SludgeBehavior.plan(s.terrain, 0, 200)
	assert_eq(cols.size(), 200, "nothing is lost")
	for c: int in cols:
		assert_true(c >= 0)
	var cols_r: PackedInt32Array = SludgeBehavior.plan(s.terrain, 1599, 200)
	assert_eq(cols_r.size(), 200)
	for c: int in cols_r:
		assert_true(c <= 1599)


func test_cells_that_cannot_be_placed_are_dropped() -> void:
	var t := Terrain.new(40, 20)
	t.flatten(0, 39, 2)  # two free rows: room for 80 cells
	var cols: PackedInt32Array = SludgeBehavior.plan(t, 20, 200)
	assert_true(cols.size() > 40 and cols.size() <= 80, "placed %d of 200" % cols.size())
	var before: int = WU.solid_count(t)
	t.pour(cols, 3)
	assert_eq(WU.solid_count(t) - before, cols.size())
	for x: int in range(40):
		assert_true(t.surface_y(x) >= 0)


func test_material_comes_from_the_impact_column_surface() -> void:
	var s: MatchState = _valley()
	var p: int = WU.power_for_landing(s, 450, 500)
	var ev: Array[Dictionary] = WU.fire(s, "sludge_shell", 450, p)
	var pour: Dictionary = U.find(ev, "terrain_pour")[0]
	assert_eq(pour["material"], 1)
	var cols: PackedInt32Array = pour["cells"]
	assert_eq(s.terrain.get_cell(cols[cols.size() - 1], s.terrain.surface_y(cols[cols.size() - 1])), 1)


func test_lost_shell_pours_nothing() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[0].x = 20
	var before: PackedByteArray = s.terrain.cells.duplicate()
	var ev: Array[Dictionary] = WU.fire(s, "sludge_shell", 1750, 900)
	assert_eq(U.find(ev, "terrain_pour").size(), 0)
	assert_eq(s.terrain.cells, before)


func test_sludge_can_bury_a_tank_in_the_valley() -> void:
	var s: MatchState = _valley()
	WU.place_tank(s, 1, 800)
	var p: int = WU.power_for_landing(s, 450, 600)
	var ev: Array[Dictionary] = WU.fire(s, "sludge_shell", 450, p)
	assert_eq(U.find(ev, "terrain_pour").size(), 1)
	assert_gt(WU.solid_in_box(s.terrain, s.tanks[1]), 0, "sludge rose into the box")
	assert_eq(s.tanks[1].health, 100)
