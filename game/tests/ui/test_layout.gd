extends GutTest
## HUD layout at several screen shapes. Each case simulates the engine's stretch mode
## canvas_items + expand: the visible canvas area is window / min(win.x/1600, win.y/900).

# [window px, dpi, label]
const CASES: Array = [
	[Vector2(2340, 1080), 500.0, "S26 Ultra-like 19.5:9"],
	[Vector2(2560, 1080), 450.0, "21:9 phone"],
	[Vector2(2048, 1536), 264.0, "4:3 tablet"],
	[Vector2(2560, 1600), 280.0, "16:10 tablet"],
	[Vector2(1600, 900), 320.0, "16:9 base, 800 dp wide"],
	[Vector2(2340, 1080), 535.0, "narrowest realistic: ~700 dp wide"],
	[Vector2(1280, 720), 240.0, "small 16:9"],
]


func after_each() -> void:
	UiScale.reset_overrides()


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
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child_autofree(vp)
	var hud: BattleHud = (load("res://ui/hud/hud.tscn") as PackedScene).instantiate()
	vp.add_child(hud)
	hud.show_turn(7)  # longest-looking banner: emblem + "PLAYER 8'S TURN"
	hud.set_angle_tenths(1800)
	hud.set_power(1000)
	hud.set_wind(-100)
	await wait_frames(3)
	return {"hud": hud, "vis": vis}


func test_no_control_outside_visible_rect() -> void:
	for case: Array in CASES:
		var win: Vector2 = case[0]
		var label: String = case[2]
		var built: Dictionary = await _build(win, float(case[1]))
		var hud: BattleHud = built["hud"]
		var vis: Vector2 = built["vis"]
		var rect := Rect2(Vector2.ZERO, vis).grow(1.5)
		var all: Array[Control] = []
		_controls(hud, all)
		assert_gt(all.size(), 10, label)
		for c: Control in all:
			if not c.is_visible_in_tree():
				continue
			var r: Rect2 = c.get_global_rect()
			assert_true(rect.encloses(r), "%s: %s %s outside %s" % [label, c.get_path(), r, Rect2(Vector2.ZERO, vis)])
		# Left and right clusters must not overlap the banner or each other.
		var banner: Rect2 = hud.get_turn_banner().get_global_rect()
		var angle: Rect2 = hud.get_angle_panel().get_global_rect()
		var wind: Rect2 = hud.get_wind_indicator().get_global_rect()
		var power: Rect2 = hud.get_power_panel().get_global_rect()
		var fire: Rect2 = hud.get_fire_button().get_global_rect()
		assert_false(banner.intersects(wind), "%s: banner/wind overlap" % label)
		assert_false(banner.intersects(power), "%s: banner/power overlap" % label)
		assert_false(angle.intersects(fire), "%s: angle/fire overlap" % label)
		assert_false(fire.intersects(power), "%s: fire/power overlap" % label)
		hud.get_parent().queue_free()


func test_touch_targets_at_least_48dp() -> void:
	for case: Array in CASES:
		var win: Vector2 = case[0]
		var label: String = case[2]
		var built: Dictionary = await _build(win, float(case[1]))
		var hud: BattleHud = built["hud"]
		var all: Array[Control] = []
		_controls(hud, all)
		for c: Control in all:
			if c is BaseButton or c is PowerSlider:
				var shortest: float = minf(c.size.x, c.size.y)
				var dp: float = UiScale.canvas_to_dp(shortest)
				assert_gte(dp, 47.5, "%s: %s is only %.1f dp" % [label, c.get_path(), dp])
		var fire: Control = hud.get_fire_button()
		assert_gte(UiScale.canvas_to_dp(minf(fire.size.x, fire.size.y)), 48.0, "%s FIRE" % label)
		assert_gte(UiScale.canvas_to_dp(fire.size.x), 96.0, "%s FIRE is big" % label)
		hud.get_parent().queue_free()
