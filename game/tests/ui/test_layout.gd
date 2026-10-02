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
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child_autofree(vp)
	var hud: BattleHud = (load("res://ui/hud/hud.tscn") as PackedScene).instantiate()
	vp.add_child(hud)
	hud.show_turn(7)  # longest-looking banner: emblem + "PLAYER 8'S TURN"
	hud.set_angle_tenths(1800)
	hud.set_power(1000)
	hud.set_wind(-100)
	# The crowded case: money, the longest weapon name, every usable item, fuel, items row open.
	hud.set_money(1000000)
	hud.set_weapon("singularity_seed", 99)
	hud.set_items([
		{"id": "glow_shield", "count": 99}, {"id": "ion_shield", "count": 99}, {"id": "fortress_field", "count": 99},
		{"id": "repulsor_field", "count": 99}, {"id": "nanorepair_kit", "count": 99},
	] as Array[Dictionary])
	hud.toggle_items()
	hud.set_fuel(9900)
	await wait_frames(3)
	return {"hud": hud, "vis": vis}


func test_no_control_outside_visible_rect() -> void:
	await _check_all_cases("")


func test_no_overlap_at_the_largest_text_size() -> void:
	ShowSettings.set_text_size(150)
	await _check_all_cases(" @150%")


func _check_all_cases(suffix: String) -> void:
	for case: Array in CASES:
		var win: Vector2 = case[0]
		var label: String = str(case[2]) + suffix
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
		var pause: Rect2 = hud.get_pause_button().get_global_rect()
		var speed: Rect2 = hud.get_speed_button().get_global_rect()
		assert_false(banner.intersects(pause), "%s: banner/pause overlap" % label)
		assert_false(banner.intersects(speed), "%s: banner/speed overlap" % label)
		assert_false(pause.intersects(power), "%s: pause/power overlap" % label)
		assert_false(speed.intersects(wind), "%s: speed/wind overlap" % label)
		assert_gte(UiScale.canvas_to_dp(minf(pause.size.x, pause.size.y)), 47.5, "%s: pause >= 48 dp" % label)
		assert_false(banner.intersects(wind), "%s: banner/wind overlap" % label)
		assert_false(banner.intersects(power), "%s: banner/power overlap" % label)
		assert_false(angle.intersects(fire), "%s: angle/fire overlap" % label)
		assert_false(fire.intersects(power), "%s: fire/power overlap" % label)
		_check_tray(hud, label)
		hud.get_parent().queue_free()


## The M3 controls (money, move, weapon button, items row) must not collide with anything.
func _check_tray(hud: BattleHud, label: String) -> void:
	var tray: Rect2 = hud.get_tray().get_global_rect()
	var weapon: Rect2 = hud.get_weapon_button().get_global_rect()
	var toggle: Rect2 = hud.get_items_toggle().get_global_rect()
	var items: Rect2 = hud.get_item_tray().get_global_rect()
	var moves: Rect2 = hud.get_move_controls().get_global_rect()
	var money: Rect2 = hud.get_money_label().get_global_rect()
	var others: Dictionary = {
		"banner": hud.get_turn_banner().get_global_rect(), "angle": hud.get_angle_panel().get_global_rect(),
		"wind": hud.get_wind_indicator().get_global_rect(), "power": hud.get_power_panel().get_global_rect(),
		"fire": hud.get_fire_button().get_global_rect(),
	}
	assert_true(hud.get_item_tray().visible, "%s: items row is open" % label)
	assert_false(weapon.intersects(toggle), "%s: weapon/items toggle overlap" % label)
	for k: String in others.keys():
		var r: Rect2 = others[k]
		assert_false(tray.intersects(r), "%s: tray/%s overlap (%s vs %s)" % [label, k, tray, r])
		assert_false(moves.intersects(r), "%s: moves/%s overlap" % [label, k])
		assert_false(money.intersects(r), "%s: money/%s overlap" % [label, k])
	assert_false(moves.intersects(money), "%s: moves/money overlap" % label)
	assert_false(items.intersects(weapon), "%s: items row/weapon overlap" % label)
	assert_gte(UiScale.canvas_to_dp(hud.get_weapon_button().size.y), 47.5, "%s: weapon button >= 48 dp" % label)


func test_weapon_picker_fits_every_screen_at_large_text() -> void:
	ShowSettings.set_text_size(150)
	for case: Array in CASES:
		var win: Vector2 = case[0]
		var label: String = case[2]
		var built: Dictionary = await _build(win, float(case[1]))
		var hud: BattleHud = built["hud"]
		var entries: Array[Dictionary] = []
		for id: String in Catalog.IDS:
			if WeaponDefs.has(id):
				entries.append({"id": id, "count": 99})
		hud.open_weapon_picker(entries, "pulse_missile")
		await wait_frames(3)
		var vis := Rect2(Vector2.ZERO, built["vis"] as Vector2).grow(1.5)
		assert_true(vis.encloses(hud.get_weapon_popup().get_panel().get_global_rect()), "%s: picker panel on screen" % label)
		for chip: HudChip in hud.get_weapon_popup().get_chips():
			assert_gte(UiScale.canvas_to_dp(chip.custom_minimum_size.y), 47.5, "%s: %s row >= 48 dp" % [label, chip.name])
		hud.get_parent().queue_free()
	ShowSettings.reset()


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
