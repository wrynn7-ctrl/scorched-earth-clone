extends GutTest
## Owner bug round 2 (Galaxy S26 Ultra): the battle HUD still covered only ~1586x645 of the 1950x900
## canvas. The cause is unproven, so the HUD and the overlays now assert their own rectangle every
## frame (LayoutGuard) and the hidden diagnostics screen can be opened inside a battle.

const BATTLE: String = "res://show/battle/battle_scene.tscn"
const WIN: Vector2 = Vector2(3120, 1440)

var _vp: SubViewport = null


func before_each() -> void:
	LayoutGuard.reset()
	UiScale.dpi_override = 560.0
	UiScale.window_px_override = WIN
	var vis: Vector2 = UiScale.visible_size(WIN)
	_vp = SubViewport.new()
	_vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
	_vp.disable_3d = true
	add_child_autofree(_vp)


func after_each() -> void:
	get_tree().paused = false
	UiScale.reset_overrides()
	ShowSettings.reset()
	BattleConfig.reset()
	PlayerLooks.reset()


func _battle() -> BattleController:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(3, 4242, true, 2)
	_vp.add_child(c)
	c.quick_start()
	return c


func _full() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(_vp.size))


func _assert_covers(hud: BattleHud, label: String) -> void:
	var full: Rect2 = _full()
	assert_eq(hud.get_global_rect(), full, "%s: HUD root covers the visible rect" % label)
	var safe: Control = hud.get_node("Safe")
	assert_eq(safe.get_global_rect(), full, "%s: Safe covers the visible rect" % label)
	assert_eq(hud.get_weapon_popup().get_global_rect(), full, "%s: weapon popup covers the visible rect" % label)


# --- the guard restores full coverage ---

func test_a_shrunken_hud_root_is_restored_by_the_next_layout_pass() -> void:
	var c: BattleController = _battle()
	await wait_process_frames(2)
	var hud: BattleHud = c.get_hud()
	_assert_covers(hud, "start")
	assert_eq(hud.get_layout_corrections(), 0, "nothing needed fixing so far")
	# What the device showed: roughly 1586x645 of the canvas.
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	hud.position = Vector2(20.0, 30.0)
	hud.size = Vector2(1586.0, 645.0)
	hud.apply_scale()
	_assert_covers(hud, "after apply_scale")
	assert_gte(hud.get_layout_corrections(), 1)
	assert_ne(LayoutGuard.last_fix, "")


func test_stale_offsets_are_fixed_without_an_explicit_layout_call() -> void:
	var c: BattleController = _battle()
	await wait_process_frames(2)
	var hud: BattleHud = c.get_hud()
	hud.offset_right = -364.0
	hud.offset_bottom = -255.0
	await wait_process_frames(2)
	_assert_covers(hud, "per-frame guard")
	assert_gte(hud.get_layout_corrections(), 1)


func test_a_shrunken_safe_container_is_restored() -> void:
	var c: BattleController = _battle()
	await wait_process_frames(2)
	var hud: BattleHud = c.get_hud()
	var safe: MarginContainer = hud.get_node("Safe")
	safe.offset_left = 40.0
	safe.offset_right = -300.0
	safe.offset_bottom = -200.0
	await wait_process_frames(2)
	_assert_covers(hud, "safe")
	assert_eq(safe.offset_left, 0.0)
	assert_eq(safe.offset_right, 0.0)
	assert_eq(safe.offset_bottom, 0.0)
	assert_gte(hud.get_layout_corrections(), 1)
	# The columns are back at the edges.
	var m: Vector4 = UiScale.edge_margins()
	assert_almost_eq(hud.get_power_panel().get_global_rect().end.x, _full().size.x - m.z, 2.0)


func test_both_wrong_at_once_and_a_resize_afterwards() -> void:
	var c: BattleController = _battle()
	await wait_process_frames(2)
	var hud: BattleHud = c.get_hud()
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	hud.size = Vector2(1000.0, 500.0)
	await wait_process_frames(2)
	_assert_covers(hud, "after fix")
	# The window changes size: the explicitly placed root follows.
	UiScale.window_px_override = Vector2(3360, 1440)
	var vis: Vector2 = UiScale.visible_size(Vector2(3360, 1440))
	_vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
	await wait_process_frames(3)
	_assert_covers(hud, "after resize")


func test_battle_overlay_roots_are_restored() -> void:
	var c: BattleController = _battle()
	await wait_process_frames(2)
	var roots: Array[Control] = [c.get_pause_overlay(), c.get_settings_overlay(), c.get_round_overlay(),
			c.get_match_overlay(), c.get_diagnostics(), c.get_shop(), c.get_hud().get_weapon_popup()]
	for r: Control in roots:
		r.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
		r.position = Vector2(50.0, 40.0)
		r.size = Vector2(700.0, 300.0)
	await wait_process_frames(2)
	for r: Control in roots:
		assert_eq(r.get_global_rect(), _full(), "%s covers the visible rect" % r.name)


