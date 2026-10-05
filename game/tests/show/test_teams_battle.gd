extends GutTest
## Teams in the battle (ARCHITECTURE sections 39 and 42): team badges on the tank tags and the turn banners (only in
## team matches, CPU tanks included, never in Love), the TEAM A WINS round summary with its members, the draw
## text, and the match results grouped by team in Simulation.team_standings order.

const BATTLE: String = "res://show/battle/battle_scene.tscn"
const SEED: int = 4242
const H: int = SimConstants.CTRL_HUMAN
const NORMAL: int = SimConstants.CTRL_NORMAL
const NONE: int = TeamStyle.NONE


func before_each() -> void:
	ShowSettings.reset()
	PlayerNames.reset()


func after_each() -> void:
	ShowSettings.reset()
	UiScale.reset_overrides()
	BattleConfig.reset()
	PlayerLooks.reset()
	PlayerNames.reset()


func _battle(controllers: Array, teams: Array = [], friendly_fire: bool = true, names: PackedStringArray = PackedStringArray(),
		rounds: int = 3, instant: bool = true, love: bool = false) -> BattleController:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(rounds, SEED, instant, controllers.size())
	c.set_controllers(PackedInt32Array(controllers))
	c.set_player_names(names)
	if not teams.is_empty():
		c.set_teams(PackedInt32Array(teams), friendly_fire)
	if love:
		c.set_mode(SimConstants.MODE_LOVE)
	add_child_autofree(c)
	if c.get_state().phase == SimConstants.PHASE_SHOP:
		assert_true(c.quick_start())
	_play_out(c)
	return c


func _play_out(c: BattleController) -> void:
	var n: int = 0
	while c._playing and n < 900:
		c._process(1.0 / 30.0)
		n += 1


## Ends the round for the team that is left: every other tank is destroyed (as a team wipe would leave it), then the
## current tank passes so the core runs its round-end check.
func _wipe_out(c: BattleController, losers: Array) -> void:
	for id: int in losers:
		c.get_state().tanks[id].alive = false
		c.get_state().tanks[id].health = 0
	if not c.get_state().tanks[c.get_state().current_tank].alive:
		for t: TankState in c.get_state().tanks:
			if t.alive:
				c.get_state().current_tank = t.id
				break
	c.call("_rebuild_display")  # the views follow the state again
	assert_eq(c.pass_turn(), "")
	_play_out(c)


# --- badges ------------------------------------------------------------------------------------------

func test_tanks_wear_a_badge_only_in_a_team_match() -> void:
	var plain: BattleController = _battle([H, H, H, H])
	for t: TankState in plain.get_state().tanks:
		assert_eq(plain.get_tank_view(t.id).get_team(), NONE)
		assert_eq(plain.get_tank_view(t.id).tag_extent(), 0.0, "no name and no team: no tag at all")
	assert_false(plain.has_teams())
	var teamed: BattleController = _battle([H, H, H, H], [0, 0, 1, 1])
	assert_true(teamed.has_teams())
	for t: TankState in teamed.get_state().tanks:
		assert_eq(teamed.get_tank_view(t.id).get_team(), t.team)
		assert_gt(teamed.get_tank_view(t.id).tag_extent(), 0.0, "a badge is drawn")


func test_cpu_tanks_get_the_badge_too_without_a_name() -> void:
	var c: BattleController = _battle([H, NORMAL, H, NORMAL], [0, 1, 1, 0], true, PackedStringArray(["ANNA", "", "BOB", ""]))
	assert_eq(c.get_tank_view(1).get_name_tag(), "", "a CPU has no typed name")
	assert_eq(c.get_tank_view(1).get_team(), 1)
	assert_eq(c.get_tank_view(3).get_team(), 0)
	assert_almost_eq(c.get_tank_view(1).tag_extent(), TankView.BADGE_SIZE, 0.01, "the badge alone")
	assert_gt(c.get_tank_view(0).tag_extent(), TankView.BADGE_SIZE, "badge plus the name")


