@warning_ignore_start("integer_division")
class_name TunnelerBehavior
extends RefCounted
## Bore Shell / Deep Bore (docs/ARCHITECTURE.md section 21). On a terrain impact the shell
## keeps going along its last velocity direction (unit vector via isqrt), boring a tunnel of
## radius `tunnel_r` for `length` cells (it stops early before an alive tank's box or at the
## map edge), then the end blast (`r`, `dmg`) goes off at the tunnel's end. A hit on a tank or
## shield just fires the end blast there. The tunnel and the blast crater settle together.
## Events: tunnel {x0, y0, x1, y1, radius} (the show re-applies Terrain.carve_tunnel), then
## explosion, terrain_carve, damage*, terrain_settle ...


static func resolve(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	var weapon: String = action["weapon"]
	var tr: Dictionary = WeaponResolver.fly(state, tank_id, action, events)
	var ticks: int = tr["ticks"]
	var reason: String = tr["end_reason"]
	var ex: int = tr["end_x"]
	var ey: int = tr["end_y"]
	var extra := Rect2i()
	if reason == "terrain":
		var end: Vector2i = bore_end(state, tr["px"], tr["py"], tr["vx"], tr["vy"], def["length"])
		var radius: int = def["tunnel_r"]
		events.append({"type": "tunnel", "tick": ticks, "x0": ex, "y0": ey, "x1": end.x, "y1": end.y,
				"radius": radius})
		extra = state.terrain.carve_tunnel(ex, ey, end.x, end.y, radius)
		ex = end.x
		ey = end.y
	if WeaponResolver.is_impact(reason):
		WeaponResolver.blast(state, tank_id, ex, ey, def["r"], def["dmg"], weapon, ticks, events, extra)
	return ticks


## Cell where a tunnel of `length` cells starting at the Q16.16 point (px, py) and heading along
## (vx, vy) ends: the last cell before an alive tank's box or the map edge, else the cell
## `length` steps along.
static func bore_end(state: MatchState, px: int, py: int, vx: int, vy: int, length: int) -> Vector2i:
	var mag: int = FixedMath.isqrt(vx * vx + vy * vy)
	var cx: int = FixedMath.to_cell(px)
	var cy: int = FixedMath.to_cell(py)
	if mag == 0:
		return Vector2i(cx, cy)
	var ux: int = vx * FixedMath.ONE / mag
	var uy: int = vy * FixedMath.ONE / mag
	var terrain: Terrain = state.terrain
	var last: Vector2i = Vector2i(cx, cy)
	for i: int in range(1, length + 1):
		var nx: int = FixedMath.to_cell(px + ux * i)
		var ny: int = FixedMath.to_cell(py + uy * i)
		if nx < 0 or nx >= terrain.width or ny < 0 or ny >= terrain.height:
			break
		var blocked: bool = false
		for t: TankState in state.tanks:
			if t.alive and t.contains_cell(nx, ny):
				blocked = true
				break
		if blocked:
			break
		last = Vector2i(nx, ny)
	return last
