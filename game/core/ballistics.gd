@warning_ignore_start("integer_division")
class_name Ballistics
extends RefCounted
## Projectile flight (docs/ARCHITECTURE.md section 7). Pure: never mutates state.


## Flight modes of `_fly`.
const MODE_PLAIN: int = 0
const MODE_SEEKER: int = 1  # homes on the nearest alive enemy after the apex
const MODE_APEX: int = 2  # stops at the apex (the splitter's main shell)

## Predicted miss distance (cells) beyond which the seeker's lateral accel saturates. The
## spec says 200, but that gain corrects only about a third of a miss before impact; see
## _homing_accel.
const HOMING_SATURATION: int = 25


## Simulates one shot. Returns {path: PackedInt32Array [x0,y0,x1,y1,...] Q16.16 per tick,
## end_reason: "terrain"|"tank"|"shield"|"lost"|"timeout"|"apex", end_x, end_y (cells),
## hit_tank (id of the tank hit or whose shield bubble was hit, else -1), ticks,
## repulsor_ticks / repulsor_down_tick: PackedInt32Array per tank index (ticks of repulsor
## charge used by this flight, and the tick the charge ran out or -1),
## px, py, vx, vy (Q16.16 position and velocity at the end), apex (bool), own_armed,
## own_bubble_armed (whether the shell has left the shooter's box / bubble)}.
## Pass SimConstants.WIND_USE_STATE as wind_override to use state.wind.
## The weapon def (read from `weapon_id`) selects the flight: the seeker homes after its
## apex, a splitter's main shell stops at its apex (end_reason "apex"; see trace_children for
## the children) and a beam is a straight line (see trace_beam). Active gravity wells
## (state.wells) bend every flight.
static func trace(state: MatchState, tank_id: int, angle: int, power: int, weapon_id: String,
		wind_override: int, max_ticks: int) -> Dictionary:
	var def: Dictionary = WeaponDefs.get_def(weapon_id)
	var behavior: String = def.get("behavior", "explode")
	if behavior == "beam":
		return trace_beam(state, tank_id, angle, def)
	var shooter: TankState = state.tanks[tank_id]
	var wind: int = state.wind if wind_override == SimConstants.WIND_USE_STATE else wind_override
	var speed: int = power * SimConstants.MAX_SPEED / 1000
	var cos_a: int = FixedMath.cos10(angle)
	var sin_a: int = FixedMath.sin10(angle)
	var px: int = FixedMath.from_cell(shooter.x) + cos_a * SimConstants.BARREL_LEN
	var py: int = FixedMath.from_cell(shooter.y - SimConstants.TANK_H) - sin_a * SimConstants.BARREL_LEN
	var vx: int = FixedMath.mul(cos_a, speed)
	var vy: int = -FixedMath.mul(sin_a, speed)
	var mode: int = MODE_PLAIN
	var accel: int = 0
	if behavior == "seeker":
		mode = MODE_SEEKER
		accel = def["accel"]
	elif behavior == "splitter":
		mode = MODE_APEX
	return _fly(state, tank_id, px, py, vx, vy, wind, max_ticks, mode, accel, false, not shooter.has_shield())


## Flight of a free shell from Q16.16 position (px, py) with velocity (vx, vy): the same
## physics as trace() with a plain shell. Used for the splitter's children. `own_armed` /
## `own_bubble_armed` carry over from the parent shell (see trace()).
static func fly_from(state: MatchState, tank_id: int, px: int, py: int, vx: int, vy: int,
		wind_override: int, max_ticks: int, own_armed: bool, own_bubble_armed: bool) -> Dictionary:
	var wind: int = state.wind if wind_override == SimConstants.WIND_USE_STATE else wind_override
	return _fly(state, tank_id, px, py, vx, vy, wind, max_ticks, MODE_PLAIN, 0, own_armed, own_bubble_armed)