func test_the_turn_banner_shows_the_team_letter() -> void:
	var c: BattleController = _battle([H, H, H, H], [0, 0, 1, 1])
	var badge: TeamBadge = c.get_hud().get_turn_banner().get_badge()
	assert_true(badge.visible)
	assert_eq(badge.get_letter(), "A")
	c.pass_turn()
	c.pass_turn()
	assert_eq(c.get_hud().get_turn_banner().get_badge().get_letter(), "B", "tank 2 is on team B")
	var plain: BattleController = _battle([H, H])
	assert_false(plain.get_hud().get_turn_banner().get_badge().visible)


func test_the_cpu_banner_shows_the_team_letter_too() -> void:
	var c: BattleController = _battle([NORMAL, H], [1, 0])
	assert_true(c.get_hud().get_turn_banner().get_badge().visible)
	assert_eq(c.get_hud().get_turn_banner().get_badge().get_letter(), "B")


func test_the_big_turn_banner_carries_the_badge() -> void:
	var c: BattleController = _battle([H, H], [0, 1], true, PackedStringArray(["ANNA", "BOB"]), 3, false)
	var big: BigTurnBanner = c.get_hud().get_big_banner()
	assert_true(big.is_showing())
	assert_true(big.get_badge().visible)
	assert_eq(big.get_badge().get_letter(), "A")
	var plain: BattleController = _battle([H, H], [], true, PackedStringArray(["ANNA", "BOB"]), 3, false)
	assert_true(plain.get_hud().get_big_banner().is_showing())
	assert_false(plain.get_hud().get_big_banner().get_badge().visible)


func test_love_mode_never_shows_team_ui() -> void:
	var c: BattleController = _battle([H, H], [0, 1], true, PackedStringArray(), 1, true, true)
	assert_true(c.is_love_mode())
	assert_false(c.has_teams())
	assert_false(c.get_state().settings.has_teams(), "the core drops teams in love mode")
	assert_eq(c.get_tank_view(0).get_team(), NONE)
	assert_false(c.get_hud().get_turn_banner().get_badge().visible)
	c.get_hud().set_teams(PackedInt32Array([0, 1]))
	assert_eq(c.get_hud().team_of(0), NONE, "even a stray call cannot bring a badge into love")
	c.get_hud().show_sudden_death()
	assert_false(c.get_hud().get_sudden_banner().is_showing(), "and no sudden death either")


func test_badge_control_hides_without_a_team_and_draws_letter_and_colour() -> void:
	var b := TeamBadge.new()
	add_child_autofree(b)
	b.set_badge_size(24.0)
	assert_false(b.visible)
	assert_eq(b.get_letter(), "")
	b.set_team(2)
	assert_true(b.visible)
	assert_eq(b.get_letter(), "C")
	b.set_team(7)
	assert_false(b.visible, "anything but 0..3 is no badge")


## Tanks are placed one per lane with a jitter of +-lane/5, so two neighbours can stand 3/5 of a lane apart
## (124 units with 8 tanks), not a full 200: a badge and 12 capitals do NOT fit there on one row. The battle lifts
## the tag of such a neighbour (NameTagLayout), so no two tags on the same row ever overlap.
func test_a_widest_name_and_a_badge_get_their_own_row_beside_a_close_neighbour() -> void:
	var a: TankView = (load("res://show/tank_view.tscn") as PackedScene).instantiate()
	add_child_autofree(a)
	a.set_name_tag("WWWWWWWWWWWW")
	a.set_team(3)
	var w: float = a.tag_world_width()
	assert_gt(w, 124.0, "the widest tag is wider than the closest neighbours stand apart")
	var xs := PackedFloat32Array([0.0, 124.0, 248.0, 372.0])
	var ws := PackedFloat32Array([w, w, w, w])
	var rows: PackedInt32Array = NameTagLayout.rows(xs, ws)
	assert_eq(rows, PackedInt32Array([0, 1, 0, 1]), "neighbours alternate between two rows")
	for i: int in range(4):
		for j: int in range(i + 1, 4):
			if rows[i] == rows[j]:
				assert_gte(absf(xs[j] - xs[i]), (w + w) * 0.5 + NameTagLayout.GAP, "tags %d and %d on one row do not touch" % [i, j])


