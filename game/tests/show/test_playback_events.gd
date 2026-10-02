extends GutTest
## Playback of the M3 timeline events (ARCHITECTURE sections 17-25). Weapon behaviours may not
## produce every event yet, so these tests feed hand-written events straight to the dispatcher.

const BATTLE: String = "res://show/battle/battle_scene.tscn"
const SEED: int = 777


func after_each() -> void:
	ShowSettings.reset()
	UiScale.reset_overrides()
	BattleConfig.reset()
	PlayerLooks.reset()


## instant = false so the visual effects are really created. The round start is awaited.
func _live() -> BattleController:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(3, SEED, false)
	add_child_autofree(c)
	c.quick_start()
	await wait_until(func() -> bool: return not c.is_busy(), 10.0, 0.1)
	return c


func _instant() -> BattleController:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(3, SEED, true)
	add_child_autofree(c)
	c.quick_start()
	return c


func _dispatch(c: BattleController, e: Dictionary) -> void:
	c.call("_dispatch", e)


func test_flames_flicker_and_fade_over_about_a_second_and_a_half() -> void:
	var c: BattleController = await _live()
	var pts := PackedInt32Array([100, 400, 110, 402, 120, 405, 130, 407])
	_dispatch(c, {"type": "flames", "tick": 0, "points": pts})
	var field: FlameField = null
	for n: Node in c.get_node("World").get_children():
		if n is FlameField and (n as FlameField).is_burning():
			field = n
	assert_not_null(field, "a flame field is burning")
	assert_eq(field.point_count(), 4)
	assert_true(field.visible)
	await wait_seconds(0.8)
	assert_true(field.is_burning())
	await wait_seconds(1.0)
	assert_false(field.is_burning(), "burned out after ~1.5 s")
	assert_false(field.visible)


func test_beam_flashes_a_bright_line() -> void:
	var c: BattleController = await _live()
	_dispatch(c, {"type": "beam", "tick": 0, "x0": 100, "y0": 300, "x1": 900, "y1": 280})
	var beam: BeamFx = null
	for n: Node in c.get_node("World").get_children():
		if n is BeamFx and (n as BeamFx).is_active():
			beam = n
	assert_not_null(beam)
	assert_eq(beam.get_endpoints(), PackedVector2Array([Vector2(100, 300), Vector2(900, 280)]))
	await wait_seconds(0.6)
	assert_false(beam.is_active(), "the flash is over")


func test_well_persists_until_well_off_and_shows_its_radius() -> void:
	var c: BattleController = await _live()
	_dispatch(c, {"type": "well_on", "tick": 0, "owner": 1, "x": 800, "y": 300, "expires_turn": 6})
	var w: WellView = c.get_well_view(1)
	assert_not_null(w)
	assert_eq(w.position, Vector2(800, 300))
	assert_eq(w.get_pull_radius(), 300.0, "the faint ring is at the well's pull radius")
	assert_eq(w.expires_turn, 6)
	await wait_seconds(0.3)
	assert_true(is_instance_valid(w), "it stays between turns")
	_dispatch(c, {"type": "well_on", "tick": 0, "owner": 1, "x": 500, "y": 250, "expires_turn": 8})
	assert_eq(c.get_well_view(1).position, Vector2(500, 250), "a new well by the same owner replaces the old one")
	_dispatch(c, {"type": "well_off", "tick": 0, "owner": 1})
	await wait_process_frames(2)
	assert_null(c.get_well_view(1))


func test_wells_in_the_state_are_rebuilt_after_a_restore() -> void:
	var c: BattleController = _instant()
	c.get_state().wells.append({"owner": 0, "x": 700, "y": 320, "expires_turn": 5})
	c.call("_rebuild_display")
	assert_not_null(c.get_well_view(0))
	assert_eq(c.get_well_view(0).position, Vector2(700, 320))
	c.get_state().wells.clear()


func test_chute_draws_a_canopy_on_the_falling_tank() -> void:
	var c: BattleController = await _live()
	var v: TankView = c.get_tank_view(0)
	_dispatch(c, {"type": "tank_fall", "tick": 0, "tank": 0, "from_y": 300, "to_y": 360})
	_dispatch(c, {"type": "chute", "tick": 0, "tank": 0})
	assert_true(v.is_chute_visible())
	await wait_seconds(1.3)
	assert_false(v.is_chute_visible(), "the canopy fades after the landing")
	assert_eq(v.position.y, 360.0)


