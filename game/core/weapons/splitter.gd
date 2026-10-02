@warning_ignore_start("integer_division")
class_name SplitterBehavior
extends RefCounted
## Prism Splitter / Prism Cascade (docs/ARCHITECTURE.md section 21). The main shell flies
## until its apex (the first tick with vy >= 0) and ends there with reason "split"; N children
## then spawn at that point with vx_i = vx + (i - (N-1)/2) * spread and the same vy. Each child
## flies against the world as left by the previous children and explodes on its own, in index
## order, with its own `projectile` (id 1..N, tick = apex tick, path[i] = tick apex + i + 1),
## `projectile_end` and impact events. A main shell that hits something before its apex
## explodes there like a child would.


static func resolve(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	var weapon: String = action["weapon"]
	var radius: int = def["r"]
	var dmg: int = def["dmg"]
	var tr: Dictionary = Ballistics.trace(state, tank_id, action["angle"], action["power"], weapon,
			SimConstants.WIND_USE_STATE, SimConstants.MAX_FLIGHT_TICKS)
	var apex_tick: int = tr["ticks"]
	var reason: String = tr["end_reason"]
	WeaponResolver.emit_projectile(state, weapon, 0, 0, tr["path"], tr, events)
	if reason != "apex":
		WeaponResolver.emit_end(0, 0, reason, apex_tick, tr["end_x"], tr["end_y"], events)
		if WeaponResolver.is_impact(reason):
			WeaponResolver.blast(state, tank_id, tr["end_x"], tr["end_y"], radius, dmg, weapon, apex_tick, events)
		return apex_tick
	WeaponResolver.emit_end(0, 0, "split", apex_tick, tr["end_x"], tr["end_y"], events)
	var last_tick: int = apex_tick
	var n: int = def["children"]
	for i: int in range(n):
		var child: Dictionary = Ballistics.fly_from(state, tank_id, tr["px"], tr["py"],
				Ballistics.child_vx(tr["vx"], i, n, def["spread"]), tr["vy"], SimConstants.WIND_USE_STATE,
				maxi(1, SimConstants.MAX_FLIGHT_TICKS - apex_tick), tr["own_armed"], tr["own_bubble_armed"])
		var id: int = i + 1
		var c_reason: String = child["end_reason"]
		var end_tick: int = apex_tick + (child["ticks"] as int)
		WeaponResolver.emit_projectile(state, weapon, id, apex_tick, child["path"], child, events)
		WeaponResolver.emit_end(id, apex_tick, c_reason, child["ticks"], child["end_x"], child["end_y"], events)
		if WeaponResolver.is_impact(c_reason):
			WeaponResolver.blast(state, tank_id, child["end_x"], child["end_y"], radius, dmg, weapon, end_tick, events)
		last_tick = maxi(last_tick, end_tick)
	return last_tick
