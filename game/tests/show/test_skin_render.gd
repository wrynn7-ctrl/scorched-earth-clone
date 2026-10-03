extends GutTest
## Skins on a TankView: every part draws, the hull texture is baked once, and the player identity
## (outline colour, emblem) never comes from the skin.

const TANK: PackedScene = preload("res://show/tank_view.tscn")


func _view() -> TankView:
	var v: TankView = TANK.instantiate()
	add_child_autofree(v)
	return v


func _skin(body: int = 0, turret: int = 0, pattern: int = 0, decal: int = 1) -> SkinData:
	var s: SkinData = SkinData.make_default("t", "T")
	s.body_style = body
	s.turret_style = turret
	s.pattern = pattern
	s.decal = decal
	return s


func test_the_player_outline_colour_stays_the_player_colour_for_any_skin() -> void:
	var v: TankView = _view()
	var skins: Array[SkinData] = []
	for body: int in range(SkinData.BODY_STYLES):
		skins.append(_skin(body, 3 - body, body, body))
	# A skin painted exactly in the player's own colour, in white, in black, and fully glowing.
	for c: Color in [NeonPalette.tank_color(5), Color.WHITE, Color.BLACK, Color(1, 0, 1)]:
		var s: SkinData = _skin()
		s.base = c
		s.accent = c
		s.pattern_color = c
		s.glow = 100
		skins.append(s)
	for player: int in range(NeonPalette.TANK_COLORS.size()):
		v.set_look(player, player)
		v.set_skin(null)
		var plain: Color = v.outline_color()
		assert_eq(plain, NeonPalette.tank_color(player))
		for s: SkinData in skins:
			v.set_skin(s)
			assert_eq(v.outline_color(), NeonPalette.tank_color(player), "skin must not recolour the outline of player %d" % player)
			assert_eq(v.get_emblem_index(), player, "emblem unchanged")
			assert_eq(v.get_color_index(), player)
	await wait_process_frames(1)


func test_a_dead_tank_dims_the_player_colour_only() -> void:
	var v: TankView = _view()
	v.set_look(2, 2)
	v.set_dead(true)
	v.set_skin(null)
	var plain: Color = v.outline_color()
	v.set_skin(_skin())
	assert_eq(v.outline_color(), plain)
	assert_ne(v.outline_color(), NeonPalette.tank_color(2), "dead tanks are dimmed")


func test_every_body_turret_pattern_and_decal_draws() -> void:
	var v: TankView = _view()
	v.skin_ppu = 2
	for body: int in range(SkinData.BODY_STYLES):
		for turret: int in range(SkinData.TURRET_STYLES):
			v.set_skin(_skin(body, turret, (body + turret) % SkinData.PATTERNS, (body * 4 + turret) % SkinData.DECALS))
			v.set_health(60, 100)
			v.set_shield(40, 100)
			v.hit_flash(Color.ORANGE, true)
			v.shield_hit(30)
			await wait_process_frames(1)
	for pattern: int in range(SkinData.PATTERNS):
		for decal: int in range(SkinData.DECALS):
			v.set_skin(_skin(pattern % 4, decal % 4, pattern, decal))
			v.set_compact(decal % 2 == 0)
			await wait_process_frames(1)
	v.set_dead(true)
	await wait_process_frames(1)
	assert_true(v.has_skin())
	v.set_skin(null)
	assert_false(v.has_skin())
	await wait_process_frames(1)


func test_all_shapes_are_valid_polygons_that_fit_the_hull_texture() -> void:
	for body: int in range(SkinData.BODY_STYLES):
		var h: PackedVector2Array = SkinShapes.hull(body)
		assert_gt(Geometry2D.triangulate_polygon(h).size(), 0, "hull %d triangulates" % body)
		for p: Vector2 in h:
			assert_true(SkinShapes.BAKE_RECT.grow(0.001).has_point(p), "hull %d point %s inside the bake rect" % [body, p])
		assert_true(h[0].is_equal_approx(Vector2(-12, 0)) and h[1].is_equal_approx(Vector2(12, 0)), "hull %d sits on the ground" % body)
	for turret: int in range(SkinData.TURRET_STYLES):
		var tip: float = -INF
		for poly: PackedVector2Array in SkinShapes.turret_polys(turret):
			assert_gt(Geometry2D.triangulate_polygon(poly).size(), 0, "turret %d triangulates" % turret)
			for p: Vector2 in poly:
				tip = maxf(tip, p.x)
		assert_eq(tip, SkinShapes.BARREL_TIP, "turret %d ends at the muzzle position shells spawn from" % turret)
	for decal: int in range(SkinData.DECALS):
		var shapes: Array[Dictionary] = SkinShapes.decal_shapes(decal)
		assert_gt(shapes.size(), 0)
		for shape: Dictionary in shapes:
			var pts: PackedVector2Array = shape["p"]
			for p: Vector2 in pts:
				assert_lte(absf(p.x), 1.3)
				assert_lte(absf(p.y), 1.3)
			if shape["k"] == "poly":
				assert_gt(Geometry2D.triangulate_polygon(pts).size(), 0, "decal %d polygon triangulates" % decal)


