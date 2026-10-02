@warning_ignore_start("integer_division")
class_name RollerBehavior
extends RefCounted
## Glide Orb / Heavy Orb (docs/ARCHITECTURE.md section 21). After a terrain impact the shell
## becomes a roller on the surface of the impact column (one extra tick on the path), then
## each tick it takes `speed` single-cell steps toward the strictly lower neighbouring column
## (ties go left). It explodes on contact with an alive tank's hit box, when no neighbour is
## lower (valley, or a map wall) and after `max_roll` ticks. A shell that hits a tank or a
## shield bubble explodes there at once. The rolling positions are appended to the same
## projectile path, one entry per tick, so projectile_end.tick is the end of the roll.


static func resolve(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	var weapon: String = action["weapon"]
	var tr: Dictionary = Ballistics.trace(state, tank_id, action["angle"], action["power"], weapon,
			SimConstants.WIND_USE_STATE, SimConstants.MAX_FLIGHT_TICKS)
	var path: PackedInt32Array = tr["path"]
	var ticks: int = tr["ticks"]
	var reason: String = tr["end_reason"]
	var ex: int = tr["end_x"]
	var ey: int = tr["end_y"]
	if reason == "terrain":
		var rolled: Dictionary = roll(state, ex, def["speed"], def["max_roll"], path)
		if rolled["started"]:
			ex = rolled["x"]
			ey = rolled["y"]
			ticks += rolled["ticks"] as int
			path = rolled["path"]
			if rolled["contact"]:
				reason = "tank"
	WeaponResolver.emit_projectile(state, weapon, 0, 0, path, tr, events)
	WeaponResolver.emit_end(0, 0, reason, ticks, ex, ey, events)
	if WeaponResolver.is_impact(reason):
		WeaponResolver.blast(state, tank_id, ex, ey, def["r"], def["dmg"], weapon, ticks, events)
	return ticks


## Rolls from the surface of column `x`. Returns {started, x, y, ticks, path, contact}:
## `ticks` includes the placing tick, `path` is `path_in` plus one entry per tick.
static func roll(state: MatchState, x: int, speed: int, max_roll: int, path_in: PackedInt32Array) -> Dictionary:
	var terrain: Terrain = state.terrain
	var path: PackedInt32Array = path_in.duplicate()
	var cache := SurfaceCache.new(terrain)
	var rx: int = x
	var ry: int = cache.top(rx) - 1
	if ry < 0:
		return {"started": false, "x": rx, "y": ry, "ticks": 0, "path": path, "contact": false}
	var ticks: int = 1  # the shell settles onto the surface
	path.append(FixedMath.from_cell(rx))
	path.append(FixedMath.from_cell(ry))
	var contact: bool = _touches_tank(state, rx, ry)
	var rolled: int = 0
	var stopped: bool = false
	while rolled < max_roll and not contact and not stopped:
		var moved: bool = false
		for _s: int in range(speed):
			var d: int = cache.pick_dir(rx, false)
			if d == 0:
				stopped = true
				break
			rx += d
			ry = maxi(0, cache.top(rx) - 1)
			moved = true
			if _touches_tank(state, rx, ry):
				contact = true
				break
		if moved:
			rolled += 1
			ticks += 1
			path.append(FixedMath.from_cell(rx))
			path.append(FixedMath.from_cell(ry))
	return {"started": true, "x": rx, "y": ry, "ticks": ticks, "path": path, "contact": contact}


static func _touches_tank(state: MatchState, cx: int, cy: int) -> bool:
	for t: TankState in state.tanks:
		if t.alive and t.contains_cell(cx, cy):
			return true
	return false