func test_the_battle_keeps_eight_widest_tags_apart_for_many_seeds() -> void:
	var names := PackedStringArray()
	var teams: Array = []
	var ctl: Array = []
	for i: int in range(8):
		names.append("WWWWWWWWWWWW")
		teams.append(i % 2)
		ctl.append(H)
	var lifted: int = 0
	for seed_value: int in range(4000, 4012):
		var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
		c.configure(3, seed_value, true, 8)
		c.set_controllers(PackedInt32Array(ctl))
		c.set_player_names(names)
		c.set_teams(PackedInt32Array(teams), true)
		add_child_autofree(c)
		if c.get_state().phase == SimConstants.PHASE_SHOP:
			assert_true(c.quick_start())
		_play_out(c)
		c._process(0.016)
		var views: Array[TankView] = []
		for t: TankState in c.get_state().tanks:
			views.append(c.get_tank_view(t.id))
		for i: int in range(views.size()):
			lifted += 1 if views[i].get_tag_row() > 0 else 0
			for j: int in range(i + 1, views.size()):
				if views[i].get_tag_row() != views[j].get_tag_row():
					continue
				var need: float = (views[i].tag_world_width() + views[j].tag_world_width()) * 0.5
				assert_gte(absf(views[i].position.x - views[j].position.x), need, "seed %d: tags %d and %d overlap on row %d" % [seed_value, i, j, views[i].get_tag_row()])
	assert_gt(lifted, 0, "some tags had to be lifted")


func test_tag_rows_are_only_recomputed_when_something_changed() -> void:
	var c: BattleController = _battle([H, H], [0, 1], true, PackedStringArray(["WWWWWWWWWWWW", "WWWWWWWWWWWW"]))
	c._process(0.016)
	var before: PackedFloat32Array = c.get("_tag_sig_x")
	c.get_tank_view(0).position.x = c.get_tank_view(1).position.x - 40.0
	c._process(0.016)
	assert_ne(c.get("_tag_sig_x"), before, "a moved tank is noticed")
	assert_ne(c.get_tank_view(0).get_tag_row(), c.get_tank_view(1).get_tag_row(), "and the two close tags take different rows")


func test_a_tank_without_a_tag_takes_no_room() -> void:
	var rows: PackedInt32Array = NameTagLayout.rows(PackedFloat32Array([0.0, 10.0, 20.0]), PackedFloat32Array([100.0, 0.0, 100.0]))
	assert_eq(rows[1], 0)
	assert_eq(rows[2], 1)


# --- round summary ---------------------------------------------------------------------------------------

func test_the_summary_says_team_a_wins_and_lists_the_members() -> void:
	var c: BattleController = _battle([H, H, H, H], [0, 0, 1, 1], true, PackedStringArray(["ANNA", "BOB", "CY", "DEE"]))
	_wipe_out(c, [2, 3])
	assert_eq(c.get_state().phase, SimConstants.PHASE_SHOP)
	var o: RoundEndOverlay = c.get_round_overlay()
	assert_true(o.visible)
	assert_eq(o.get_title_text(), "TEAM A WINS")
	assert_eq(o.get_members_text(), "ANNA · BOB")
	assert_eq(o.get_table().badge_count(), 4, "every row carries its badge")
	assert_eq(o.get_table().get_badge_teams(), PackedInt32Array([0, 0, 1, 1]))


func test_a_team_wins_with_a_member_destroyed_and_both_are_listed() -> void:
	var c: BattleController = _battle([H, H, H, H], [0, 1, 0, 1], true, PackedStringArray(["ANNA", "BOB", "CY", "DEE"]))
	_wipe_out(c, [1, 2, 3])  # only tank 0 of team A lives, tank 2 (team A) is destroyed
	var o: RoundEndOverlay = c.get_round_overlay()
	assert_eq(o.get_title_text(), "TEAM A WINS")
	assert_eq(o.get_members_text(), "ANNA · CY", "the winning team's destroyed members share the win")


func test_the_other_team_can_win_too() -> void:
	var c: BattleController = _battle([H, H, H, H], [0, 0, 1, 1])
	c.get_state().current_tank = 2
	_wipe_out(c, [0, 1])
	assert_eq(c.get_round_overlay().get_title_text(), "TEAM B WINS")
	assert_eq(c.get_round_overlay().get_members_text(), "PLAYER 3 · PLAYER 4")


