class_name Catalog
extends RefCounted
## The one ordered list of every weapon then every item (docs/ARCHITECTURE.md section 17).
## Inventories are PackedInt32Array indexed by position in IDS. NEVER reorder: only append,
## because saves and fingerprints depend on the indices.

const SPARK_DART: String = "spark_dart"

const IDS: PackedStringArray = [
	# weapons
	"spark_dart", "pulse_missile", "hyperpulse", "nova_core", "supernova",
	"prism_splitter", "prism_cascade", "glide_orb", "heavy_orb", "bore_shell", "deep_bore",
	"mound_mortar", "landslide", "sludge_shell", "ember_rain", "inferno_gel", "seeker",
	"photon_lance", "static_burst", "singularity_seed", "riptide_anchor",
	# items
	"glow_shield", "ion_shield", "fortress_field", "repulsor_field", "drift_chute", "fuel_cell",
	"nanorepair_kit",
]


static func count() -> int:
	return IDS.size()


## Catalog position of `id`, or -1 for an unknown id.
static func index_of(id: String) -> int:
	return IDS.find(id)


## Id at catalog position `index`, or "" when out of range.
static func id_at(index: int) -> String:
	if index < 0 or index >= IDS.size():
		return ""
	return IDS[index]


static func has(id: String) -> bool:
	return WeaponDefs.has(id) or ItemDefs.has(id)


static func is_weapon(id: String) -> bool:
	return WeaponDefs.has(id)


static func is_item(id: String) -> bool:
	return ItemDefs.has(id)


## Definition of a weapon or item, or an empty Dictionary for an unknown id.
static func get_def(id: String) -> Dictionary:
	if WeaponDefs.has(id):
		return WeaponDefs.get_def(id)
	return ItemDefs.get_def(id)


## An empty inventory: one zero per catalog entry.
static func new_inventory() -> PackedInt32Array:
	var inv: PackedInt32Array = PackedInt32Array()
	inv.resize(IDS.size())
	return inv