## Q16.16 vx of splitter child `i` (0-based) of `n` for a parent moving at `vx`:
## vx + (i - (n-1)/2) * spread, where `spread` is in tenths of a cell/tick.
static func child_vx(vx: int, i: int, n: int, spread: int) -> int:
	var step: int = spread * FixedMath.ONE / 10
	return vx + ((2 * i - (n - 1)) * step) / 2


## Preview of a splitter shot: one trace per child (Array of trace dictionaries, each with an
## extra `start_tick` = the apex tick), computed against the current state without mutating
## it. Empty for other weapons, or when the main shell never reaches its apex.
static func trace_children(state: MatchState, tank_id: int, angle: int, power: int, weapon_id: String,
		wind_override: int, max_ticks: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var def: Dictionary = WeaponDefs.get_def(weapon_id)
	if def.get("behavior", "") != "splitter":
		return out
	var main: Dictionary = trace(state, tank_id, angle, power, weapon_id, wind_override, max_ticks)
	if main["end_reason"] != "apex":
		return out
	var n: int = def["children"]
	var apex_tick: int = main["ticks"]
	for i: int in range(n):
		var tr: Dictionary = fly_from(state, tank_id, main["px"], main["py"],
				child_vx(main["vx"], i, n, def["spread"]), main["vy"], wind_override,
				maxi(1, max_ticks - apex_tick), main["own_armed"], main["own_bubble_armed"])
		tr["start_tick"] = apex_tick
		out.append(tr)
	return out


## Straight beam from the muzzle along the aim direction, one cell per step, ignoring wind,
## gravity, wells and repulsors. Stops at the first tank or shield bubble, at the map edge
## (sides and top), after `length` steps, or once `cut` solid cells have been crossed.
## Returns the trace() keys plus `start_x/y` (muzzle cell), `solid_steps`, `first_solid_x/y`, `last_solid_x/y` (cells;
## -1 when no solid cell was crossed). `ticks` is the number of steps.
static func trace_beam(state: MatchState, tank_id: int, angle: int, def: Dictionary) -> Dictionary:
	var shooter: TankState = state.tanks[tank_id]
	var terrain: Terrain = state.terrain
	var cos_a: int = FixedMath.cos10(angle)
	var sin_a: int = FixedMath.sin10(angle)
	var px: int = FixedMath.from_cell(shooter.x) + cos_a * SimConstants.BARREL_LEN
	var py: int = FixedMath.from_cell(shooter.y - SimConstants.TANK_H) - sin_a * SimConstants.BARREL_LEN
	var length: int = def.get("length", 900)
	var cut: int = def.get("cut", 120)
	var start_x: int = FixedMath.to_cell(px)
	var start_y: int = FixedMath.to_cell(py)
	var shield_tanks: Array[TankState] = []
	for t: TankState in state.tanks:
		if t.alive and t.has_shield():
			shield_tanks.append(t)
	var shield_r2: int = SimConstants.SHIELD_RADIUS * SimConstants.SHIELD_RADIUS
	var own_bubble_armed: bool = not shooter.has_shield()
	var own_armed: bool = false
	var path: PackedInt32Array = PackedInt32Array()
	var end_reason: String = "lost"
	var end_x: int = FixedMath.to_cell(px)
	var end_y: int = FixedMath.to_cell(py)
	var hit_tank: int = -1
	var steps: int = 0
	var solid_steps: int = 0
	var first_x: int = -1
	var first_y: int = -1
	var last_x: int = -1
	var last_y: int = -1
	while steps < length:
		steps += 1
		px += cos_a
		py -= sin_a
		var cx: int = FixedMath.to_cell(px)
		var cy: int = FixedMath.to_cell(py)
		end_x = cx
		end_y = cy
		path.append(px)
		path.append(py)
		if cx < 0 or cx >= terrain.width or cy < 0:
			break
		var bubble: int = _bubble_at(shield_tanks, cx, cy, shield_r2, tank_id, own_bubble_armed)
		if bubble >= 0:
			end_reason = "shield"
			hit_tank = bubble
			break
		if not own_bubble_armed and not _in_bubble(shooter, cx, cy, shield_r2):
			own_bubble_armed = true
		var tank_hit: int = _tank_at(state, cx, cy, tank_id, own_armed)
		if tank_hit >= 0:
			end_reason = "tank"
			hit_tank = tank_hit
			break
		if not own_armed and not shooter.contains_cell(cx, cy):
			own_armed = true
		if terrain.is_solid(cx, cy):
			solid_steps += 1
			if first_x < 0:
				first_x = cx
				first_y = cy
			last_x = cx
			last_y = cy
			if solid_steps >= cut:
				end_reason = "terrain"
				break
	return {
		"path": path,
		"end_reason": end_reason,
		"end_x": end_x,
		"end_y": end_y,
		"hit_tank": hit_tank,
		"ticks": steps,
		"repulsor_ticks": _zeros(state.tanks.size(), 0),
		"repulsor_down_tick": _zeros(state.tanks.size(), -1),
		"start_x": start_x,
		"start_y": start_y,
		"solid_steps": solid_steps,
		"first_solid_x": first_x,
		"first_solid_y": first_y,
		"last_solid_x": last_x,
		"last_solid_y": last_y,
	}


static func _zeros(n: int, value: int) -> PackedInt32Array:
	var a: PackedInt32Array = PackedInt32Array()
	a.resize(n)
	a.fill(value)
	return a


## The shell flight proper. Per tick: accelerations (wind, repulsors, wells, seeker homing),
## then collision sub-steps (section 7).
static func _fly(state: MatchState, shooter_id: int, start_x: int, start_y: int, start_vx: int, start_vy: int,
		wind: int, max_ticks: int, mode: int, seek_accel: int, start_own_armed: bool,
		start_own_bubble_armed: bool) -> Dictionary:
	var shooter: TankState = state.tanks[shooter_id]
	var terrain: Terrain = state.terrain
	var wind_ax: int = wind * SimConstants.WIND_ACCEL_PER_UNIT
	var px: int = start_x
	var py: int = start_y
	var vx: int = start_vx
	var vy: int = start_vy

	# Shield bubbles and repulsors of other tanks (the shooter's own field never pushes its shell).
	var shield_tanks: Array[TankState] = []
	var repulsors: Array[TankState] = []
	var charge: PackedInt32Array = PackedInt32Array()
	var rep_ticks: PackedInt32Array = PackedInt32Array()
	var rep_down: PackedInt32Array = PackedInt32Array()
	charge.resize(state.tanks.size())
	rep_ticks.resize(state.tanks.size())
	rep_down.resize(state.tanks.size())
	rep_down.fill(-1)
	for t: TankState in state.tanks:
		if not t.alive:
			continue
		if t.has_shield():
			shield_tanks.append(t)
		if t.repulsor_charge > 0 and t.id != shooter_id:
			repulsors.append(t)
			charge[t.id] = t.repulsor_charge
	var shield_r2: int = SimConstants.SHIELD_RADIUS * SimConstants.SHIELD_RADIUS
	var own_bubble_armed: bool = start_own_bubble_armed
	var wells: Array[Dictionary] = state.wells
	var well_r: int = 0
	var well_strength: int = 0
	if not wells.is_empty():
		var wdef: Dictionary = WeaponDefs.get_def("singularity_seed")
		well_r = FixedMath.from_cell(wdef["well_r"] as int)
		well_strength = wdef["strength"]

	var path: PackedInt32Array = PackedInt32Array()
	var own_armed: bool = start_own_armed
	var end_reason: String = "timeout"
	var end_x: int = FixedMath.to_cell(px)
	var end_y: int = FixedMath.to_cell(py)
	var hit_tank: int = -1
	var ticks: int = 0
	var done: bool = false
	var apex: bool = false
	var homing: bool = false
	var target_x: int = 0
	var target_y: int = 0

	while ticks < max_ticks and not done:
		ticks += 1
		var push_x: int = 0
		var push_y: int = 0
		for rt: TankState in repulsors:
			if charge[rt.id] <= 0:
				continue
			var push: Vector2i = _repulse(rt, px, py)
			if push.x == 0 and push.y == 0:
				continue
			push_x += push.x
			push_y += push.y
			charge[rt.id] -= 1
			rep_ticks[rt.id] += 1
			if charge[rt.id] == 0:
				rep_down[rt.id] = ticks
		if not wells.is_empty():
			var pull: Vector2i = _well_pull(wells, px, py, well_r, well_strength)
			push_x += pull.x
			push_y += pull.y
		if homing:
			push_x += _homing_accel(target_x - _predict_x(px, py, vx, vy, target_y, wind_ax), seek_accel)
		vx += wind_ax + push_x
		vy += SimConstants.GRAVITY + push_y
		var n: int = maxi(1, (maxi(absi(vx), absi(vy)) + FixedMath.ONE - 1) >> 16)
		var ox: int = px
		var oy: int = py
		for i: int in range(n):
			px = ox + (vx * (i + 1)) / n
			py = oy + (vy * (i + 1)) / n
			var cx: int = FixedMath.to_cell(px)
			var cy: int = FixedMath.to_cell(py)
			end_x = cx
			end_y = cy
			if cx < 0 or cx >= terrain.width:
				end_reason = "lost"
				done = true
				break
			var bubble: int = _bubble_at(shield_tanks, cx, cy, shield_r2, shooter_id, own_bubble_armed)
			if bubble >= 0:
				end_reason = "shield"
				hit_tank = bubble
				done = true
				break
			if not own_bubble_armed and not _in_bubble(shooter, cx, cy, shield_r2):
				own_bubble_armed = true
			var tank_hit: int = _tank_at(state, cx, cy, shooter_id, own_armed)
			if tank_hit >= 0:
				end_reason = "tank"
				hit_tank = tank_hit
				done = true
				break
			if not own_armed and not shooter.contains_cell(cx, cy):
				own_armed = true
			if terrain.is_solid(cx, cy):
				end_reason = "terrain"
				done = true
				break
		path.append(px)
		path.append(py)
		if mode != MODE_PLAIN and not done and not apex and vy >= 0:
			apex = true
			if mode == MODE_APEX:
				end_reason = "apex"
				done = true
			else:
				var target: TankState = _nearest_enemy(state, shooter, px, py)
				homing = target != null
				if homing:
					target_x = FixedMath.from_cell(target.x)
					target_y = FixedMath.from_cell(target.y - SimConstants.TANK_H / 2)
	return {
		"path": path,
		"end_reason": end_reason,
		"end_x": end_x,
		"end_y": end_y,
		"hit_tank": hit_tank,
		"ticks": ticks,
		"repulsor_ticks": rep_ticks,
		"repulsor_down_tick": rep_down,
		"px": px,
		"py": py,
		"vx": vx,
		"vy": vy,
		"apex": apex,
		"own_armed": own_armed,
		"own_bubble_armed": own_bubble_armed,
	}


## Lateral (x) acceleration of a homing shell, proportional to the predicted miss `err`
## (Q16.16: target x minus predicted landing x), clamped to +-accel and saturating at
## HOMING_SATURATION cells. Spec resolution: section 21 steers on the current horizontal gap,
## which only pushes the shell further past a far target (it overshoots in nearly every case);
## steering on the predicted landing point is what lets the shell fix a miss.
static func _homing_accel(err: int, accel: int) -> int:
	var a: int = err * accel / FixedMath.from_cell(HOMING_SATURATION)
	return clampi(a, -accel, accel)


## Where (Q16.16 x) a shell at (px, py) moving at (vx, vy) would be when it falls to the
## Q16.16 height `ty` under gravity and wind alone. The current x if it never gets there.
static func _predict_x(px: int, py: int, vx: int, vy: int, ty: int, wind_ax: int) -> int:
	var disc: int = vy * vy / FixedMath.ONE + 2 * SimConstants.GRAVITY * (ty - py) / FixedMath.ONE
	if disc < 0:
		return px
	var t: int = (FixedMath.isqrt(disc * FixedMath.ONE) - vy) * FixedMath.ONE / SimConstants.GRAVITY
	if t <= 0:
		return px
	var ticks: int = t >> 16
	return px + vx * t / FixedMath.ONE + wind_ax * ticks * ticks / 2


## The alive enemy (other team) nearest to the Q16.16 point (px, py); the lowest id wins
## ties. null if there is none.
static func _nearest_enemy(state: MatchState, shooter: TankState, px: int, py: int) -> TankState:
	var best: TankState = null
	var best_d2: int = 0
	for t: TankState in state.tanks:
		if not t.alive or t.team == shooter.team:
			continue
		var dx: int = FixedMath.from_cell(t.x) - px
		var dy: int = FixedMath.from_cell(t.y - SimConstants.TANK_H / 2) - py
		var d2: int = dx * dx + dy * dy
		if best == null or d2 < best_d2:
			best = t
			best_d2 = d2
	return best


## Summed acceleration (Q16.16 per axis) of every active well on a shell at Q16.16 (px, py):
## for 4 < d < well_r, a = strength * (R - d) / R toward the well (section 21).
static func _well_pull(wells: Array[Dictionary], px: int, py: int, r_fp: int, strength: int) -> Vector2i:
	var ax: int = 0
	var ay: int = 0
	var min_d: int = FixedMath.from_cell(4)
	for w: Dictionary in wells:
		var dx: int = FixedMath.from_cell(w["x"] as int) - px
		var dy: int = FixedMath.from_cell(w["y"] as int) - py
		if absi(dx) >= r_fp or absi(dy) >= r_fp:
			continue
		var d: int = FixedMath.isqrt(dx * dx + dy * dy)
		if d <= min_d or d >= r_fp:
			continue
		var a: int = strength * (r_fp - d) / r_fp
		ax += a * dx / d
		ay += a * dy / d
	return Vector2i(ax, ay)


## Acceleration (Q16.16 per axis) a repulsor tank gives a shell at Q16.16 position (px, py):
## away from the tank centre, PUSH * (R - d) / R, zero at or beyond R (and at d = 0).
static func _repulse(t: TankState, px: int, py: int) -> Vector2i:
	var r_fp: int = FixedMath.from_cell(SimConstants.REPULSOR_RADIUS)
	var dx: int = px - FixedMath.from_cell(t.x)
	var dy: int = py - FixedMath.from_cell(t.y - SimConstants.SHIELD_CENTER_DY)
	if absi(dx) >= r_fp or absi(dy) >= r_fp:
		return Vector2i.ZERO
	var d: int = FixedMath.isqrt(dx * dx + dy * dy)
	if d >= r_fp or d == 0:
		return Vector2i.ZERO
	var a: int = SimConstants.REPULSOR_PUSH * (r_fp - d) / r_fp
	return Vector2i(a * dx / d, a * dy / d)


static func _in_bubble(t: TankState, cx: int, cy: int, r2: int) -> bool:
	var dx: int = cx - t.x
	var dy: int = cy - (t.y - SimConstants.SHIELD_CENTER_DY)
	return dx * dx + dy * dy <= r2


## Id of the first shielded tank whose bubble contains the cell, or -1. The shooter's own
## bubble only counts once the shell has left it (own_armed).
static func _bubble_at(shield_tanks: Array[TankState], cx: int, cy: int, r2: int, shooter_id: int,
		own_armed: bool) -> int:
	for t: TankState in shield_tanks:
		if t.id == shooter_id and not own_armed:
			continue
		if _in_bubble(t, cx, cy, r2):
			return t.id
	return -1


## Id of the alive tank whose box contains the cell, or -1. The shooter only counts once
## the shell has left its own box (own_armed).
static func _tank_at(state: MatchState, cx: int, cy: int, shooter_id: int, own_armed: bool) -> int:
	for t: TankState in state.tanks:
		if not t.alive:
			continue
		if t.id == shooter_id and not own_armed:
			continue
		if t.contains_cell(cx, cy):
			return t.id
	return -1
