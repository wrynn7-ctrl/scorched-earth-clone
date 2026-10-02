extends GutTest
## M3 in the battle: weapon picker, items, shields, movement, money and the round summary.

const BATTLE: String = "res://show/battle/battle_scene.tscn"
const SEED: int = 4242


func after_each() -> void:
	ShowSettings.reset()
	UiScale.reset_overrides()
	BattleConfig.reset()
	PlayerLooks.reset()
	get_tree().paused = false


## A controller whose round has started. `shopping` = [tank, item, bundles] purchases made in
## the shop first.
func _round(shopping: Array = [], rounds: int = 3, players: int = 2) -> BattleController:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(rounds, SEED, true, players)
	add_child_autofree(c)
	for s: Array in shopping:
		var res: Dictionary = c.get_session().submit({"kind": "buy", "tank": s[0], "item": s[1], "qty": s[2]})
		assert_eq(res["err"], "", "shop purchase %s" % str(s))
	assert_true(c.quick_start())
	return c


func test_weapon_button_shows_the_spark_dart_with_infinity_by_default() -> void:
	var c: BattleController = _round()
	assert_eq(c.get_selected_weapon(), "spark_dart")
	var chip: HudChip = c.get_hud().get_weapon_button()
	assert_eq(chip.get_item(), "spark_dart")
	assert_eq(chip.get_name_text(), "Spark Dart")
	assert_eq(chip.get_sub_text(), "∞")


func test_weapon_picker_lists_owned_weapons_and_switches() -> void:
	var c: BattleController = _round([[0, "pulse_missile", 1], [0, "glide_orb", 1]])
	c.get_hud().get_weapon_button().pressed.emit()
	var popup: WeaponPopup = c.get_hud().get_weapon_popup()
	assert_true(popup.visible, "tapping the weapon button opens the picker")
	var ids: Array[String] = []
	for chip: HudChip in popup.get_chips():
		ids.append(chip.get_item())
	assert_eq(ids, ["spark_dart", "pulse_missile", "glide_orb"] as Array[String], "only what the player owns, in catalog order")
	assert_eq(popup.get_chip("pulse_missile").get_sub_text(), "x5")
	assert_eq(popup.get_chip("spark_dart").get_sub_text(), "∞")
	popup.get_chip("glide_orb").pressed.emit()
	assert_false(popup.visible)
	assert_eq(c.get_selected_weapon(), "glide_orb")
	var chip: HudChip = c.get_hud().get_weapon_button()
	assert_eq(chip.get_item(), "glide_orb")
	assert_eq(chip.get_sub_text(), "x3")
	# Firing uses it.
	assert_eq(c.fire_current(), "")
	assert_eq(c.get_session().actions.back()["weapon"], "glide_orb")
	assert_eq(c.get_state().tanks[0].stock_of("glide_orb"), 2)
	# The weapon is remembered for this player's next turn.
	assert_eq(c.get_state().current_tank, 1)
	assert_eq(c.get_selected_weapon(), "spark_dart", "player 2 has their own selection")
	assert_eq(c.fire_current(), "")
	assert_eq(c.get_state().current_tank, 0)
	assert_eq(c.get_selected_weapon(), "glide_orb", "last used weapon is back, still in stock")


func test_selecting_a_weapon_you_do_not_own_is_refused() -> void:
	var c: BattleController = _round()
	assert_eq(c.select_weapon("nova_core"), "out_of_stock")
	assert_eq(c.get_selected_weapon(), "spark_dart")
	assert_ne(c.get_toast().get_text(), "")
	assert_eq(c.select_weapon("banana"), "unknown_weapon")


