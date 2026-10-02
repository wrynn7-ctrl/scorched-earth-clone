class_name ItemDefs
extends RefCounted
## Item data table keyed by id (docs/ARCHITECTURE.md section 17).
##
## Params per behaviour:
##   shield    hp (anchor_resist: halves Riptide pull)
##   repulsor  field_r (cells), charge (ticks of use), push (Q16.16 cell/tick^2 at the centre)
##   chute     passive, consumed automatically on a fall > FALL_SAFE
##   fuel      amount (fuel units per cell)
##   repair    heal (HP, capped at MAX_HEALTH); ends the turn

const DEFS: Dictionary = {
	"glow_shield": {"id": "glow_shield", "kind": "item", "tier": "free", "price": 2000, "bundle": 1,
			"behavior": "shield", "hp": 30},
	"ion_shield": {"id": "ion_shield", "kind": "item", "tier": "free", "price": 4000, "bundle": 1,
			"behavior": "shield", "hp": 60},
	"fortress_field": {"id": "fortress_field", "kind": "item", "tier": "full", "price": 7000, "bundle": 1,
			"behavior": "shield", "hp": 100, "anchor_resist": true},
	"repulsor_field": {"id": "repulsor_field", "kind": "item", "tier": "full", "price": 6000, "bundle": 1,
			"behavior": "repulsor", "field_r": 60, "charge": 100, "push": 6554},
	"drift_chute": {"id": "drift_chute", "kind": "item", "tier": "free", "price": 1500, "bundle": 2,
			"behavior": "chute", "passive": true},
	"fuel_cell": {"id": "fuel_cell", "kind": "item", "tier": "free", "price": 1000, "bundle": 1,
			"behavior": "fuel", "amount": 100},
	"nanorepair_kit": {"id": "nanorepair_kit", "kind": "item", "tier": "free", "price": 3000, "bundle": 1,
			"behavior": "repair", "heal": 40},
}


static func has(id: String) -> bool:
	return DEFS.has(id)


## Returns the definition, or an empty Dictionary for an unknown id.
static func get_def(id: String) -> Dictionary:
	if DEFS.has(id):
		return DEFS[id]
	return {}