func test_the_summary_of_a_match_without_teams_is_unchanged() -> void:
	var c: BattleController = _battle([H, H, H], [])
	_wipe_out(c, [1, 2])
	var o: RoundEndOverlay = c.get_round_overlay()
	assert_eq(o.get_title_text(), "PLAYER 1 WINS THE ROUND")
	assert_eq(o.get_members_text(), "")
	assert_eq(o.get_table().badge_count(), 0)


func test_the_draw_message_for_a_team_game() -> void:
	var o := RoundEndOverlay.new()
	add_child_autofree(o)
	var rows: Array[Dictionary] = [
		{"id": 0, "earned": 0, "kills": 0, "wins": 0}, {"id": 1, "earned": 0, "kills": 0, "wins": 0}]
	o.show_summary(-1, rows, 1, 3, [] as Array[Dictionary], PackedInt32Array([0, 1]), -1)
	assert_eq(o.get_title_text(), "DRAW — NO SURVIVORS")
	assert_eq(o.get_members_text(), "")
	var plain := RoundEndOverlay.new()
	add_child_autofree(plain)
	plain.show_summary(-1, rows, 1, 3)
	assert_eq(plain.get_title_text(), "DRAW", "without teams the old text stays")


func test_a_restored_summary_still_names_the_winning_team() -> void:
	var path: String = "user://test_team_summary.crtl"
	var c: BattleController = _battle([H, H, H, H], [0, 0, 1, 1], true, PackedStringArray(), 3)
	c.set_autosave_path(path)
	_wipe_out(c, [2, 3])
	assert_true(c.autosave_now())
	BattleConfig.autosave_path = path
	BattleConfig.resume = true
	BattleConfig.instant = true
	var r: BattleController = (load(BATTLE) as PackedScene).instantiate()
	add_child_autofree(r)
	assert_true(r.get_round_overlay().visible)
	assert_eq(r.get_round_overlay().get_title_text(), "TEAM A WINS")
	assert_eq(r.get_round_overlay().get_members_text(), "PLAYER 1 · PLAYER 2")
	SaveStore.delete(path)


# --- match results -------------------------------------------------------------------------------------------

func _team_order_of_headers(text: String) -> Array[int]:
	var order: Array[int] = []
	for part: String in text.split("; "):
		for t: int in range(4):
			if part.begins_with("%d. TEAM %s" % [order.size() + 1, TeamStyle.letter(t)]):
				order.append(t)
	return order


func test_match_results_are_grouped_by_team_in_standings_order() -> void:
	var c: BattleController = _battle([H, H, H, H], [0, 1, 0, 1], true, PackedStringArray(["ANNA", "BOB", "CY", "DEE"]), 1)
	_wipe_out(c, [1, 3])
	assert_eq(c.get_state().phase, SimConstants.PHASE_MATCH_OVER)
	var m: MatchEndOverlay = c.get_match_overlay()
	assert_true(m.visible)
	assert_eq(m.get_title_text(), "TEAM A WINS THE MATCH")
	var text: String = m.get_table().get_text()
	var standings: Array[int] = Simulation.team_standings(c.get_state())
	assert_eq(standings[0], 0)
	assert_eq(_team_order_of_headers(text), standings, "teams appear in team_standings order")
	assert_eq(m.get_table().row_count(), 6, "two headers and four members")
	assert_true(text.begins_with("1. TEAM A"), text)
	# Members sit under their own team's header, in tank-standings order.
	var rows: PackedStringArray = text.split("; ")
	assert_true(rows[0].begins_with("1. TEAM A"))
	assert_true(rows[1].begins_with("ANNA") or rows[1].begins_with("CY"))
	assert_true(rows[2].begins_with("ANNA") or rows[2].begins_with("CY"))
	assert_true(rows[3].begins_with("2. TEAM B"))
	assert_true(rows[4].begins_with("BOB") or rows[4].begins_with("DEE"))
	assert_eq(m.get_table().get_badge_teams(), PackedInt32Array([0, 0, 0, 1, 1, 1]))


