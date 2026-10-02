extends GutTest
## Catalog, weapon table and item table (docs/ARCHITECTURE.md section 17).

## [id, tier, price, bundle, behavior] straight from the section 17 table, in catalog order.
const TABLE: Array = [
	["spark_dart", "free", 0, 1, "explode"],
	["pulse_missile", "free", 1500, 5, "explode"],
	["hyperpulse", "free", 2500, 3, "explode"],
	["nova_core", "free", 6000, 1, "explode"],
	["supernova", "full", 12000, 1, "explode"],
	["prism_splitter", "free", 4000, 2, "splitter"],
	["prism_cascade", "full", 7000, 1, "splitter"],
	["glide_orb", "free", 2000, 3, "roller"],
	["heavy_orb", "full", 3500, 2, "roller"],
	["bore_shell", "free", 1800, 3, "tunneler"],
	["deep_bore", "full", 3000, 2, "tunneler"],
	["mound_mortar", "free", 1500, 3, "dirt"],
	["landslide", "full", 3000, 2, "dirt"],
	["sludge_shell", "full", 3500, 2, "sludge"],
	["ember_rain", "free", 3000, 2, "fire"],
	["inferno_gel", "full", 5500, 1, "fire"],
	["seeker", "free", 4500, 2, "seeker"],
	["photon_lance", "full", 4000, 2, "beam"],
	["static_burst", "full", 2500, 2, "static"],
	["singularity_seed", "full", 5000, 1, "well"],
	["riptide_anchor", "full", 4000, 2, "anchor"],
	["glow_shield", "free", 2000, 1, "shield"],
	["ion_shield", "free", 4000, 1, "shield"],
	["fortress_field", "full", 7000, 1, "shield"],
	["repulsor_field", "full", 6000, 1, "repulsor"],
	["drift_chute", "free", 1500, 2, "chute"],
	["fuel_cell", "free", 1000, 1, "fuel"],
	["nanorepair_kit", "free", 3000, 1, "repair"],
]


func test_ids_are_in_table_order_and_unique() -> void:
	assert_eq(Catalog.IDS.size(), 28)
	assert_eq(Catalog.count(), 28)
	var seen: Dictionary = {}
	for i: int in range(TABLE.size()):
		var id: String = TABLE[i][0]
		assert_eq(Catalog.IDS[i], id, "position %d" % i)
		assert_eq(Catalog.index_of(id), i)
		assert_eq(Catalog.id_at(i), id)
		assert_false(seen.has(id), "unique %s" % id)
		seen[id] = true


func test_weapons_first_then_items() -> void:
	assert_eq(WeaponDefs.DEFS.size(), 21)
	assert_eq(ItemDefs.DEFS.size(), 7)
	for i: int in range(28):
		var id: String = Catalog.IDS[i]
		assert_eq(Catalog.is_weapon(id), i < 21, id)
		assert_eq(Catalog.is_item(id), i >= 21, id)
		assert_eq(WeaponDefs.has(id), i < 21)
		assert_eq(ItemDefs.has(id), i >= 21)
		assert_true(Catalog.has(id))


func test_every_entry_matches_the_contract_table() -> void:
	for row: Array in TABLE:
		var id: String = row[0]
		var def: Dictionary = Catalog.get_def(id)
		assert_false(def.is_empty(), id)
		assert_eq(def["id"], id)
		assert_eq(def["tier"], row[1], "%s tier" % id)
		assert_eq(def["price"], row[2], "%s price" % id)
		assert_eq(def["bundle"], row[3], "%s bundle" % id)
		assert_eq(def["behavior"], row[4], "%s behavior" % id)
		assert_eq(def["kind"], "weapon" if WeaponDefs.has(id) else "item", "%s kind" % id)


func test_key_params_from_the_table() -> void:
	var w: Dictionary = WeaponDefs.DEFS
	assert_eq([w["spark_dart"]["r"], w["spark_dart"]["dmg"]], [14, 30])
	assert_eq([w["pulse_missile"]["r"], w["pulse_missile"]["dmg"]], [28, 55])
	assert_eq([w["hyperpulse"]["r"], w["hyperpulse"]["dmg"]], [44, 70])
	assert_eq([w["nova_core"]["r"], w["nova_core"]["dmg"]], [90, 100])
	assert_eq([w["supernova"]["r"], w["supernova"]["dmg"]], [160, 100])
	assert_eq([w["prism_splitter"]["children"], w["prism_splitter"]["spread"], w["prism_splitter"]["r"],
			w["prism_splitter"]["dmg"]], [5, 6, 24, 40])
	assert_eq([w["prism_cascade"]["children"], w["prism_cascade"]["spread"], w["prism_cascade"]["r"],
			w["prism_cascade"]["dmg"]], [9, 4, 18, 30])
	assert_eq([w["glide_orb"]["r"], w["glide_orb"]["dmg"], w["glide_orb"]["max_roll"]], [30, 55, 400])
	assert_eq([w["heavy_orb"]["r"], w["heavy_orb"]["dmg"]], [44, 70])
	assert_gt(w["heavy_orb"]["speed"] as int, w["glide_orb"]["speed"] as int, "heavy orb is faster")
	assert_eq([w["bore_shell"]["length"], w["bore_shell"]["tunnel_r"], w["bore_shell"]["r"], w["bore_shell"]["dmg"]],
			[80, 6, 12, 20])
	assert_eq([w["deep_bore"]["length"], w["deep_bore"]["tunnel_r"], w["deep_bore"]["r"], w["deep_bore"]["dmg"]],
			[180, 7, 14, 25])
	assert_eq([w["mound_mortar"]["r"], w["landslide"]["r"]], [40, 80])
	assert_eq(w["sludge_shell"]["volume"], 1800)
	assert_eq([w["ember_rain"]["points"], w["ember_rain"]["dmg_per_point"], w["ember_rain"]["reach"],
			w["ember_rain"]["cap"]], [60, 2, 6, 40])
	assert_eq([w["inferno_gel"]["points"], w["inferno_gel"]["dmg_per_point"], w["inferno_gel"]["cap"]], [110, 3, 70])
	assert_eq([w["seeker"]["r"], w["seeker"]["dmg"]], [28, 55])
	assert_eq(w["seeker"]["accel"], 3277, "0.05 cell/tick^2 in Q16.16")
	assert_eq([w["photon_lance"]["length"], w["photon_lance"]["cut"], w["photon_lance"]["beam_r"],
			w["photon_lance"]["dmg"]], [900, 120, 3, 35])
	assert_eq([w["static_burst"]["r"], w["static_burst"]["dmg"]], [40, 10])
	assert_eq([w["singularity_seed"]["well_r"], w["singularity_seed"]["strength"], w["singularity_seed"]["cycles"]],
			[300, 7864, 2])
	assert_eq([w["riptide_anchor"]["pull_r"], w["riptide_anchor"]["max_pull"]], [180, 120])
	var it: Dictionary = ItemDefs.DEFS
	assert_eq([it["glow_shield"]["hp"], it["ion_shield"]["hp"], it["fortress_field"]["hp"]], [30, 60, 100])
	assert_eq([it["repulsor_field"]["field_r"], it["repulsor_field"]["charge"]], [60, 100])
	assert_eq(it["fuel_cell"]["amount"], 100)
	assert_eq(it["nanorepair_kit"]["heal"], 40)


