extends GutTest
## Owner bug (Galaxy S26 Ultra): the HUD sat in a smaller rect than the visible screen. Every screen
## must hug the real edges (edge margin + a sane safe-area inset only), also after the window
## changes size (Android reports the final landscape size late) and when the safe area is bogus.

const BATTLE: String = "res://show/battle/battle_scene.tscn"
const SETUP: String = "res://ui/setup/setup_screen.tscn"
const TITLE: String = "res://ui/title/title_screen.tscn"
const TOL: float = 2.0

# [final window px, dpi, label]
const CASES: Array = [
	[Vector2(1600, 900), 320.0, "16:9"],
	[Vector2(3120, 1440), 500.0, "19.5:9 (S26 Ultra)"],
	[Vector2(3360, 1440), 450.0, "21:9"],
	[Vector2(2048, 1536), 264.0, "4:3"],
	[Vector2(2560, 1600), 280.0, "16:10"],
]
# Sizes the window passes through before the final landscape one (portrait first, as on Android).
const EARLY: Array = [Vector2(1440, 3120), Vector2(1600, 900)]

var _state: MatchState = null


func after_each() -> void:
	UiScale.reset_overrides()
	ShowSettings.reset()
	BattleConfig.reset()
	PlayerLooks.reset()


## A SubViewport that stands in for the game window.
func _window(win: Vector2, dpi: float) -> SubViewport:
	UiScale.dpi_override = dpi
	UiScale.window_px_override = win
	var vis: Vector2 = UiScale.visible_size(win)
	var vp := SubViewport.new()
	vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
	vp.disable_3d = true
	add_child_autofree(vp)
	return vp


## What the engine does on a window resize: new stretch size, then the viewport signal.
func _resize(vp: SubViewport, win: Vector2) -> void:
	UiScale.window_px_override = win
	var vis: Vector2 = UiScale.visible_size(win)
	vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
	await wait_process_frames(3)


func _vis(vp: SubViewport) -> Vector2:
	return Vector2(vp.size)


## Literal version of the owner's complaint: with no real inset on a side, the gap to the
## screen edge is just the 12 dp margin (never a band of empty screen).
func _check_hud_gaps(hud: BattleHud, vis: Vector2, label: String, left: bool = true) -> void:
	var edge: float = UiScale.dp(UiScale.EDGE_MARGIN_DP) + TOL
	assert_lte(vis.x - hud.get_power_panel().get_global_rect().end.x, edge, "%s: right gap" % label)
	assert_lte(vis.y - hud.get_fire_button().get_global_rect().end.y, edge, "%s: bottom gap" % label)
	if left:
		assert_lte(hud.get_angle_panel().get_global_rect().position.x, edge, "%s: left gap" % label)


func _check_hud_edges(hud: BattleHud, vis: Vector2, label: String) -> void:
	var m: Vector4 = UiScale.edge_margins()
	var power: Rect2 = hud.get_power_panel().get_global_rect()
	var angle: Rect2 = hud.get_angle_panel().get_global_rect()
	var wind: Rect2 = hud.get_wind_indicator().get_global_rect()
	var fire: Rect2 = hud.get_fire_button().get_global_rect()
	var pause: Rect2 = hud.get_pause_button().get_global_rect()
	assert_true(absf((vis.x - power.end.x) - m.z) <= TOL, "%s: power right edge %s vs visible %s (margin %.1f)" % [label, power.end.x, vis.x, m.z])
	assert_true(absf(angle.position.x - m.x) <= TOL, "%s: angle left edge %.1f vs margin %.1f" % [label, angle.position.x, m.x])
	assert_true(absf(wind.position.x - m.x) <= TOL, "%s: wind left edge %.1f vs margin %.1f" % [label, wind.position.x, m.x])
	assert_true(absf((vis.y - angle.end.y) - m.w) <= TOL, "%s: angle bottom edge" % label)
	assert_true(absf((vis.y - fire.end.y) - m.w) <= TOL, "%s: FIRE bottom edge %.1f vs visible %.1f" % [label, fire.end.y, vis.y])
	assert_true(absf((vis.y - power.end.y) - m.w) <= TOL, "%s: power bottom edge" % label)
	assert_true(absf(power.position.y - m.y) <= TOL, "%s: power top edge" % label)
	assert_true(absf(wind.position.y - m.y) <= TOL, "%s: wind top edge" % label)
	assert_lt(pause.end.x, power.position.x, "%s: pause left of the power column" % label)
	# The root of the HUD fills the whole visible rect.
	assert_eq(hud.get_global_rect(), Rect2(Vector2.ZERO, vis), "%s: HUD root fills the visible rect" % label)


func _battle_in(vp: SubViewport) -> BattleController:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(3, 4242, true, 2)
	vp.add_child(c)
	for t: TankState in c.get_state().tanks:
		c.get_session().submit({"kind": "buy", "tank": t.id, "item": "pulse_missile", "qty": 1})
	c.quick_start()
	return c


