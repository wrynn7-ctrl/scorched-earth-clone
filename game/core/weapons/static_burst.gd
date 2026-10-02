@warning_ignore_start("integer_division")
class_name StaticBehavior
extends RefCounted
## Static Burst (docs/ARCHITECTURE.md section 21): a small explosion (`r`, `dmg`) that also
## strips the shield and repulsor charge of every alive tank whose centre is inside the radius
## (`shield_down` / `repulsor_down`, emitted before the damage so the blast reaches health).


static func resolve(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	var tr: Dictionary = WeaponResolver.fly(state, tank_id, action, events)
	if WeaponResolver.is_impact(tr["end_reason"]):
		WeaponResolver.blast(state, tank_id, tr["end_x"], tr["end_y"], def["r"], def["dmg"], action["weapon"],
				tr["ticks"], events, Rect2i(), true)
	return tr["ticks"]
