extends GutTest


func after_each() -> void:
	UiScale.reset_overrides()


func test_angle_formatting() -> void:
	assert_eq(HudFormat.format_angle(452), "45.2°")
	assert_eq(HudFormat.format_angle(0), "0.0°")
	assert_eq(HudFormat.format_angle(900), "90.0°")
	assert_eq(HudFormat.format_angle(1800), "0.0°", "facing left, flat")
	assert_eq(HudFormat.format_angle(5), "0.5°")
	assert_eq(HudFormat.format_angle(1795), "0.5°")
	assert_eq(HudFormat.format_angle(1350), "45.0°")
	assert_eq(HudFormat.format_angle(1351), "44.9°")
	assert_eq(HudFormat.format_angle(2500), "0.0°", "clamped")
	assert_eq(HudFormat.power(1200), "1000")
	assert_eq(HudFormat.wind(-37), "37")


func test_facing_of() -> void:
	assert_eq(HudFormat.facing_of(0), HudFormat.FACING_RIGHT)
	assert_eq(HudFormat.facing_of(450), HudFormat.FACING_RIGHT)
	assert_eq(HudFormat.facing_of(899), HudFormat.FACING_RIGHT)
	assert_eq(HudFormat.facing_of(900), HudFormat.FACING_UP)
	assert_eq(HudFormat.facing_of(901), HudFormat.FACING_LEFT)
	assert_eq(HudFormat.facing_of(1800), HudFormat.FACING_LEFT)


func test_power_slider_clamps_and_emits() -> void:
	var s: PowerSlider = add_child_autofree(PowerSlider.new())
	watch_signals(s)
	s.set_value(1500)
	assert_eq(s.value, 1000)
	assert_signal_emitted_with_parameters(s, "power_changed", [1000])
	s.set_value(-20)
	assert_eq(s.value, 0)
	assert_signal_emit_count(s, "power_changed", 2)
	s.set_value(0)
	assert_signal_emit_count(s, "power_changed", 2, "no emit when unchanged")
	s.nudge(1)
	assert_eq(s.value, 1)
	s.set_value_silent(700)
	assert_eq(s.value, 700)
	assert_signal_emit_count(s, "power_changed", 3, "silent set does not emit")


func test_power_slider_value_mapping() -> void:
	assert_eq(PowerSlider.value_for_y(100.0, 100.0, 500.0), 1000)
	assert_eq(PowerSlider.value_for_y(500.0, 100.0, 500.0), 0)
	assert_eq(PowerSlider.value_for_y(300.0, 100.0, 500.0), 500)
	assert_eq(PowerSlider.value_for_y(-50.0, 100.0, 500.0), 1000, "clamped above")
	assert_eq(PowerSlider.value_for_y(900.0, 100.0, 500.0), 0, "clamped below")


func test_power_slider_responds_to_mouse_drag() -> void:
	var s: PowerSlider = add_child_autofree(PowerSlider.new())
	s.size = Vector2(80, 400)
	watch_signals(s)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(40, 0)
	s._gui_input(press)
	assert_eq(s.value, 1000)
	var move := InputEventMouseMotion.new()
	move.position = Vector2(40, s.size.y)
	s._gui_input(move)
	assert_eq(s.value, 0)


func test_aim_angle_from_drag() -> void:
	var p := Vector2(400, 500)
	assert_eq(AimInput.angle_from_drag(p, Vector2(500, 500)), 0)
	assert_eq(AimInput.angle_from_drag(p, Vector2(400, 400)), 900)
	assert_eq(AimInput.angle_from_drag(p, Vector2(300, 500)), 1800)
	assert_eq(AimInput.angle_from_drag(p, Vector2(500, 400)), 450)
	assert_eq(AimInput.angle_from_drag(p, Vector2(500, 600)), 0, "below horizon snaps right")
	assert_eq(AimInput.angle_from_drag(p, Vector2(300, 600)), 1800, "below horizon snaps left")
	assert_eq(AimInput.angle_from_drag(p, Vector2(402, 500), 14.0), -1, "too close to pivot")


func test_aim_input_emits_angle_changed() -> void:
	var a: AimInput = add_child_autofree(AimInput.new())
	a.set_pivot(Vector2(400, 500))
	a.set_angle_tenths(450)
	watch_signals(a)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(400, 300)
	a._gui_input(press)
	assert_signal_emitted_with_parameters(a, "angle_changed", [900])
	var move := InputEventMouseMotion.new()
	move.position = Vector2(400, 301)
	a._gui_input(move)
	assert_signal_emit_count(a, "angle_changed", 1, "unchanged angle does not re-emit")
	press.pressed = false
	a._gui_input(press)
	assert_false(a.is_dragging())


