extends GutTest


func _solid_block(w: int, h: int) -> Terrain:
	var t := Terrain.new(w, h)
	t.flatten(0, w - 1, 0)
	return t


func _count_air(t: Terrain) -> int:
	var n: int = 0
	for b: int in t.cells:
		if b == 0:
			n += 1
	return n


func _brute_count(cx: int, cy: int, r: int, w: int, h: int) -> int:
	var n: int = 0
	for x: int in range(w):
		for y: int in range(h):
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r:
				n += 1
	return n


func test_generate_deterministic() -> void:
	var a: Terrain = Terrain.generate(400, 300, Rng.new(5))
	var b: Terrain = Terrain.generate(400, 300, Rng.new(5))
	var c: Terrain = Terrain.generate(400, 300, Rng.new(6))
	assert_eq(a.cells, b.cells, "same seed -> identical bytes")
	assert_ne(a.cells, c.cells, "different seed -> different bytes")
	assert_eq(a.cells.size(), 400 * 300)


func test_generate_surface_in_bounds_full_size() -> void:
	var t: Terrain = Terrain.generate(SimConstants.WORLD_W, SimConstants.WORLD_H, Rng.new(1234))
	var lo: int = SimConstants.WORLD_H * 30 / 100
	var hi: int = SimConstants.WORLD_H * 85 / 100
	var min_s: int = 1 << 30
	var max_s: int = 0
	for x: int in range(t.width):
		var s: int = t.surface_y(x)
		assert_true(s >= lo and s <= hi, "column %d surface %d" % [x, s])
		min_s = mini(min_s, s)
		max_s = maxi(max_s, s)
	assert_true(max_s - min_s > 40, "terrain has some relief: %d" % (max_s - min_s))


func test_generate_surface_in_bounds_many_seeds_small() -> void:
	for seed_value: int in range(20):
		var t: Terrain = Terrain.generate(200, 100, Rng.new(seed_value))
		for x: int in range(t.width):
			var s: int = t.surface_y(x)
			assert_true(s >= 30 and s <= 85, "seed %d col %d surface %d" % [seed_value, x, s])


func test_generate_solid_below_surface_with_materials() -> void:
	var t: Terrain = Terrain.generate(200, 100, Rng.new(3))
	for x: int in range(0, 200, 13):
		var s: int = t.surface_y(x)
		for y: int in range(s, 100):
			var m: int = t.get_cell(x, y)
			assert_true(m >= 1 and m <= 15, "material %d" % m)
		for y: int in range(0, s):
			assert_eq(t.get_cell(x, y), 0)
	# strata: the material changes with depth
	var x0: int = 50
	var s0: int = t.surface_y(x0)
	assert_ne(t.get_cell(x0, s0), t.get_cell(x0, mini(99, s0 + 40)))


func test_is_solid_and_surface_edges() -> void:
	var t: Terrain = Terrain.new(10, 20)
	t.flatten(0, 9, 12)
	assert_false(t.is_solid(5, 11))
	assert_true(t.is_solid(5, 12))
	assert_true(t.is_solid(5, 19))
	assert_true(t.is_solid(5, 20), "below the map is bedrock")
	assert_true(t.is_solid(5, 500))
	assert_false(t.is_solid(5, -1), "above the map is sky")
	assert_false(t.is_solid(-1, 15), "outside the side walls is open")
	assert_false(t.is_solid(10, 15))
	assert_eq(t.surface_y(5), 12)
	var empty := Terrain.new(4, 8)
	assert_eq(empty.surface_y(2), 8, "empty column -> height")


func test_carve_circle_exact_count_full_block() -> void:
	var t: Terrain = _solid_block(100, 100)
	var rect: Rect2i = t.carve_circle(50, 50, 10)
	assert_eq(_count_air(t), 317, "Gauss circle count for r=10")
	assert_eq(_count_air(t), _brute_count(50, 50, 10, 100, 100))
	assert_eq(rect, Rect2i(40, 40, 21, 21))
	assert_false(t.is_solid(50, 50))
	assert_false(t.is_solid(60, 50), "dx == r is inside")
	assert_true(t.is_solid(61, 50))
	assert_true(t.is_solid(58, 58), "corner outside radius stays")
	assert_true(t.is_solid(57, 58), "49 + 64 > 100")
	assert_false(t.is_solid(57, 56), "49 + 36 = 85 <= 100")
	assert_false(t.is_solid(57, 57), "49 + 49 = 98 <= 100")


func test_carve_circle_various_radii_match_brute_force() -> void:
	for r: int in [0, 1, 2, 3, 5, 17, 28]:
		var t: Terrain = _solid_block(120, 120)
		t.carve_circle(60, 61, r)
		assert_eq(_count_air(t), _brute_count(60, 61, r, 120, 120), "r=%d" % r)


func test_carve_circle_clipped_and_outside() -> void:
	var t: Terrain = _solid_block(50, 50)
	var rect: Rect2i = t.carve_circle(0, 0, 10)
	assert_eq(rect, Rect2i(0, 0, 11, 11))
	assert_eq(_count_air(t), _brute_count(0, 0, 10, 50, 50))
	var t2: Terrain = _solid_block(50, 50)
	assert_eq(t2.carve_circle(500, 500, 10), Rect2i(), "fully outside -> empty rect")
	assert_eq(_count_air(t2), 0)
	assert_eq(t2.carve_circle(10, 10, -1), Rect2i(), "negative radius")
	var t3: Terrain = _solid_block(50, 50)
	var above: Rect2i = t3.carve_circle(25, -5, 10)
	assert_eq(above.position.y, 0)
	assert_eq(_count_air(t3), _brute_count(25, -5, 10, 50, 50))