func test_every_weapon_behavior_is_known_to_the_resolver() -> void:
	var known: Array[String] = ["explode", "splitter", "roller", "tunneler", "dirt", "sludge", "fire", "seeker", "beam",
			"static", "well", "anchor"]
	for id: String in WeaponDefs.DEFS:
		assert_true(known.has(WeaponDefs.get_def(id)["behavior"]), id)


func test_unknown_ids() -> void:
	assert_eq(Catalog.index_of("nope"), -1)
	assert_eq(Catalog.index_of(""), -1)
	assert_eq(Catalog.id_at(-1), "")
	assert_eq(Catalog.id_at(28), "")
	assert_false(Catalog.has("nope"))
	assert_true(Catalog.get_def("nope").is_empty())
	assert_true(WeaponDefs.get_def("glow_shield").is_empty(), "items are not weapons")
	assert_true(ItemDefs.get_def("pulse_missile").is_empty(), "weapons are not items")
	assert_false(WeaponDefs.has("glow_shield"))


func test_new_inventory_is_empty_and_independent() -> void:
	var a: PackedInt32Array = Catalog.new_inventory()
	assert_eq(a.size(), 28)
	for n: int in a:
		assert_eq(n, 0)
	a[1] = 5
	assert_eq(Catalog.new_inventory()[1], 0)
	var t := TankState.new()
	var u := TankState.new()
	t.set_stock("pulse_missile", 3)
	assert_eq(u.stock_of("pulse_missile"), 0, "tanks do not share an inventory")
	assert_eq(t.stock_of("pulse_missile"), 3)
	assert_eq(t.stock_of("nope"), 0)
	t.set_stock("nope", 4)  # ignored


func test_spark_dart_is_free_and_unlimited() -> void:
	var d: Dictionary = WeaponDefs.get_def("spark_dart")
	assert_eq(d["price"], 0)
	assert_true(d["unlimited"])


func test_display_names_and_descriptions_exist_in_the_locale_csv() -> void:
	var names: Dictionary = {
		"spark_dart": "Spark Dart", "pulse_missile": "Pulse Missile", "hyperpulse": "Hyperpulse",
		"nova_core": "Nova Core", "supernova": "Supernova", "prism_splitter": "Prism Splitter",
		"prism_cascade": "Prism Cascade", "glide_orb": "Glide Orb", "heavy_orb": "Heavy Orb",
		"bore_shell": "Bore Shell", "deep_bore": "Deep Bore", "mound_mortar": "Mound Mortar",
		"landslide": "Landslide", "sludge_shell": "Sludge Shell", "ember_rain": "Ember Rain",
		"inferno_gel": "Inferno Gel", "seeker": "Seeker", "photon_lance": "Photon Lance",
		"static_burst": "Static Burst", "singularity_seed": "Singularity Seed",
		"riptide_anchor": "Riptide Anchor", "glow_shield": "Glow Shield", "ion_shield": "Ion Shield",
		"fortress_field": "Fortress Field", "repulsor_field": "Repulsor Field", "drift_chute": "Drift Chute",
		"fuel_cell": "Fuel Cell", "nanorepair_kit": "Nanorepair Kit",
	}
	var rows: Dictionary = {}
	var f: FileAccess = FileAccess.open("res://locale/strings.csv", FileAccess.READ)
	assert_not_null(f)
	while not f.eof_reached():
		var cols: PackedStringArray = f.get_csv_line()
		if cols.size() >= 2:
			rows[cols[0]] = cols[1]
	for id: String in Catalog.IDS:
		var key: String = "ITEM_" + id.to_upper()
		assert_eq(rows.get(key, ""), names[id], "%s name" % key)
		assert_true(rows.has(key + "_DESC") and (rows[key + "_DESC"] as String).length() > 5, "%s_DESC" % key)