func test_fine_button_press_and_repeat() -> void:
	var b: FineButton = add_child_autofree(FineButton.new())
	watch_signals(b)
	b.begin_hold()
	assert_signal_emit_count(b, "stepped", 1)
	b._process(FineButton.HOLD_DELAY - 0.01)
	assert_signal_emit_count(b, "stepped", 1, "no repeat before the delay")
	b._process(0.02)
	assert_signal_emit_count(b, "stepped", 2)
	b._process(FineButton.REPEAT_INTERVAL * 3.0 + 0.001)
	assert_signal_emit_count(b, "stepped", 5)
	assert_eq(b.multiplier_for(0), 1)
	assert_eq(b.multiplier_for(FineButton.FAST_AFTER), 5)
	assert_eq(b.multiplier_for(FineButton.FASTER_AFTER), 10)
	b.end_hold()
	b._process(5.0)
	assert_signal_emit_count(b, "stepped", 5, "released: no more steps")


func _angle_panel() -> AnglePanel:
	var p: AnglePanel = add_child_autofree(AnglePanel.new())
	await wait_frames(1)
	return p


func _tap(b: FineButton) -> void:
	b.begin_hold()
	b.end_hold()


func _shown(p: AnglePanel) -> String:
	return (p.get_node("Box/ReadRow/Readout") as Label).text


func _marks(p: AnglePanel) -> Array[bool]:
	return [(p.get_node("Box/ReadRow/MarkLeft") as FacingMark).lit,
			(p.get_node("Box/ReadRow/MarkRight") as FacingMark).lit]


func test_angle_buttons_are_screen_relative_facing_right() -> void:
	var p: AnglePanel = await _angle_panel()
	var left: FineButton = p.get_node("Box/Row/Left")
	var right: FineButton = p.get_node("Box/Row/Right")
	p.set_angle_tenths(450)
	assert_eq(_shown(p), "45.0°")
	_tap(left)
	assert_eq(p.get_angle_tenths(), 451, "left turns the barrel toward screen-left: raw +1")
	assert_eq(_shown(p), "45.1°")
	_tap(right)
	_tap(right)
	assert_eq(p.get_angle_tenths(), 449)
	assert_eq(_shown(p), "44.9°")
	assert_eq(_marks(p), [false, true], "chevron on the right side while facing right")


func test_angle_buttons_are_screen_relative_facing_left() -> void:
	var p: AnglePanel = await _angle_panel()
	var left: FineButton = p.get_node("Box/Row/Left")
	var right: FineButton = p.get_node("Box/Row/Right")
	p.set_angle_tenths(1350)
	assert_eq(_shown(p), "45.0°")
	_tap(left)
	assert_eq(p.get_angle_tenths(), 1351)
	assert_eq(_shown(p), "44.9°", "facing left, the left button lowers the number")
	_tap(right)
	_tap(right)
	assert_eq(p.get_angle_tenths(), 1349)
	assert_eq(_shown(p), "45.1°")
	assert_eq(_marks(p), [true, false], "chevron on the left side while facing left")


func test_angle_buttons_clamp_and_emit() -> void:
	var p: AnglePanel = await _angle_panel()
	var left: FineButton = p.get_node("Box/Row/Left")
	var right: FineButton = p.get_node("Box/Row/Right")
	watch_signals(p)
	p.set_angle_tenths(1799)
	assert_signal_not_emitted(p, "angle_changed")
	_tap(left)
	assert_eq(p.get_angle_tenths(), 1800)
	assert_signal_emitted_with_parameters(p, "angle_changed", [1800])
	_tap(left)
	assert_eq(p.get_angle_tenths(), 1800, "clamped at 1800")
	assert_signal_emit_count(p, "angle_changed", 1, "no emit when clamped")
	p.set_angle_tenths(1)
	_tap(right)
	assert_eq(p.get_angle_tenths(), 0)
	_tap(right)
	assert_eq(p.get_angle_tenths(), 0, "clamped at 0")
	assert_signal_emit_count(p, "angle_changed", 2)


func test_holding_left_across_vertical_flips_the_facing() -> void:
	var p: AnglePanel = await _angle_panel()
	var left: FineButton = p.get_node("Box/Row/Left")
	p.set_angle_tenths(899)
	assert_eq(_shown(p), "89.9°")
	assert_eq(_marks(p), [false, true])
	_tap(left)
	assert_eq(p.get_angle_tenths(), 900)
	assert_eq(_shown(p), "90.0°")
	assert_eq(HudFormat.facing_of(p.get_angle_tenths()), HudFormat.FACING_UP)
	assert_eq(_marks(p), [false, false], "straight up: no chevron")
	_tap(left)
	assert_eq(p.get_angle_tenths(), 901)
	assert_eq(_shown(p), "89.9°", "89.9 -> 90.0 -> 89.9")
	assert_eq(_marks(p), [true, false], "facing flipped to the left")