func test_running_out_falls_back_to_the_spark_dart() -> void:
	var c: BattleController = _round([[0, "nova_core", 1], [1, "nova_core", 1]])
	assert_eq(c.select_weapon("nova_core"), "")
	assert_eq(c.get_hud().get_weapon_button().get_sub_text(), "x1")
	assert_eq(c.fire_current(), "")
	assert_eq(c.get_state().tanks[0].stock_of("nova_core"), 0)
	# Player 2's turn now; when player 1 is back the last Nova Core is gone.
	if c.get_state().phase == SimConstants.PHASE_AIM:
		assert_eq(c.fire_current(), "")
	if c.get_state().phase == SimConstants.PHASE_AIM and c.get_state().current_tank == 0:
		assert_eq(c.get_selected_weapon(), "spark_dart", "automatic fallback")
		assert_eq(c.get_hud().get_weapon_button().get_item(), "spark_dart")
		assert_eq(c.get_hud().get_weapon_button().get_sub_text(), "∞")
	# Firing an out-of-stock weapon is impossible through the simulation too.
	var bad: Dictionary = {"kind": "fire", "tank": 0, "angle": 450, "power": 500, "weapon": "nova_core"}
	if c.get_state().phase == SimConstants.PHASE_AIM:
		assert_eq(Simulation.validate_action(c.get_state(), bad), "out_of_stock")


func test_money_readout_follows_the_current_player() -> void:
	var c: BattleController = _round([[0, "pulse_missile", 1]])
	assert_eq(c.get_hud().get_money_label().get_amount(), 8500)
	c.fire_current()
	assert_eq(c.get_state().current_tank, 1)
	assert_eq(c.get_hud().get_money_label().get_amount(), c.get_state().tanks[1].money)
	assert_eq(c.get_hud().get_money_label().get_text(), "10,000")


func test_item_buttons_show_owned_items_and_use_item_shows_the_shield_bubble() -> void:
	var c: BattleController = _round([[0, "glow_shield", 2], [0, "nanorepair_kit", 1], [0, "drift_chute", 1]])
	var hud: BattleHud = c.get_hud()
	assert_true(hud.get_items_toggle().visible)
	hud.get_items_toggle().pressed.emit()
	var tray: ItemTray = hud.get_item_tray()
	assert_true(tray.visible)
	assert_eq(tray.item_count(), 2, "shield and repair kit are usable; the chute is passive")
	assert_eq(tray.get_button("glow_shield").get_sub_text(), "x2")
	assert_null(tray.get_button("drift_chute"))
	assert_false(c.get_tank_view(0).has_shield_bubble())
	tray.get_button("glow_shield").pressed.emit()
	var view: TankView = c.get_tank_view(0)
	assert_true(view.has_shield_bubble(), "the bubble appears")
	assert_eq(view.get_shield_hp(), 30, "its HP is shown on the tank")
	var t: TankState = c.get_state().tanks[0]
	assert_eq(t.shield_hp, 30)
	assert_eq(t.stock_of("glow_shield"), 1)
	assert_eq(c.get_state().current_tank, 0, "using a shield does not end the turn")
	assert_eq(tray.get_button("glow_shield").get_sub_text(), "x1")
	assert_eq(c.mismatch_count, 0)
	# Using the repair kit ends the turn.
	assert_eq(c.use_item("nanorepair_kit"), "")
	assert_eq(c.get_state().current_tank, 1)
	assert_eq(c.use_item("glow_shield"), "out_of_stock", "player 2 owns no shield")


func test_using_an_item_you_do_not_own_toasts_and_changes_nothing() -> void:
	var c: BattleController = _round()
	var before: String = Simulation.fingerprint(c.get_state())
	assert_eq(c.use_item("ion_shield"), "out_of_stock")
	assert_eq(Simulation.fingerprint(c.get_state()), before)
	assert_ne(c.get_toast().get_text(), "")
	assert_eq(c.use_item("drift_chute"), "not_usable")
	assert_false(c.get_hud().get_items_toggle().visible, "no items, no toggle")


