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
