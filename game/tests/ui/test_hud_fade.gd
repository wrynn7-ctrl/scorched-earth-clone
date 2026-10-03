extends GutTest
## HUD panels fade while the action is behind them (docs: M3-U2): ~30% over ~150 ms, back to
## full when clear, still touchable while faded, and a touch brings them to full at once.

const BATTLE: String = "res://show/battle/battle_scene.tscn"
const SEED: int = 4242


func after_each() -> void:
	ShowSettings.reset()
	UiScale.reset_overrides()
	BattleConfig.reset()
	PlayerLooks.reset()


## The containers lay the HUD out on the next frames; panel rectangles mean nothing before.
func _round(players: int = 4) -> BattleController:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(3, SEED, true, players)
	add_child_autofree(c)
	assert_true(c.quick_start())
	await wait_process_frames(3)
	_park_tanks(c)
	return c


## Every tank view goes to a spot in the middle of the screen that no panel covers.
func _park_tanks(c: BattleController) -> void:
	var vis: Vector2 = c.get_viewport().get_visible_rect().size
	var xf: Transform2D = c.get_viewport().get_canvas_transform()
	var at: Vector2 = xf.affine_inverse() * Vector2(vis.x * 0.5, vis.y * 0.55)
	for i: int in range(c.get_state().tanks.size()):
		c.get_tank_view(i).position = at + Vector2(float(i) * 3.0, 0.0)
	c.call("_update_overlays")
	c.get_hud().get_fade().step(1.0)


## Puts tank `i` (its footprint) under the middle of `panel`.
func _put_under(c: BattleController, i: int, panel: Control) -> void:
	var xf: Transform2D = c.get_viewport().get_canvas_transform()
	var centre: Vector2 = panel.get_global_rect().get_center()
	c.get_tank_view(i).position = xf.affine_inverse() * centre + Vector2(0.0, 30.0)


func test_a_tank_under_the_angle_panel_fades_it_and_moving_away_restores_it() -> void:
	var c: BattleController = await _round()
	var hud: BattleHud = c.get_hud()
	var fade: HudFade = hud.get_fade()
	var panel: AnglePanel = hud.get_angle_panel()
	assert_eq(panel.modulate.a, 1.0, "nothing behind it: fully visible")
	_put_under(c, 1, panel)
	c.call("_update_overlays")
	assert_eq(fade.get_target(panel), HudFade.FADED_ALPHA)
	fade.step(HudFade.FADE_SECONDS * 0.5)
	assert_between(panel.modulate.a, HudFade.FADED_ALPHA + 0.05, 0.99, "halfway through the fade")
	fade.step(HudFade.FADE_SECONDS)
	assert_almost_eq(panel.modulate.a, 0.3, 0.001, "faded to ~30%")
	assert_eq(hud.get_power_panel().modulate.a, 1.0, "the other panels stay put")
	assert_eq(hud.get_wind_indicator().modulate.a, 1.0)
	_park_tanks(c)
	assert_eq(panel.modulate.a, 1.0, "clear again: back to full")


func test_the_fade_takes_about_150_ms() -> void:
	assert_eq(HudFade.FADE_SECONDS, 0.15)
	assert_eq(HudFade.FADED_ALPHA, 0.3)
	var c: BattleController = await _round()
	var fade: HudFade = c.get_hud().get_fade()
	var panel: PowerPanel = c.get_hud().get_power_panel()
	_put_under(c, 0, panel)
	c.call("_update_overlays")
	fade.step(0.149)
	assert_gt(panel.modulate.a, 0.3, "not there yet at 149 ms")
	fade.step(0.01)
	assert_almost_eq(panel.modulate.a, 0.3, 0.001, "there at 150 ms")


