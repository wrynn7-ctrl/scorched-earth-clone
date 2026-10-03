extends GutTest
## The Love Edition win strip: its text, its buttons, and that it fits every screen without covering the middle.

const CASES: Array = [
	[Vector2(2340, 1080), 500.0, "19.5:9 phone"],
	[Vector2(2340, 1080), 535.0, "narrowest realistic"],
	[Vector2(2560, 1080), 450.0, "21:9 phone"],
	[Vector2(2048, 1536), 264.0, "4:3 tablet"],
	[Vector2(2560, 1600), 280.0, "16:10 tablet"],
	[Vector2(1280, 720), 240.0, "small 16:9"],
]


func after_each() -> void:
	UiScale.reset_overrides()
	ShowSettings.reset()
	PlayerLooks.reset()


func test_the_title_text_and_buttons() -> void:
	var o := LoveWinOverlay.new()
	add_child_autofree(o)
	o.show_win(1, 0.2)
	assert_true(o.is_open())
	assert_eq(o.get_title_text(), "PLAYER 2 WINS")
	assert_eq(o.get_winner(), 1)
	assert_eq(o.get_rematch_button().text, "REMATCH")
	assert_eq(o.get_title_button().text, "TITLE")
	watch_signals(o)
	o.get_rematch_button().pressed.emit()
	o.get_title_button().pressed.emit()
	assert_signal_emitted(o, "rematch_pressed")
	assert_signal_emitted(o, "title_pressed")


func test_the_strip_fits_every_screen_at_both_text_sizes_and_stays_low() -> void:
	for pct: int in [80, 150]:
		ShowSettings.set_text_size(pct)
		for case: Array in CASES:
			var label: String = "%s @%d%%" % [case[2], pct]
			UiScale.dpi_override = float(case[1])
			UiScale.window_px_override = case[0]
			var vis: Vector2 = UiScale.visible_size(case[0])
			var vp := SubViewport.new()
			vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
			vp.disable_3d = true
			add_child_autofree(vp)
			var o := LoveWinOverlay.new()
			vp.add_child(o)
			o.show_win(0, 0.3)
			await wait_process_frames(3)
			var r: Rect2 = o.get_panel().get_global_rect()
			assert_true(Rect2(Vector2.ZERO, vis).grow(1.5).encloses(r), "%s: panel %s in %s" % [label, r, vis])
			assert_lt(r.position.y, vis.y, label)
			assert_lte(r.size.y, vis.y * 0.5, "%s: leaves the picture alone (%.0f of %.0f)" % [label, r.size.y, vis.y])
			for b: Button in [o.get_rematch_button(), o.get_title_button()]:
				assert_gte(UiScale.canvas_to_dp(b.size.y), 47.5, "%s: %s >= 48 dp" % [label, b.name])
				assert_true(Rect2(Vector2.ZERO, vis).grow(1.5).encloses(b.get_global_rect()), "%s: %s on screen" % [label, b.name])
			vp.queue_free()
