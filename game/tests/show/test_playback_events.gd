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


func test_terrain_tools_are_applied_with_the_same_core_functions() -> void:
	var c: BattleController = _instant()
	var before: PackedByteArray = c.display_terrain.cells.duplicate()
	var cx: int = c.get_state().tanks[0].x + 200
	var cy: int = c.get_state().terrain.surface_y(cx) + 10
	var want: Terrain = c.display_terrain.duplicate_terrain()
	_dispatch(c, {"type": "tunnel", "tick": 0, "x0": cx, "y0": cy, "x1": cx + 40, "y1": cy + 20, "radius": 5})
	want.carve_tunnel(cx, cy, cx + 40, cy + 20, 5)
	assert_eq(c.display_terrain.cells, want.cells, "tunnel: same Terrain function as the core")
	assert_ne(c.display_terrain.cells, before)
	var cols := PackedInt32Array([cx, cx + 1, cx])
	_dispatch(c, {"type": "terrain_pour", "tick": 0, "x": cx, "cells": cols, "material": 3})
	want.pour(cols, 3)
	assert_eq(c.display_terrain.cells, want.cells, "pour")
	_dispatch(c, {"type": "terrain_add", "tick": 0, "x": cx, "y": cy - 80, "radius": 20, "material": 2, "skip": PackedInt32Array()})
	want.add_circle_skipping(cx, cy - 80, 20, 2, PackedInt32Array())
	assert_eq(c.display_terrain.cells, want.cells, "add")
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


# --- M3-U2: scheduling, sludge flow, damage causes, anchor rings -----------------------------

func test_visual_events_keep_their_own_ticks_and_terrain_events_stay_in_list_order() -> void:
	var c: BattleController = _instant()
	var events: Array[Dictionary] = [
		{"type": "fire", "tick": 0, "tank": 0, "angle": 1, "power": 1, "weapon": "prism_splitter"},
		{"type": "projectile", "tick": 0, "id": 0, "weapon": "prism_splitter", "path": PackedInt32Array([0, 0])},
		{"type": "projectile_end", "tick": 40, "id": 0, "reason": "split", "x": 1, "y": 1},
		{"type": "projectile", "tick": 40, "id": 1, "weapon": "prism_splitter", "path": PackedInt32Array([0, 0])},
		{"type": "projectile_end", "tick": 96, "id": 1, "reason": "terrain", "x": 1, "y": 1},
		{"type": "explosion", "tick": 96, "x": 1, "y": 1, "radius": 24, "weapon": "prism_splitter"},
		{"type": "terrain_carve", "tick": 96, "x": 1, "y": 1, "radius": 24},
		{"type": "terrain_settle", "tick": 96, "x0": 0, "x1": 5, "falls": []},
		{"type": "projectile", "tick": 40, "id": 2, "weapon": "prism_splitter", "path": PackedInt32Array([0, 0])},
		{"type": "projectile_end", "tick": 91, "id": 2, "reason": "terrain", "x": 1, "y": 1},
		{"type": "explosion", "tick": 91, "x": 1, "y": 1, "radius": 24, "weapon": "prism_splitter"},
		{"type": "terrain_carve", "tick": 91, "x": 1, "y": 1, "radius": 24},
	]
	var present: PackedInt32Array = c.call("_compute_present", events)
	for i: int in [1, 2, 3, 4, 5, 8, 9, 10]:
		assert_eq(present[i], -1, "event %d is shown at its own tick" % i)
	var last: int = 0
	for i: int in range(events.size()):
		if present[i] >= 0:
			assert_gte(present[i], last, "list-order events never go back in time (%d)" % i)
			last = present[i]
	assert_eq(present[6], 96, "carve of child 1 at its explosion tick")
	assert_gte(present[11], present[7], "child 2's carve waits for child 1's settle: same order as the core")
	var vis: Array[Dictionary] = BattleController._visual_events(events)
	assert_eq((vis[2]["tick"] as int), 40, "children start at the apex tick, together")
	assert_eq((vis[3]["tick"] as int), 40)
	assert_eq((vis[2]["id"] as int), 1)
	assert_eq((vis[3]["id"] as int), 2)
	for i: int in range(1, vis.size()):
		assert_gte(vis[i]["tick"] as int, vis[i - 1]["tick"] as int, "visual events sorted by tick")


