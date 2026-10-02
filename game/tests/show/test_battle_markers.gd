extends GutTest
## The "you" arrow above the HUD and the off-screen shell chevron.

const BATTLE: String = "res://show/battle/battle_scene.tscn"
const SEED: int = 4242


func after_each() -> void:
	ShowSettings.reset()
	UiScale.reset_overrides()
	BattleConfig.reset()
	PlayerLooks.reset()


func _round(instant: bool = true, players: int = 4) -> BattleController:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(3, SEED, instant, players)
	add_child_autofree(c)
	assert_true(c.quick_start())
	await wait_process_frames(3)  # the HUD containers lay out on the next frames
	return c


func _park_tanks(c: BattleController) -> void:
	var vis: Vector2 = c.get_viewport().get_visible_rect().size
	var xf: Transform2D = c.get_viewport().get_canvas_transform()
	var at: Vector2 = xf.affine_inverse() * Vector2(vis.x * 0.5, vis.y * 0.55)
	for i: int in range(c.get_state().tanks.size()):
		c.get_tank_view(i).position = at + Vector2(float(i) * 3.0, 0.0)


func test_the_marker_layer_sits_above_the_hud_and_below_the_overlays() -> void:
	var c: BattleController = await _round()
	var layer: CanvasLayer = c.get_markers().get_parent() as CanvasLayer
	var hud_layer: CanvasLayer = c.get_hud().get_parent() as CanvasLayer
	assert_gt(layer.layer, hud_layer.layer)
	assert_lt(layer.layer, (c.get_node("OverlayLayer") as CanvasLayer).layer)
	assert_eq(c.get_markers().mouse_filter, Control.MOUSE_FILTER_IGNORE, "never steals touches")


func test_you_marker_appears_over_the_active_tank_when_it_is_under_a_panel() -> void:
	var c: BattleController = await _round()
	_park_tanks(c)
	c.call("_update_overlays")
	assert_false(c.get_markers().is_you_visible(), "tank in the open: no marker needed")
	var active: int = c.get_state().current_tank
	var panel: Control = c.get_hud().get_angle_panel()
	var xf: Transform2D = c.get_viewport().get_canvas_transform()
	c.get_tank_view(active).position = xf.affine_inverse() * panel.get_global_rect().get_center() + Vector2(0, 30)
	c.call("_update_overlays")
	var m: BattleMarkers = c.get_markers()
	assert_true(m.is_you_visible(), "under the angle panel: the arrow shows above the HUD")
	var tank_screen: Vector2 = xf * c.get_tank_view(active).position
	assert_almost_eq(m.get_you_position().x, tank_screen.x, 1.0, "centred on the tank")
	assert_lt(m.get_you_position().y, tank_screen.y, "above it")
	assert_eq(m.get("_you_color"), PlayerLooks.color(active), "in the player colour")
	# Another tank under a panel does not get the arrow.
	_park_tanks(c)
	var other: int = (active + 1) % 4
	c.get_tank_view(other).position = xf.affine_inverse() * panel.get_global_rect().get_center() + Vector2(0, 30)
	c.call("_update_overlays")
	assert_false(m.is_you_visible())


func test_you_marker_follows_the_turn_after_a_shot() -> void:
	var c: BattleController = await _round()
	var first: int = c.get_state().current_tank
	assert_eq(c.fire_current(), "")
	var second: int = c.get_state().current_tank
	assert_ne(first, second)
	_park_tanks(c)
	var panel: Control = c.get_hud().get_power_panel()
	var xf: Transform2D = c.get_viewport().get_canvas_transform()
	c.get_tank_view(first).position = xf.affine_inverse() * panel.get_global_rect().get_center()
	c.call("_update_overlays")
	assert_false(c.get_markers().is_you_visible(), "the tank that just fired is not the active one")
	c.get_tank_view(second).position = xf.affine_inverse() * panel.get_global_rect().get_center()
	c.call("_update_overlays")
	assert_true(c.get_markers().is_you_visible())


func test_offscreen_shell_gets_a_chevron_with_its_height_in_the_shooter_colour() -> void:
	var c: BattleController = await _round(false, 2)
	await wait_until(func() -> bool: return not c.is_busy(), 10.0, 0.1)
	c.call("_dispatch", {"type": "fire", "tick": 0, "tank": 1, "angle": 450, "power": 500, "weapon": "spark_dart"})
	var path := PackedInt32Array()
	for i: int in range(60):
		path.append(800 * FixedMath.ONE)
		path.append((400 - i * 20) * FixedMath.ONE)
	c.call("_dispatch", {"type": "projectile", "tick": 0, "id": 0, "weapon": "spark_dart", "path": path})
	var trail: ShellTrail = (c.get("_shells") as Dictionary)[0]["trail"]
	var xf: Transform2D = c.get_viewport().get_canvas_transform()
	trail.set_progress(2.0)
	c.call("_update_overlays")
	assert_eq(c.get_markers().shell_count(), 0, "low over the battlefield: no chevron")
	trail.set_progress(59.0)  # y = -780 cells: far above the top edge
	c.call("_update_overlays")
	var m: BattleMarkers = c.get_markers()
	assert_eq(m.shell_count(), 1)
	var item: Dictionary = m.get_shell_markers()[0]
	assert_almost_eq(item["x"] as float, (xf * Vector2(800, 0)).x, 1.0, "at the shell's x")
	var head: Vector2 = trail.head_position()
	var top_world_y: float = (xf.affine_inverse() * Vector2(0, 0)).y
	assert_almost_eq(float(item["height"]), top_world_y - head.y, 1.5, "height above the top edge, in cells")
	assert_gt(item["height"] as int, 20)
	assert_eq(item["color"], PlayerLooks.color(1), "the shooter's colour")
	# Back into view: the chevron goes away.
	trail.set_progress(10.0)
	c.call("_update_overlays")
	assert_eq(m.shell_count(), 0)
	c.call("_clear_shells")


func test_chevron_text_is_translated() -> void:
	assert_ne(tr("HUD_SHELL_UP_FMT"), "HUD_SHELL_UP_FMT")
	assert_ne(tr("HUD_YOU"), "HUD_YOU")
	assert_ne(tr("DMG_BURN_FMT"), "DMG_BURN_FMT")
	assert_ne(tr("DMG_BEAM_FMT"), "DMG_BEAM_FMT")
	assert_eq(ErrorText.message("bad_phase"), "You can't do that right now")
	assert_eq(ErrorText.message("no_fuel"), tr("ERR_NO_FUEL"))
