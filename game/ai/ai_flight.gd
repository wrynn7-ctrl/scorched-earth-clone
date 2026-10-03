@warning_ignore_start("integer_division")
class_name AiFlight
extends RefCounted
## A cheap integer copy of the shell physics, used by the aim search.
##
## Why it exists: one Ballistics.trace costs about 2.5 ms in GDScript (more with wells or many
## tanks), and the AI has to try several powers and angles per decision, in about 15 ms. This
## class flies the same semi-implicit Euler flight as Ballistics (so a free flight is *exactly*
## the same path) but only looks at the terrain where the shell is near the ground, using a
## lazily filled height map with a binary search per column.
## It models wind, gravity wells and repulsor fields. It ignores tank boxes and shield bubbles
## (a shell that hits an enemy is a fine outcome for the AI) and a Seeker's steering.
## AimSolver confirms a plan with the real Ballistics.trace in the one case where that matters
## (a teammate standing in the line of fire).
## Pure integer maths. Never mutates the state.

const REASON_NONE: int = 0
const REASON_TERRAIN: int = 1
const REASON_LOST: int = 2
const REASON_TIMEOUT: int = 3


var terrain: Terrain
var _top: PackedInt32Array = PackedInt32Array()
var _wells: Array[Dictionary] = []
var _well_r: int = 0
var _well_strength: int = 0
# Active repulsor fields of the other tanks: Q16.16 centre and charge (ticks left).
var _rep_x: PackedInt32Array = PackedInt32Array()
var _rep_y: PackedInt32Array = PackedInt32Array()
var _rep_charge: PackedInt32Array = PackedInt32Array()
# Q16.16 box around every well and repulsor field: outside it no force acts, so most ticks skip them.
var _fx0: int = 0
var _fx1: int = 0
var _fy0: int = 0
var _fy1: int = 0
# Highest terrain row of the whole map (computed on first use): above it nothing can be hit.
var _peak_row: int = -1
var _free: bool = false

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
## True when the last flight stopped at the `stop_y` row in open air rather than at terrain.
var r_row_stop: bool = false
## Q16.16 launch position (set by fly_shot), handy for range estimates.
var muzzle_px: int = 0
var muzzle_py: int = 0


## `wells` is MatchState.wells (the gravity wells bend every flight); `repulsors` the other
## tanks (never the shooter) that may have a charged repulsor field.
func _init(t: Terrain, wells: Array[Dictionary] = [], repulsors: Array[TankState] = []) -> void:
	terrain = t
	_top.resize(t.width)
	_top.fill(-1)
	if not wells.is_empty():
		var def: Dictionary = WeaponDefs.get_def("singularity_seed")
		_wells = wells
		_well_r = FixedMath.from_cell(def["well_r"] as int)
		_well_strength = def["strength"]
	for r: TankState in repulsors:
		if r.alive and r.repulsor_charge > 0:
			_rep_x.append(FixedMath.from_cell(r.x))
			_rep_y.append(FixedMath.from_cell(r.y - SimConstants.SHIELD_CENTER_DY))
			_rep_charge.append(r.repulsor_charge)
	_build_force_box()


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


