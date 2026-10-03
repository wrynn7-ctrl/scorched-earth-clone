extends GutTest
## Left-handed battle HUD: power slider + FIRE on the left, angle panel + move buttons on the right; wind, money and the
## top row stay up top. Nothing leaves the screen or overlaps in either mode, at every resolution and text size.

# [window px, dpi, label]
const CASES: Array = [
	[Vector2(2340, 1080), 500.0, "19.5:9 phone"],
	[Vector2(3120, 1440), 560.0, "S26 Ultra"],
	[Vector2(2560, 1080), 450.0, "21:9 phone"],
	[Vector2(2048, 1536), 264.0, "4:3 tablet"],
	[Vector2(2560, 1600), 280.0, "16:10 tablet"],
	[Vector2(1600, 900), 320.0, "16:9 base"],
	[Vector2(2340, 1080), 535.0, "narrowest realistic"],
	[Vector2(1280, 720), 240.0, "small 16:9"],
]


func after_each() -> void:
	UiScale.reset_overrides()
	ShowSettings.reset()


func _controls(root: Node, out: Array[Control]) -> void:
	for c: Node in root.get_children():
		if c is Control:
			out.append(c as Control)
		_controls(c, out)


func _build(win: Vector2, dpi: float) -> Dictionary:
	UiScale.dpi_override = dpi
	UiScale.window_px_override = win
	var vis: Vector2 = UiScale.visible_size(win)
	var vp := SubViewport.new()
	vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
	vp.disable_3d = true
	add_child_autofree(vp)
	var hud: BattleHud = (load("res://ui/hud/hud.tscn") as PackedScene).instantiate()
	vp.add_child(hud)
	hud.show_cpu_turn(7, SimConstants.CTRL_EXPERT, true)
	hud.set_angle_tenths(1800)
	hud.set_power(1000)
	hud.set_wind(-100)
	hud.set_money(1000000)
	hud.set_weapon("singularity_seed", 99)
	hud.set_items([
		{"id": "glow_shield", "count": 99}, {"id": "ion_shield", "count": 99}, {"id": "fortress_field", "count": 99},
		{"id": "repulsor_field", "count": 99}, {"id": "nanorepair_kit", "count": 99},
	] as Array[Dictionary])
	hud.toggle_items()
	hud.set_fuel(9900)
	await wait_frames(3)
	return {"hud": hud, "vis": vis, "vp": vp}


func _no_overlaps(hud: BattleHud, label: String) -> void:
	var names: Array[String] = ["banner", "angle", "wind", "power", "fire", "money", "moves", "tray", "pause", "speed"]
	var rects: Array[Rect2] = [
		hud.get_turn_banner().get_global_rect(), hud.get_angle_panel().get_global_rect(),
		hud.get_wind_indicator().get_global_rect(), hud.get_power_panel().get_global_rect(),
		hud.get_fire_button().get_global_rect(), hud.get_money_label().get_global_rect(),
		hud.get_move_controls().get_global_rect(), hud.get_tray().get_global_rect(),
		hud.get_pause_button().get_global_rect(), hud.get_speed_button().get_global_rect(),
	]
	for i: int in range(rects.size()):
		for j: int in range(i + 1, rects.size()):
			assert_false(rects[i].intersects(rects[j]), "%s: %s overlaps %s (%s vs %s)" % [label, names[i], names[j], rects[i], rects[j]])


func _check_in_bounds(hud: BattleHud, vis: Vector2, label: String) -> void:
	var rect := Rect2(Vector2.ZERO, vis).grow(1.5)
	var all: Array[Control] = []
	_controls(hud, all)
	for c: Control in all:
		if c.is_visible_in_tree():
			assert_true(rect.encloses(c.get_global_rect()), "%s: %s %s outside %s" % [label, c.get_path(), c.get_global_rect(), vis])


