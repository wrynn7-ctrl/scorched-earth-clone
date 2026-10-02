@warning_ignore_start("integer_division")
class_name Ballistics
extends RefCounted
## Projectile flight (docs/ARCHITECTURE.md section 7). Pure: never mutates state.


## Simulates one shot. Returns {path: PackedInt32Array [x0,y0,x1,y1,...] Q16.16 per tick,
## end_reason: "terrain"|"tank"|"shield"|"lost"|"timeout", end_x, end_y (cells),
## hit_tank (id of the tank hit or whose shield bubble was hit, else -1), ticks,
## repulsor_ticks / repulsor_down_tick: PackedInt32Array per tank index (ticks of repulsor
## charge used by this flight, and the tick the charge ran out or -1)}.
## Pass SimConstants.WIND_USE_STATE as wind_override to use state.wind.
## `weapon_id` is reserved for per-weapon flight parameters (all weapons share the same
## flight so far).
static func trace(state: MatchState, tank_id: int, angle: int, power: int, _weapon_id: String,
		wind_override: int, max_ticks: int) -> Dictionary:
	var shooter: TankState = state.tanks[tank_id]
	var terrain: Terrain = state.terrain
	var wind: int = state.wind if wind_override == SimConstants.WIND_USE_STATE else wind_override
	var wind_ax: int = wind * SimConstants.WIND_ACCEL_PER_UNIT

	var speed: int = power * SimConstants.MAX_SPEED / 1000
	var cos_a: int = FixedMath.cos10(angle)
	var sin_a: int = FixedMath.sin10(angle)
	var px: int = FixedMath.from_cell(shooter.x) + cos_a * SimConstants.BARREL_LEN
	var py: int = FixedMath.from_cell(shooter.y - SimConstants.TANK_H) - sin_a * SimConstants.BARREL_LEN
	var vx: int = FixedMath.mul(cos_a, speed)
	var vy: int = -FixedMath.mul(sin_a, speed)

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
		if t.repulsor_charge > 0 and t.id != tank_id:
			repulsors.append(t)
			charge[t.id] = t.repulsor_charge
	var shield_r2: int = SimConstants.SHIELD_RADIUS * SimConstants.SHIELD_RADIUS
	var own_bubble_armed: bool = not shooter.has_shield()

	var path: PackedInt32Array = PackedInt32Array()
	var own_armed: bool = false
	var end_reason: String = "timeout"
	var end_x: int = FixedMath.to_cell(px)
	var end_y: int = FixedMath.to_cell(py)
	var hit_tank: int = -1
	var ticks: int = 0
	var done: bool = false

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
			var bubble: int = _bubble_at(shield_tanks, cx, cy, shield_r2, tank_id, own_bubble_armed)
			if bubble >= 0:
				end_reason = "shield"
				hit_tank = bubble
				done = true
				break
			if not own_bubble_armed and not _in_bubble(shooter, cx, cy, shield_r2):
				own_bubble_armed = true
			var tank_hit: int = _tank_at(state, cx, cy, tank_id, own_armed)
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
	return {
		"path": path,
		"end_reason": end_reason,
		"end_x": end_x,
		"end_y": end_y,
		"hit_tank": hit_tank,
		"ticks": ticks,
		"repulsor_ticks": rep_ticks,
		"repulsor_down_tick": rep_down,
	}


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
