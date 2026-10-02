@warning_ignore_start("integer_division")
class_name Terrain
extends RefCounted
## Destructible terrain grid, column-major: index = x * height + y.
## 0 = air, 1..15 = dirt materials (strata bands), 16..255 reserved.

const BAND_HEIGHT: int = 32
const BAND_COUNT: int = 15
## Reported by get_cell below the map (matches is_solid's bedrock floor). Never stored in cells.
const BEDROCK: int = 16

var width: int = 0
var height: int = 0
var cells: PackedByteArray = PackedByteArray()


func _init(w: int = 0, h: int = 0) -> void:
	width = w
	height = h
	cells.resize(w * h)  # zero filled = all air


## Material for a cell `depth` below the surface of its column.
static func material_at_depth(depth: int) -> int:
	return 1 + (maxi(depth, 0) / BAND_HEIGHT) % BAND_COUNT


## Rolling hills from 4 octaves of integer value noise. Surface stays within
## [h*30/100, h*85/100].
static func generate(w: int, h: int, rng: Rng) -> Terrain:
	var t := Terrain.new(0, h)
	t.width = w
	var lo: int = h * 30 / 100
	var hi: int = h * 85 / 100
	var acc: PackedInt32Array = PackedInt32Array()
	acc.resize(w)
	var weight: int = 8
	var weight_sum: int = 0
	for o: int in range(4):
		var period: int = maxi(8, (w >> 2) >> o)
		var n_pts: int = w / period + 3
		var lat: PackedInt32Array = PackedInt32Array()
		for k: int in range(n_pts):
			lat.append(rng.range_int(0, 1023))
		for x: int in range(w):
			var k: int = x / period
			var frac: int = ((x % period) * 1024) / period
			var s: int = (frac * frac * (3 * 1024 - 2 * frac)) >> 20  # smoothstep, 0..1024
			var a: int = lat[k]
			var v: int = a + (((lat[k + 1] - a) * s) >> 10)
			acc[x] += v * weight
		weight_sum += weight
		weight >>= 1
	# Build each column with bulk slice/append (no per-cell loop).
	var air: PackedByteArray = PackedByteArray()
	air.resize(h)
	var strip: PackedByteArray = PackedByteArray()
	strip.resize(h)
	for d: int in range(h):
		strip[d] = material_at_depth(d)
	var out: PackedByteArray = PackedByteArray()
	for x: int in range(w):
		var v: int = acc[x] / weight_sum
		v = clampi((v - 512) * 5 / 4 + 512, 0, 1023)  # stretch contrast a little
		var sy: int = lo + (hi - lo) * v / 1023
		out.append_array(air.slice(0, sy))
		out.append_array(strip.slice(0, h - sy))
	t.cells = out
	return t


func duplicate_terrain() -> Terrain:
	var t := Terrain.new(0, height)
	t.width = width
	t.cells = cells.duplicate()
	return t


func get_cell(x: int, y: int) -> int:
	if x < 0 or x >= width or y < 0:
		return 0
	if y >= height:
		return BEDROCK
	return cells[x * height + y]


## Outside the side walls and above the map is open; y >= height is bedrock.
func is_solid(x: int, y: int) -> bool:
	if x < 0 or x >= width or y < 0:
		return false
	if y >= height:
		return true
	return cells[x * height + y] != 0


## First solid y from the top, or `height` if the column is empty.
func surface_y(x: int) -> int:
	if x < 0 or x >= width:
		return height
	var base: int = x * height
	for y: int in range(height):
		if cells[base + y] != 0:
			return y
	return height


## Clears cells with dx^2 + dy^2 <= r^2. Returns the clipped bounding box of the
## circle (empty Rect2i if nothing is on the map or r < 0).
func carve_circle(cx: int, cy: int, r: int) -> Rect2i:
	return _fill_circle(cx, cy, r, 0, false)


## Fills air cells only, within the circle, with `material`.
func add_circle(cx: int, cy: int, r: int, material: int) -> Rect2i:
	return _fill_circle(cx, cy, r, material, true)


