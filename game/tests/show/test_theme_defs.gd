extends GutTest
## Theme definitions: complete, tiered as ARCHITECTURE section 32 says, "Random" deterministic, and the
## sky / terrain views actually take the colours.

const SEED_A: int = 123456789
const SEED_B: int = 987654321


func after_each() -> void:
	ThemeDefs.full_override = -1


func test_every_theme_defines_all_fields() -> void:
	assert_eq(ThemeDefs.ids().size(), 5)
	for id: String in ThemeDefs.ids():
		var def: Dictionary = ThemeDefs.get_def(id)
		for key: String in ThemeDefs.REQUIRED_KEYS:
			assert_true(def.has(key), "%s has %s" % [id, key])
		assert_eq(def["id"], id)
		assert_eq((def["strata"] as Array[Color]).size(), ThemeDefs.STRATA_COUNT, "%s: 15 strata" % id)
		assert_eq(def.size(), ThemeDefs.REQUIRED_KEYS.size(), "%s defines nothing undocumented" % id)
		assert_ne(tr(def["name_key"] as String), def["name_key"], "%s name is translated" % id)
		assert_true(ThemeDefs.AMBIENT_NONE == def["ambient"] or ThemeDefs.AMBIENT_EMBERS == def["ambient"]
				or ThemeDefs.AMBIENT_SPORES == def["ambient"])


func test_styles_match_the_brief() -> void:
	assert_eq(ThemeDefs.get_def(ThemeDefs.ICE_CIRCUIT)["sun_style"], ThemeDefs.SUN_MOON, "pale moon")
	assert_gt(ThemeDefs.get_def(ThemeDefs.ICE_CIRCUIT)["aurora"] as float, 0.0, "aurora streaks")
	assert_gt(ThemeDefs.get_def(ThemeDefs.MAGMA_CITY)["city"] as float, 0.0, "horizon city")
	assert_eq(ThemeDefs.get_def(ThemeDefs.MAGMA_CITY)["ambient"], ThemeDefs.AMBIENT_EMBERS)
	assert_eq(ThemeDefs.get_def(ThemeDefs.TOXIC_MARSH)["ambient"], ThemeDefs.AMBIENT_SPORES)
	assert_eq(ThemeDefs.get_def(ThemeDefs.MIDNIGHT_CHROME)["sun_style"], ThemeDefs.SUN_CHROME, "chrome sun")
	assert_gt(ThemeDefs.get_def(ThemeDefs.MIDNIGHT_CHROME)["stars"] as float,
			ThemeDefs.get_def(ThemeDefs.SUNSET_GRID)["stars"] as float, "denser starfield")


func test_tiers() -> void:
	assert_true(ThemeDefs.is_free(ThemeDefs.SUNSET_GRID))
	assert_true(ThemeDefs.is_free(ThemeDefs.ICE_CIRCUIT))
	for id: String in [ThemeDefs.MAGMA_CITY, ThemeDefs.TOXIC_MARSH, ThemeDefs.MIDNIGHT_CHROME]:
		assert_false(ThemeDefs.is_free(id), id)
		assert_true(ThemeDefs.is_locked(id, false))
		assert_false(ThemeDefs.is_locked(id, true))
	assert_false(ThemeDefs.is_locked(ThemeDefs.RANDOM, false), "Random is always available")
	assert_eq(ThemeDefs.usable_ids(false), PackedStringArray([ThemeDefs.SUNSET_GRID, ThemeDefs.ICE_CIRCUIT]))
	assert_eq(ThemeDefs.usable_ids(true).size(), 5)


func test_sanitize_and_unknown_ids() -> void:
	assert_eq(ThemeDefs.sanitize("magma_city"), "magma_city")
	assert_eq(ThemeDefs.sanitize("random"), "random")
	assert_eq(ThemeDefs.sanitize("nope"), ThemeDefs.DEFAULT_ID)
	assert_eq(ThemeDefs.sanitize(42), ThemeDefs.DEFAULT_ID)
	assert_eq(ThemeDefs.get_def("nope")["id"], ThemeDefs.DEFAULT_ID)


func test_sunset_grid_is_the_original_look() -> void:
	var d: Dictionary = ThemeDefs.get_def(ThemeDefs.SUNSET_GRID)
	assert_eq(d["sky_low"], Color(1.0, 0.22, 0.52))
	assert_eq(d["edge_a"], Color(0.0, 0.93, 1.0))
	assert_eq((d["strata"] as Array[Color])[0], Color(0.30, 0.12, 0.45))


func test_random_is_deterministic_per_seed_and_round() -> void:
	for round_index: int in range(8):
		var a: String = ThemeDefs.resolve(ThemeDefs.RANDOM, SEED_A, round_index, true)
		var b: String = ThemeDefs.resolve(ThemeDefs.RANDOM, SEED_A, round_index, true)
		assert_eq(a, b, "same (seed, round) -> same theme (round %d)" % round_index)
		assert_true(ThemeDefs.has_theme(a))
	var seq_a: PackedStringArray = PackedStringArray()
	var seq_b: PackedStringArray = PackedStringArray()
	for r: int in range(40):
		seq_a.append(ThemeDefs.resolve(ThemeDefs.RANDOM, SEED_A, r, true))
		seq_b.append(ThemeDefs.resolve(ThemeDefs.RANDOM, SEED_B, r, true))
	assert_ne(seq_a, seq_b, "another seed gives another sequence")
	var seen: Dictionary = {}
	for id: String in seq_a:
		seen[id] = true
	assert_gte(seen.size(), 4, "rounds differ: 40 rounds show at least 4 of the 5 themes")
	var changes: int = 0
	for r: int in range(1, 40):
		if seq_a[r] != seq_a[r - 1]:
			changes += 1
	assert_gt(changes, 10, "consecutive rounds usually differ")


