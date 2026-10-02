class_name WeaponDefs
extends RefCounted
## Weapon data table keyed by id. M2 ships only the Pulse Missile.

const DEFS: Dictionary = {
	"pulse_missile": {"radius": 28, "damage": 55, "price": 0, "behavior": "explode"},
}


static func has(id: String) -> bool:
	return DEFS.has(id)


## Returns the definition, or an empty Dictionary for an unknown id.
static func get_def(id: String) -> Dictionary:
	if DEFS.has(id):
		return DEFS[id]
	return {}
