@warning_ignore_start("integer_division")
class_name Ballistics
extends RefCounted
## Projectile flight (docs/ARCHITECTURE.md section 7). Pure: never mutates state.


## Simulates one shot. Returns {path: PackedInt32Array [x0,y0,x1,y1,...] Q16.16 per tick,
## end_reason: "terrain"|"tank"|"lost"|"timeout", end_x, end_y (cells), hit_tank (id or -1),
## ticks}. Pass SimConstants.WIND_USE_STATE as wind_override to use state.wind.
## `weapon_id` is reserved for per-weapon flight parameters (all weapons share the same
## flight in M2).
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
		vx += wind_ax
		vy += SimConstants.GRAVITY
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
	}


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