func test_add_circle_fills_air_only() -> void:
	var t: Terrain = Terrain.new(40, 40)
	t.flatten(0, 39, 30)
	var before_solid: int = t.get_cell(20, 35)
	t.add_circle(20, 30, 8, 7)
	assert_eq(t.get_cell(20, 25), 7, "air filled")
	assert_eq(t.get_cell(20, 35), before_solid, "existing solid untouched")
	assert_eq(t.get_cell(20, 21), 0, "outside radius stays air")
	t.add_circle(-100, -100, 5, 3)  # no-op off-map
	assert_eq(t.get_cell(0, 0), 0)


func test_settle_simple_column_preserves_order() -> void:
	var t := Terrain.new(3, 20)
	t.cells[0 * 20 + 2] = 5
	t.cells[0 * 20 + 3] = 6
	t.cells[0 * 20 + 10] = 7
	var falls: Array[Dictionary] = t.settle(0, 2)
	assert_eq(t.get_cell(0, 19), 7)
	assert_eq(t.get_cell(0, 18), 6)
	assert_eq(t.get_cell(0, 17), 5)
	for y: int in range(0, 17):
		assert_eq(t.get_cell(0, y), 0, "air above at %d" % y)
	assert_eq(falls.size(), 2)
	assert_eq(falls[0], {"x": 0, "from_y": 10, "to_y": 19, "length": 1})
	assert_eq(falls[1], {"x": 0, "from_y": 2, "to_y": 17, "length": 2})


func test_settle_noop_on_settled_terrain() -> void:
	var t: Terrain = Terrain.generate(100, 80, Rng.new(8))
	var before: PackedByteArray = t.cells.duplicate()
	var falls: Array[Dictionary] = t.settle(0, 99)
	assert_eq(falls.size(), 0)
	assert_eq(t.cells, before)


func test_settle_after_carving_has_no_floating_cells() -> void:
	var t: Terrain = Terrain.generate(300, 200, Rng.new(21))
	var before: Array[PackedByteArray] = _column_materials(t)
	var rng := Rng.new(4)
	# Cut tunnels underneath the surface so the cells above float.
	for i: int in range(12):
		t.carve_circle(rng.range_int(0, 299), rng.range_int(100, 190), rng.range_int(5, 25))
	var carved_before_settle: Array[PackedByteArray] = _column_materials(t)
	t.settle(0, 299)
	var after: Array[PackedByteArray] = _column_materials(t)
	for x: int in range(300):
		var seen_air: bool = false
		for y: int in range(199, -1, -1):
			var m: int = t.get_cell(x, y)
			if m == 0:
				seen_air = true
			else:
				assert_false(seen_air, "solid above air at (%d,%d)" % [x, y])
		assert_eq(after[x], carved_before_settle[x], "material order preserved in column %d" % x)
	assert_eq(before.size(), 300)


func _column_materials(t: Terrain) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	for x: int in range(t.width):
		var col: PackedByteArray = PackedByteArray()
		for y: int in range(t.height):
			var m: int = t.get_cell(x, y)
			if m != 0:
				col.append(m)
		out.append(col)
	return out


func test_settle_only_touches_requested_columns() -> void:
	var t := Terrain.new(5, 10)
	for x: int in range(5):
		t.cells[x * 10 + 2] = 4  # floating cell in every column
	t.settle(1, 3)
	assert_eq(t.get_cell(0, 2), 4, "column 0 untouched")
	assert_eq(t.get_cell(4, 2), 4, "column 4 untouched")
	assert_eq(t.get_cell(2, 9), 4, "column 2 settled")
	assert_eq(t.get_cell(2, 2), 0)


func test_flatten() -> void:
	var t: Terrain = Terrain.generate(100, 80, Rng.new(2))
	var outside_before: int = t.get_cell(0, 70)
	t.flatten(10, 20, 50)
	for x: int in range(10, 21):
		assert_eq(t.surface_y(x), 50, "flat at column %d" % x)
		for y: int in range(50, 80):
			assert_true(t.is_solid(x, y))
	assert_eq(t.get_cell(0, 70), outside_before, "other columns unchanged")
	# flatten a clipped range
	t.flatten(-5, 2, 40)
	assert_eq(t.surface_y(0), 40)
	assert_eq(t.surface_y(2), 40)


func test_write_read_roundtrip() -> void:
	var t: Terrain = Terrain.generate(120, 90, Rng.new(77))
	t.carve_circle(50, 60, 12)
	var buf := StreamPeerBuffer.new()
	t.write_bytes(buf)
	buf.seek(0)
	var u: Terrain = Terrain.read_bytes(buf)
	assert_eq(u.width, 120)
	assert_eq(u.height, 90)
	assert_eq(u.cells, t.cells)


func test_duplicate_terrain_is_independent() -> void:
	var t: Terrain = _solid_block(20, 20)
	var d: Terrain = t.duplicate_terrain()
	d.carve_circle(10, 10, 5)
	assert_true(t.is_solid(10, 10))
	assert_false(d.is_solid(10, 10))


func test_generate_performance_full_size() -> void:
	var t0: int = Time.get_ticks_msec()
	var t: Terrain = Terrain.generate(SimConstants.WORLD_W, SimConstants.WORLD_H, Rng.new(42))
	var ms: int = Time.get_ticks_msec() - t0
	print("PERF Terrain.generate 1600x900: %d ms" % ms)
	assert_eq(t.cells.size(), 1600 * 900)
	assert_lt(ms, SimTestUtil.perf_budget(1500), "generate must be fast on phones")