## Highest terrain row of the map (the smallest surface y over all columns). Most columns are
## rejected with one probe: a column only needs a binary search if it is solid above the best
## row found so far. Columns are visited in a scattered order so the best row settles quickly.
func peak_row() -> int:
	if _peak_row < 0:
		var best: int = terrain.height
		var w: int = terrain.width
		for i: int in range(w):
			var x: int = (i * 37) % w
			if best > 0 and terrain.is_solid(x, best - 1):
				best = mini(best, surface(x))
		_peak_row = best
	return _peak_row


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
## With `free` the shell ignores the terrain altogether (only the stop_y row and the map sides
## end it): where would the believed physics have taken it, had nothing been in the way?
func fly_shot(tank_x: int, tank_y: int, angle: int, power: int, wind: int, max_ticks: int,
		stop_y: int = -1, split_dvx: int = 0, free: bool = false) -> void:
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
	r_row_stop = false
	_free = free
	var peak: int = peak_row()
	var split_pending: bool = split_dvx != 0
	var charge: PackedInt32Array = _rep_charge.duplicate()
	var forces: bool = not _wells.is_empty() or not charge.is_empty()
	for tick: int in range(1, max_ticks + 1):
		if not forces or px <= _fx0 or px >= _fx1 or py <= _fy0 or py >= _fy1:
			vx += wind_ax
			vy += SimConstants.GRAVITY
		else:
			var push: Vector2i = _repulse_all(px, py, charge)
			if not _wells.is_empty():
				push += _well_pull(px, py)
			vx += wind_ax + push.x
			vy += SimConstants.GRAVITY + push.y
		var ox: int = px
		var oy: int = py
		px = ox + vx
		py = oy + vy
		var cx: int = px >> 16
		var cy: int = py >> 16
		var check: bool = false
		if cx < 0 or cx >= width:
			check = true
		else:
			# Can any cell this tick passes through be solid? Only if its lowest row is at or
			# below the highest ground of the columns it spans (the map's peak row prunes the
			# open-sky ticks without looking at a single column).
			var low: int = maxi(oy, py) >> 16
			if not free and low >= peak:
				var a: int = clampi(mini(ox >> 16, cx), 0, width - 1)
				var b: int = clampi(maxi(ox >> 16, cx), 0, width - 1)
				var top: int = surface(a)
				for c: int in range(a + 1, b + 1):
					top = mini(top, surface(c))
				check = low >= top
			if not check and stop_y >= 0 and vy > 0 and cy >= stop_y:
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
		elif not _free and terrain.is_solid(cx, cy):
			reason = REASON_TERRAIN
			r_row_stop = false
		elif stop_y >= 0 and vy > 0 and cy >= stop_y:
			reason = REASON_TERRAIN
			r_row_stop = true
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


## Same as Ballistics' repulsor push: away from the field's centre, PUSH * (R - d) / R, one
## charge used per tick the shell is inside. `charge` is this flight's copy of the charges.
func _repulse_all(px: int, py: int, charge: PackedInt32Array) -> Vector2i:
	var ax: int = 0
	var ay: int = 0
	var r_fp: int = FixedMath.from_cell(SimConstants.REPULSOR_RADIUS)
	for i: int in range(charge.size()):
		if charge[i] <= 0:
			continue
		var dx: int = px - _rep_x[i]
		var dy: int = py - _rep_y[i]
		if absi(dx) >= r_fp or absi(dy) >= r_fp:
			continue
		var d: int = FixedMath.isqrt(dx * dx + dy * dy)
		if d >= r_fp or d == 0:
			continue
		var a: int = SimConstants.REPULSOR_PUSH * (r_fp - d) / r_fp
		ax += a * dx / d
		ay += a * dy / d
		charge[i] -= 1
	return Vector2i(ax, ay)


func _build_force_box() -> void:
	var first: bool = true
	var r_rep: int = FixedMath.from_cell(SimConstants.REPULSOR_RADIUS)
	for w: Dictionary in _wells:
		_grow_box(FixedMath.from_cell(w["x"] as int), FixedMath.from_cell(w["y"] as int), _well_r, first)
		first = false
	for i: int in range(_rep_x.size()):
		_grow_box(_rep_x[i], _rep_y[i], r_rep, first)
		first = false


func _grow_box(cx: int, cy: int, r: int, first: bool) -> void:
	if first:
		_fx0 = cx - r
		_fx1 = cx + r
		_fy0 = cy - r
		_fy1 = cy + r
	else:
		_fx0 = mini(_fx0, cx - r)
		_fx1 = maxi(_fx1, cx + r)
		_fy0 = mini(_fy0, cy - r)
		_fy1 = maxi(_fy1, cy + r)