func test_shield_events_flicker_and_break_the_bubble() -> void:
	var c: BattleController = _round([[1, "glow_shield", 1]])
	# Player 1 passes, player 2 shields (a turn-neutral action), then takes hits.
	assert_eq(c.pass_turn(), "")
	assert_eq(c.use_item("glow_shield"), "")
	var view: TankView = c.get_tank_view(1)
	assert_eq(view.get_shield_hp(), 30)
	var events: Array[Dictionary] = []
	var st: MatchState = c.get_state()
	Simulation.apply_damage(st, 0, 1, 20, "explosion", 0, events)
	c.call("_play", events)
	assert_eq(view.get_shield_hp(), 10, "shield_hit lowers the readout")
	assert_true(view.has_shield_bubble())
	assert_eq(st.tanks[1].health, 100, "the shield took it all")
	events = []
	Simulation.apply_damage(st, 0, 1, 25, "explosion", 0, events)
	c.call("_play", events)
	assert_false(view.has_shield_bubble(), "shield_down: the bubble is gone")
	assert_eq(view.get_health(), st.tanks[1].health, "the remainder hit the tank")
	assert_eq(c.mismatch_count, 0)


func test_move_buttons_send_move_actions_and_fuel_decreases() -> void:
	var c: BattleController = _round([[0, "fuel_cell", 1], [1, "fuel_cell", 1]])
	var hud: BattleHud = c.get_hud()
	var moves: MoveControls = hud.get_move_controls()
	assert_true(moves.visible, "a fuel cell in stock shows the move buttons")
	assert_eq(moves.get_fuel_total(), 100)
	var t: TankState = c.get_state().tanks[0]
	var x0: int = t.x
	moves.get_right_button().button_down.emit()
	moves.get_right_button().button_up.emit()
	assert_eq(c.get_session().actions.back()["kind"], "move")
	assert_eq(c.get_session().actions.back()["dx"], 10)
	assert_gt(t.x, x0, "the tank drove right")
	assert_lte(t.x - x0, 10)
	assert_eq(c.get_state().current_tank, 0, "moving keeps the turn")
	var driven: int = t.x - x0
	assert_eq(t.stock_of("fuel_cell"), 0, "the cell was drawn when fuel ran out")
	assert_eq(t.fuel, 100 - driven)
	assert_eq(moves.get_fuel_total(), 100 - driven, "the readout follows")
	assert_eq(c.get_tank_view(0).position, Vector2(t.x, t.y), "the view followed the state")
	var x1: int = t.x
	assert_eq(c.move_current(-1), "")
	assert_lt(t.x, x1)
	assert_eq(c.get_session().actions.back()["dx"], -10)
	assert_eq(c.mismatch_count, 0)


func test_move_buttons_are_hidden_without_fuel_and_move_is_refused() -> void:
	var c: BattleController = _round()
	assert_false(c.get_hud().get_move_controls().visible)
	var before: String = Simulation.fingerprint(c.get_state())
	assert_eq(c.move_current(1), "no_fuel")
	assert_eq(Simulation.fingerprint(c.get_state()), before)
	assert_ne(c.get_toast().get_text(), "")


func test_holding_a_move_button_repeats_every_150_ms() -> void:
	var c: BattleController = _round([[0, "fuel_cell", 1]])
	var moves: MoveControls = c.get_hud().get_move_controls()
	assert_eq(MoveControls.REPEAT_SECONDS, 0.15)
	watch_signals(moves)
	moves.get_left_button().button_down.emit()
	assert_true(moves.is_repeating())
	assert_signal_emit_count(moves, "move_pressed", 1, "immediate on press")
	await wait_seconds(0.5)
	assert_gte(get_signal_emit_count(moves, "move_pressed"), 3, "repeats while held")
	moves.get_left_button().button_up.emit()
	assert_false(moves.is_repeating())
	var n: int = get_signal_emit_count(moves, "move_pressed")
	await wait_seconds(0.4)
	assert_eq(get_signal_emit_count(moves, "move_pressed"), n, "stops on release")


