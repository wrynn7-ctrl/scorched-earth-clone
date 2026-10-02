extends GutTest
## Pause / round-end / match-end overlays must fit the screen (a phone in landscape is only
## ~330 dp tall) and keep every button at least 48 dp.

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


func test_overlays_fit_all_screens() -> void:
	for case: Array in CASES:
		var label: String = case[2]
		var vp: SubViewport = _viewport(case[0], float(case[1]))
		var pause := PauseOverlay.new()
		var rnd := RoundEndOverlay.new()
		var fin := MatchEndOverlay.new()
		vp.add_child(pause)
		vp.add_child(rnd)
		vp.add_child(fin)
		pause.open_for(2, 5)
		rnd.show_result(1, PackedInt32Array([2, 3]), 5, 5)
		fin.show_result(PackedInt32Array([3, 2]))
		await wait_process_frames(3)
		_check(pause, vp, label)
		_check(rnd, vp, label)
		_check(fin, vp, label)
		vp.queue_free()
		await wait_process_frames(1)


func test_round_overlay_text_and_tally() -> void:
	var vp: SubViewport = _viewport(Vector2(2340, 1080), 500.0)
	var rnd := RoundEndOverlay.new()
	vp.add_child(rnd)
	rnd.show_result(1, PackedInt32Array([2, 1]), 3, 3)
	assert_eq(rnd.get_title_text(), "PLAYER 2 WINS THE ROUND")
	assert_eq(rnd.get_tally_text(), "PLAYER 1 2, PLAYER 2 1")
	rnd.show_result(-1, PackedInt32Array([1, 1]), 2, 3)
	assert_eq(rnd.get_title_text(), "DRAW")
	var fin := MatchEndOverlay.new()
	vp.add_child(fin)
	fin.show_result(PackedInt32Array([1, 2]))
	assert_eq(fin.get_title_text(), "PLAYER 2 WINS THE MATCH")
	fin.show_result(PackedInt32Array([2, 2]))
	assert_eq(fin.get_title_text(), "DRAW")
