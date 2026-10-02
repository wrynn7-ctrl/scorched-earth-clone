extends GutTest
## Touch-friendly scrolling: wide scrollbars at every density, swipe-to-scroll over cards,
## taps that still select, and no content hidden under the bar.

var _state: MatchState = null


func after_each() -> void:
	UiScale.reset_overrides()
	ShowSettings.reset()
	PlayerLooks.reset()


func _new_state() -> MatchState:
	var m := MatchSettings.new()
	m.num_tanks = 2
	m.rounds = 3
	m.seed = 99
	m.start_money = 10000
	m.full_unlocked = true
	_state = Simulation.new_match(m)
	return _state


func _submit(action: Dictionary) -> String:
	var a: Dictionary = Simulation.normalize_action(action)
	var err: String = Simulation.validate_action(_state, a)
	if err == "":
		Simulation.apply_action(_state, a)
	return err


func _viewport(win: Vector2, dpi: float) -> SubViewport:
	UiScale.dpi_override = dpi
	UiScale.window_px_override = win
	var vis: Vector2 = UiScale.visible_size(win)
	var vp := SubViewport.new()
	vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
	vp.disable_3d = true
	add_child_autofree(vp)
	return vp


## An open shop (player 1, `tab`) in a viewport of the given size/density.
func _shop(win: Vector2, dpi: float, tab: int = ShopScreen.TAB_WEAPONS) -> Array:
	_new_state()
	var vp: SubViewport = _viewport(win, dpi)
	var f := ShopFlow.new()
	vp.add_child(f)
	f.open(_state, _submit)
	await wait_process_frames(2)
	f.get_handover().get_tap_button().pressed.emit()
	await wait_process_frames(2)
	var screen: ShopScreen = f.get_screen()
	screen.set_tab(tab)
	await wait_process_frames(3)
	return [vp, screen]


func _mouse(vp: SubViewport, pos: Vector2, pressed: bool, mask: int = 0) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	vp.push_input(e)