func test_a_replaced_well_goes_off_with_the_new_one_but_an_expiry_waits_for_the_turn() -> void:
	var c: BattleController = _instant()
	var replaced: Array[Dictionary] = [
		{"type": "fire", "tick": 0, "tank": 0, "angle": 1, "power": 1, "weapon": "singularity_seed"},
		{"type": "well_off", "tick": 80, "owner": 0},
		{"type": "well_on", "tick": 80, "owner": 0, "x": 5, "y": 5, "expires_turn": 9},
		{"type": "wind", "tick": 80, "wind": 3},
		{"type": "turn", "tick": 80, "tank": 1},
	]
	var p: PackedInt32Array = c.call("_compute_present", replaced)
	assert_eq(p[1], 80, "off together with the new well on the same owner")
	assert_eq(p[2], 80)
	assert_gt(p[4], 80, "the turn waits")
	var expiry: Array[Dictionary] = [
		{"type": "fire", "tick": 0, "tank": 0, "angle": 1, "power": 1, "weapon": "spark_dart"},
		{"type": "well_off", "tick": 80, "owner": 1},
		{"type": "wind", "tick": 80, "wind": 3},
		{"type": "turn", "tick": 80, "tank": 1},
	]
	p = c.call("_compute_present", expiry)
	assert_eq(p[1], p[3], "an expiring well goes off with the turn change")


func test_a_shot_that_ends_at_tick_zero_still_hands_the_turn_over_after_a_beat() -> void:
	var c: BattleController = _instant()
	var beam: Array[Dictionary] = [
		{"type": "fire", "tick": 0, "tank": 0, "angle": 1, "power": 1, "weapon": "photon_lance"},
		{"type": "beam", "tick": 0, "x0": 0, "y0": 0, "x1": 5, "y1": 5},
		{"type": "wind", "tick": 0, "wind": 3},
		{"type": "turn", "tick": 0, "tank": 1},
	]
	var p: PackedInt32Array = c.call("_compute_present", beam)
	assert_eq(p[1], 0, "the beam fires at tick 0")
	assert_eq(p[3], BattleController.POST_DELAY)
	var pass_turn: Array[Dictionary] = [
		{"type": "wind", "tick": 0, "wind": 3},
		{"type": "turn", "tick": 0, "tank": 1},
	]
	p = c.call("_compute_present", pass_turn)
	assert_eq(p[1], 0, "a pass or a round start has no beat")


func test_sludge_pours_progressively_and_ends_exactly_like_the_core() -> void:
	var c: BattleController = await _live()
	var cx: int = 700
	var cols := PackedInt32Array()
	for i: int in range(120):
		cols.append(cx + (i % 9) - 4)
	var want: Terrain = c.display_terrain.duplicate_terrain()
	want.pour(cols, 3)
	var start: PackedByteArray = c.display_terrain.cells.duplicate()
	c.set("_playhead", 100.0)
	_dispatch(c, {"type": "terrain_pour", "tick": 100, "x": cx, "cells": cols, "material": 3})
	assert_eq(c.display_terrain.cells, start, "nothing poured yet at the first tick")
	c.set("_playhead", 100.0 + float(BattleController.POUR_TICKS) * 0.5)
	c.call("_advance_pour")
	assert_ne(c.display_terrain.cells, start, "sludge is flowing")
	assert_ne(c.display_terrain.cells, want.cells, "but not finished halfway")
	# The next terrain event flushes the rest first, so ordering matches the core.
	_dispatch(c, {"type": "terrain_settle", "tick": 100, "x0": cx - 5, "x1": cx + 5, "falls": []})
	want.settle(cx - 5, cx + 5)
	assert_eq(c.display_terrain.cells, want.cells)
	assert_true((c.get("_pour") as Dictionary).is_empty())


func test_pour_delays_the_events_that_follow_it() -> void:
	var c: BattleController = _instant()
	var events: Array[Dictionary] = [
		{"type": "terrain_pour", "tick": 100, "x": 5, "cells": PackedInt32Array([5, 6]), "material": 1},
		{"type": "damage", "tick": 100, "tank": 0, "amount": 1, "health": 99, "cause": "explosion"},
	]
	var p: PackedInt32Array = c.call("_compute_present", events)
	assert_eq(p[0], 100)
	assert_gte(p[1], 100 + BattleController.POUR_TICKS)