## Fills air cells only, within the circle, skipping every cell inside the half-open boxes
## `skip_boxes` = [x0, y0, x1, y1, ...] (cells with x0 <= x < x1 and y0 <= y < y1). Used by the
## dirt weapons: the core skips alive tank boxes and records them in the `terrain_add` event so
## the show layer can repeat exactly the same call.
func add_circle_skipping(cx: int, cy: int, r: int, material: int, skip_boxes: PackedInt32Array) -> Rect2i:
	if r < 0:
		return Rect2i()
	var x0: int = maxi(cx - r, 0)
	var x1: int = mini(cx + r, width - 1)
	var bb_y0: int = maxi(cy - r, 0)
	var bb_y1: int = mini(cy + r, height - 1)
	if x0 > x1 or bb_y0 > bb_y1:
		return Rect2i()
	var r2: int = r * r
	var nb: int = skip_boxes.size() / 4
	for x: int in range(x0, x1 + 1):
		var dx: int = x - cx
		var dy: int = FixedMath.isqrt(r2 - dx * dx)
		var y0: int = maxi(cy - dy, 0)
		var y1: int = mini(cy + dy, height - 1)
		var base: int = x * height
		var blocked: PackedInt32Array = PackedInt32Array()  # [ya0, ya1) pairs for this column
		for b: int in range(nb):
			if x >= skip_boxes[b * 4] and x < skip_boxes[b * 4 + 2]:
				blocked.append(skip_boxes[b * 4 + 1])
				blocked.append(skip_boxes[b * 4 + 3])
		for y: int in range(y0, y1 + 1):
			if cells[base + y] != 0 or _in_ranges(blocked, y):
				continue
			cells[base + y] = material
	return Rect2i(x0, bb_y0, x1 - x0 + 1, bb_y1 - bb_y0 + 1)


static func _in_ranges(ranges: PackedInt32Array, y: int) -> bool:
	for i: int in range(0, ranges.size(), 2):
		if y >= ranges[i] and y < ranges[i + 1]:
			return true
	return false


## Clears every cell within `r` of the segment (x0, y0)-(x1, y1): the union of discs of radius
## `r` centred on each integer step of the segment (step i of n = max(|dx|, |dy|) is at
## (x0 + dx*i/n, y0 + dy*i/n), integer division truncating toward zero). Returns the clipped
## bounding box (empty if nothing is on the map or r < 0). Used by the tunneler and the beam;
## the show layer re-applies it from the `tunnel` event.
func carve_tunnel(x0: int, y0: int, x1: int, y1: int, r: int) -> Rect2i:
	if r < 0:
		return Rect2i()
	var bx0: int = maxi(mini(x0, x1) - r, 0)
	var bx1: int = mini(maxi(x0, x1) + r, width - 1)
	var by0: int = maxi(mini(y0, y1) - r, 0)
	var by1: int = mini(maxi(y0, y1) + r, height - 1)
	if bx0 > bx1 or by0 > by1:
		return Rect2i()
	var cols: int = bx1 - bx0 + 1
	var lo: PackedInt32Array = PackedInt32Array()
	var hi: PackedInt32Array = PackedInt32Array()
	lo.resize(cols)
	hi.resize(cols)
	lo.fill(height)
	hi.fill(-1)
	var half: PackedInt32Array = PackedInt32Array()
	for k: int in range(r + 1):
		half.append(FixedMath.isqrt(r * r - k * k))
	var dx: int = x1 - x0
	var dy: int = y1 - y0
	var n: int = maxi(absi(dx), absi(dy))
	# A convex capsule has one y-interval per column, and discs one step apart overlap, so the
	# per-column union of the discs' chords is exact.
	for i: int in range(n + 1):
		var cx: int = x0
		var cy: int = y0
		if n > 0:
			cx = x0 + (dx * i) / n
			cy = y0 + (dy * i) / n
		var xa: int = maxi(cx - r, bx0)
		var xb: int = mini(cx + r, bx1)
		for x: int in range(xa, xb + 1):
			var h: int = half[absi(x - cx)]
			var k: int = x - bx0
			lo[k] = mini(lo[k], cy - h)
			hi[k] = maxi(hi[k], cy + h)
	for k: int in range(cols):
		var ya: int = maxi(lo[k], 0)
		var yb: int = mini(hi[k], height - 1)
		var base: int = (bx0 + k) * height
		for y: int in range(ya, yb + 1):
			cells[base + y] = 0
	return Rect2i(bx0, by0, cols, by1 - by0 + 1)