func test_the_guard_leaves_a_correct_layout_alone() -> void:
	var c: BattleController = _battle()
	await wait_process_frames(10)
	assert_eq(c.get_hud().get_layout_corrections(), 0)
	assert_eq(LayoutGuard.corrections, 0)


# --- diagnostics inside a battle ---

func test_hud_diagnostics_lines() -> void:
	var c: BattleController = _battle()
	await wait_process_frames(2)
	var text: String = "\n".join(c.get_hud().diagnostics_lines())
	for part: String in ["HUD root:", "Safe:", "margins L", "Row:", "Left:", "Center:", "Right:", "PowerPanel:", "Fire:",
			"AnglePanel:", "parent: CanvasLayer", "layer 10", "follow_viewport", "camera: zoom", "canvas_transform",
			"global_canvas_transform", "layout corrections"]:
		assert_true(text.contains(part), "HUD diagnostics list '%s'" % part)
	assert_true(text.contains("0,0 %dx%d" % [_vp.size.x, _vp.size.y]), "the HUD root rect is listed")


func test_diagnostics_screen_shows_the_hud_block_and_outlines() -> void:
	var c: BattleController = _battle()
	await wait_process_frames(2)
	c.open_diagnostics()
	await wait_process_frames(2)
	var diag: DiagnosticsOverlay = c.get_diagnostics()
	assert_true(diag.visible)
	assert_true(get_tree().paused)
	assert_true(diag.get_text().contains("window (UiScale)"), "the usual lines are still there")
	assert_true(diag.get_hud_text().contains("PowerPanel:"))
	assert_eq(diag.get_global_rect(), _full())
	var rects: Dictionary = c.get_hud().get_outline_rects()
	assert_eq((rects["columns"] as Array).size(), 3)
	assert_eq(rects["root"], _full())
	diag.close()
	assert_false(get_tree().paused, "closing the diagnostics resumes the battle")


func test_diagnostics_fit_the_canvas() -> void:
	var c: BattleController = _battle()
	await wait_process_frames(2)
	c.open_diagnostics()
	await wait_process_frames(4)
	var panel: Control = c.get_diagnostics().get_node("Center/Panel")
	var r: Rect2 = panel.get_global_rect()
	assert_gte(r.position.x, 0.0)
	assert_gte(r.position.y, 0.0)
	assert_lte(r.end.x, _full().size.x + 1.0, "the text fits the width: %s" % str(r))
	assert_lte(r.end.y, _full().size.y + 1.0, "the text fits the height: %s" % str(r))
	c.get_diagnostics().close()


func test_long_press_on_pause_opens_the_diagnostics() -> void:
	var c: BattleController = _battle()
	await wait_process_frames(2)
	var hud: BattleHud = c.get_hud()
	var btn: Button = hud.get_pause_button()
	watch_signals(hud)
	btn.button_down.emit()
	hud._process(1.0)
	assert_false(c.get_diagnostics().visible, "1 s is not long enough")
	hud._process(0.6)
	assert_signal_emitted(hud, "diagnostics_requested")
	assert_true(c.get_diagnostics().visible)
	assert_false(c.is_paused(), "the pause menu is not opened")
	btn.button_up.emit()
	btn.pressed.emit()  # the release that follows the long press
	assert_signal_not_emitted(hud, "pause_pressed")
	assert_false(c.is_paused())
	c.get_diagnostics().close()


func test_short_press_still_pauses_and_an_early_release_cancels_the_hold() -> void:
	var c: BattleController = _battle()
	await wait_process_frames(2)
	var hud: BattleHud = c.get_hud()
	var btn: Button = hud.get_pause_button()
	watch_signals(hud)
	btn.button_down.emit()
	hud._process(0.5)
	btn.button_up.emit()
	btn.pressed.emit()
	assert_signal_emitted(hud, "pause_pressed")
	assert_true(c.is_paused())
	hud._process(5.0)
	assert_false(c.get_diagnostics().visible, "a released button never fires the long press")
	c.close_pause()


func test_pause_settings_version_taps_open_the_diagnostics_with_the_hud_block() -> void:
	var c: BattleController = _battle()
	await wait_process_frames(2)
	c.open_pause()
	c._open_settings_from_pause()
	await wait_process_frames(2)
	var s: SettingsOverlay = c.get_settings_overlay()
	assert_true(s.visible)
	for i: int in range(5):
		s.get_version_button().pressed.emit()
	await wait_process_frames(2)
	var diag: DiagnosticsOverlay = s.get_diagnostics()
	assert_true(diag.visible)
	assert_true(diag.get_hud_text().contains("AnglePanel:"), "the battle HUD lines are listed")
	diag.close()
	c.close_pause()
