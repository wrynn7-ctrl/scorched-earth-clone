@warning_ignore_start("integer_division")
class_name DirtBehavior
extends RefCounted
## Mound Mortar / Landslide (docs/ARCHITECTURE.md section 21): at the impact, fills the air
## cells of a circle of radius `r` with dirt, skipping cells inside alive tank boxes, then
## settles the columns (loose dirt falls, tanks drop). Cells above a tank can still fall into
## its box while settling, so a tank can end up buried.
## Events: terrain_add {x, y, radius, material, skip: [x0, y0, x1, y1, ...]} (half-open boxes
## of the tanks that overlap the circle, which the show passes to
## Terrain.add_circle_skipping), then terrain_settle (+ falls).


static func resolve(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	var tr: Dictionary = WeaponResolver.fly(state, tank_id, action, events)
	var ticks: int = tr["ticks"]
	if not WeaponResolver.is_impact(tr["end_reason"]):
		return ticks
	var r: int = def["r"]
	var ex: int = tr["end_x"]
	var ey: int = tr["end_y"]
	var terrain: Terrain = state.terrain
	var material: int = WeaponResolver.surface_material(terrain, ex)
	var skip: PackedInt32Array = skip_boxes(state, ex, ey, r)
	events.append({"type": "terrain_add", "tick": ticks, "x": ex, "y": ey, "radius": r,
			"material": material, "skip": skip})
	var rect: Rect2i = terrain.add_circle_skipping(ex, ey, r, material, skip)
	if rect.size.x > 0:
		Settle.settle_region(state, rect.position.x, rect.end.x - 1, tank_id, ticks, events)
	return ticks


## Half-open hit boxes [x0, y0, x1, y1, ...] of the alive tanks that overlap the bounding box
## of the circle (cx, cy, r), in tank id order.
static func skip_boxes(state: MatchState, cx: int, cy: int, r: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var half: int = SimConstants.TANK_W / 2
	for t: TankState in state.tanks:
		if not t.alive:
			continue
		var x0: int = t.x - half
		var x1: int = t.x + half
		var y0: int = t.y - SimConstants.TANK_H
		var y1: int = t.y
		if x1 <= cx - r or x0 > cx + r or y1 <= cy - r or y0 > cy + r:
			continue
		out.append(x0)
		out.append(y0)
		out.append(x1)
		out.append(y1)
	return out
