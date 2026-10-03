extends GutTest
## Two fingers at once: one drags the aim, another moves the power slider. Each control follows only the finger
## that started on it. The engine's emulated copies (mouse from touch, touch from mouse) are never counted twice.


func after_each() -> void:
	UiScale.reset_overrides()


func _touch(index: int, pressed: bool, pos: Vector2) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.pressed = pressed
	e.position = pos
	return e


func _drag(index: int, pos: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	return e


func _aim() -> AimInput:
	var a: AimInput = add_child_autofree(AimInput.new())
	a.set_pivot(Vector2(400, 500))
	a.set_angle_tenths(450)
	return a


func _slider() -> PowerSlider:
	var s: PowerSlider = add_child_autofree(PowerSlider.new())
	s.size = Vector2(80, 400)
	s.set_value_silent(500)
	return s


## y (in the slider's own coordinates) that gives `value`.
func _y_for(s: PowerSlider, value: int) -> float:
	var r: Rect2 = s._track_rect()
	return r.end.y - r.size.y * float(value) / 1000.0


func test_aim_follows_a_touch_finger() -> void:
	var a: AimInput = _aim()
	watch_signals(a)
	a._gui_input(_touch(0, true, Vector2(400, 300)))
	assert_true(a.is_dragging())
	assert_eq(a.get_angle_tenths(), 900)
	a._gui_input(_drag(0, Vector2(500, 400)))
	assert_eq(a.get_angle_tenths(), 450)
	a._gui_input(_touch(0, false, Vector2(500, 400)))
	assert_false(a.is_dragging())
	assert_signal_emit_count(a, "drag_started", 1)
	assert_signal_emit_count(a, "drag_ended", 1)


func test_aim_ignores_a_second_finger() -> void:
	var a: AimInput = _aim()
	a._gui_input(_touch(0, true, Vector2(400, 300)))
	a._gui_input(_touch(1, true, Vector2(300, 500)))  # would be 180 degrees
	a._gui_input(_drag(1, Vector2(300, 500)))
	assert_eq(a.get_angle_tenths(), 900, "the second finger does not steer")
	a._gui_input(_touch(1, false, Vector2(300, 500)))
	assert_true(a.is_dragging(), "lifting the other finger does not end the drag")
	a._gui_input(_drag(0, Vector2(500, 400)))
	assert_eq(a.get_angle_tenths(), 450)
	a._gui_input(_touch(0, false, Vector2(500, 400)))
	assert_false(a.is_dragging())


func test_aim_finger_can_be_any_index() -> void:
	var a: AimInput = _aim()
	a._gui_input(_touch(1, true, Vector2(400, 300)))
	a._gui_input(_drag(0, Vector2(300, 500)))
	assert_eq(a.get_angle_tenths(), 900, "a drag of another index is ignored")
	a._gui_input(_drag(1, Vector2(500, 400)))
	assert_eq(a.get_angle_tenths(), 450)


func test_slider_follows_a_touch_finger_and_ignores_others() -> void:
	var s: PowerSlider = _slider()
	s._gui_input(_touch(1, true, Vector2(40, _y_for(s, 1000))))
	assert_eq(s.value, 1000)
	s._gui_input(_drag(0, Vector2(40, _y_for(s, 0))))
	assert_eq(s.value, 1000, "a drag of another finger is ignored")
	s._gui_input(_drag(1, Vector2(40, _y_for(s, 0))))
	assert_eq(s.value, 0)
	s._gui_input(_touch(0, false, Vector2(40, 400)))
	assert_true(s.is_dragging(), "another finger lifting does not release the slider")
	s._gui_input(_touch(1, false, Vector2(40, 400)))
	assert_false(s.is_dragging())


func test_aim_and_power_at_the_same_time() -> void:
	var a: AimInput = _aim()
	var s: PowerSlider = _slider()
	# Finger 0 aims, finger 1 sets the power; the events interleave like on a real phone.
	a._gui_input(_touch(0, true, Vector2(400, 300)))
	s._gui_input(_touch(1, true, Vector2(40, _y_for(s, 750))))
	assert_eq(a.get_angle_tenths(), 900)
	assert_eq(s.value, 750)
	a._gui_input(_drag(0, Vector2(500, 400)))
	s._gui_input(_drag(1, Vector2(40, _y_for(s, 250))))
	assert_eq(a.get_angle_tenths(), 450)
	assert_eq(s.value, 250)
	# The controls never see each other's finger: they only get events the viewport routes to them,
	# but even if both got both, the finger index keeps them apart.
	a._gui_input(_drag(1, Vector2(300, 500)))
	s._gui_input(_drag(0, Vector2(40, 0)))
	assert_eq(a.get_angle_tenths(), 450)
	assert_eq(s.value, 250)
	a._gui_input(_touch(0, false, Vector2.ZERO))
	s._gui_input(_touch(1, false, Vector2.ZERO))
	assert_false(a.is_dragging())
	assert_false(s.is_dragging())


func test_mouse_still_works_and_touch_can_join() -> void:
	var s: PowerSlider = _slider()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(40, _y_for(s, 1000))
	s._gui_input(press)
	assert_eq(s.value, 1000)
	s._gui_input(_touch(0, true, Vector2(40, _y_for(s, 0))))  # a finger while the mouse drags: ignored
	assert_eq(s.value, 1000)
	var move := InputEventMouseMotion.new()
	move.position = Vector2(40, _y_for(s, 0))
	s._gui_input(move)
	assert_eq(s.value, 0)


func test_emulated_copies_are_ignored() -> void:
	var a: AimInput = _aim()
	var s: PowerSlider = _slider()
	var fake_mouse := InputEventMouseButton.new()  # mouse press the engine made from a touch
	fake_mouse.device = InputEvent.DEVICE_ID_EMULATION
	fake_mouse.button_index = MOUSE_BUTTON_LEFT
	fake_mouse.pressed = true
	fake_mouse.position = Vector2(400, 300)
	a._gui_input(fake_mouse)
	assert_false(a.is_dragging())
	var fake_touch := _touch(0, true, Vector2(40, 0))  # touch the engine made from the mouse
	fake_touch.device = InputEvent.DEVICE_ID_EMULATION
	s._gui_input(fake_touch)
	assert_false(s.is_dragging())
	assert_eq(s.value, 500)


func test_a_real_touch_through_the_viewport_acts_once() -> void:
	# Whole path: Input -> emulated mouse -> Viewport -> controls. A button must press once, the slider must
	# move, and no control may see the same finger as both a touch and a mouse press.
	var vp := SubViewport.new()
	vp.size = Vector2i(400, 400)
	vp.gui_disable_input = false
	add_child_autofree(vp)
	var button := Button.new()
	button.text = "x"
	button.position = Vector2(200, 0)
	button.size = Vector2(100, 100)
	vp.add_child(button)
	var slider := PowerSlider.new()
	slider.position = Vector2(0, 0)
	slider.size = Vector2(80, 400)
	vp.add_child(slider)
	slider.size = Vector2(80, 400)
	await wait_process_frames(2)
	var presses: Array[int] = [0]
	button.pressed.connect(func() -> void: presses[0] += 1)
	# Drive the viewport the way the engine does for a real tap: the touch event, then the mouse copy.
	vp.push_input(_touch(0, true, Vector2(250, 50)))
	var copy := InputEventMouseButton.new()
	copy.device = InputEvent.DEVICE_ID_EMULATION
	copy.button_index = MOUSE_BUTTON_LEFT
	copy.pressed = true
	copy.position = Vector2(250, 50)
	vp.push_input(copy)
	copy = copy.duplicate()
	copy.pressed = false
	vp.push_input(copy)
	vp.push_input(_touch(0, false, Vector2(250, 50)))
	await wait_process_frames(1)
	assert_eq(presses[0], 1, "buttons still react to a tap (through the emulated mouse)")
	vp.push_input(_touch(1, true, Vector2(40, _y_for(slider, 750))))
	await wait_process_frames(1)
	assert_eq(slider.value, 750, "the slider takes a real touch")
	vp.push_input(_touch(1, false, Vector2(40, 100)))