func test_hull_silhouettes_are_distinct() -> void:
	var seen: Dictionary = {}
	for body: int in range(SkinData.BODY_STYLES):
		seen[str(SkinShapes.hull(body))] = true
	assert_eq(seen.size(), SkinData.BODY_STYLES)
	seen.clear()
	for turret: int in range(SkinData.TURRET_STYLES):
		seen[str(SkinShapes.turret_polys(turret))] = true
	assert_eq(seen.size(), SkinData.TURRET_STYLES)


func test_the_baked_texture_has_the_expected_size_and_content() -> void:
	for pattern: int in range(SkinData.PATTERNS):
		for decal: int in range(SkinData.DECALS):
			var s: SkinData = _skin(0, 0, pattern, decal)
			s.base = Color(0.1, 0.1, 0.3)
			s.accent = Color(1, 0.5, 0)
			s.pattern_color = Color(0, 1, 0)
			var img: Image = SkinBaker.bake_image(s, 4)
			assert_eq(img.get_size(), Vector2i(96, 36))
			var accent_px: int = 0
			var pattern_px: int = 0
			for y: int in range(img.get_height()):
				for x: int in range(img.get_width()):
					var c: Color = img.get_pixel(x, y)
					assert_eq(c.a, 1.0)
					if c.r > 0.9 and c.g > 0.4 and c.b < 0.1:
						accent_px += 1
					if c.g > 0.9 and c.r < 0.1:
						pattern_px += 1
			assert_gt(accent_px, 8, "decal %d is drawn in the accent colour" % decal)
			if pattern == SkinData.Pattern.NONE:
				assert_eq(pattern_px, 0, "no pattern, no pattern pixels")
			else:
				assert_gt(pattern_px, 8, "pattern %d is drawn in its own colour" % pattern)


func test_different_skins_bake_differently() -> void:
	var a: Image = SkinBaker.bake_image(_skin(0, 0, 1, 0), 2)
	var b: Image = SkinBaker.bake_image(_skin(0, 0, 4, 0), 2)
	var c: Image = SkinBaker.bake_image(_skin(0, 0, 1, 5), 2)
	assert_ne(a.get_data(), b.get_data())
	assert_ne(a.get_data(), c.get_data())


func test_a_picture_is_mapped_onto_the_hull_texture() -> void:
	var s: SkinData = _skin()
	s.base = Color.BLACK
	s.image = Image.create(128, 64, false, Image.FORMAT_RGBA8)
	s.image.fill(Color(0.0, 0.0, 1.0))
	var img: Image = SkinBaker.bake_image(s, 4)
	var blue: int = 0
	for y: int in range(img.get_height()):
		for x: int in range(img.get_width()):
			if img.get_pixel(x, y).b > 0.9:
				blue += 1
	assert_gt(blue, img.get_width() * img.get_height() / 2, "the picture covers the hull")


func test_the_texture_is_baked_once_and_can_be_shared() -> void:
	var v: TankView = _view()
	var s: SkinData = _skin(1, 1, 2, 3)
	v.set_skin(s)
	var tex: Texture2D = v.get_skin_texture()
	assert_not_null(tex)
	v.set_look(3, 3)
	v.set_angle_tenths(400)
	v.set_health(10, 100)
	v.set_dead(true)
	v.set_dead(false)
	assert_same(v.get_skin_texture(), tex, "looks, aim and health never re-bake")
	var w: TankView = _view()
	w.set_skin(s, tex)
	assert_same(w.get_skin_texture(), tex, "a baked texture can be shared")
	v.set_skin(null)
	assert_null(v.get_skin_texture())


func test_without_a_skin_the_look_is_the_standard_one() -> void:
	var v: TankView = _view()
	assert_false(v.has_skin())
	assert_eq(v.get_skin_texture(), null)
	v.set_look(1, 4)
	assert_eq(v.outline_color(), NeonPalette.tank_color(1))
	assert_eq(v.muzzle_position(), Vector2.ZERO + (Vector2(0, -TankView.TANK_H) + Vector2(cos(deg_to_rad(90.0)), -sin(deg_to_rad(90.0))) * TankView.BARREL_LEN) * TankView.VISUAL_SCALE)


func test_the_skin_glow_layer_pulses_without_touching_the_identity_layers() -> void:
	var v: TankView = _view()
	v.set_skin(_skin())
	v.set_skin_glow_pulse(0.3)
	assert_almost_eq((v.get_node("SkinGlow") as Node2D).modulate.a, 0.3, 0.001)
	assert_eq((v.get_node("Glow") as Node2D).modulate.a, 1.0, "the player-colour halo is untouched")
	assert_eq((v.get_node("Body") as Node2D).modulate.a, 1.0)