func test_readout_and_buttons_agree_after_a_drag() -> void:
	var hud: BattleHud = add_child_autofree(BattleHud.new())
	await wait_frames(1)
	var aim: AimInput = hud.get_aim_input()
	aim.set_pivot(Vector2(400, 500))
	# Finger up-left of the tank: raw 1350, shown 45.0 facing left.
	aim.angle_changed.emit(AimInput.angle_from_drag(Vector2(400, 500), Vector2(300, 400)))
	assert_eq(hud.get_angle_tenths(), 1350)
	var panel: AnglePanel = hud.get_angle_panel()
	assert_eq(_shown(panel), "45.0°")
	_tap(panel.get_node("Box/Row/Left"))
	assert_eq(hud.get_angle_tenths(), 1351, "the buttons continue from the dragged angle")
	assert_eq(aim.get_angle_tenths(), 1351, "and the drag surface follows")


func test_angle_buttons_show_arrows_and_tooltips() -> void:
	var p: AnglePanel = await _angle_panel()
	var left: FineButton = p.get_node("Box/Row/Left")
	var right: FineButton = p.get_node("Box/Row/Right")
	assert_eq(left.get_arrow(), FineButton.Arrow.LEFT)
	assert_eq(right.get_arrow(), FineButton.Arrow.RIGHT)
	assert_eq(left.text, "", "no text on arrow buttons")
	assert_eq(right.text, "")
	assert_eq(left.tooltip_text, "Turn barrel left 0.1°")
	assert_eq(right.tooltip_text, "Turn barrel right 0.1°")
	assert_eq(left.accessibility_name, left.tooltip_text)
	assert_eq(right.accessibility_name, right.tooltip_text)
	assert_true(left.size.y >= UiScale.touch() and right.size.y >= UiScale.touch(), "touch target")
	assert_true(left.size.x >= UiScale.touch() and right.size.x >= UiScale.touch(), "touch target")
	p.set_angle_tenths(1350)
	var readout: Label = p.get_node("Box/ReadRow/Readout")
	assert_eq(readout.accessibility_name, "45.0° facing left")
	p.set_angle_tenths(450)
	assert_eq(readout.accessibility_name, "45.0° facing right")
	p.set_angle_tenths(900)
	assert_eq(readout.accessibility_name, "90.0° straight up")


func test_all_arrow_directions_draw_without_errors() -> void:
	for a: int in [FineButton.Arrow.UP, FineButton.Arrow.DOWN, FineButton.Arrow.LEFT, FineButton.Arrow.RIGHT]:
		var b: FineButton = add_child_autofree(FineButton.new())
		b.custom_minimum_size = Vector2(120.0, 90.0)
		b.arrow = a
		await wait_frames(2)
		assert_eq(b.get_arrow(), a)
		assert_eq(b._arrow_dir().length(), 1.0, "unit direction")
		b.disabled = true
		await wait_frames(1)
		assert_true(b.is_inside_tree())


func test_power_buttons_keep_text_without_arrow() -> void:
	var p: PowerPanel = add_child_autofree(PowerPanel.new())
	await wait_frames(1)
	assert_eq((p.get_node("Box/Plus") as FineButton).get_arrow(), FineButton.Arrow.NONE)
	assert_ne((p.get_node("Box/Plus") as FineButton).text, "")


func test_power_panel_fine_buttons() -> void:
	var p: PowerPanel = add_child_autofree(PowerPanel.new())
	await wait_frames(1)
	watch_signals(p)
	p.set_power(500)
	var plus: FineButton = p.get_node("Box/Plus")
	plus.begin_hold()
	plus.end_hold()
	assert_eq(p.get_power(), 501)
	assert_signal_emitted_with_parameters(p, "power_changed", [501])


func test_wind_indicator_clamps() -> void:
	var w: WindIndicator = add_child_autofree(WindIndicator.new())
	await wait_frames(1)
	w.set_wind(-250)
	assert_eq(w.get_wind(), -100)
	w.set_wind(35)
	assert_eq((w.get_node("Row/Col/Value") as Label).text, "35")


func test_turn_banner_text() -> void:
	var b: TurnBanner = add_child_autofree(TurnBanner.new())
	await wait_frames(1)
	b.show_turn(1)
	assert_string_contains(b.get_text(), "2")
	b.show_turn(0, "ALICE")
	assert_string_contains(b.get_text(), "ALICE")