func test_random_without_the_full_game_only_picks_free_themes() -> void:
	for r: int in range(30):
		var id: String = ThemeDefs.resolve(ThemeDefs.RANDOM, SEED_A, r, false)
		assert_true(ThemeDefs.is_free(id), id)


func test_fixed_choice_resolves_to_itself_unless_locked() -> void:
	assert_eq(ThemeDefs.resolve("ice_circuit", SEED_A, 3, false), "ice_circuit")
	assert_eq(ThemeDefs.resolve("magma_city", SEED_A, 3, true), "magma_city")
	assert_eq(ThemeDefs.resolve("magma_city", SEED_A, 3, false), ThemeDefs.DEFAULT_ID, "locked falls back")
	assert_eq(ThemeDefs.resolve("garbage", SEED_A, 3, true), ThemeDefs.DEFAULT_ID)


func test_full_game_check_has_an_override() -> void:
	ThemeDefs.full_override = 0
	assert_false(ThemeDefs.is_full_game())
	ThemeDefs.full_override = 1
	assert_true(ThemeDefs.is_full_game())


func test_terrain_view_takes_the_strata_and_edge_colours() -> void:
	var tv: TerrainView = add_child_autofree(TerrainView.new())
	var cells := PackedByteArray()
	cells.resize(16 * 16)
	tv.setup(cells, 16, 16)
	assert_eq(tv.get_theme_id(), ThemeDefs.DEFAULT_ID)
	for id: String in ThemeDefs.ids():
		tv.apply_theme(id)
		var def: Dictionary = ThemeDefs.get_def(id)
		var img: Image = tv.get_strata_image()
		for m: int in range(1, 16):
			var want: Color = (def["strata"] as Array[Color])[m - 1]
			var got: Color = img.get_pixel(m, 0)
			assert_lt(absf(got.r - want.r) + absf(got.g - want.g) + absf(got.b - want.b), 0.02, "%s material %d" % [id, m])
		var mat: ShaderMaterial = tv.material as ShaderMaterial
		assert_eq(mat.get_shader_parameter("edge_a"), def["edge_a"])
		assert_eq(mat.get_shader_parameter("edge_b"), def["edge_b"])


func test_terrain_view_applies_a_theme_chosen_before_setup() -> void:
	var tv: TerrainView = add_child_autofree(TerrainView.new())
	tv.apply_theme(ThemeDefs.MAGMA_CITY)
	var cells := PackedByteArray()
	cells.resize(16 * 16)
	tv.setup(cells, 16, 16)
	assert_eq(tv.get_theme_id(), ThemeDefs.MAGMA_CITY)
	assert_eq((tv.material as ShaderMaterial).get_shader_parameter("edge_a"), ThemeDefs.get_def(ThemeDefs.MAGMA_CITY)["edge_a"])


func test_sky_takes_the_theme() -> void:
	var sky: NeonSky = add_child_autofree(NeonSky.new())
	sky.apply_theme(ThemeDefs.ICE_CIRCUIT)
	var m: ShaderMaterial = sky.get_sky_material()
	assert_eq(m.get_shader_parameter("sun_style"), ThemeDefs.SUN_MOON)
	assert_eq(m.get_shader_parameter("aurora_mix"), 1.0)
	assert_eq(m.get_shader_parameter("sky_low"), ThemeDefs.get_def(ThemeDefs.ICE_CIRCUIT)["sky_low"])
	assert_eq(sky.get_theme_id(), ThemeDefs.ICE_CIRCUIT)
	sky.apply_theme(ThemeDefs.SUNSET_GRID)
	assert_eq(m.get_shader_parameter("aurora_mix"), 0.0)


func test_sky_applies_a_theme_requested_before_it_is_ready() -> void:
	var sky := NeonSky.new()
	sky.apply_theme(ThemeDefs.MAGMA_CITY)
	add_child_autofree(sky)
	assert_eq(sky.get_sky_material().get_shader_parameter("city_mix"), 1.0)


func test_ambient_particles_are_one_cheap_node() -> void:
	var sky: NeonSky = add_child_autofree(NeonSky.new())
	sky.apply_theme(ThemeDefs.MAGMA_CITY)
	var amb: ThemeAmbient = sky.get_ambient()
	assert_true(amb.is_emitting())
	assert_lte(amb.particle_count(), 40)
	sky.apply_theme(ThemeDefs.TOXIC_MARSH)
	assert_eq(amb.get_style(), ThemeDefs.AMBIENT_SPORES)
	assert_true(amb.is_emitting())
	sky.apply_theme(ThemeDefs.ICE_CIRCUIT)
	assert_false(amb.is_emitting(), "no ambient particles on a theme without them")
	ShowSettings.reduce_motion = true
	sky.apply_theme(ThemeDefs.MAGMA_CITY)
	assert_false(amb.is_emitting(), "reduce motion stops ambient particles")
	ShowSettings.reset()


func test_explosion_tint_is_applied() -> void:
	var fx: Explosion = (load("res://show/fx/explosion.tscn") as PackedScene).instantiate()
	add_child_autofree(fx)
	var def: Dictionary = ThemeDefs.get_def(ThemeDefs.TOXIC_MARSH)
	fx.set_tint(def["tint_core"] as Color, def["tint_ring"] as Color, def["tint_mid"] as Color, def["tint_end"] as Color)
	fx.play(Vector2(100, 100), 30.0)
	var flash: Sprite2D = fx.get_node("Flash")
	assert_eq(flash.modulate.r, (def["tint_core"] as Color).r)
	assert_eq((fx.get_node("Ring") as Sprite2D).modulate.g, (def["tint_ring"] as Color).g)
