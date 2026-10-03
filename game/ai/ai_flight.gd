@warning_ignore_start("integer_division")
class_name AiFlight
extends RefCounted
## A cheap integer copy of the shell physics, used by the aim search.
##
## Why it exists: one Ballistics.trace costs about 2.5 ms in GDScript, and the AI has to try
## several powers and angles per decision. This class flies the same semi-implicit Euler
## flight as Ballistics (so a free flight is *exactly* the same path) but only looks at the
## terrain where the shell is near the ground, using a lazily filled height map and a binary
## search per column. It ignores tank boxes, shields, repulsors and wells. The AI uses it to
## search, then confirms the final answer with the real Ballistics.trace when something the
## model does not know about could matter (a repulsor, a steering shell).
## It does include gravity wells, because a trace with a well active is several times slower.
## Pure integer maths. Never mutates the state.

const REASON_NONE: int = 0
const REASON_TERRAIN: int = 1
const REASON_LOST: int = 2
const REASON_TIMEOUT: int = 3

## Shells above this row are assumed to be over open sky (generated surfaces are at y >= 270).
const SKY_Y: int = 150
## A tick that ends this close above the ground is walked sub-step by sub-step, because a
## shell skimming a crest can dip into it between two tick-end samples.
const GRAZE: int = 4

var terrain: Terrain
var _top: PackedInt32Array = PackedInt32Array()
var _wells: Array[Dictionary] = []
var _well_r: int = 0
var _well_strength: int = 0

## Results of the last fly_shot(): why it ended, the cell it ended in, and the Q16.16
## position/velocity at the end (what Ballistics.trace reports as px, py, vx, vy).
var r_reason: int = REASON_NONE
var r_x: int = 0
var r_y: int = 0
var r_px: int = 0
var r_py: int = 0
var r_vx: int = 0
var r_vy: int = 0
var r_ticks: int = 0
## Q16.16 launch position (set by fly_shot), handy for range estimates.
var muzzle_px: int = 0
var muzzle_py: int = 0


## `wells` is MatchState.wells (the gravity wells bend every flight).
func _init(t: Terrain, wells: Array[Dictionary] = []) -> void:
	terrain = t
	_top.resize(t.width)
	_top.fill(-1)
	if not wells.is_empty():
		var def: Dictionary = WeaponDefs.get_def("singularity_seed")
		_wells = wells
		_well_r = FixedMath.from_cell(def["well_r"] as int)
		_well_strength = def["strength"]


## First solid y of column x (terrain.height when the column is empty). Terrain columns never
## float (settle), so "solid" is monotone down a column and a binary search finds the surface.
func surface(x: int) -> int:
	var v: int = _top[x]
	if v < 0:
		var lo: int = 0
		var hi: int = terrain.height
		while lo < hi:
			var mid: int = (lo + hi) / 2
			if terrain.is_solid(x, mid):
				hi = mid
			else:
				lo = mid + 1
		v = lo
		_top[x] = v
	return v


## Resting y of a tank centred on column cx (the highest surface under its width).
func rest_y(cx: int) -> int:
	var best: int = terrain.height
	var half: int = SimConstants.TANK_W / 2
	for c: int in range(cx - half, cx + half):
		if c >= 0 and c < terrain.width:
			best = mini(best, surface(c))
	return best


