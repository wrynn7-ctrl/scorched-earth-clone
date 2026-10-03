extends GutTest
## Neon wipe between screens: it completes, changes the scene while covered, then never blocks
## input again. Reduce motion gives a plain fade; headless default is an instant change.

const TITLE: String = "res://ui/title/title_screen.tscn"
const SETUP: String = "res://ui/setup/setup_screen.tscn"


func before_each() -> void:
	Transition.reset()
	Transition.animate_in_headless = true


func after_each() -> void:
	Transition.animate_in_headless = false
	Transition.reset()
	ShowSettings.reset()
	UiScale.reset_overrides()
	BattleConfig.reset()


func _scene_is(path: String) -> bool:
	var cur: Node = get_tree().current_scene
	return cur != null and cur.scene_file_path == path


func _clean_current() -> void:
	var cur: Node = get_tree().current_scene
	if cur != null:
		cur.queue_free()


func test_wipe_changes_scene_and_finishes() -> void:
	Transition.go(get_tree(), TITLE)
	assert_true(Transition.is_busy(), "running")
	var wipe: ColorRect = Transition.of(get_tree()).get_wipe_rect()
	assert_eq(wipe.mouse_filter, Control.MOUSE_FILTER_STOP, "swallows input while covering")
	await wait_seconds(0.12)
	assert_true(wipe.visible)
	await wait_seconds(0.5)
	assert_false(Transition.is_busy(), "done within ~250 ms plus the build frames")
	assert_true(_scene_is(TITLE), "the new scene is current")
	_clean_current()
	await wait_process_frames(2)


func test_input_is_not_blocked_afterwards() -> void:
	Transition.go(get_tree(), TITLE)
	await wait_seconds(0.6)
	var t: Transition = Transition.of(get_tree())
	assert_false(t.get_wipe_rect().visible, "hidden")
	assert_eq(t.get_wipe_rect().mouse_filter, Control.MOUSE_FILTER_IGNORE, "ignores the mouse")
	# A real click reaches the button underneath.
	var title: TitleScreen = get_tree().current_scene as TitleScreen
	assert_not_null(title)
	var pressed: Array[bool] = [false]
	title.get_settings_button().pressed.connect(func() -> void: pressed[0] = true)
	title.get_settings_button().pressed.emit()
	assert_true(pressed[0])
	_clean_current()
	await wait_process_frames(2)


func test_second_request_during_a_wipe_is_ignored() -> void:
	Transition.go(get_tree(), TITLE)
	Transition.go(get_tree(), SETUP)  # a double tap
	await wait_seconds(0.6)
	assert_true(_scene_is(TITLE), "only the first navigation happened")
	_clean_current()
	await wait_process_frames(2)


func test_reduce_motion_is_a_plain_fade() -> void:
	ShowSettings.reduce_motion = true
	Transition.go(get_tree(), TITLE)
	var t: Transition = Transition.of(get_tree())
	await wait_process_frames(2)
	var mat: ShaderMaterial = t.get_wipe_rect().material as ShaderMaterial
	assert_eq(mat.get_shader_parameter("plain"), 1.0, "no moving wipe")
	await wait_seconds(0.6)
	assert_false(Transition.is_busy())
	assert_true(_scene_is(TITLE))
	_clean_current()
	await wait_process_frames(2)


func test_headless_default_changes_scene_at_once() -> void:
	Transition.animate_in_headless = false
	assert_false(Transition.animates())
	Transition.go(get_tree(), TITLE)
	await wait_process_frames(2)
	assert_true(_scene_is(TITLE))
	assert_false(Transition.is_busy())
	_clean_current()
	await wait_process_frames(2)


func test_panel_fade_in_completes_and_leaves_full_alpha() -> void:
	var panel := ColorRect.new()
	add_child_autofree(panel)
	Transition.fade_in(panel, 0.1)
	assert_eq(panel.modulate.a, 0.0, "starts transparent")
	await wait_seconds(0.25)
	assert_eq(panel.modulate.a, 1.0)
	ShowSettings.reduce_motion = true
	Transition.fade_in(panel, 0.1)
	assert_eq(panel.modulate.a, 1.0, "reduce motion: no fade at all")


func test_overlays_fade_in_on_open() -> void:
	var o := OverlayPanel.new()
	add_child_autofree(o)
	o.open()
	assert_true(o.visible, "visible at once")
	assert_eq(o.modulate.a, 0.0)
	await wait_seconds(0.25)
	assert_eq(o.modulate.a, 1.0)
	o.close()
	assert_false(o.visible)