func _move(vp: SubViewport, pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	vp.push_input(e)


func test_scrollbars_are_wide_and_the_grabber_long_at_every_density() -> void:
	for dpi: float in [160.0, 320.0, 560.0]:
		var made: Array = await _shop(Vector2(2340, 1080), dpi)
		var screen: ShopScreen = made[1]
		var scroll: TouchScroll = screen.get_scroll()
		var bar: VScrollBar = scroll.get_v_scroll_bar()
		assert_true(bar.visible, "dpi %d: the list overflows, so the bar shows" % int(dpi))
		var w_dp: float = UiScale.canvas_to_dp(bar.size.x)
		assert_gte(w_dp, 20.0, "dpi %d: bar is %.1f dp wide" % [int(dpi), w_dp])
		var track: StyleBoxFlat = bar.get_theme_stylebox("scroll") as StyleBoxFlat
		var visible_dp: float = UiScale.canvas_to_dp(bar.size.x + track.expand_margin_left)
		assert_gte(visible_dp, 20.0, "dpi %d: the drawn track is %.1f dp wide" % [int(dpi), visible_dp])
		var grab: StyleBoxFlat = bar.get_theme_stylebox("grabber") as StyleBoxFlat
		var grab_dp: float = UiScale.canvas_to_dp(grab.get_minimum_size().y)
		assert_gte(grab_dp, 48.0, "dpi %d: grabber at least %.1f dp long" % [int(dpi), grab_dp])
		# The bar uses the full width, edge to edge.
		assert_almost_eq(bar.get_global_rect().end.x, scroll.get_global_rect().end.x, 1.5)
		# And an overflowing list does not draw a grabber shorter than the minimum.
		var page_fraction: float = bar.page / bar.max_value
		assert_lt(page_fraction, 1.0)
		made[0].queue_free()
		await wait_process_frames(1)


func test_bar_sizes_follow_the_density_after_a_resize() -> void:
	var made: Array = await _shop(Vector2(2340, 1080), 160.0)
	var screen: ShopScreen = made[1]
	var bar: VScrollBar = screen.get_scroll().get_v_scroll_bar()
	var small: float = bar.custom_minimum_size.x
	UiScale.dpi_override = 560.0
	UiScale.notify_changed(get_tree())
	await wait_process_frames(2)
	assert_gt(bar.custom_minimum_size.x, small * 2.0, "a denser screen gets a thicker bar in canvas units")
	assert_gte(UiScale.canvas_to_dp(bar.custom_minimum_size.x), 20.0)


func test_horizontal_bars_get_the_same_treatment() -> void:
	UiScale.dpi_override = 320.0
	UiScale.window_px_override = Vector2(2340, 1080)
	var s := TouchScroll.new()
	add_child_autofree(s)
	var hb: HScrollBar = s.get_h_scroll_bar()
	assert_gte(UiScale.canvas_to_dp(hb.custom_minimum_size.y), 20.0)
	var grab: StyleBoxFlat = hb.get_theme_stylebox("grabber") as StyleBoxFlat
	assert_gte(UiScale.canvas_to_dp(grab.get_minimum_size().x), 48.0)


func test_a_swipe_that_starts_on_a_card_scrolls_and_buys_nothing() -> void:
	var made: Array = await _shop(Vector2(2340, 1080), 560.0)
	var vp: SubViewport = made[0]
	var screen: ShopScreen = made[1]
	var scroll: TouchScroll = screen.get_scroll()
	watch_signals(screen)
	var money: int = _state.tanks[0].money
	var card: ShopCard = screen.get_card(screen.card_ids()[0])
	var from: Vector2 = card.get_global_rect().get_center()
	assert_eq(scroll.scroll_vertical, 0)
	_mouse(vp, from, true)
	var drag: float = UiScale.dp(120.0)
	for i: int in range(1, 7):
		_move(vp, from + Vector2(0.0, -drag * float(i) / 6.0))
		await wait_process_frames(1)  # real fingers report once per frame: the card is moved under them
	assert_true(scroll.is_dragging())
	_mouse(vp, from + Vector2(0.0, -drag), false)
	await wait_process_frames(1)
	assert_gt(scroll.scroll_vertical, 0, "finger up = content up")
	assert_gte(float(scroll.scroll_vertical), drag * 0.9, "the content followed the finger")
	assert_eq(screen.get_selected(), "", "a swipe is not a tap: nothing selected")
	assert_false(screen.is_popup_open(), "and no detail popup")
	assert_eq(_state.tanks[0].money, money, "nothing bought")
	assert_signal_not_emitted(screen, "message")


func test_a_tap_on_a_card_still_selects_and_opens_the_detail() -> void:
	var made: Array = await _shop(Vector2(2340, 1080), 560.0)
	var vp: SubViewport = made[0]
	var screen: ShopScreen = made[1]
	var id: String = screen.card_ids()[2]
	var card: ShopCard = screen.get_card(id)
	var at: Vector2 = card.get_global_rect().get_center()
	_mouse(vp, at, true)
	_move(vp, at + Vector2(UiScale.dp(4.0), UiScale.dp(3.0)))  # a shaky finger, under the 10 dp slop
	_mouse(vp, at, false)
	await wait_process_frames(2)
	assert_eq(screen.get_scroll().scroll_vertical, 0, "no scrolling")
	assert_eq(screen.get_selected(), id)
	assert_true(screen.is_popup_open(), "phones open the detail popup")


func test_a_tap_selects_in_the_tablet_list_too_and_a_swipe_scrolls_it() -> void:
	var made: Array = await _shop(Vector2(2048, 1536), 264.0, ShopScreen.TAB_ITEMS)
	var vp: SubViewport = made[0]
	var screen: ShopScreen = made[1]
	assert_true(screen.is_tablet_layout())
	var scroll: TouchScroll = screen.get_scroll()
	var ids: Array[String] = screen.card_ids()
	var card: ShopCard = screen.get_card(ids[1])
	var at: Vector2 = card.get_global_rect().get_center()
	_mouse(vp, at, true)
	_mouse(vp, at, false)
	await wait_process_frames(2)
	assert_eq(screen.get_selected(), ids[1])
	var before: String = screen.get_selected()
	if scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page > 1.0:
		var start: Vector2 = screen.get_card(ids[3]).get_global_rect().get_center()
		_mouse(vp, start, true)
		_move(vp, start + Vector2(0.0, -UiScale.dp(60.0)))
		_move(vp, start + Vector2(0.0, -UiScale.dp(90.0)))
		_mouse(vp, start + Vector2(0.0, -UiScale.dp(90.0)), false)
		await wait_process_frames(1)
		assert_gt(scroll.scroll_vertical, 0)
		assert_eq(screen.get_selected(), before, "the swipe selected nothing new")


func test_a_flick_coasts_then_stops_at_the_end() -> void:
	var made: Array = await _shop(Vector2(2340, 1080), 560.0)
	var vp: SubViewport = made[0]
	var scroll: TouchScroll = made[1].get_scroll()
	var from: Vector2 = scroll.get_global_rect().get_center()
	_mouse(vp, from, true)
	_move(vp, from + Vector2(0.0, -UiScale.dp(30.0)))
	_move(vp, from + Vector2(0.0, -UiScale.dp(60.0)))
	_mouse(vp, from + Vector2(0.0, -UiScale.dp(60.0)), false)
	assert_true(scroll.is_coasting(), "a quick lift keeps it moving")
	var at_lift: int = scroll.scroll_vertical
	await wait_seconds(0.5)
	assert_gt(scroll.scroll_vertical, at_lift, "it kept scrolling after the finger left")
	await wait_seconds(4.0)
	assert_false(scroll.is_coasting(), "and friction brought it to a stop")


func test_a_press_on_the_bar_is_left_to_the_bar() -> void:
	var made: Array = await _shop(Vector2(2340, 1080), 560.0)
	var vp: SubViewport = made[0]
	var scroll: TouchScroll = made[1].get_scroll()
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	var at: Vector2 = bar.get_global_rect().get_center()
	_mouse(vp, at, true)
	_move(vp, at + Vector2(0.0, UiScale.dp(40.0)))
	assert_false(scroll.is_dragging(), "no swipe is started from the scrollbar")
	_mouse(vp, at, false)


func test_no_card_hides_under_the_bar() -> void:
	for case: Array in [[Vector2(2340, 1080), 500.0], [Vector2(2560, 1080), 450.0], [Vector2(1280, 720), 240.0],
			[Vector2(2048, 1536), 264.0], [Vector2(3120, 1440), 560.0]]:
		for tab: int in [ShopScreen.TAB_WEAPONS, ShopScreen.TAB_ITEMS]:
			var made: Array = await _shop(case[0], case[1], tab)
			var screen: ShopScreen = made[1]
			var scroll: TouchScroll = screen.get_scroll()
			var bar: VScrollBar = scroll.get_v_scroll_bar()
			var label: String = "%s dpi %d tab %d" % [str(case[0]), int(case[1]), tab]
			var limit: float = scroll.get_global_rect().end.x
			if bar.visible:
				limit = bar.get_global_rect().position.x
			for id: String in screen.card_ids():
				var r: Rect2 = screen.get_card(id).get_global_rect()
				assert_lte(r.end.x, limit + 1.0, "%s: %s ends at %.1f under the bar at %.1f" % [label, id, r.end.x, limit])
				assert_gte(r.position.x, scroll.get_global_rect().position.x - 1.0, label)
			made[0].queue_free()
			await wait_process_frames(1)


func test_every_scroll_list_in_the_game_is_a_touch_scroll() -> void:
	UiScale.dpi_override = 320.0
	UiScale.window_px_override = Vector2(2340, 1080)
	var setup: Control = load("res://ui/setup/setup_screen.tscn").instantiate()
	add_child_autofree(setup)
	await wait_process_frames(2)
	assert_true(setup.get_scroll() is TouchScroll)
	assert_gte(UiScale.canvas_to_dp(setup.get_scroll().get_v_scroll_bar().custom_minimum_size.x), 20.0)
