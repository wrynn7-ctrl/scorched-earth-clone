extends GutTest
## WeaponResolver (docs/ARCHITECTURE.md section 21): stock, dispatch, fallback behaviours.

const U = preload("res://tests/core/sim_test_util.gd")

const STUBS: Array[String] = ["prism_splitter", "prism_cascade", "glide_orb", "heavy_orb", "bore_shell", "deep_bore",
		"mound_mortar", "landslide", "sludge_shell", "ember_rain", "inferno_gel", "seeker", "photon_lance",
		"static_burst", "singularity_seed", "riptide_anchor"]
const EXPLODERS: Array[String] = ["spark_dart", "pulse_missile", "hyperpulse", "nova_core", "supernova"]


func _fire_with(s: MatchState, weapon: String, angle: int = 450, power: int = 700) -> Array[Dictionary]:
	var a: Dictionary = U.fire(s.current_tank, angle, power)
	a["weapon"] = weapon
	return Simulation.apply_action(s, a)


func test_fire_requires_stock_except_for_the_spark_dart() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[0].set_stock("pulse_missile", 0)
	var a: Dictionary = U.fire(0, 450, 500)
	assert_eq(Simulation.validate_action(s, a), "out_of_stock")
	var before: String = Simulation.fingerprint(s)
	assert_eq(Simulation.apply_action(s, a).size(), 0)
	assert_eq(Simulation.fingerprint(s), before)
	a["weapon"] = "spark_dart"
	assert_eq(Simulation.validate_action(s, a), "", "the spark dart needs no stock")
	for id: String in WeaponDefs.DEFS:
		if id == "spark_dart":
			continue
		var b: Dictionary = U.fire(0, 450, 500)
		b["weapon"] = id
		assert_eq(Simulation.validate_action(s, b), "out_of_stock", id)


func test_firing_consumes_exactly_one_unit() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[0].set_stock("pulse_missile", 5)
	_fire_with(s, "pulse_missile")
	assert_eq(s.tanks[0].stock_of("pulse_missile"), 4)
	assert_eq(s.tanks[1].stock_of("pulse_missile"), 50, "only the shooter pays")
	s.tanks[0].set_stock("pulse_missile", 1)
	s.current_tank = 0
	_fire_with(s, "pulse_missile")
	assert_eq(s.tanks[0].stock_of("pulse_missile"), 0)
	s.current_tank = 0
	assert_eq(Simulation.validate_action(s, U.fire(0, 450, 500)), "out_of_stock")


func test_spark_dart_never_consumes_anything() -> void:
	var s: MatchState = U.flat_state(2)
	var before: PackedInt32Array = s.tanks[0].inventory.duplicate()
	for i: int in range(3):
		s.current_tank = 0
		var ev: Array[Dictionary] = _fire_with(s, "spark_dart")
		assert_eq(U.find(ev, "fire")[0]["weapon"], "spark_dart")
	assert_eq(s.tanks[0].inventory, before)
	assert_eq(s.tanks[0].stock_of("spark_dart"), 0)


func test_lost_shot_still_consumes_stock() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[0].x = 50
	s.tanks[0].set_stock("pulse_missile", 2)
	_fire_with(s, "pulse_missile", 1350, 600)
	assert_eq(s.tanks[0].stock_of("pulse_missile"), 1)


func test_explode_weapons_use_their_own_radius_and_damage() -> void:
	var expect: Dictionary = {"spark_dart": [14, 30], "pulse_missile": [28, 55], "hyperpulse": [44, 70],
			"nova_core": [90, 100], "supernova": [160, 100]}
	for id: String in EXPLODERS:
		var s: MatchState = U.flat_state(2)
		s.tanks[0].set_stock(id, 3)
		var ev: Array[Dictionary] = _fire_with(s, id)
		var e: Dictionary = U.find(ev, "explosion")[0]
		assert_eq(e["radius"], (expect[id] as Array)[0], id)
		assert_eq(e["weapon"], id)
		assert_eq(U.find(ev, "terrain_carve")[0]["radius"], (expect[id] as Array)[0], id)