func test_move_and_item_hud_is_locked_during_playback() -> void:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(3, SEED, false)
	add_child_autofree(c)
	c.get_session().submit({"kind": "buy", "tank": 0, "item": "glow_shield", "qty": 1})
	c.quick_start()
	await wait_until(func() -> bool: return not c.is_busy(), 10.0, 0.1)
	c.set_speed(2.0)
	assert_eq(c.fire_current(), "")
	assert_true(c.get_hud().get_weapon_button().disabled, "no weapon change mid-shot")
	assert_eq(c.use_item("glow_shield"), "busy")
	assert_eq(c.move_current(1), "busy")
	await wait_until(func() -> bool: return not c.is_busy(), 10.0, 0.1)
	assert_false(c.get_hud().get_weapon_button().disabled)


func _earn_a_round(c: BattleController) -> void:
	var guard: int = 0
	while c.get_state().phase == SimConstants.PHASE_AIM and guard < 100:
		var shot: Vector2i = AutoShot.find_shot(c.get_state(), c.get_state().current_tank)
		c.set_aim(shot.x, shot.y)
		c.select_weapon("pulse_missile")
		c.fire_current()
		guard += 1


func test_round_summary_shows_money_earned_kills_and_wins() -> void:
	var c: BattleController = _round([[0, "pulse_missile", 4], [1, "pulse_missile", 4]], 2)
	var before: Array[int] = []
	for t: TankState in c.get_state().tanks:
		before.append(t.money)
	_earn_a_round(c)
	var st: MatchState = c.get_state()
	assert_eq(st.phase, SimConstants.PHASE_SHOP)
	assert_true(c.get_round_overlay().visible)
	var table: StatTable = c.get_round_overlay().get_table()
	assert_eq(table.row_count(), 2)
	for t: TankState in st.tanks:
		var earned: int = t.money - before[t.id]
		assert_eq(c.round_earnings(t.id), earned, "the sum of the money events is what the bank gained")
		var cells: PackedStringArray = table.get_row_cells(t.id)
		assert_eq(cells[0], HudFormat.money_delta(earned))
		assert_eq(cells[1], str(t.kills))
		assert_eq(cells[2], str(t.round_wins))
	var winner_earned: int = maxi(c.round_earnings(0), c.round_earnings(1))
	assert_gte(winner_earned, SimConstants.SURVIVE_PAY + SimConstants.WIN_PAY, "the winner got the round pay")
	# NEXT -> shop; the earnings counter resets for the next round.
	c.get_round_overlay().get_next_button().pressed.emit()
	assert_false(c.get_round_overlay().visible)
	assert_true(c.get_shop().is_showing_handover())
	c.quick_start()
	assert_eq(c.round_earnings(0), 0)
	assert_eq(c.round_earnings(1), 0)


func test_match_over_shows_standings_from_the_simulation() -> void:
	var c: BattleController = _round([[0, "pulse_missile", 4], [1, "pulse_missile", 4]], 1)
	_earn_a_round(c)
	assert_eq(c.get_state().phase, SimConstants.PHASE_MATCH_OVER)
	var table: StatTable = c.get_match_overlay().get_table()
	var order: Array[int] = Simulation.standings(c.get_state())
	assert_true(table.get_text().begins_with("1. PLAYER %d" % (order[0] + 1)))
	assert_eq(table.row_count(), 2)


func test_many_players_fit_the_round_summary() -> void:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(2, SEED, true, 6)
	add_child_autofree(c)
	c.quick_start()
	assert_eq(c.get_state().tanks.size(), 6)
	assert_eq(c.get_state().phase, SimConstants.PHASE_AIM)
	for t: TankState in c.get_state().tanks:
		assert_false(c.get_tank_view(t.id).is_dead())


func test_player_looks_reach_the_tank_views() -> void:
	PlayerLooks.set_looks(PackedInt32Array([5, 2]), PackedInt32Array([7, 3]))
	var c: BattleController = _round()
	assert_eq(c.get_tank_view(0).get_color_index(), 5)
	assert_eq(c.get_tank_view(0).get_emblem_index(), 7)
	assert_eq(c.get_tank_view(1).get_color_index(), 2)
	assert_eq(c.get_tank_view(1).get_emblem_index(), 3)