func test_left_handed_mirrors_the_bottom_controls_at_every_resolution_and_text_size() -> void:
	for size_pct: int in [100, 150]:
		ShowSettings.set_text_size(size_pct)
		ShowSettings.left_handed = true
		for case: Array in CASES:
			var label: String = "%s @%d%% left-handed" % [case[2], size_pct]
			var built: Dictionary = await _build(case[0], float(case[1]))
			var hud: BattleHud = built["hud"]
			var vis: Vector2 = built["vis"]
			assert_true(hud.is_left_handed(), label)
			var m: Vector4 = UiScale.edge_margins()
			var tol: float = 2.0
			var power: Rect2 = hud.get_power_panel().get_global_rect()
			var fire: Rect2 = hud.get_fire_button().get_global_rect()
			var angle: Rect2 = hud.get_angle_panel().get_global_rect()
			var moves: Rect2 = hud.get_move_controls().get_global_rect()
			var wind: Rect2 = hud.get_wind_indicator().get_global_rect()
			var money: Rect2 = hud.get_money_label().get_global_rect()
			# Power slider on the left edge, FIRE next to it on its right; both on the bottom/top edges as before.
			assert_true(absf(power.position.x - m.x) <= tol, "%s: power on the left edge" % label)
			assert_true(absf(power.position.y - m.y) <= tol, "%s: power top edge" % label)
			assert_true(absf((vis.y - power.end.y) - m.w) <= tol, "%s: power bottom edge" % label)
			assert_true(absf((vis.y - fire.end.y) - m.w) <= tol, "%s: FIRE bottom edge" % label)
			assert_gte(fire.position.x, power.end.x - tol, "%s: FIRE right of the power panel" % label)
			assert_lt(fire.end.x, vis.x * 0.5, "%s: FIRE in the left half" % label)
			# Angle panel + move buttons on the right edge.
			assert_true(absf((vis.x - angle.end.x) - m.z) <= tol, "%s: angle on the right edge" % label)
			assert_true(absf((vis.y - angle.end.y) - m.w) <= tol, "%s: angle bottom edge" % label)
			assert_gt(angle.position.x, vis.x * 0.5, "%s: angle in the right half" % label)
			assert_true(absf(moves.end.x - angle.end.x) <= tol + angle.size.x, "%s: moves above the angle panel" % label)
			assert_gt(moves.position.x, vis.x * 0.5, "%s: moves in the right half" % label)
			# Wind and money stay at the top, on the left; the pause button is still left of nothing it overlaps.
			assert_true(absf(wind.position.y - m.y) <= tol, "%s: wind top edge" % label)
			assert_lt(wind.position.x, vis.x * 0.5, "%s: wind on the left" % label)
			assert_lt(money.position.x, vis.x * 0.5, "%s: money on the left" % label)
			_check_in_bounds(hud, vis, label)
			_no_overlaps(hud, label)
			assert_gte(UiScale.canvas_to_dp(minf(hud.get_pause_button().size.x, hud.get_pause_button().size.y)), 47.5, "%s: pause >= 48 dp" % label)
			(built["vp"] as SubViewport).queue_free()
			await wait_frames(1)


func test_right_handed_default_is_unchanged() -> void:
	for case: Array in CASES:
		var label: String = "%s right-handed" % case[2]
		var built: Dictionary = await _build(case[0], float(case[1]))
		var hud: BattleHud = built["hud"]
		var vis: Vector2 = built["vis"]
		assert_false(hud.is_left_handed(), label)
		var m: Vector4 = UiScale.edge_margins()
		assert_true(absf((vis.x - hud.get_power_panel().get_global_rect().end.x) - m.z) <= 2.0, "%s: power on the right edge" % label)
		assert_true(absf(hud.get_angle_panel().get_global_rect().position.x - m.x) <= 2.0, "%s: angle on the left edge" % label)
		assert_true(absf(hud.get_wind_indicator().get_global_rect().position.x - m.x) <= 2.0, "%s: wind on the left edge" % label)
		_check_in_bounds(hud, vis, label)
		_no_overlaps(hud, label)
		(built["vp"] as SubViewport).queue_free()
		await wait_frames(1)


func test_switching_the_setting_moves_the_controls_back_and_forth() -> void:
	var built: Dictionary = await _build(Vector2(2340, 1080), 500.0)
	var hud: BattleHud = built["hud"]
	var right_x: float = hud.get_power_panel().get_global_rect().position.x
	ShowSettings.left_handed = true
	hud.apply_scale()
	await wait_frames(3)
	assert_lt(hud.get_power_panel().get_global_rect().position.x, right_x * 0.2, "power moved to the left")
	ShowSettings.left_handed = false
	hud.apply_scale()
	await wait_frames(3)
	assert_almost_eq(hud.get_power_panel().get_global_rect().position.x, right_x, 1.5, "and back")
	assert_false(hud.is_left_handed())


func test_the_hud_still_works_when_left_handed() -> void:
	ShowSettings.left_handed = true
	var built: Dictionary = await _build(Vector2(2340, 1080), 500.0)
	var hud: BattleHud = built["hud"]
	watch_signals(hud)
	hud.get_fire_button().pressed.emit()
	assert_signal_emitted(hud, "fire_pressed")
	hud.get_power_panel().get_slider().set_value(250)
	assert_signal_emitted_with_parameters(hud, "power_changed", [250])
