class_name WeaponDefs
extends RefCounted
## Weapon data table keyed by id (docs/ARCHITECTURE.md section 17). Values are integers:
## cells, HP, ticks, or Q16.16 where noted. Display names come from tr("ITEM_<ID>").
##
## Params per behaviour (all consumed by WeaponResolver and its behaviours):
##   explode   r, dmg
##   splitter  children, spread (tenths of a cell/tick of vx step), r, dmg (per child)
##   roller    r, dmg, max_roll (ticks), speed (cells/tick)
##   tunneler  length (cells), tunnel_r, r, dmg (end blast)
##   dirt      r (add_circle radius)
##   sludge    volume (cells)
##   fire      points, dmg_per_point, reach (cells), cap (per tank)
##   seeker    accel (Q16.16 max lateral cell/tick^2; tuned to 0.10 in M3-C2), r, dmg
##   beam      length, cut (max solid cells), beam_r, dmg
##   static    r, dmg
##   well      well_r, strength (Q16.16 cell/tick^2 at centre; tuned to 0.15 in M3-C2), cycles (full turn cycles)
##   anchor    pull_r, max_pull (cells)
## spark_dart is unlimited (never stored in inventories): `bundle` is 1 only to keep maths safe.

const DEFS: Dictionary = {
	"spark_dart": {"id": "spark_dart", "kind": "weapon", "tier": "free", "price": 0, "bundle": 1,
			"behavior": "explode", "r": 14, "dmg": 30, "unlimited": true},
	"pulse_missile": {"id": "pulse_missile", "kind": "weapon", "tier": "free", "price": 1500, "bundle": 5,
			"behavior": "explode", "r": 28, "dmg": 55},
	"hyperpulse": {"id": "hyperpulse", "kind": "weapon", "tier": "free", "price": 2500, "bundle": 3,
			"behavior": "explode", "r": 44, "dmg": 70},
	"nova_core": {"id": "nova_core", "kind": "weapon", "tier": "free", "price": 6000, "bundle": 1,
			"behavior": "explode", "r": 90, "dmg": 100},
	"supernova": {"id": "supernova", "kind": "weapon", "tier": "full", "price": 12000, "bundle": 1,
			"behavior": "explode", "r": 160, "dmg": 100},
	"prism_splitter": {"id": "prism_splitter", "kind": "weapon", "tier": "free", "price": 4000, "bundle": 2,
			"behavior": "splitter", "children": 5, "spread": 6, "r": 24, "dmg": 40},
	"prism_cascade": {"id": "prism_cascade", "kind": "weapon", "tier": "full", "price": 7000, "bundle": 1,
			"behavior": "splitter", "children": 9, "spread": 4, "r": 18, "dmg": 30},
	"glide_orb": {"id": "glide_orb", "kind": "weapon", "tier": "free", "price": 2000, "bundle": 3,
			"behavior": "roller", "r": 30, "dmg": 55, "max_roll": 400, "speed": 1},
	"heavy_orb": {"id": "heavy_orb", "kind": "weapon", "tier": "full", "price": 3500, "bundle": 2,
			"behavior": "roller", "r": 44, "dmg": 70, "max_roll": 400, "speed": 2},
	"bore_shell": {"id": "bore_shell", "kind": "weapon", "tier": "free", "price": 1800, "bundle": 3,
			"behavior": "tunneler", "length": 80, "tunnel_r": 6, "r": 12, "dmg": 20},
	"deep_bore": {"id": "deep_bore", "kind": "weapon", "tier": "full", "price": 3000, "bundle": 2,
			"behavior": "tunneler", "length": 180, "tunnel_r": 7, "r": 14, "dmg": 25},
	"mound_mortar": {"id": "mound_mortar", "kind": "weapon", "tier": "free", "price": 1500, "bundle": 3,
			"behavior": "dirt", "r": 40},
	"landslide": {"id": "landslide", "kind": "weapon", "tier": "full", "price": 3000, "bundle": 2,
			"behavior": "dirt", "r": 80},
	"sludge_shell": {"id": "sludge_shell", "kind": "weapon", "tier": "full", "price": 3500, "bundle": 2,
			"behavior": "sludge", "volume": 1800},
	"ember_rain": {"id": "ember_rain", "kind": "weapon", "tier": "free", "price": 3000, "bundle": 2,
			"behavior": "fire", "points": 60, "dmg_per_point": 2, "reach": 6, "cap": 40},
	"inferno_gel": {"id": "inferno_gel", "kind": "weapon", "tier": "full", "price": 5500, "bundle": 1,
			"behavior": "fire", "points": 110, "dmg_per_point": 3, "reach": 6, "cap": 70},
	"seeker": {"id": "seeker", "kind": "weapon", "tier": "free", "price": 4500, "bundle": 2,
			"behavior": "seeker", "accel": 6554, "r": 28, "dmg": 55},
	"photon_lance": {"id": "photon_lance", "kind": "weapon", "tier": "full", "price": 4000, "bundle": 2,
			"behavior": "beam", "length": 900, "cut": 120, "beam_r": 3, "dmg": 35},
	"static_burst": {"id": "static_burst", "kind": "weapon", "tier": "full", "price": 2500, "bundle": 2,
			"behavior": "static", "r": 40, "dmg": 10},
	"singularity_seed": {"id": "singularity_seed", "kind": "weapon", "tier": "full", "price": 5000, "bundle": 1,
			"behavior": "well", "well_r": 300, "strength": 9830, "cycles": 2},
	"riptide_anchor": {"id": "riptide_anchor", "kind": "weapon", "tier": "full", "price": 4000, "bundle": 2,
			"behavior": "anchor", "pull_r": 180, "max_pull": 120},
}


static func has(id: String) -> bool:
	return DEFS.has(id)


## Returns the definition, or an empty Dictionary for an unknown id.
static func get_def(id: String) -> Dictionary:
	if DEFS.has(id):
		return DEFS[id]
	return {}
