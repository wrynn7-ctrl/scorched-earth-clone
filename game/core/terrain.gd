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
