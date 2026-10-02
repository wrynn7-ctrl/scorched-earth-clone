extends GutTest
## Pause / settings / round summary / standings overlays must fit the screen (a phone in
## landscape is only ~330 dp tall) and keep every button at least 48 dp.

# [window px, dpi, label]
const CASES: Array = [
	[Vector2(2340, 1080), 500.0, "19.5:9 phone"],
	[Vector2(2340, 1080), 535.0, "narrowest realistic"],
	[Vector2(2560, 1080), 450.0, "21:9 phone"],
	[Vector2(2048, 1536), 264.0, "4:3 tablet"],
	[Vector2(1280, 720), 240.0, "small 16:9"],
]


func after_each() -> void:
	UiScale.reset_overrides()
	ShowSettings.reset()


func _viewport(win: Vector2, dpi: float) -> SubViewport:
	UiScale.dpi_override = dpi
	UiScale.window_px_override = win
	var vis: Vector2 = UiScale.visible_size(win)
	var vp := SubViewport.new()
	vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child_autofree(vp)
	return vp


func _buttons(root: Node, out: Array[BaseButton]) -> void:
	for c: Node in root.get_children():
		if c is BaseButton:
			out.append(c as BaseButton)
		_buttons(c, out)


func _check(overlay: OverlayPanel, vp: SubViewport, label: String) -> void:
	var vis := Rect2(Vector2.ZERO, Vector2(vp.size))
	var panel: Control = overlay.get_node("Center/Panel")
	var r: Rect2 = panel.get_global_rect()
	assert_true(vis.encloses(r), "%s %s: panel %s outside %s" % [label, overlay.name, r, vis])
	var btns: Array[BaseButton] = []
	_buttons(overlay, btns)
	assert_gt(btns.size(), 0)
	for b: BaseButton in btns:
		var dp: float = UiScale.canvas_to_dp(minf(b.size.y, b.size.x))
		assert_gte(dp, 47.5, "%s %s: %s is %.1f dp" % [label, overlay.name, b.name, dp])
		assert_true(vis.encloses(b.get_global_rect()), "%s %s: button %s off screen" % [label, overlay.name, b.name])


func _rows(n: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for i: int in range(n):
		rows.append({"id": i, "earned": 3500 + i * 1000, "kills": i, "wins": 2, "damage": 120 * i, "money": 20000})
	return rows


func _order(n: int) -> Array[int]:
	var o: Array[int] = []
	for i: int in range(n):
		o.append(i)
	return o


func test_overlays_fit_all_screens() -> void:
	SettingsStore.path = "user://test_settings_overlay.cfg"
	for size_pct: int in [100, 150]:
		ShowSettings.set_text_size(size_pct)
		for case: Array in CASES:
			var label: String = "%s @%d%%" % [case[2], size_pct]
			var vp: SubViewport = _viewport(case[0], float(case[1]))
			var pause := PauseOverlay.new()
			var rnd := RoundEndOverlay.new()
			var fin := MatchEndOverlay.new()
			var settings := SettingsOverlay.new()
			var confirm := ConfirmOverlay.new()
			for o: OverlayPanel in [pause, rnd, fin, settings, confirm]:
				vp.add_child(o)
			pause.open_for(2, 5)
			rnd.show_summary(1, _rows(8), 5, 5)  # eight players: the table must scroll, not overflow
			fin.show_standings(_order(8), _rows(8))
			settings.open()
			confirm.ask("Starting a new match deletes your saved game.")
			await wait_process_frames(3)
			for o: OverlayPanel in [pause, rnd, fin, settings, confirm]:
				_check(o, vp, label)
			vp.queue_free()
			await wait_process_frames(1)
	SettingsStore.delete()
	SettingsStore.path = SettingsStore.DEFAULT_PATH


func test_round_summary_shows_money_kills_and_wins() -> void:
	var vp: SubViewport = _viewport(Vector2(2340, 1080), 500.0)
	var rnd := RoundEndOverlay.new()
	vp.add_child(rnd)
	var rows: Array[Dictionary] = [
		{"id": 0, "earned": 4200, "kills": 1, "wins": 2},
		{"id": 1, "earned": -300, "kills": 0, "wins": 1},
	]
	rnd.show_summary(0, rows, 3, 3)
	assert_eq(rnd.get_title_text(), "PLAYER 1 WINS THE ROUND")
	assert_eq(rnd.get_table().get_text(), "PLAYER 1 +$4,200 1 2; PLAYER 2 -$300 0 1")
	rnd.show_summary(-1, rows, 2, 3)
	assert_eq(rnd.get_title_text(), "DRAW")
	assert_eq(rnd.get_next_button().text, "NEXT")


func test_pause_overlay_buttons() -> void:
	var vp: SubViewport = _viewport(Vector2(2340, 1080), 500.0)
	var pause := PauseOverlay.new()
	vp.add_child(pause)
	pause.open_for(1, 3)
	for n: String in ["Resume", "Settings", "Restart", "Quit"]:
		assert_not_null(pause.find_child(n, true, false), n)
	watch_signals(pause)
	(pause.find_child("Settings", true, false) as Button).pressed.emit()
	assert_signal_emitted(pause, "settings_pressed")
	(pause.find_child("Restart", true, false) as Button).pressed.emit()
	assert_signal_not_emitted(pause, "restart_pressed")
	(pause.find_child("Restart", true, false) as Button).pressed.emit()
	assert_signal_emitted(pause, "restart_pressed")