func test_repair_raises_the_health_bar_with_a_sparkle() -> void:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(3, SEED, true)
	add_child_autofree(c)
	c.get_session().submit({"kind": "buy", "tank": 0, "item": "nanorepair_kit", "qty": 1})
	c.quick_start()
	var events: Array[Dictionary] = []
	Simulation.apply_damage(c.get_state(), 1, 0, 50, "explosion", 0, events)
	c.call("_play", events)
	assert_eq(c.get_tank_view(0).get_health(), 50)
	assert_eq(c.use_item("nanorepair_kit"), "")
	assert_eq(c.get_tank_view(0).get_health(), 90)
	assert_eq(c.mismatch_count, 0)
	assert_eq(c.get_state().current_tank, 1, "repair ends the turn")


func test_repair_event_shows_sparkles_and_a_popup_when_live() -> void:
	var c: BattleController = await _live()
	var v: TankView = c.get_tank_view(0)
	_dispatch(c, {"type": "repair", "tick": 0, "tank": 0, "amount": 40, "health": 100})
	assert_eq(v.get_health(), 100)
	var sparkle: CPUParticles2D = v.get_node("Sparkle")
	assert_true(sparkle.emitting)


func test_tank_move_and_drag_slide_the_tank_along_the_surface() -> void:
	var c: BattleController = _instant()
	var t: TankState = c.get_state().tanks[0]
	var v: TankView = c.get_tank_view(0)
	var from_x: int = t.x
	_dispatch(c, {"type": "tank_drag", "tick": 0, "tank": 0, "from_x": from_x, "to_x": from_x + 6})
	assert_eq(v.position.x, float(from_x + 6))
	var ground: float = float(TankState.rest_y(c.display_terrain, from_x + 6))
	assert_lte(absf(v.position.y - ground), 6.0, "follows the ground (a drop is shown by tank_fall)")
	_dispatch(c, {"type": "tank_move", "tick": 0, "tank": 0, "from_x": from_x + 6, "to_x": from_x + 6, "fuel": 0})
	assert_eq(v.position.x, float(from_x + 6), "a blocked move changes nothing")


func test_live_tank_move_animates_then_lands_on_the_state_position() -> void:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(3, SEED, false)
	add_child_autofree(c)
	c.get_session().submit({"kind": "buy", "tank": 0, "item": "fuel_cell", "qty": 1})
	c.quick_start()
	await wait_until(func() -> bool: return not c.is_busy(), 10.0, 0.1)
	var t: TankState = c.get_state().tanks[0]
	var x0: int = t.x
	assert_eq(c.move_current(1), "")
	assert_true(c.is_busy(), "input is blocked while the tank slides")
	await wait_until(func() -> bool: return not c.is_busy(), 5.0, 0.05)
	assert_gt(t.x, x0)
	assert_eq(c.get_tank_view(0).position, Vector2(t.x, t.y))
	assert_eq(c.mismatch_count, 0)
	assert_false(c.get_hud().is_controls_locked(), "walking does not dim the HUD")


func test_several_projectiles_fly_at_once_each_starting_at_its_own_tick() -> void:
	var c: BattleController = await _live()
	var path := PackedInt32Array()
	for i: int in range(40):
		path.append((200 + i * 5) * FixedMath.ONE)
		path.append((300 - i * 2) * FixedMath.ONE)
	_dispatch(c, {"type": "projectile", "tick": 0, "id": 0, "weapon": "prism_splitter", "path": path})
	for id: int in range(1, 6):
		_dispatch(c, {"type": "projectile", "tick": 10 + id, "id": id, "weapon": "prism_splitter", "path": path})
	var shells: Dictionary = c.get("_shells")
	assert_eq(shells.size(), 6, "main shell + 5 children")
	var trails: Dictionary = {}
	for k: Variant in shells.keys():
		trails[(shells[k] as Dictionary)["trail"]] = true
	assert_eq(trails.size(), 6, "each one has its own trail")
	assert_eq((shells[3] as Dictionary)["start"], 13)
	_dispatch(c, {"type": "projectile_end", "tick": 30, "id": 2, "reason": "terrain", "x": 1, "y": 1})
	assert_eq((c.get("_shells") as Dictionary).size(), 5)
	c.call("_clear_shells")
	assert_eq((c.get("_shells") as Dictionary).size(), 0)


