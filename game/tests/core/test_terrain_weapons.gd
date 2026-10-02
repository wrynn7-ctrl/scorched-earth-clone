@warning_ignore_start("integer_division")
extends GutTest
## Terrain functions added for the weapon behaviours: carve_tunnel, pour, add_circle_skipping.

const W: int = 200
const H: int = 100


func _flat(ground_y: int = 50) -> Terrain:
	var t := Terrain.new(W, H)
	t.flatten(0, W - 1, ground_y)
	return t


func _solid_count(t: Terrain) -> int:
	var n: int = 0
	for b: int in t.cells:
		if b != 0:
			n += 1
	return n


## Reference: union of carve_circle at each integer step of the segment.
func _reference_tunnel(t: Terrain, x0: int, y0: int, x1: int, y1: int, r: int) -> void:
	var dx: int = x1 - x0
	var dy: int = y1 - y0
	var n: int = maxi(absi(dx), absi(dy))
	for i: int in range(n + 1):
		var cx: int = x0
		var cy: int = y0
		if n > 0:
			cx = x0 + (dx * i) / n
			cy = y0 + (dy * i) / n
		t.carve_circle(cx, cy, r)


# --- carve_tunnel ---------------------------------------------------------------------

func test_tunnel_matches_the_union_of_discs() -> void:
	var rng := Rng.new(11)
	for _k: int in range(60):
		var a: Terrain = _flat(30)
		var b: Terrain = a.duplicate_terrain()
		var x0: int = rng.range_int(-10, W + 10)
		var y0: int = rng.range_int(-10, H + 10)
		var x1: int = rng.range_int(-10, W + 10)
		var y1: int = rng.range_int(-10, H + 10)
		var r: int = rng.range_int(0, 9)
		a.carve_tunnel(x0, y0, x1, y1, r)
		_reference_tunnel(b, x0, y0, x1, y1, r)
		assert_eq(a.cells, b.cells, "tunnel (%d,%d)-(%d,%d) r%d" % [x0, y0, x1, y1, r])


func test_tunnel_horizontal_has_the_expected_shape() -> void:
	var t: Terrain = _flat(30)
	var rect: Rect2i = t.carve_tunnel(50, 60, 120, 60, 5)
	assert_eq(rect, Rect2i(45, 55, 81, 11))
	for x: int in [50, 85, 120]:
		assert_false(t.is_solid(x, 55))
		assert_false(t.is_solid(x, 65))
		assert_true(t.is_solid(x, 54))
		assert_true(t.is_solid(x, 66))
	assert_false(t.is_solid(50 - 5, 60), "round cap at the start")
	assert_true(t.is_solid(50 - 6, 60))
	assert_false(t.is_solid(120 + 5, 60), "round cap at the end")
	assert_true(t.is_solid(120 + 6, 60))


func test_tunnel_zero_length_is_a_disc() -> void:
	var a: Terrain = _flat(30)
	var b: Terrain = _flat(30)
	a.carve_tunnel(80, 60, 80, 60, 7)
	b.carve_circle(80, 60, 7)
	assert_eq(a.cells, b.cells)


func test_tunnel_is_symmetric_when_reversed_up_to_rounding() -> void:
	# Same end points: both directions carve the same cells for axis-aligned and 45 degree tunnels.
	for seg: Array in [[40, 60, 120, 60], [40, 40, 120, 40], [40, 40, 100, 100], [100, 40, 40, 100]]:
		var a: Terrain = _flat(30)
		var b: Terrain = _flat(30)
		a.carve_tunnel(seg[0], seg[1], seg[2], seg[3], 4)
		b.carve_tunnel(seg[2], seg[3], seg[0], seg[1], 4)
		assert_eq(a.cells, b.cells, str(seg))


func test_tunnel_edge_cases() -> void:
	var t: Terrain = _flat(30)
	var before: PackedByteArray = t.cells.duplicate()
	assert_eq(t.carve_tunnel(10, 60, 90, 60, -1), Rect2i(), "negative radius")
	assert_eq(t.cells, before)
	assert_eq(t.carve_tunnel(-100, 60, -50, 60, 5), Rect2i(), "entirely left of the map")
	assert_eq(t.carve_tunnel(10, 500, 90, 500, 5), Rect2i(), "entirely below the map")
	assert_eq(t.cells, before)
	var rect: Rect2i = t.carve_tunnel(-20, 60, 20, 60, 3)
	assert_eq(rect.position.x, 0, "clipped to the map")
	assert_false(t.is_solid(0, 60))
	assert_false(t.is_solid(22, 60))
	assert_true(t.is_solid(24, 60))
	t.carve_tunnel(180, 95, 260, 95, 6)
	assert_false(t.is_solid(W - 1, 95))
	t.carve_tunnel(100, 90, 100, 140, 4)
	assert_false(t.is_solid(100, H - 1), "bottom row clipped, not out of range")


func test_tunnel_diagonal_leaves_no_gaps() -> void:
	var t: Terrain = _flat(0)
	t.carve_tunnel(20, 10, 160, 90, 2)
	var n: int = maxi(absi(140), absi(80))
	for i: int in range(n + 1):
		var cx: int = 20 + (140 * i) / n
		var cy: int = 10 + (80 * i) / n
		assert_false(t.is_solid(cx, cy), "axis cell %d" % i)