func test_explosion_damage_scales_with_the_weapon() -> void:
	# A point-blank hit on tank 1 with each weapon: damage = D * (r - d) / r with d = 0.
	for pair: Array in [["spark_dart", 30], ["pulse_missile", 55], ["hyperpulse", 70], ["nova_core", 100]]:
		var s: MatchState = U.flat_state(2)
		var id: String = pair[0]
		s.tanks[0].set_stock(id, 1)
		var p: int = U.power_for_target(s, 450, s.tanks[1].x)
		var ev: Array[Dictionary] = _fire_with(s, id, 450, p)
		var first: Dictionary = U.find(ev, "damage")[0]
		assert_eq(first["tank"], 1)
		assert_true((first["amount"] as int) <= (pair[1] as int), id)
		assert_gt(first["amount"] as int, 0, id)


func test_every_other_behavior_resolves_as_a_plain_explosion_for_now() -> void:
	assert_eq(STUBS.size(), 16)
	for id: String in STUBS:
		var def: Dictionary = WeaponDefs.get_def(id)
		var s: MatchState = U.flat_state(2)
		s.tanks[0].set_stock(id, 2)
		var ev: Array[Dictionary] = _fire_with(s, id)
		assert_eq(U.find(ev, "fire")[0]["weapon"], id)
		assert_eq(U.find(ev, "projectile").size(), 1, "%s: one flight" % id)
		var ex: Array[Dictionary] = U.find(ev, "explosion")
		assert_eq(ex.size(), 1, id)
		assert_eq(ex[0]["radius"], def.get("r", 28), "%s: r from the def, else 28" % id)
		assert_eq(s.tanks[0].stock_of(id), 1, "%s consumed one" % id)
		assert_eq(s.current_tank, 1, "%s ended the turn" % id)
		var types: Array[String] = U.types(ev)
		assert_eq(types.slice(types.size() - 2), ["wind", "turn"] as Array[String])


func test_fallback_damage_uses_dmg_or_55() -> void:
	# mound_mortar has r 40 but no dmg -> 55; prism_splitter has dmg 40 (children r 24 / dmg 40).
	for pair: Array in [["mound_mortar", 55, 40], ["singularity_seed", 55, 28], ["prism_splitter", 40, 24],
			["static_burst", 10, 40]]:
		var s: MatchState = U.flat_state(2)
		var id: String = pair[0]
		s.tanks[0].set_stock(id, 1)
		var p: int = U.power_for_target(s, 450, s.tanks[1].x)
		var ev: Array[Dictionary] = _fire_with(s, id, 450, p)
		assert_eq(U.find(ev, "explosion")[0]["radius"], pair[2], id)
		var d: Dictionary = U.find(ev, "damage")[0]
		var dist: int = 0  # the shell ends inside tank 1's box
		assert_eq(d["amount"], maxi(1, (pair[1] as int) * ((pair[2] as int) - dist) / (pair[2] as int)), id)


func test_all_weapons_survive_the_event_contract_on_random_terrain() -> void:
	var s: MatchState = U.started_match(_settings())
	var rng := Rng.new(3)
	for id: String in WeaponDefs.DEFS:
		for t: TankState in s.tanks:
			t.set_stock(id, 5)
	var fired: int = 0
	for id: String in WeaponDefs.DEFS:
		if s.phase != "aim":
			break
		var ev: Array[Dictionary] = _fire_with(s, id, rng.range_int(200, 1600), rng.range_int(300, 1000))
		assert_gt(ev.size(), 3, id)
		assert_eq(ev[0]["type"], "fire")
		fired += 1
	assert_gt(fired, 5)


func test_destroyed_events_come_after_the_blast_and_use_the_final_tick() -> void:
	var s: MatchState = U.flat_state(3)
	s.tanks[1].health = 1
	var p: int = U.power_for_target(s, 450, s.tanks[1].x)
	var ev: Array[Dictionary] = _fire_with(s, "pulse_missile", 450, p)
	var d: Array[Dictionary] = U.find(ev, "tank_destroyed")
	assert_eq(d.size(), 1)
	assert_eq(d[0]["tick"], U.find(ev, "projectile_end")[0]["tick"])
	var types: Array[String] = U.types(ev)
	assert_true(types.find("tank_destroyed") > types.find("terrain_settle"))


func _settings() -> MatchSettings:
	var st := MatchSettings.new()
	st.seed = 202
	st.num_tanks = 4
	st.rounds = 2
	return st