func test_money_events_pop_up_signed_amounts() -> void:
	var c: BattleController = await _live()
	_dispatch(c, {"type": "money", "tick": 0, "tank": 0, "delta": 1500, "money": 11500, "reason": "kill"})
	_dispatch(c, {"type": "money", "tick": 0, "tank": 1, "delta": -300, "money": 9700, "reason": "self_damage"})
	var texts: Array[String] = []
	for n: Node in c.get_node("World").get_children():
		if n is DamagePopup and (n as DamagePopup).visible:
			texts.append((n as DamagePopup).text)
	assert_true(texts.has("+$1,500"), str(texts))
	assert_true(texts.has("-$300"), str(texts))
	assert_eq(c.round_earnings(0), 1500)
	assert_eq(c.round_earnings(1), -300)
	# Shop purchases are not "earned".
	_dispatch(c, {"type": "money", "tick": 0, "tank": 0, "delta": -1500, "money": 10000, "reason": "buy"})
	assert_eq(c.round_earnings(0), 1500)


func test_terrain_tools_are_applied_when_the_core_has_them_and_resynced_when_not() -> void:
	var c: BattleController = _instant()
	var before: PackedByteArray = c.display_terrain.cells.duplicate()
	var cx: int = c.get_state().tanks[0].x + 200
	var cy: int = c.get_state().terrain.surface_y(cx) + 10
	var probe := Terrain.new(8, 8)
	if probe.has_method("carve_tunnel"):
		_dispatch(c, {"type": "tunnel", "tick": 0, "x0": cx, "y0": cy, "x1": cx + 40, "y1": cy + 20, "radius": 5})
		var want: Terrain = c.state.terrain.duplicate_terrain()
		want.call("carve_tunnel", cx, cy, cx + 40, cy + 20, 5)
		assert_eq(c.display_terrain.cells, want.cells, "same Terrain function as the core")
		assert_ne(c.display_terrain.cells, before)
	else:
		_dispatch(c, {"type": "tunnel", "tick": 0, "x0": cx, "y0": cy, "x1": cx + 40, "y1": cy + 20, "radius": 5})
		assert_true(c.get("_needs_snap"), "guarded: resync with the state after playback")
	if probe.has_method("pour"):
		var cols := PackedInt32Array([cx, cx + 1, cx])
		_dispatch(c, {"type": "terrain_pour", "tick": 0, "x": cx, "cells": cols, "material": 3})
		var want2: Terrain = c.display_terrain.duplicate_terrain()
		assert_eq(want2.cells, c.display_terrain.cells)
	if probe.has_method("add_circle_skipping"):
		_dispatch(c, {"type": "terrain_add", "tick": 0, "x": cx, "y": cy - 80, "radius": 20, "material": 2, "skip": PackedInt32Array()})
		assert_ne(c.display_terrain.cells, before)
	# Playback resyncs a display that missed an update.
	c.call("_snap_display_to_state")
	assert_eq(c.display_terrain.cells, c.get_state().terrain.cells)


func test_presentation_ticks_are_monotone_and_money_follows_its_damage() -> void:
	var c: BattleController = _instant()
	var events: Array[Dictionary] = [
		{"type": "explosion", "tick": 100, "x": 0, "y": 0, "radius": 10, "weapon": "x"},
		{"type": "damage", "tick": 100, "tank": 0, "amount": 10, "health": 90, "cause": "explosion"},
		{"type": "money", "tick": 100, "tank": 1, "delta": 150, "money": 1, "reason": "damage"},
		{"type": "tank_fall", "tick": 100, "tank": 0, "from_y": 1, "to_y": 50},
		{"type": "damage", "tick": 100, "tank": 0, "amount": 10, "health": 80, "cause": "fall"},
		{"type": "money", "tick": 100, "tank": 1, "delta": 150, "money": 1, "reason": "damage"},
		{"type": "round_end", "tick": 100, "winner": 1},
		{"type": "money", "tick": 100, "tank": 1, "delta": 1000, "money": 1, "reason": "survive"},
	]
	var present: PackedInt32Array = c.call("_compute_present", events)
	for i: int in range(1, present.size()):
		assert_gte(present[i], present[i - 1], "event %d is not before event %d" % [i, i - 1])
	assert_eq(present[2], present[1], "the +$ popup comes with the damage it pays for")
	assert_eq(present[5], present[4], "also for a fall's damage, which is shown later")
	assert_gt(present[4], present[1])
	assert_eq(present[7], present[6], "round pay comes with the round end")


func test_reduce_flashing_dims_the_beam_and_flames() -> void:
	ShowSettings.reduce_flashing = true
	var beam := BeamFx.new()
	add_child_autofree(beam)
	beam.play(Vector2.ZERO, Vector2(100, 0))
	assert_true(beam.is_active())
	var flames := FlameField.new()
	add_child_autofree(flames)
	flames.play(PackedInt32Array([1, 2]))
	assert_true(flames.is_burning())