## Flies a shell launched from a tank standing at (tank_x, tank_y). `wind` is the wind the
## AI believes (cell/tick^2 = wind * WIND_ACCEL_PER_UNIT). With stop_y >= 0 the flight also
## ends when the shell, on its way down, reaches that row (used to read where an old shot
## crossed the height it landed at, even though its crater has changed the terrain since).
## With split_dvx != 0 the shell behaves like the splitter child that starts with that extra
## Q16.16 vx at the apex (the first tick where it is no longer rising).
func fly_shot(tank_x: int, tank_y: int, angle: int, power: int, wind: int, max_ticks: int,
		stop_y: int = -1, split_dvx: int = 0) -> void:
	var speed: int = power * SimConstants.MAX_SPEED / 1000
	var cos_a: int = FixedMath.cos10(angle)
	var sin_a: int = FixedMath.sin10(angle)
	var px: int = FixedMath.from_cell(tank_x) + cos_a * SimConstants.BARREL_LEN
	var py: int = FixedMath.from_cell(tank_y - SimConstants.TANK_H) - sin_a * SimConstants.BARREL_LEN
	muzzle_px = px
	muzzle_py = py
	var vx: int = FixedMath.mul(cos_a, speed)
	var vy: int = -FixedMath.mul(sin_a, speed)
	var wind_ax: int = wind * SimConstants.WIND_ACCEL_PER_UNIT
	var width: int = terrain.width
	r_reason = REASON_TIMEOUT
	r_ticks = max_ticks
	var split_pending: bool = split_dvx != 0
	for tick: int in range(1, max_ticks + 1):
		if _wells.is_empty():
			vx += wind_ax
			vy += SimConstants.GRAVITY
		else:
			var pull: Vector2i = _well_pull(px, py)
			vx += wind_ax + pull.x
			vy += SimConstants.GRAVITY + pull.y
		var ox: int = px
		var oy: int = py
		px = ox + vx
		py = oy + vy
		var cx: int = px >> 16
		var cy: int = py >> 16
		var check: bool = false
		if cx < 0 or cx >= width:
			check = true
		elif cy >= SKY_Y:
			if cy + GRAZE >= surface(cx) or (stop_y >= 0 and vy > 0 and cy >= stop_y):
				check = true
		if check and _resolve_tick(ox, oy, vx, vy, stop_y):
			r_ticks = tick
			return
		if split_pending and vy >= 0:
			split_pending = false
			vx += split_dvx
	r_x = px >> 16
	r_y = py >> 16
	r_px = px
	r_py = py
	r_vx = vx
	r_vy = vy


## Walks the sub-steps of the tick that started at (ox, oy) with velocity (vx, vy), exactly as
## Ballistics does, and records the first one that leaves the map, touches terrain or (with
## stop_y) reaches the row. False if none does.
func _resolve_tick(ox: int, oy: int, vx: int, vy: int, stop_y: int) -> bool:
	var n: int = maxi(1, (maxi(absi(vx), absi(vy)) + FixedMath.ONE - 1) >> 16)
	for i: int in range(n):
		var sx: int = ox + (vx * (i + 1)) / n
		var sy: int = oy + (vy * (i + 1)) / n
		var cx: int = sx >> 16
		var cy: int = sy >> 16
		var reason: int = REASON_NONE
		if cx < 0 or cx >= terrain.width:
			reason = REASON_LOST
		elif terrain.is_solid(cx, cy) or (stop_y >= 0 and vy > 0 and cy >= stop_y):
			reason = REASON_TERRAIN
		if reason != REASON_NONE:
			r_reason = reason
			r_x = cx
			r_y = cy
			r_px = sx
			r_py = sy
			r_vx = vx
			r_vy = vy
			return true
	return false


## Same formula as Ballistics' gravity-well pull: for 4 < d < well radius,
## a = strength * (R - d) / R towards the well, summed over all wells.
func _well_pull(px: int, py: int) -> Vector2i:
	var ax: int = 0
	var ay: int = 0
	var min_d: int = FixedMath.from_cell(4)
	for w: Dictionary in _wells:
		var dx: int = FixedMath.from_cell(w["x"] as int) - px
		var dy: int = FixedMath.from_cell(w["y"] as int) - py
		if absi(dx) >= _well_r or absi(dy) >= _well_r:
			continue
		var d: int = FixedMath.isqrt(dx * dx + dy * dy)
		if d <= min_d or d >= _well_r:
			continue
		var a: int = _well_strength * (_well_r - d) / _well_r
		ax += a * dx / d
		ay += a * dy / d
	return Vector2i(ax, ay)