## Places one cell of `material` on top of each listed column, in order (the cell above the
## column's first solid cell; a column that is already full to y = 0 is skipped, off-map
## columns are ignored). Returns the bounding box of the cells placed (empty if none). Used
## by the sludge; the show layer re-applies it from the `terrain_pour` event.
func pour(columns: PackedInt32Array, material: int) -> Rect2i:
	var tops: PackedInt32Array = PackedInt32Array()
	tops.resize(width)
	tops.fill(-1)
	var min_x: int = width
	var max_x: int = -1
	var min_y: int = height
	var max_y: int = -1
	for x: int in columns:
		if x < 0 or x >= width:
			continue
		var top: int = tops[x]
		if top < 0:
			top = surface_y(x)
		if top <= 0:
			tops[x] = 0
			continue
		top -= 1
		tops[x] = top
		cells[x * height + top] = material
		min_x = mini(min_x, x)
		max_x = maxi(max_x, x)
		min_y = mini(min_y, top)
		max_y = maxi(max_y, top)
	if max_x < 0:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _fill_circle(cx: int, cy: int, r: int, value: int, air_only: bool) -> Rect2i:
	if r < 0:
		return Rect2i()
	var x0: int = maxi(cx - r, 0)
	var x1: int = mini(cx + r, width - 1)
	var bb_y0: int = maxi(cy - r, 0)
	var bb_y1: int = mini(cy + r, height - 1)
	if x0 > x1 or bb_y0 > bb_y1:
		return Rect2i()
	var r2: int = r * r
	for x: int in range(x0, x1 + 1):
		var dx: int = x - cx
		var dy: int = FixedMath.isqrt(r2 - dx * dx)
		var y0: int = maxi(cy - dy, 0)
		var y1: int = mini(cy + dy, height - 1)
		var base: int = x * height
		if air_only:
			for y: int in range(y0, y1 + 1):
				if cells[base + y] == 0:
					cells[base + y] = value
		else:
			for y: int in range(y0, y1 + 1):
				cells[base + y] = 0
	return Rect2i(x0, bb_y0, x1 - x0 + 1, bb_y1 - bb_y0 + 1)


## In each column of [x0, x1] (inclusive), solid cells fall straight down until nothing
## floats; material order is preserved. Returns one segment per moved solid run:
## {x, from_y, to_y, length} where from_y/to_y are the run's top cell before/after.
func settle(x0: int, x1: int) -> Array[Dictionary]:
	var falls: Array[Dictionary] = []
	var cx0: int = maxi(x0, 0)
	var cx1: int = mini(x1, width - 1)
	for x: int in range(cx0, cx1 + 1):
		_settle_column(x, falls)
	return falls


func _settle_column(x: int, falls: Array[Dictionary]) -> void:
	var base: int = x * height
	var air_below: int = 0
	var y: int = height - 1
	while y >= 0:
		if cells[base + y] == 0:
			air_below += 1
			y -= 1
			continue
		# Found the bottom of a solid run; find its top.
		var bot: int = y
		while y >= 0 and cells[base + y] != 0:
			y -= 1
		var top: int = y + 1
		if air_below > 0:
			for yy: int in range(bot, top - 1, -1):
				cells[base + yy + air_below] = cells[base + yy]
			var clear_end: int = mini(bot, top + air_below - 1)
			for yy: int in range(top, clear_end + 1):
				cells[base + yy] = 0
			falls.append({"x": x, "from_y": top, "to_y": top + air_below, "length": bot - top + 1})


## Columns [x0, x1] (inclusive): cells above y become air, cells at/below y become solid.
## Existing solid cells keep their material; new solid cells get a depth-band material.
func flatten(x0: int, x1: int, y: int) -> void:
	var cx0: int = maxi(x0, 0)
	var cx1: int = mini(x1, width - 1)
	var fy: int = clampi(y, 0, height)
	for x: int in range(cx0, cx1 + 1):
		var base: int = x * height
		for yy: int in range(0, fy):
			cells[base + yy] = 0
		for yy: int in range(fy, height):
			if cells[base + yy] == 0:
				cells[base + yy] = material_at_depth(yy - fy)


func write_bytes(buf: StreamPeerBuffer) -> void:
	buf.put_32(width)
	buf.put_32(height)
	buf.put_data(cells)


static func read_bytes(buf: StreamPeerBuffer) -> Terrain:
	var w: int = buf.get_32()
	var h: int = buf.get_32()
	var t := Terrain.new(0, h)
	t.width = w
	var res: Array = buf.get_data(w * h)
	t.cells = res[1]
	return t
