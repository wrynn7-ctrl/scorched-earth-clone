extends GutTest
## Love Edition pieces on their own: the drawn heart, the love theme (and that nothing else can pick it), the effects nodes,
## and the sounds with their event mapping.

const LOVE_SOUNDS: Array[String] = ["love_fire", "heart_burst", "love_win", "love_found"]


func before_each() -> void:
	ShowSettings.reset()
	AudioDirector.reset_for_tests()


func after_each() -> void:
	ShowSettings.reset()
	AudioDirector.reset_for_tests()


# --- the heart ---------------------------------------------------------------------------------

func test_heart_outline_is_a_symmetric_heart_with_a_cleft_and_a_tip() -> void:
	var o: PackedVector2Array = HeartShape.unit_outline()
	assert_gt(o.size(), 20)
	var minx: float = 9.0
	var maxx: float = -9.0
	var top: float = 9.0
	var bottom: float = -9.0
	for p: Vector2 in o:
		minx = minf(minx, p.x)
		maxx = maxf(maxx, p.x)
		top = minf(top, p.y)
		bottom = maxf(bottom, p.y)
	assert_almost_eq(minx, -maxx, 0.02, "symmetric")
	assert_almost_eq(maxx, 1.0, 0.05)
	assert_lt(top, -0.85)
	assert_gt(bottom, 0.85)
	# The cleft: the outline at x = 0 on the top side sits lower than the lobes.
	var cleft: float = -9.0
	for p: Vector2 in o:
		if absf(p.x) < 0.08 and p.y < 0.0:
			cleft = maxf(cleft, p.y)
	assert_gt(cleft, top + 0.25, "a dip between the lobes")


func test_a_filled_part_grows_from_the_tip() -> void:
	var c := Vector2(50, 50)
	var prev: float = 0.0
	for f: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var area: float = 0.0
		for poly: PackedVector2Array in HeartShape.filled_part(c, 20.0, f):
			area += absf(_area(poly))
		assert_gte(area, prev - 0.001, "monotone at %.2f" % f)
		prev = area
	assert_eq(HeartShape.filled_part(c, 20.0, 0.0).size(), 0, "empty")
	assert_eq(HeartShape.filled_part(c, 20.0, 1.0).size(), 1, "whole")
	assert_gte(HeartShape.filled_part(c, 20.0, 0.97).size(), 1, "nearly full still draws")