func test_battle_hud_hugs_the_edges_after_the_window_changes_size() -> void:
	for case: Array in CASES:
		var win: Vector2 = case[0]
		var label: String = str(case[2])
		var vp: SubViewport = _window(EARLY[0] as Vector2, float(case[1]))
		var c: BattleController = _battle_in(vp)
		await wait_process_frames(2)
		for step: Vector2 in EARLY:
			await _resize(vp, step)
		await _resize(vp, win)
		_check_hud_edges(c.get_hud(), _vis(vp), label)
		_check_hud_gaps(c.get_hud(), _vis(vp), label)
		vp.queue_free()
		await wait_process_frames(1)


func test_battle_hud_with_a_real_cutout_on_the_left_only() -> void:
	UiScale.safe_px_override = Vector4(100.0, 0.0, 0.0, 0.0)
	for case: Array in CASES:
		var label: String = "%s + 100 px left cutout" % case[2]
		var vp: SubViewport = _window(Vector2(1600, 900), float(case[1]))
		var c: BattleController = _battle_in(vp)
		await _resize(vp, case[0] as Vector2)
		var m: Vector4 = UiScale.edge_margins()
		var ins: Vector4 = UiScale.safe_insets()
		assert_gt(ins.x, 10.0, label + ": the inset is applied on the left")
		assert_eq(ins.z, 0.0, label + ": none on the right")
		assert_gt(m.x, m.z + 10.0, label + ": left margin is the larger one")
		_check_hud_edges(c.get_hud(), _vis(vp), label)
		vp.queue_free()
		await wait_process_frames(1)


func test_insets_are_physical_pixels_converted_to_canvas_units() -> void:
	UiScale.window_px_override = Vector2(3120, 1440)  # 1.6 px per canvas unit
	UiScale.dpi_override = 500.0
	UiScale.safe_px_override = Vector4(120.0, 0.0, 0.0, 48.0)
	var ins: Vector4 = UiScale.safe_insets()
	assert_almost_eq(ins.x, 75.0, 0.01)
	assert_almost_eq(ins.w, 30.0, 0.01)
	assert_eq(ins.y, 0.0)


func test_a_bogus_safe_area_never_shrinks_the_layout() -> void:
	# What the S26 reported (right ~570 px, bottom ~420 px): far more than any cutout or gesture bar.
	UiScale.window_px_override = Vector2(3120, 1440)
	UiScale.dpi_override = 500.0
	UiScale.safe_px_override = Vector4(140.0, 0.0, 578.0, 421.0)
	var ins: Vector4 = UiScale.safe_insets()
	assert_gt(ins.x, 0.0, "the plausible left cutout is kept")
	assert_eq(ins.z, 0.0, "an implausible right inset is ignored")
	assert_eq(ins.w, 0.0, "an implausible bottom inset is ignored")
	var vp: SubViewport = _window(Vector2(3120, 1440), 500.0)
	var hud: BattleHud = (load("res://ui/hud/hud.tscn") as PackedScene).instantiate()
	vp.add_child(hud)
	await wait_process_frames(3)
	_check_hud_edges(hud, _vis(vp), "bogus insets")
	_check_hud_gaps(hud, _vis(vp), "bogus insets", false)


func test_layout_follows_changes_that_come_without_a_resize_signal() -> void:
	# Android may report the density or safe area a moment after the resize signal.
	var vp: SubViewport = _window(Vector2(3120, 1440), 320.0)
	var hud: BattleHud = (load("res://ui/hud/hud.tscn") as PackedScene).instantiate()
	vp.add_child(hud)
	await wait_process_frames(3)
	var before: float = hud.get_power_panel().size.x
	UiScale.dpi_override = 560.0
	UiScale.safe_px_override = Vector4(0.0, 0.0, 90.0, 0.0)
	await wait_seconds(LayoutWatch.POLL_SECONDS * 2.5)
	await wait_process_frames(2)
	assert_gt(hud.get_power_panel().size.x, before, "bigger density gives bigger controls")
	_check_hud_edges(hud, _vis(vp), "late density + safe area")
	assert_gt(UiScale.safe_insets().z, 0.0)


func _union(root: Control, vis: Vector2) -> Rect2:
	var acc: Rect2 = Rect2()
	var first: bool = true
	for n: Node in root.find_children("*", "Control", true, false):
		var c: Control = n as Control
		if not c.is_visible_in_tree() or c.size.x < 1.0 or c.size.y < 1.0:
			continue
		if _inside_scroll(c, root):
			continue  # scrolled content may extend past the scroll area by design
		var r: Rect2 = c.get_global_rect()
		if r.size.x >= vis.x - 2.0 and r.size.y >= vis.y - 2.0:
			continue  # full-screen backdrops (sky, dim, margin containers)
		acc = r if first else acc.merge(r)
		first = false
	return acc