func test_the_winning_team_comes_first_whichever_team_it_is() -> void:
	var c: BattleController = _battle([H, H, H, H], [0, 1, 0, 1], true, PackedStringArray(), 1)
	_wipe_out(c, [0, 2])
	var m: MatchEndOverlay = c.get_match_overlay()
	assert_eq(m.get_title_text(), "TEAM B WINS THE MATCH")
	assert_true(m.get_table().get_text().begins_with("1. TEAM B"), m.get_table().get_text())
	assert_eq(_team_order_of_headers(m.get_table().get_text()), Simulation.team_standings(c.get_state()))


func test_team_totals_in_the_results() -> void:
	var o := MatchEndOverlay.new()
	add_child_autofree(o)
	var rows: Array[Dictionary] = [
		{"id": 0, "wins": 2, "damage": 300, "kills": 1}, {"id": 1, "wins": 1, "damage": 900, "kills": 0},
		{"id": 2, "wins": 2, "damage": 120, "kills": 2}, {"id": 3, "wins": 1, "damage": 50, "kills": 0}]
	var order: Array[int] = [0, 2, 1, 3]
	var team_order: Array[int] = [0, 1]
	o.show_team_standings(team_order, order, rows, PackedInt32Array([0, 1, 0, 1]))
	var t: StatTable = o.get_table()
	assert_eq(t.get_row_cells(0), PackedStringArray(["2", "420", "3"]), "wins are shared, damage and kills add up")
	assert_eq(t.get_row_cells(3), PackedStringArray(["1", "950", "0"]))
	assert_eq(o.get_title_text(), "TEAM A WINS THE MATCH")


func test_a_level_top_is_a_draw_in_team_results() -> void:
	var o := MatchEndOverlay.new()
	add_child_autofree(o)
	var rows: Array[Dictionary] = [
		{"id": 0, "wins": 1, "damage": 100, "kills": 1}, {"id": 1, "wins": 1, "damage": 100, "kills": 1}]
	var team_order: Array[int] = [0, 1]
	var order: Array[int] = [0, 1]
	o.show_team_standings(team_order, order, rows, PackedInt32Array([0, 1]))
	assert_eq(o.get_title_text(), "DRAW")


func test_results_without_teams_stay_as_they_are() -> void:
	var c: BattleController = _battle([H, H, H], [], true, PackedStringArray(), 1)
	_wipe_out(c, [1, 2])
	var m: MatchEndOverlay = c.get_match_overlay()
	assert_eq(m.get_title_text(), "PLAYER 1 WINS THE MATCH")
	assert_true(m.get_table().get_text().begins_with("1. PLAYER 1"))
	assert_eq(m.get_table().badge_count(), 0)
	assert_eq(m.get_table().row_count(), 3)


func test_team_screens_fit_a_phone() -> void:
	UiScale.dpi_override = 535.0
	UiScale.window_px_override = Vector2(2340, 1080)
	var vis: Vector2 = UiScale.visible_size(Vector2(2340, 1080))
	var vp := SubViewport.new()
	vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
	vp.disable_3d = true
	add_child_autofree(vp)
	var o := MatchEndOverlay.new()
	vp.add_child(o)
	var rows: Array[Dictionary] = []
	var teams := PackedInt32Array()
	var order: Array[int] = []
	for i: int in range(8):
		rows.append({"id": i, "wins": 1, "damage": 12345, "kills": 2})
		teams.append(i % 4)
		order.append(i)
		PlayerNames.set_names(PackedStringArray(["WWWWWWWWWWWW", "WWWWWWWWWWWW", "WWWWWWWWWWWW", "WWWWWWWWWWWW",
				"WWWWWWWWWWWW", "WWWWWWWWWWWW", "WWWWWWWWWWWW", "WWWWWWWWWWWW"]))
	var team_order: Array[int] = [0, 1, 2, 3]
	o.show_team_standings(team_order, order, rows, teams)
	await wait_process_frames(4)
	var r: Rect2 = o.get_table().get_global_rect()
	assert_true(Rect2(Vector2.ZERO, vis).grow(1.5).encloses(o.get_table().get_global_rect().intersection(Rect2(Vector2.ZERO, vis))), "table inside the screen")
	assert_gte(r.size.x, 100.0)
	var btn: Button = o.find_child("NewMatch", true, false) as Button
	assert_true(Rect2(Vector2.ZERO, vis).grow(1.5).encloses(btn.get_global_rect()), "NEW MATCH stays on screen with eight players in four teams")