func test_faded_panels_still_take_touches() -> void:
	var c: BattleController = await _round()
	var hud: BattleHud = c.get_hud()
	var panel: AnglePanel = hud.get_angle_panel()
	_put_under(c, 1, panel)
	c.call("_update_overlays")
	hud.get_fade().step(1.0)
	assert_almost_eq(panel.modulate.a, 0.3, 0.001)
	assert_eq(panel.mouse_filter, Control.MOUSE_FILTER_STOP, "a faded panel is still a hit target")
	var left: FineButton = panel.get_node("Box/Row/Left")
	assert_false(left.disabled)
	var before: int = hud.get_angle_tenths()
	# Opacity never affects hit-testing: the button is a live target and answers a press.
	assert_ne(left.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_true(left.is_visible_in_tree())
	assert_ne(panel.process_mode, Node.PROCESS_MODE_DISABLED)
	left.button_down.emit()
	left.button_up.emit()
	assert_eq(hud.get_angle_tenths(), before + 1, "the left button worked through the faded panel")


func test_a_touch_on_a_faded_panel_brings_it_to_full_at_once_and_keeps_it() -> void:
	var c: BattleController = await _round()
	var hud: BattleHud = c.get_hud()
	var fade: HudFade = hud.get_fade()
	var panel: PowerPanel = hud.get_power_panel()
	_put_under(c, 2, panel)
	c.call("_update_overlays")
	fade.step(1.0)
	assert_almost_eq(panel.modulate.a, 0.3, 0.001)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = panel.get_global_rect().get_center()
	hud._input(press)
	assert_eq(panel.modulate.a, 1.0, "full opacity immediately, no fade-in")
	# The tank is still behind it, but a panel in use stays readable for a moment.
	for _i: int in range(5):
		c.call("_update_overlays")
		fade.step(0.2)
	assert_eq(panel.modulate.a, 1.0, "held while in use")
	for _i: int in range(5):
		c.call("_update_overlays")
		fade.step(0.2)
	assert_almost_eq(panel.modulate.a, 0.3, 0.001, "fades again once the finger has been away a while")
	# A touch elsewhere changes nothing.
	var elsewhere := InputEventMouseButton.new()
	elsewhere.button_index = MOUSE_BUTTON_LEFT
	elsewhere.pressed = true
	elsewhere.position = Vector2(c.get_viewport().get_visible_rect().size.x * 0.5, 5.0)
	hud._input(elsewhere)
	assert_almost_eq(panel.modulate.a, 0.3, 0.001)


func test_shells_blasts_beams_and_flames_fade_panels_too() -> void:
	var c: BattleController = await _round()
	var hud: BattleHud = c.get_hud()
	var fade: HudFade = hud.get_fade()
	var panel: Control = hud.get_angle_panel()
	var r: Rect2 = panel.get_global_rect()
	var inside := Rect2(r.get_center() - Vector2(10, 10), Vector2(20, 20))
	hud.set_occluders([inside] as Array[Rect2])
	assert_eq(fade.get_target(panel), HudFade.FADED_ALPHA, "a blast or shell rectangle")
	hud.set_occluders([] as Array[Rect2], PackedVector2Array([Vector2(r.position.x - 50.0, r.get_center().y), Vector2(r.end.x + 50.0, r.get_center().y)]))
	assert_eq(fade.get_target(panel), HudFade.FADED_ALPHA, "a beam crossing the panel")
	hud.set_occluders([] as Array[Rect2], PackedVector2Array([Vector2(r.position.x - 50.0, r.position.y - 80.0), Vector2(r.end.x + 50.0, r.position.y - 40.0)]))
	assert_eq(fade.get_target(panel), 1.0, "a beam passing above it")
	hud.set_occluders([Rect2(r.end + Vector2(40, 40), Vector2(30, 30))] as Array[Rect2])
	assert_eq(fade.get_target(panel), 1.0, "something elsewhere")


func test_locked_dimming_and_fade_multiply() -> void:
	var c: BattleController = await _round()
	var hud: BattleHud = c.get_hud()
	var panel: AnglePanel = hud.get_angle_panel()
	hud.set_controls_locked(true)
	assert_almost_eq(panel.modulate.a, 0.45, 0.001)
	_put_under(c, 1, panel)
	c.call("_update_overlays")
	hud.get_fade().step(1.0)
	assert_almost_eq(panel.modulate.a, 0.45 * 0.3, 0.001)
	hud.set_controls_locked(false)
	assert_almost_eq(panel.modulate.a, 0.3, 0.001, "unlocking keeps the fade")


func test_the_fire_button_fades_through_self_modulate() -> void:
	var c: BattleController = await _round()
	var hud: BattleHud = c.get_hud()
	var fire: FireButton = hud.get_fire_button()
	_put_under(c, 3, fire)
	c.call("_update_overlays")
	hud.get_fade().step(1.0)
	assert_almost_eq(fire.self_modulate.a, 0.3, 0.001, "its pulse owns modulate, so the fade uses self_modulate")
	assert_eq(fire.mouse_filter, Control.MOUSE_FILTER_STOP)


func test_a_hidden_hud_never_fades_and_reset_restores_everything() -> void:
	var c: BattleController = await _round()
	var hud: BattleHud = c.get_hud()
	var panel: AnglePanel = hud.get_angle_panel()
	_put_under(c, 1, panel)
	c.call("_update_overlays")
	hud.get_fade().step(1.0)
	hud.get_fade().reset()
	assert_eq(panel.modulate.a, 1.0)
	hud.visible = false
	c.call("_update_overlays")
	hud.get_fade().step(1.0)
	assert_eq(panel.modulate.a, 1.0)