static func _area(p: PackedVector2Array) -> float:
	var a: float = 0.0
	for i: int in range(p.size()):
		var q: Vector2 = p[(i + 1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return a * 0.5


func test_heart_textures_are_drawn_not_glyphs() -> void:
	var icon: Texture2D = HeartShape.icon_texture(Color(1, 0.4, 0.7))
	var img: Image = icon.get_image()
	assert_gt(img.get_pixel(32, 28).a, 0.9, "solid in the middle")
	assert_lt(img.get_pixel(1, 1).a, 0.05, "empty in the corner")
	assert_lt(img.get_pixel(32, 5).a, 0.3, "the cleft at the top is open")
	assert_eq(HeartShape.icon_texture(Color(1, 0.4, 0.7)), icon, "cached")
	assert_eq(FxTextures.heart().get_width(), 96)
	assert_eq(FxTextures.sparkle().get_width(), 64)
	assert_gt(FxTextures.heart().get_image().get_pixel(48, 48).a, 0.9)


# --- the love theme ----------------------------------------------------------------------------

func test_the_love_theme_exists_but_no_choice_can_select_it() -> void:
	var def: Dictionary = ThemeDefs.get_def(ThemeDefs.LOVE_THEME)
	assert_eq(def["id"], ThemeDefs.LOVE_THEME)
	for k: String in ThemeDefs.REQUIRED_KEYS:
		assert_true(def.has(k), k)
	assert_eq((def["strata"] as Array[Color]).size(), ThemeDefs.STRATA_COUNT)
	assert_eq(def["sun_style"], ThemeDefs.SUN_HEART, "a heart-shaped sun")
	assert_false(ThemeDefs.ids().has(ThemeDefs.LOVE_THEME), "not in the picker list")
	assert_eq(ThemeDefs.ids().size(), 5)
	assert_eq(ThemeDefs.all_ids().size(), 6)
	assert_eq(ThemeDefs.sanitize(ThemeDefs.LOVE_THEME), ThemeDefs.DEFAULT_ID, "not a valid saved choice")
	for seed_value: int in range(40):
		assert_ne(ThemeDefs.resolve(ThemeDefs.RANDOM, seed_value, seed_value % 5, true), ThemeDefs.LOVE_THEME, "never by Random")
	assert_ne(ThemeDefs.resolve(ThemeDefs.LOVE_THEME, 1, 0, true), ThemeDefs.LOVE_THEME)
	assert_true(ThemeDefs.is_love(ThemeDefs.LOVE_THEME))


func test_the_love_theme_is_pink_not_the_default_look() -> void:
	var def: Dictionary = ThemeDefs.get_def(ThemeDefs.LOVE_THEME)
	var mid: Color = def["sky_mid"]
	assert_gt(mid.r, mid.b * 1.3, "rose sky")
	var low: Color = def["sky_low"]
	assert_gt(low.r, 0.9, "peach-pink horizon")
	assert_gt(low.g, low.b, "peach, not magenta")
	assert_eq(def["ambient"], ThemeDefs.AMBIENT_HEARTS)


func test_the_sky_and_terrain_accept_the_love_theme() -> void:
	var sky: NeonSky = (load("res://show/sky.tscn") as PackedScene).instantiate()
	add_child_autofree(sky)
	sky.apply_theme(ThemeDefs.LOVE_THEME)
	assert_eq(sky.get_theme_id(), ThemeDefs.LOVE_THEME)
	assert_eq(sky.get_sky_material().get_shader_parameter("sun_style"), ThemeDefs.SUN_HEART)
	assert_eq(sky.get_ambient().get_style(), ThemeDefs.AMBIENT_HEARTS)
	assert_true(sky.get_ambient().is_emitting())
	ShowSettings.reduce_motion = true
	sky.apply_theme(ThemeDefs.SUNSET_GRID)
	sky.apply_theme(ThemeDefs.LOVE_THEME)
	assert_false(sky.get_ambient().is_emitting(), "no drifting hearts with reduced motion")


# --- effects ---------------------------------------------------------------------------------

func test_smiley_floats_up_over_the_tank_and_hearts_orbit() -> void:
	var s := LoveSmiley.new()
	add_child_autofree(s)
	s.show_over(Vector2(400, 600), false)
	assert_true(s.is_showing())
	assert_eq(s.position, s.get_rest_position())
	assert_almost_eq(s.get_rest_position().x, 400.0, 0.01)
	assert_lt(s.get_rest_position().y, 600.0 - LoveSmiley.HOVER + 1.0)
	assert_true(s.is_processing(), "bobs")
	var y0: float = s.position.y
	s.show_over(Vector2(400, 600), true)
	assert_eq(s.modulate.a, 0.0, "starts invisible and fades in while it rises")
	assert_gt(s.position.y, y0, "starts below its resting place")
	ShowSettings.reduce_motion = true
	s.show_over(Vector2(400, 600), true)
	assert_eq(s.position, s.get_rest_position(), "reduced motion: simply there")
	assert_false(s.is_processing())
	s.hide_smiley()
	assert_false(s.visible)


func test_a_tank_high_on_a_hill_keeps_the_smiley_on_screen() -> void:
	var s := LoveSmiley.new()
	add_child_autofree(s)
	s.show_over(Vector2(400, 150), false)
	assert_gte(s.get_rest_position().y, LoveSmiley.RADIUS * 1.5)


func test_confetti_rains_and_calms_with_reduced_motion() -> void:
	var c := HeartConfetti.new()
	add_child_autofree(c)
	await wait_process_frames(1)
	assert_false(c.is_active())
	c.start()
	assert_true(c.is_active())
	assert_eq(c.particle_count(), HeartConfetti.COUNT)
	c.stop()
	assert_false(c.is_active())
	ShowSettings.reduce_motion = true
	c.start()
	assert_eq(c.particle_count(), HeartConfetti.COUNT_CALM)


func test_the_burst_is_reusable_and_reports_its_area() -> void:
	var b := HeartBurst.new()
	add_child_autofree(b)
	assert_eq(b.get_world_rect(), Rect2(), "idle: no area")
	b.play(Vector2(300, 300), 30.0)
	assert_true(b.is_playing())
	assert_true(b.get_world_rect().has_point(Vector2(300, 300)))
	b.play(Vector2(500, 200), 30.0)
	assert_eq(b.position, Vector2(500, 200))
	var n: int = b.get_child_count()
	b.play(Vector2(500, 200), 30.0)
	assert_eq(b.get_child_count(), n, "no node per play")


func test_the_love_popup_shows_the_amount_with_a_drawn_heart() -> void:
	var p := LovePopup.new()
	add_child_autofree(p)
	p.pop(34, Vector2(100, 100))
	assert_eq(p.text, "+34")
	assert_true(p.visible)
	assert_gt(p.size.x, 40.0, "room for the heart after the number")


# --- sound -----------------------------------------------------------------------------------

func test_the_love_sounds_exist_and_are_registered() -> void:
	for key: String in LOVE_SOUNDS:
		assert_true(AudioDirector.SOUNDS.has(key), key)
		var s: AudioStreamWAV = (AudioDirector.SOUNDS[key] as Dictionary)["s"] as AudioStreamWAV
		assert_not_null(s)
		assert_gt(s.get_length(), 0.2, key)
		assert_lt(s.get_length(), 3.0, key)


func test_love_events_map_to_the_new_sounds() -> void:
	assert_eq(AudioDirector.sound_for_event({"type": "fire", "weapon": "heart"}), "love_fire")
	assert_eq(AudioDirector.sound_for_event({"type": "heart_burst", "radius": 30}), "heart_burst")
	assert_eq(AudioDirector.sound_for_event({"type": "love", "tank": 1, "amount": 34}), "love_fire")
	assert_eq(AudioDirector.sound_for_event({"type": "round_end", "winner": 0}, true, true), "love_win")
	assert_eq(AudioDirector.sound_for_event({"type": "round_end", "winner": 1}, false, true), "love_win")
	assert_eq(AudioDirector.sound_for_event({"type": "round_end", "winner": 0}, true, false), "match_win", "standard unchanged")
	assert_eq(AudioDirector.sound_for_event({"type": "round_end", "winner": -1}, true, true), "")
	assert_eq(AudioDirector.fire_key("heart"), "love_fire")
	AudioDirector.record_log = true
	AudioDirector.on_event({"type": "heart_burst", "radius": 30}, false, true)
	AudioDirector.on_event({"type": "round_end", "winner": 0}, true, true)
	assert_eq(AudioDirector.played_log, ["heart_burst", "love_win"] as Array[String])