func test_turn_banner_for_a_cpu_player() -> void:
	var b: TurnBanner = add_child_autofree(TurnBanner.new())
	await wait_frames(1)
	b.show_cpu_turn(2, SimConstants.CTRL_NORMAL)
	assert_eq(b.get_text(), "CPU NORMAL — PLAYER 3")
	assert_false(b.is_thinking(), "the thinking line is off until asked")
	b.set_thinking(true)
	assert_true(b.is_thinking())
	assert_eq(b.get_thinking_text(), "thinking…")
	for pair: Array in [[SimConstants.CTRL_EASY, "CPU EASY — PLAYER 3"], [SimConstants.CTRL_HARD, "CPU HARD — PLAYER 3"],
			[SimConstants.CTRL_EXPERT, "CPU EXPERT — PLAYER 3"]]:
		b.show_cpu_turn(2, pair[0])
		assert_eq(b.get_text(), pair[1])
	# A human turn afterwards is the plain banner again.
	b.show_turn(1)
	assert_eq(b.get_text(), "PLAYER 2'S TURN")
	b.set_thinking(false)
	assert_false(b.is_thinking())
	# Reduced motion: the line is shown without pulsing.
	ShowSettings.reduce_motion = true
	b.set_thinking(true)
	assert_true(b.is_thinking())
	assert_eq((b.find_child("Thinking", true, false) as Label).modulate.a, 1.0)
	ShowSettings.reset()


func test_hud_cpu_turn_helpers() -> void:
	var hud: BattleHud = add_child_autofree(BattleHud.new())
	await wait_frames(1)
	hud.show_cpu_turn(3, SimConstants.CTRL_HARD)
	assert_eq(hud.get_turn_banner().get_text(), "CPU HARD — PLAYER 4")
	assert_true(hud.get_turn_banner().is_thinking())
	hud.set_thinking(false)
	assert_false(hud.get_turn_banner().is_thinking())
	hud.show_cpu_turn(3, SimConstants.CTRL_HARD, false)
	assert_false(hud.get_turn_banner().is_thinking())
	hud.show_cpu_turn(3, SimConstants.CTRL_HARD, true)
	hud.show_turn(0)
	assert_false(hud.get_turn_banner().is_thinking(), "a human turn clears the thinking line")


func test_fire_button_signal_and_disabled() -> void:
	var f: FireButton = add_child_autofree(FireButton.new())
	await wait_frames(1)
	watch_signals(f)
	f.pressed.emit()
	assert_signal_emit_count(f, "fire_pressed", 1)
	f.set_enabled(false)
	assert_true(f.disabled)
	f.pressed.emit()
	assert_signal_emit_count(f, "fire_pressed", 1, "disabled: no signal")
	f.set_enabled(true)
	assert_false(f.disabled)


func test_ui_scale_dp() -> void:
	UiScale.dpi_override = 320.0
	UiScale.window_px_override = Vector2(1600, 900)
	assert_almost_eq(UiScale.dp(48.0), 96.0, 0.01, "320 dpi at 1:1 canvas = 2 px per dp")
	UiScale.window_px_override = Vector2(3200, 1800)
	assert_almost_eq(UiScale.dp(48.0), 48.0, 0.01, "bigger window = fewer canvas units per dp")
	assert_almost_eq(UiScale.canvas_to_dp(UiScale.touch()), 48.0, 0.01)
	assert_true(UiScale.visible_size(Vector2(2340, 1080)).is_equal_approx(Vector2(1950, 900)))


func test_theme_and_font() -> void:
	var th: Theme = load("res://ui/theme/neon_theme.tres")
	assert_not_null(th)
	assert_true(th.default_font is FontFile, "futuristic font loaded")
	assert_eq(th.get_type_variation_base(&"FireButton"), &"Button")
	assert_eq(th.get_type_variation_base(&"FineButton"), &"Button")
	assert_true(th.has_stylebox(&"normal", &"FireButton"))


func test_hud_scenes_instantiate() -> void:
	for path: String in [
		"aim_input", "angle_panel", "power_slider", "power_panel", "fire_button",
		"wind_indicator", "turn_banner", "emblem_icon", "fine_button", "hud",
	]:
		var node: Node = (load("res://ui/hud/%s.tscn" % path) as PackedScene).instantiate()
		assert_not_null(node, path)
		add_child_autofree(node)
		await wait_frames(1)
		assert_true(node.is_inside_tree(), path)


func test_locale_keys_exist() -> void:
	var f := FileAccess.open("res://locale/strings.csv", FileAccess.READ)
	var text: String = f.get_as_text()
	for key: String in ["HUD_ANGLE", "HUD_POWER", "HUD_FIRE", "HUD_WIND", "HUD_TURN_OF", "HUD_PLAYER_N"]:
		assert_true(text.contains("\n" + key + ","), key)
	for k: String in NeonPalette.TANK_COLOR_NAME_KEYS + NeonPalette.EMBLEM_NAME_KEYS:
		assert_true(text.contains("\n" + k + ","), k)
