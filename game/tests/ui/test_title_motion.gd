extends GutTest
## Title polish stays cheap and respects reduce motion.

const TITLE: String = "res://ui/title/title_screen.tscn"


func after_each() -> void:
	ShowSettings.reset()
	UiScale.reset_overrides()
	BattleConfig.reset()


func test_logo_glow_and_grid_drift_run_by_default() -> void:
	var t: TitleScreen = (load(TITLE) as PackedScene).instantiate()
	add_child_autofree(t)
	await wait_process_frames(2)
	var logo: Label = t.find_child("Logo", true, false) as Label
	assert_eq((logo.material as ShaderMaterial).get_shader_parameter("shimmer"), 1.0)
	assert_true(t.is_processing(), "the grid sways")
	var sky: NeonSky = t.get_node("Sky") if t.has_node("Sky") else t.find_child("*Sky*", true, false) as NeonSky
	assert_almost_eq(float(sky.get_sky_material().get_shader_parameter("scroll_speed")), TitleScreen.TITLE_GRID_SPEED, 0.0001)


func test_reduce_motion_stills_the_title() -> void:
	ShowSettings.reduce_motion = true
	var t: TitleScreen = (load(TITLE) as PackedScene).instantiate()
	add_child_autofree(t)
	await wait_process_frames(2)
	var logo: Label = t.find_child("Logo", true, false) as Label
	assert_eq((logo.material as ShaderMaterial).get_shader_parameter("shimmer"), 0.0)
	assert_false(t.is_processing())
	for n: Node in t.get_children():
		if n is NeonSky:
			assert_eq(float((n as NeonSky).get_sky_material().get_shader_parameter("scroll_speed")), 0.0)


func test_ember_sparks_drift_by_default() -> void:
	var t: TitleScreen = (load(TITLE) as PackedScene).instantiate()
	add_child_autofree(t)
	await wait_process_frames(2)
	var sparks: EmberSparks = t.find_child("EmberSparks", true, false) as EmberSparks
	assert_not_null(sparks)
	assert_true(sparks.is_processing(), "the sparks drift")
	assert_gt(sparks.visible_count(), 3, "a handful of sparks are alight")
	assert_eq(sparks.mouse_filter, Control.MOUSE_FILTER_IGNORE, "sparks never take taps (the logo is the secret)")


func test_ember_sparks_are_still_under_reduce_motion() -> void:
	ShowSettings.reduce_motion = true
	var t: TitleScreen = (load(TITLE) as PackedScene).instantiate()
	add_child_autofree(t)
	await wait_process_frames(2)
	var sparks: EmberSparks = t.find_child("EmberSparks", true, false) as EmberSparks
	assert_true(sparks.is_still())
	var before: int = sparks.visible_count()
	await wait_process_frames(5)
	assert_eq(sparks.visible_count(), before)
	assert_gt(before, 3, "the still frame still shows sparks")


func test_ember_sparks_do_not_flicker_under_reduce_flashing() -> void:
	var s := EmberSparks.new()
	add_child_autofree(s)
	ShowSettings.reduce_flashing = true
	# No twinkle: a spark's alpha is exactly its slow fade-in / fade-out envelope.
	for i: int in range(EmberSparks.TRACKS.size()):
		s._clock = 3.0
		var life: Array = s._life(i)
		var p: float = life[0] as float
		var envelope: float = smoothstep(0.0, 0.12, p) * (1.0 - smoothstep(0.5, 1.0, p))
		assert_almost_eq(life[1] as float, envelope, 0.0001, "spark %d" % i)
	ShowSettings.reduce_flashing = false
	var twinkled: bool = false
	for i: int in range(EmberSparks.TRACKS.size()):
		var life2: Array = s._life(i)
		var p2: float = life2[0] as float
		var env2: float = smoothstep(0.0, 0.12, p2) * (1.0 - smoothstep(0.5, 1.0, p2))
		if env2 > 0.1 and absf((life2[1] as float) - env2) > 0.001:
			twinkled = true
	assert_true(twinkled, "without the setting the sparks twinkle")


func test_logo_keeps_the_seven_tap_secret_and_fits_the_screen() -> void:
	var t: TitleScreen = (load(TITLE) as PackedScene).instantiate()
	add_child_autofree(t)
	await wait_process_frames(2)
	assert_eq(t.get_logo_text(), "CHARRED HORIZONS")
	assert_eq(t.get_logo_holder().mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_lte(t.get_logo_holder().get_global_rect().size.x, t.get_viewport_rect().size.x, "the logo fits the width")