func test_burn_and_beam_damage_get_their_own_popup_and_glow() -> void:
	var c: BattleController = await _live()
	var v: TankView = c.get_tank_view(1)
	_dispatch(c, {"type": "damage", "tick": 0, "tank": 1, "amount": 12, "health": 88, "cause": "burn"})
	assert_true(v.is_hit_flashing(), "the hull glows")
	var texts: Array[String] = []
	for n: Node in c.get_node("World").get_children():
		if n is DamagePopup and (n as DamagePopup).visible:
			texts.append((n as DamagePopup).text)
	assert_true(texts.has("-12 burn"), str(texts))
	_dispatch(c, {"type": "damage", "tick": 0, "tank": 0, "amount": 35, "health": 65, "cause": "beam"})
	texts.clear()
	for n: Node in c.get_node("World").get_children():
		if n is DamagePopup and (n as DamagePopup).visible:
			texts.append((n as DamagePopup).text)
	assert_true(texts.has("-35 beam"), str(texts))
	assert_true(c.get_tank_view(0).is_hit_flashing())
	_dispatch(c, {"type": "damage", "tick": 0, "tank": 1, "amount": 5, "health": 83, "cause": "explosion"})
	await wait_seconds(0.9)
	assert_false(v.is_hit_flashing(), "the glow is short")


func test_reduced_flashing_keeps_the_hit_glow_but_drops_the_flicker() -> void:
	ShowSettings.reduce_flashing = true
	var v := TankView.new()
	add_child_autofree(v)
	v.hit_flash(NeonPalette.SUNSET, true)
	assert_true(v.is_hit_flashing())
	assert_false(v.get("_hit_flicker"))


func test_anchor_impact_plays_pull_rings_over_the_pull_radius() -> void:
	var c: BattleController = await _live()
	_dispatch(c, {"type": "fire", "tick": 0, "tank": 0, "angle": 1, "power": 1, "weapon": "riptide_anchor"})
	var path := PackedInt32Array([200 * FixedMath.ONE, 300 * FixedMath.ONE, 210 * FixedMath.ONE, 310 * FixedMath.ONE])
	_dispatch(c, {"type": "projectile", "tick": 0, "id": 0, "weapon": "riptide_anchor", "path": path})
	_dispatch(c, {"type": "projectile_end", "tick": 2, "id": 0, "reason": "terrain", "x": 210, "y": 310})
	var rings: PullRings = null
	for n: Node in c.get_node("World").get_children():
		if n is PullRings and (n as PullRings).is_playing():
			rings = n
	assert_not_null(rings)
	assert_eq(rings.position, Vector2(210, 310))
	assert_eq(rings.get_world_rect().size, Vector2.ONE * 360.0, "the 180-cell pull radius")
	await wait_seconds(0.9)
	assert_false(rings.is_playing())


func test_static_burst_uses_the_cold_blast_style() -> void:
	var c: BattleController = await _live()
	_dispatch(c, {"type": "explosion", "tick": 0, "x": 300, "y": 300, "radius": 40, "weapon": "static_burst"})
	var cold: Explosion = null
	for n: Node in c.get_node("World").get_children():
		if n is Explosion and (n as Explosion).is_playing():
			cold = n
	assert_not_null(cold)
	assert_true((cold.get_node("Flash") as Sprite2D).modulate.b > (cold.get_node("Flash") as Sprite2D).modulate.r, "cyan-white, not the orange fireball")


func test_the_last_fall_after_a_drag_rests_on_the_ground_it_was_dragged_onto() -> void:
	var c: BattleController = _instant()
	var t: TankState = c.get_state().tanks[0]
	var v: TankView = c.get_tank_view(0)
	var to_x: int = t.x + 20
	var ground: float = float(TankState.rest_y(c.display_terrain, to_x))
	var events: Array[Dictionary] = [
		{"type": "tank_drag", "tick": 5, "tank": 0, "from_x": t.x, "to_x": to_x},
		{"type": "tank_fall", "tick": 5, "tank": 0, "from_y": t.y, "to_y": int(ground) - 2},
	]
	c.set("_events", events)
	c.set("_ev_i", 0)
	_dispatch(c, events[0])
	c.set("_ev_i", 1)
	_dispatch(c, events[1])
	assert_eq(v.position, Vector2(float(to_x), ground), "the walk ended on the ground, whatever the last fall reported")