func _inside_scroll(c: Control, root: Control) -> bool:
	var p: Node = c.get_parent()
	while p != null and p != root:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _check_screen_edges(screen: Control, vis: Vector2, label: String) -> void:
	var m: Vector4 = UiScale.edge_margins()
	assert_eq(screen.get_global_rect(), Rect2(Vector2.ZERO, vis), "%s: root fills the visible rect" % label)
	var u: Rect2 = _union(screen, vis)
	assert_true(absf(u.position.x - m.x) <= TOL, "%s: content left %.1f vs margin %.1f" % [label, u.position.x, m.x])
	assert_true(absf(u.position.y - m.y) <= TOL, "%s: content top %.1f vs margin %.1f" % [label, u.position.y, m.y])
	assert_true(absf((vis.x - u.end.x) - m.z) <= TOL, "%s: content right %.1f vs visible %.1f" % [label, u.end.x, vis.x])
	assert_true(absf((vis.y - u.end.y) - m.w) <= TOL, "%s: content bottom %.1f vs visible %.1f" % [label, u.end.y, vis.y])


func test_setup_screen_hugs_the_edges_after_the_window_changes_size() -> void:
	UiScale.safe_px_override = Vector4(0.0, 0.0, 0.0, 0.0)
	for case: Array in CASES:
		var vp: SubViewport = _window(EARLY[0] as Vector2, float(case[1]))
		var s: SetupScreen = (load(SETUP) as PackedScene).instantiate()
		vp.add_child(s)
		await wait_process_frames(2)
		for step: Vector2 in EARLY:
			await _resize(vp, step)
		await _resize(vp, case[0] as Vector2)
		_check_screen_edges(s, _vis(vp), "setup " + str(case[2]))
		vp.queue_free()
		await wait_process_frames(1)


func test_shop_screen_hugs_the_edges_after_the_window_changes_size() -> void:
	var m := MatchSettings.new()
	m.num_tanks = 2
	m.rounds = 3
	m.seed = 99
	m.start_money = 10000
	m.full_unlocked = true
	_state = Simulation.new_match(m)
	for case: Array in CASES:
		var vp: SubViewport = _window(EARLY[0] as Vector2, float(case[1]))
		var f := ShopFlow.new()
		vp.add_child(f)
		f.open(_state, func(_a: Dictionary) -> String: return "", 0, true)
		await wait_process_frames(2)
		for step: Vector2 in EARLY:
			await _resize(vp, step)
		await _resize(vp, case[0] as Vector2)
		var shop: ShopScreen = f.get_screen()
		assert_true(shop.visible)
		_check_screen_edges(shop, _vis(vp), "shop " + str(case[2]))
		vp.queue_free()
		await wait_process_frames(1)


func test_title_and_overlays_fill_the_visible_rect() -> void:
	for case: Array in CASES:
		var vp: SubViewport = _window(EARLY[0] as Vector2, float(case[1]))
		var t: TitleScreen = (load(TITLE) as PackedScene).instantiate()
		vp.add_child(t)
		await wait_process_frames(2)
		await _resize(vp, case[0] as Vector2)
		var rect := Rect2(Vector2.ZERO, _vis(vp))
		assert_eq(t.get_global_rect(), rect, "title " + str(case[2]))
		t.open_settings()
		await wait_process_frames(2)
		assert_eq(t.get_settings_overlay().get_global_rect(), rect, "settings " + str(case[2]))
		var diag: DiagnosticsOverlay = t.get_settings_overlay().get_diagnostics()
		assert_eq(diag.get_global_rect(), rect, "diagnostics " + str(case[2]))
		vp.queue_free()
		await wait_process_frames(1)


func test_five_taps_on_the_version_open_the_diagnostics() -> void:
	var vp: SubViewport = _window(Vector2(3120, 1440), 500.0)
	var s := SettingsOverlay.new()
	vp.add_child(s)
	s.open()
	await wait_process_frames(2)
	var diag: DiagnosticsOverlay = s.get_diagnostics()
	var btn: Button = s.get_version_button()
	assert_true(btn.text.contains(BuildInfo.VERSION))
	assert_gte(UiScale.canvas_to_dp(btn.size.y), 47.5, "the version button is a 48 dp target")
	for i: int in range(4):
		btn.pressed.emit()
	assert_false(diag.visible, "four taps are not enough")
	btn.pressed.emit()
	assert_true(diag.visible)
	await wait_process_frames(2)
	var text: String = diag.get_text()
	for part: String in ["window (UiScale): 3120 x 1440", "visible canvas rect", "safe area", "dpi", "screen scale", "insets"]:
		assert_true(text.contains(part), "diagnostics list '%s'" % part)
	assert_lt(diag.get_node("Frames").size.x, 2000.0)
	diag.close()
	assert_false(diag.visible)
	assert_true(s.visible, "closing the diagnostics keeps the settings open")
	s.close()


func test_taps_far_apart_do_not_count() -> void:
	var vp: SubViewport = _window(Vector2(3120, 1440), 500.0)
	var s := SettingsOverlay.new()
	vp.add_child(s)
	s.open()
	for i: int in range(4):
		s.tap_version()
	s._last_tap_ms -= SettingsOverlay.TAP_WINDOW_MS + 50
	s.tap_version()
	assert_false(s.get_diagnostics().visible)