# --- pour -----------------------------------------------------------------------------

func test_pour_stacks_in_order_on_top_of_each_column() -> void:
	var t: Terrain = _flat(50)
	var rect: Rect2i = t.pour(PackedInt32Array([10, 11, 10, 10, 12]), 7)
	assert_eq(t.surface_y(10), 47)
	assert_eq(t.surface_y(11), 49)
	assert_eq(t.surface_y(12), 49)
	assert_eq(t.get_cell(10, 47), 7)
	assert_eq(t.get_cell(10, 49), 7)
	assert_ne(t.get_cell(10, 50), 7, "ground keeps its own material")
	assert_eq(rect, Rect2i(10, 47, 3, 3))
	assert_eq(_solid_count(t), (H - 50) * W + 5)


func test_pour_ignores_off_map_columns_and_empty_lists() -> void:
	var t: Terrain = _flat(50)
	var before: PackedByteArray = t.cells.duplicate()
	assert_eq(t.pour(PackedInt32Array(), 3), Rect2i())
	assert_eq(t.pour(PackedInt32Array([-1, W, 5000]), 3), Rect2i())
	assert_eq(t.cells, before)
	t.pour(PackedInt32Array([-1, 0, W - 1, W]), 3)
	assert_eq(t.surface_y(0), 49)
	assert_eq(t.surface_y(W - 1), 49)
	assert_eq(_solid_count(t), (H - 50) * W + 2)


func test_pour_skips_columns_that_are_full() -> void:
	var t: Terrain = Terrain.new(W, H)
	t.flatten(0, W - 1, 1)  # only row 0 is free
	var rect: Rect2i = t.pour(PackedInt32Array([5, 5, 5, 6]), 2)
	assert_eq(t.surface_y(5), 0)
	assert_eq(t.surface_y(6), 0)
	assert_eq(rect, Rect2i(5, 0, 2, 1))
	assert_eq(_solid_count(t), (H - 1) * W + 2, "the 2nd and 3rd cell on column 5 are dropped")


func test_pour_on_an_empty_column_lands_on_the_bottom() -> void:
	var t := Terrain.new(W, H)
	t.pour(PackedInt32Array([3, 3]), 4)
	assert_eq(t.get_cell(3, H - 1), 4)
	assert_eq(t.get_cell(3, H - 2), 4)
	assert_eq(t.surface_y(3), H - 2)


# --- add_circle_skipping --------------------------------------------------------------

func test_add_circle_skipping_without_boxes_equals_add_circle() -> void:
	var a: Terrain = _flat(60)
	var b: Terrain = _flat(60)
	var ra: Rect2i = a.add_circle_skipping(100, 55, 20, 3, PackedInt32Array())
	var rb: Rect2i = b.add_circle(100, 55, 20, 3)
	assert_eq(a.cells, b.cells)
	assert_eq(ra, rb)


func test_add_circle_skipping_leaves_box_cells_empty() -> void:
	var t: Terrain = _flat(60)
	var box: PackedInt32Array = PackedInt32Array([90, 45, 114, 60])  # half-open
	t.add_circle_skipping(100, 55, 20, 3, box)
	for x: int in range(90, 114):
		for y: int in range(45, 60):
			assert_false(t.is_solid(x, y), "box cell %d,%d stays air" % [x, y])
	assert_true(t.is_solid(89, 55), "left of the box is filled")
	assert_true(t.is_solid(114, 55), "right of the box is filled")
	assert_true(t.is_solid(100, 44), "above the box is filled")


func test_add_circle_skipping_with_several_boxes_and_never_overwrites() -> void:
	var t: Terrain = _flat(60)
	t.cells[100 * H + 55] = 9  # an existing cell is never changed
	t.cells[100 * H + 70] = 9
	var boxes: PackedInt32Array = PackedInt32Array([80, 40, 90, 60, 105, 50, 130, 58])
	var ref: Terrain = t.duplicate_terrain()
	t.add_circle_skipping(100, 55, 25, 3, boxes)
	ref.add_circle(100, 55, 25, 3)
	assert_eq(t.get_cell(100, 55), 9)
	assert_eq(t.get_cell(100, 70), 9)
	var skipped: int = 0
	for x: int in range(W):
		for y: int in range(H):
			if t.get_cell(x, y) != ref.get_cell(x, y):
				skipped += 1
				var inside: bool = (x >= 80 and x < 90 and y >= 40 and y < 60) or (x >= 105 and x < 130 and y >= 50 and y < 58)
				assert_true(inside, "only box cells differ: %d,%d" % [x, y])
				assert_eq(t.get_cell(x, y), 0)
	assert_gt(skipped, 0)


func test_add_circle_skipping_edges() -> void:
	var t: Terrain = _flat(60)
	assert_eq(t.add_circle_skipping(100, 55, -1, 3, PackedInt32Array()), Rect2i())
	assert_eq(t.add_circle_skipping(-100, 55, 10, 3, PackedInt32Array()), Rect2i())
	var rect: Rect2i = t.add_circle_skipping(2, 2, 10, 3, PackedInt32Array([0, 0, 5, 5]))
	assert_eq(rect.position, Vector2i(0, 0), "clipped to the map")
	assert_false(t.is_solid(1, 1), "inside the box")
	assert_true(t.is_solid(8, 2))
