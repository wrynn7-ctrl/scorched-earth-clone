extends OnlineTestBase
## The online battle screen (OnlineBattleController) driven by a scripted OnlineMatch: the lock-step display, input only on
## this phone's turn, sending moves, CPU turns and opponents' shots played from the log, catch-up, the private shop, the
## connection indicator and timer ring, quick messages, the dispute screen, leaving and the end of the match.

const SCENE: String = "res://show/online/online_battle_scene.tscn"
const ME: String = OnlineFakes.ME
const OTHER: String = OnlineFakes.OTHER

var _net: OnlineFakes.FakeNet = null


func before_each() -> void:
	super.before_each()
	_net = OnlineFakes.net()
	OnlineHub.session = _net
	BattleConfig.reset()


func after_each() -> void:
	BattleConfig.reset()
	super.after_each()


func _seats() -> Array:
	return [OnlineFakes.human_seat(ME, "HANA"), OnlineFakes.human_seat(OTHER, "ANNA"), OnlineFakes.cpu_seat(2, "CPU")]


## Both humans press READY (and the CPU shops), as history.
static func _ready_all(replay: NetReplay) -> void:
	for t: TankState in replay.state.tanks:
		if not replay.seat_is_cpu(t.id) and not t.ready:
			replay.apply_entry({"kind": "ready", "tank": t.id})
	while not replay.pending_cpu_entry().is_empty():
		replay.apply_entry(replay.pending_cpu_entry())


## A match in the aim phase. `mine_first` decides whether the first turn is this phone's. The current tank's owner
## among the two humans is `me`, or the other one.
func _aim_match(mine_first: bool, seats: Array = []) -> OnlineFakes.FakeMatch:
	var list: Array = seats if not seats.is_empty() else _seats()
	var scratch: NetReplay = NetReplay.create(NetTestUtil.meta(list))
	_ready_all(scratch)
	while scratch.state.current_tank >= 0 and scratch.seat_is_cpu(scratch.state.current_tank) and scratch.pending_cpu_entry().is_empty() == false:
		scratch.apply_entry(scratch.pending_cpu_entry())
	var owner: String = scratch.seat_uid(scratch.state.current_tank)
	var me: String = owner if mine_first else (OTHER if owner == ME else ME)
	if owner == "":
		me = ME  # a CPU starts: whoever
	var fm: OnlineFakes.FakeMatch = OnlineFakes.match_for(me, list)
	_ready_all(fm.replay)
	fm._set_stored_turn(fm.replay.expected_turn())
	return fm


func _battle(fm: OnlineMatch, instant: bool = true) -> OnlineBattleController:
	var b: OnlineBattleController = (load(SCENE) as PackedScene).instantiate()
	b.attach_match(fm)
	b.configure(3, 4242, instant)
	add_child_autofree(b)
	return b


func _other_entry(fm: OnlineFakes.FakeMatch) -> Dictionary:
	# A legal shot for whoever's turn it is now.
	return AiPlayer.next_action(fm.replay.state, fm.replay.state.current_tank)


# --- start and the display ------------------------------------------------------------------------------------------

func test_it_shows_the_match_in_its_current_state() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	var b: OnlineBattleController = _battle(fm)
	await settle()
	assert_eq(b.get_state().phase, SimConstants.PHASE_AIM)
	assert_eq(b.get_state().current_tank, fm.replay.state.current_tank)
	assert_ne(b.get_state(), fm.state, "the display has its own copy")
	assert_eq(b.get_display_replay().count, fm.replay.count)
	assert_eq(Simulation.fingerprint(b.get_state()), fm.replay.fingerprint())


func test_the_names_of_the_seats_label_the_tanks() -> void:
	var b: OnlineBattleController = _battle(_aim_match(true))
	await settle()
	assert_eq(PlayerNames.label(0), "HANA")
	assert_eq(PlayerNames.label(1), "ANNA")
	assert_true(b.is_cpu_tank(2))
	assert_false(b.is_cpu_tank(0))


func test_nothing_touches_the_local_autosave() -> void:
	var path: String = "user://test_online_battle_autosave.crtl"
	BattleConfig.autosave_path = path
	var b: OnlineBattleController = _battle(_aim_match(true))
	await settle()
	assert_eq(b.get_autosave_path(), "")
	assert_false(b.autosave_now())


# --- input only on my turn --------------------------------------------------------------------------------------------

func test_the_controls_are_on_when_it_is_my_turn() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	var b: OnlineBattleController = _battle(fm)
	await settle()
	assert_true(fm.is_my_turn())
	assert_true(b.may_act())
	assert_false(b.get_hud().is_controls_locked())
	assert_false(b.is_busy())


func test_the_controls_are_off_while_an_opponent_plays_and_the_pill_says_who() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(false)
	var b: OnlineBattleController = _battle(fm)
	await settle()
	assert_false(b.may_act())
	assert_true(b.get_hud().is_controls_locked())
	assert_eq(b.submit_action({"kind": "pass", "tank": b.get_state().current_tank}), "busy")
	var who: String = PlayerNames.label(b.get_state().current_tank)
	assert_eq(b.get_online_overlay().connection_text(), "Waiting for %s" % who)
	assert_eq(b.get_online_overlay().get_glyph_kind(), StatusGlyph.Kind.RING)
	assert_eq(fm.sc.count("submit_many"), 0)


func test_a_move_for_a_tank_that_is_not_mine_is_refused() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	var b: OnlineBattleController = _battle(fm)
	await settle()
	var theirs: int = 1 if fm.my_seats.has(0) else 0
	assert_eq(b._submit_now({"kind": "pass", "tank": theirs}), "not_your_seat")
	assert_eq(fm.sc.count("submit_many"), 0)


func test_firing_sends_one_action_and_the_entry_comes_back_through_the_log() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	var b: OnlineBattleController = _battle(fm)
	await settle()
	var me: int = fm.replay.state.current_tank
	var turn_before: int = b.get_state().turn_number
	b.set_aim(450, 600)
	assert_eq(b.fire_current(), "")
	await settle(4)
	assert_eq(fm.sc.count("submit_many"), 1)
	var sent: Dictionary = (fm.sc.last("submit_many")["args"][0] as Array)[0]
	assert_eq(sent["kind"], "fire")
	assert_eq(sent["tank"], me)
	assert_eq(sent["angle"], 450)
	assert_eq(sent["power"], 600)
	assert_eq(b.get_display_replay().count, fm.replay.count, "the display caught up with the log")
	assert_gt(b.get_state().turn_number, turn_before)
	assert_eq(Simulation.fingerprint(b.get_state()), fm.replay.fingerprint(), "same state as the match")


func test_while_a_move_is_being_sent_the_controls_stay_off() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	fm.hold_submit = true
	var b: OnlineBattleController = _battle(fm)
	await settle()
	b.fire_current()
	assert_true(b.is_sending())
	assert_true(b.is_busy())
	assert_eq(b.fire_current(), "busy", "a second tap does nothing")
	await settle(4)
	assert_false(b.is_sending())


func test_a_refused_move_shows_why_and_unlocks_again() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	var b: OnlineBattleController = _battle(fm)
	await settle()
	fm.fail_next = NetResult.failure(NetError.Code.ILLEGAL_ACTION, "bad_power")
	b.set_aim(450, 600)
	b.fire_current()
	await settle(3)
	assert_string_contains(b.get_toast().get_text(), "Power")
	assert_true(b.may_act(), "still my turn: the player can try again")
	assert_false(b.is_busy())


func test_an_offline_failure_asks_to_try_again() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	var b: OnlineBattleController = _battle(fm)
	await settle()
	fm.fail_next = NetResult.failure(NetError.Code.OFFLINE, "offline")
	b.set_aim(450, 600)
	b.fire_current()
	await settle(3)
	assert_string_contains(b.get_toast().get_text(), "could not be sent")
	assert_true(b.may_act())


func test_after_my_shot_the_next_turn_is_not_mine_unless_the_log_says_so() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true, [OnlineFakes.human_seat(ME, "HANA"), OnlineFakes.human_seat(OTHER, "ANNA")])
	var b: OnlineBattleController = _battle(fm)
	await settle()
	b.set_aim(450, 600)
	b.fire_current()
	await settle(4)
	assert_false(b.may_act(), "ANNA is next")
	assert_true(b.get_hud().is_controls_locked())


# --- opponents and CPUs from the log ---------------------------------------------------------------------------------

func test_an_opponents_shot_plays_from_the_log_and_the_turn_comes_back_to_me() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(false, [OnlineFakes.human_seat(ME, "HANA"), OnlineFakes.human_seat(OTHER, "ANNA")])
	var b: OnlineBattleController = _battle(fm)
	await settle()
	assert_false(b.may_act())
	fm.push_remote([_other_entry(fm)])
	await settle(4)
	assert_eq(b.get_display_replay().count, fm.replay.count)
	assert_eq(b.queue_size(), 0)
	assert_true(b.may_act(), "back to me")
	assert_false(b.get_hud().is_controls_locked())


func test_cpu_turns_play_back_from_the_log_without_asking_the_ai_locally() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true, [OnlineFakes.human_seat(ME, "HANA"), OnlineFakes.cpu_seat(2, "CPU")])
	var b: OnlineBattleController = _battle(fm)
	await settle()
	var before: int = b.get_state().turn_number
	b.set_aim(450, 600)
	b.fire_current()
	await settle(6)
	assert_gt(b.get_state().turn_number, before + 1, "the CPU's turn was in the same write")
	assert_eq(b.cpu_fallbacks, 0)
	assert_false(b.get_cpu_driver().is_active())
	assert_eq(b.get_display_replay().count, fm.replay.count)


func test_a_computers_turn_shows_its_banner_and_locks_the_controls() -> void:
	var seats: Array = [OnlineFakes.cpu_seat(3, "CPU"), OnlineFakes.human_seat(ME, "HANA")]
	var fm: OnlineFakes.FakeMatch = OnlineFakes.match_for(ME, seats)  # the first round starts with tank 0
	# History: HANA shopped, the CPU shopped; the batch writer has not yet appended the CPU's turn.
	fm.replay.apply_entry({"kind": "auto_shop", "tank": 0, "level": 3})
	fm.replay.apply_entry({"kind": "ready", "tank": 1})
	fm._turn_raw = {"tank": 0, "uid": "cpu", "deadline": fm.fixed_now + 1000, "index": 1}
	var b: OnlineBattleController = _battle(fm)
	await settle()
	assert_true(b.is_cpu_tank(b.get_state().current_tank))
	assert_true(b.is_busy())
	assert_false(b.get_cpu_driver().is_active(), "the log decides, not a local driver")
	fm.push_remote([{"kind": "auto", "tank": 0, "level": 3}])
	await settle(5)
	assert_eq(b.get_display_replay().count, fm.replay.count, "the CPU's turn played from its log entry")
	assert_eq(b.cpu_fallbacks, 0)


func test_a_burst_of_entries_plays_in_order_and_ends_in_the_same_state() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(false, [OnlineFakes.human_seat(ME, "HANA"), OnlineFakes.human_seat(OTHER, "ANNA")])
	var b: OnlineBattleController = _battle(fm, false)
	b.set_speed(10.0)
	await settle()
	for i: int in range(3):
		var e: Dictionary = AiPlayer.next_action(fm.replay.state, fm.replay.state.current_tank)
		fm.push_remote([e])
	assert_gt(b.queue_size(), 0, "entries wait while an animation runs")
	await wait_seconds(6.0)
	assert_eq(b.queue_size(), 0)
	assert_eq(b.get_display_replay().count, fm.replay.count)
	assert_eq(Simulation.fingerprint(b.get_state()), fm.replay.fingerprint())
	assert_eq(b.mismatch_count, 0, "the picture matched the state after every timeline")


func test_catch_up_entries_play_instantly() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(false, [OnlineFakes.human_seat(ME, "HANA"), OnlineFakes.human_seat(OTHER, "ANNA")])
	var b: OnlineBattleController = _battle(fm, false)
	await settle()
	var entries: Array = []
	var probe: NetReplay = fm.replay.fork()
	for i: int in range(4):
		var e: Dictionary = AiPlayer.next_action(probe.state, probe.state.current_tank)
		entries.append(e)
		probe.apply_entry(e)
	fm.push_remote(entries, true)
	assert_eq(b.queue_size(), 0, "a reconnect's history is applied at once")
	assert_eq(b.get_display_replay().count, fm.replay.count)
	assert_false(b._playing)


func test_a_large_backlog_is_played_instantly_until_it_is_short() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(false, [OnlineFakes.human_seat(ME, "HANA"), OnlineFakes.human_seat(OTHER, "ANNA")])
	var b: OnlineBattleController = _battle(fm, false)
	await settle()
	b._playing = true  # an animation is running while the entries arrive
	var start: int = b.get_display_replay().count
	for i: int in range(9):
		fm.push_remote([AiPlayer.next_action(fm.replay.state, fm.replay.state.current_tank)])
	assert_eq(b.queue_size(), 9)
	b._playing = false
	b._pump()
	assert_eq(b.queue_size(), OnlineBattleController.BACKLOG_INSTANT - 1, "the long backlog was skipped through at once")
	assert_eq(b.get_display_replay().count, start + 4)


func test_entries_seen_twice_are_ignored() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(false, [OnlineFakes.human_seat(ME, "HANA"), OnlineFakes.human_seat(OTHER, "ANNA")])
	var b: OnlineBattleController = _battle(fm)
	await settle()
	fm.push_remote([AiPlayer.next_action(fm.replay.state, fm.replay.state.current_tank)])
	await settle(3)
	var count: int = b.get_display_replay().count
	b._on_entry(count - 1, {"catch_up": false})
	assert_eq(b.get_display_replay().count, count)
	assert_eq(b.queue_size(), 0)


func test_a_player_who_left_is_a_computer_from_then_on() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	var b: OnlineBattleController = _battle(fm)
	await settle()
	var theirs: int = 1 if fm.my_seats.has(0) else 0
	fm.replace_with_cpu(theirs)
	assert_true(b.is_cpu_tank(theirs))
	assert_eq(b.get_state().settings.controllers[theirs], 2, "the display state knows the level too")


# --- timeline merging and shop batches (pure) ------------------------------------------------------------------------

func test_timeline_of_shifts_later_steps_and_skips_shop_steps() -> void:
	var steps: Array = [
		{"action": {"kind": "buy"}, "events": [{"type": "money", "tick": 0}] as Array[Dictionary]},
		{"action": {"kind": "use_item"}, "events": [{"type": "shield_on", "tick": 0}, {"type": "x", "tick": 10}] as Array[Dictionary]},
		{"action": {"kind": "fire"}, "events": [{"type": "fire", "tick": 0}, {"type": "projectile", "tick": 4}] as Array[Dictionary]},
	]
	var out: Array[Dictionary] = OnlineBattleController.timeline_of(steps)
	assert_eq(out.size(), 4, "the buy has nothing to show")
	assert_eq(out[0]["tick"], 0)
	assert_eq(out[1]["tick"], 10)
	assert_eq(out[2]["tick"], 10 + OnlineBattleController.STEP_GAP_TICKS, "the shot starts after the shield")
	assert_eq(out[3]["tick"], 14 + OnlineBattleController.STEP_GAP_TICKS)
	assert_eq((steps[2]["events"] as Array[Dictionary])[0]["tick"], 0, "the log's own events are not changed")


func test_consecutive_equal_buys_are_merged_when_still_legal() -> void:
	var st: MatchState = Simulation.new_match(NetReplay.settings_from_meta(NetTestUtil.meta(_seats())))
	var acts: Array[Dictionary] = [
		{"kind": "buy", "tank": 0, "item": "pulse_missile", "qty": 1}, {"kind": "buy", "tank": 0, "item": "pulse_missile", "qty": 1},
		{"kind": "buy", "tank": 0, "item": "pulse_missile", "qty": 1}, {"kind": "ready", "tank": 0}]
	var out: Array[Dictionary] = OnlineBattleController.compact_shop_actions(acts, st)
	assert_eq(out.size(), 2)
	assert_eq(out[0]["qty"], 3)
	assert_eq(out[1]["kind"], "ready")


func test_a_merge_that_would_not_be_legal_keeps_the_original_list() -> void:
	var st: MatchState = Simulation.new_match(NetReplay.settings_from_meta(NetTestUtil.meta(_seats(), {"start_money": 0})))
	var acts: Array[Dictionary] = [{"kind": "ready", "tank": 0}]
	assert_eq(OnlineBattleController.compact_shop_actions(acts, st).size(), 1)


func test_failure_text_uses_the_simulations_words_for_refused_moves() -> void:
	assert_eq(OnlineBattleController.failure_text(NetResult.failure(NetError.Code.ILLEGAL_ACTION, "not_your_turn")), "Not your turn")
	assert_string_contains(OnlineBattleController.failure_text(NetResult.failure(NetError.Code.TIMEOUT, "timeout")), "could not be sent")
	assert_ne(OnlineBattleController.failure_text(NetResult.failure(NetError.Code.STALE, "contention")), "")


# --- the shop ------------------------------------------------------------------------------------------------------

func _shop_match() -> OnlineFakes.FakeMatch:
	var fm: OnlineFakes.FakeMatch = OnlineFakes.match_for(ME, [OnlineFakes.human_seat(ME, "HANA"), OnlineFakes.human_seat(OTHER, "ANNA"), OnlineFakes.cpu_seat(2, "CPU")])
	return fm


func test_a_match_starts_in_the_shop_for_this_phones_seat_only() -> void:
	var fm: OnlineFakes.FakeMatch = _shop_match()
	var b: OnlineBattleController = _battle(fm)
	await settle()
	assert_true(b.get_shop().is_showing_shop())
	assert_true(b.get_shop().is_online())
	assert_eq(b.get_shop().current_player(), 0)
	assert_false(b.get_hud().visible)
	assert_eq(fm.sc.count("submit_many"), 0, "nothing is sent while shopping")


func test_ready_sends_the_whole_visit_and_waits_for_the_others() -> void:
	var fm: OnlineFakes.FakeMatch = _shop_match()
	var b: OnlineBattleController = _battle(fm)
	await settle()
	var sess: Dictionary = {}
	b._shop_local_submit({"kind": "buy", "tank": 0, "item": "pulse_missile", "qty": 1})
	b._shop_local_submit({"kind": "buy", "tank": 0, "item": "pulse_missile", "qty": 1})
	b.get_shop()._on_ready()
	await settle(4)
	assert_eq(fm.sc.count("submit_many"), 1)
	var sent: Array = fm.sc.last("submit_many")["args"][0]
	assert_eq(sent.size(), 2, "the two buys became one, then READY")
	assert_eq((sent[0] as Dictionary)["qty"], 2)
	assert_eq((sent[1] as Dictionary)["kind"], "ready")
	assert_string_contains(b.get_online_overlay().waiting_text(), "Waiting for the others")
	assert_string_contains(b.get_online_overlay().waiting_sub_text(), "ANNA")
	assert_eq(fm.replay.state.tanks[0].stock_of("pulse_missile") > 0, true, "the match has the purchase")
	assert_not_null(sess)


func test_the_round_starts_when_the_last_ready_arrives() -> void:
	var fm: OnlineFakes.FakeMatch = _shop_match()
	var b: OnlineBattleController = _battle(fm)
	await settle()
	b.get_shop()._on_ready()
	await settle(4)
	assert_eq(b.get_state().phase, SimConstants.PHASE_SHOP)
	fm.push_remote([{"kind": "ready", "tank": 1}])
	await settle(5)
	assert_eq(b.get_state().phase, SimConstants.PHASE_AIM)
	assert_true(b.get_hud().visible)
	assert_eq(b.get_online_overlay().waiting_text(), "", "the waiting text is gone")
	assert_eq(b.get_display_replay().count, fm.replay.count)


func test_a_failed_shop_send_reopens_the_shop() -> void:
	var fm: OnlineFakes.FakeMatch = _shop_match()
	var b: OnlineBattleController = _battle(fm)
	await settle()
	fm.fail_next = NetResult.failure(NetError.Code.OFFLINE, "offline")
	b.get_shop()._on_ready()
	await settle(4)
	assert_true(b.get_shop().is_showing_shop(), "the player can try again")


func test_a_phone_with_two_seats_shops_one_after_the_other_with_a_hand_over() -> void:
	var fm: OnlineFakes.FakeMatch = OnlineFakes.match_for(ME, [OnlineFakes.human_seat(ME, "HANA"), OnlineFakes.human_seat(ME, "HANA 2"), OnlineFakes.human_seat(OTHER, "ANNA")])
	var b: OnlineBattleController = _battle(fm)
	await settle()
	assert_true(b.get_shop().is_showing_handover())
	assert_eq(b.get_shop().current_player(), 0)
	b.get_shop()._on_continue()
	b.get_shop()._on_ready()
	assert_true(b.get_shop().is_showing_handover(), "the second seat gets its own hand-over")
	assert_eq(b.get_shop().current_player(), 1)
	b.get_shop()._on_continue()
	b.get_shop()._on_ready()
	await settle(4)
	var sent: Array = fm.sc.last("submit_many")["args"][0]
	assert_eq(sent.size(), 2, "both seats' READY in one update")


# --- connection, timer ----------------------------------------------------------------------------------------------

func test_the_indicator_follows_the_connection() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	var b: OnlineBattleController = _battle(fm)
	await settle()
	var o: OnlineOverlay = b.get_online_overlay()
	assert_eq(o.connection_text(), "LIVE")
	assert_eq(o.get_glyph_kind(), StatusGlyph.Kind.DOT)
	fm.set_connection_state(OnlineMatch.Connection.RECONNECTING)
	assert_eq(o.connection_text(), "Reconnecting…")
	assert_eq(o.get_glyph_kind(), StatusGlyph.Kind.BROKEN)
	fm.set_connection_state(OnlineMatch.Connection.OFFLINE)
	assert_eq(o.connection_text(), "Offline, actions queued")
	assert_eq(o.get_glyph_kind(), StatusGlyph.Kind.CROSS)
	fm.set_connection_state(OnlineMatch.Connection.LIVE)
	assert_eq(o.connection_text(), "LIVE")


func test_every_state_has_its_own_shape() -> void:
	var o := OnlineOverlay.new()
	add_child_autofree(o)
	var kinds: Array[int] = []
	for c: int in [OnlineOverlay.Conn.LIVE, OnlineOverlay.Conn.WAITING, OnlineOverlay.Conn.RECONNECTING, OnlineOverlay.Conn.OFFLINE]:
		o.set_connection(c, "ANNA")
		kinds.append(o.get_glyph_kind())
	for i: int in range(kinds.size()):
		for j: int in range(i + 1, kinds.size()):
			assert_ne(kinds[i], kinds[j], "colour is never the only cue")


func test_the_live_timer_ring_counts_down_with_the_number_in_it() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	var b: OnlineBattleController = _battle(fm)
	await settle()
	var ring: TurnRing = b.get_online_overlay().get_ring()
	assert_true(ring.visible)
	assert_eq(ring.shown_text(), "60")
	fm._turn_raw["liveDeadline"] = fm.fixed_now + 7500
	await settle(2)
	assert_eq(ring.shown_text(), "8")
	assert_eq(ring.ring_color(), NeonPalette.WARN)
	fm._turn_raw["liveDeadline"] = fm.fixed_now + 2000
	await settle(2)
	assert_eq(ring.ring_color(), NeonPalette.BAD)


func test_no_ring_without_a_live_timer() -> void:
	var seats: Array = [OnlineFakes.human_seat(ME, "HANA"), OnlineFakes.human_seat(OTHER, "ANNA")]
	var scratch: NetReplay = NetReplay.create(NetTestUtil.meta(seats, {}, {"liveSec": 0}))
	var fm: OnlineFakes.FakeMatch = OnlineFakes.match_for(ME, seats, {}, {"liveSec": 0})
	_ready_all(fm.replay)
	fm._set_stored_turn(fm.replay.expected_turn())
	var b: OnlineBattleController = _battle(fm)
	await settle()
	assert_false(b.get_online_overlay().get_ring().visible)
	assert_not_null(scratch)


func test_an_opponent_who_is_away_is_named_under_the_indicator() -> void:
	var seats: Array = [OnlineFakes.human_seat(OTHER, "ANNA"), OnlineFakes.human_seat(ME, "HANA")]
	var fm: OnlineFakes.FakeMatch = OnlineFakes.match_for(ME, seats)
	_ready_all(fm.replay)
	fm._set_stored_turn(fm.replay.expected_turn())
	fm.online_uids[OTHER] = false
	var b: OnlineBattleController = _battle(fm)
	await settle()
	b._refresh_online_ui()
	assert_eq(b.get_online_overlay().waiting_text(), "Waiting for ANNA…")
	assert_string_contains(b.get_online_overlay().waiting_sub_text(), "ANNA is away")
	fm.online_uids[OTHER] = true
	b._refresh_online_ui()
	assert_eq(b.get_online_overlay().waiting_text(), "", "online: the indicator alone says it")


# --- quick messages --------------------------------------------------------------------------------------------------

func test_the_message_button_opens_the_eight_presets() -> void:
	var b: OnlineBattleController = _battle(_aim_match(true))
	await settle()
	b.get_message_button().pressed.emit()
	var picker: MessagePicker = b.get_online_overlay().get_picker()
	assert_true(picker.is_open())
	for i: int in range(8):
		assert_not_null(picker.get_button(i))
	assert_eq(MessageDefs.COUNT, NetProtocol.MSG_COUNT)
	assert_gte(picker.get_button(0).custom_minimum_size.y, UiScale.touch() - 0.01)


func test_choosing_a_message_sends_it_as_my_seat_and_starts_the_cooldown() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	var b: OnlineBattleController = _battle(fm)
	await settle()
	var picker: MessagePicker = b.get_online_overlay().get_picker()
	picker.open()
	picker.get_button(3).pressed.emit()
	await settle(2)
	assert_eq(fm.sent_messages.size(), 1)
	assert_eq(fm.sent_messages[0]["msg"], 3)
	assert_eq(fm.sent_messages[0]["seat"], fm.replay.state.current_tank)
	assert_true(picker.is_cooling_down())
	picker.open()
	assert_true(picker.get_button(4).disabled)
	assert_string_contains(picker.get_caption_text(), "Next message in")
	picker.choose(4)
	await settle(2)
	assert_eq(fm.sent_messages.size(), 1, "no second message inside the cooldown")


func test_the_cooldown_ends_after_three_seconds() -> void:
	var p := MessagePicker.new()
	add_child_autofree(p)
	p.start_cooldown(0.2)
	await wait_seconds(0.4)
	assert_false(p.is_cooling_down())
	p.open()
	assert_false(p.get_button(0).disabled)


func test_a_received_message_shows_a_bubble_over_the_sender_for_three_seconds() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	var b: OnlineBattleController = _battle(fm)
	await settle()
	fm.message_received.emit(1, 0, OTHER)
	var o: OnlineOverlay = b.get_online_overlay()
	assert_eq(o.bubble_count(), 1)
	assert_eq(o.bubble_for(1).get_text(), "Nice shot!")
	assert_eq(MessageDefs.BUBBLE_SECONDS, 3.0)
	var bubble: MessageBubble = o.bubble_for(1)
	assert_true(bubble.tick(2.9), "still there")
	assert_false(bubble.tick(0.2), "gone after three seconds")


func test_an_emote_bubble_draws_an_icon_instead_of_text() -> void:
	var b: OnlineBattleController = _battle(_aim_match(true))
	await settle()
	b.get_online_overlay().show_bubble(0, 5, Color.WHITE)
	assert_true(b.get_online_overlay().bubble_for(0).is_emote())
	assert_eq(b.get_online_overlay().bubble_for(0).get_text(), "")
	assert_eq(MessageDefs.text_of(5), "Laughing", "the icon has a spoken name")


func test_a_muted_players_bubbles_are_hidden() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	var b: OnlineBattleController = _battle(fm)
	await settle()
	OnlineHub.set_muted(OTHER, true)
	fm.message_received.emit(1, 2, OTHER)
	assert_eq(b.get_online_overlay().bubble_count(), 0)
	OnlineHub.set_muted(OTHER, false)
	fm.message_received.emit(1, 2, OTHER)
	assert_eq(b.get_online_overlay().bubble_count(), 1)


func test_the_mute_list_is_saved() -> void:
	OnlineHub.set_muted("uidX", true)
	assert_true(FileAccess.file_exists(PREFS))
	SettingsStore.online_muted = PackedStringArray()
	SettingsStore.load_into(PREFS)
	assert_true(OnlineHub.is_muted("uidX"))


func test_a_rate_limited_message_shows_a_toast() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	var b: OnlineBattleController = _battle(fm)
	await settle()
	fm.fail_next = NetResult.failure(NetError.Code.RATE_LIMITED, "rate_limited")
	b._on_message_chosen(1)
	await settle(2)
	assert_string_contains(b.get_toast().get_text(), "Slow down")


# --- dispute, ended match, protocol -------------------------------------------------------------------------------------

func test_a_dispute_stops_play_with_a_full_screen_message_and_leave() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	var b: OnlineBattleController = _battle(fm)
	await settle()
	fm.trigger_dispute("fingerprint_mismatch")
	assert_true(b.get_notice().is_open())
	assert_eq(b.get_notice().get_title_text(), "MATCH DISPUTED")
	assert_string_contains(b.get_notice().get_text(), "fingerprint_mismatch")
	assert_false(b.may_act())
	assert_true(b.is_busy())
	var ids: PackedStringArray = b.get_notice().button_ids()
	assert_true(ids.has("leave"))
	b.get_notice().get_notice_button("leave").pressed.emit()
	assert_eq(OnlineHub.last_scene(), OnlineHub.ONLINE_SCENE)
	assert_eq(fm.connection, OnlineMatch.Connection.CLOSED, "the match was closed on the way out")


func test_only_the_host_can_end_a_disputed_match_for_everyone() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	fm.meta["hostUid"] = fm.uid
	var host: OnlineBattleController = _battle(fm)
	await settle()
	fm.trigger_dispute("bad_entry")
	assert_true(host.get_notice().button_ids().has("end"))
	var fm2: OnlineFakes.FakeMatch = _aim_match(true)
	fm2.meta["hostUid"] = "someoneElse"
	var guest: OnlineBattleController = _battle(fm2)
	await settle()
	fm2.trigger_dispute("bad_entry")
	assert_false(guest.get_notice().button_ids().has("end"))


func test_a_match_that_is_already_disputed_when_opened_shows_the_message() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	fm.replay.disputed = true
	fm.replay.dispute_reason = "history_changed"
	var b: OnlineBattleController = _battle(fm)
	await settle()
	assert_true(b.get_notice().is_open())


func test_an_abandoned_match_says_it_ended() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	var b: OnlineBattleController = _battle(fm)
	await settle()
	fm.status = NetProtocol.STATUS_ABANDONED
	fm.status_changed.emit(fm.status)
	assert_eq(b.get_notice().get_title_text(), "MATCH ENDED")
	assert_false(b.may_act())


func test_a_match_of_another_version_found_by_a_background_write_asks_for_an_update() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	var b: OnlineBattleController = _battle(fm)
	await settle()
	fm.failed.emit(NetError.Code.PROTOCOL_MISMATCH, "protocol_mismatch")
	assert_eq(b.get_notice().get_title_text(), "PLEASE UPDATE THE GAME")


# --- leaving, pause -----------------------------------------------------------------------------------------------------

func test_the_pause_menu_is_online_and_never_pauses_the_game() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	var b: OnlineBattleController = _battle(fm)
	await settle()
	b.open_pause()
	assert_true(b.is_paused())
	assert_false(get_tree().paused, "the network keeps running behind the menu")
	var p: PauseOverlay = b.get_pause_overlay()
	assert_false(p.find_child("Restart", true, false).visible)
	assert_eq(p.get_quit_button().text, "BACK TO ONLINE")
	assert_true(p.get_leave_button().get_parent().visible)
	assert_true(p.get_players_button().visible)


func test_back_to_online_keeps_the_match_and_closes_the_screen_side() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	var b: OnlineBattleController = _battle(fm)
	await settle()
	b.quit_to_title()
	assert_eq(OnlineHub.last_scene(), OnlineHub.ONLINE_SCENE)
	assert_eq(_net.sc.count("leave"), 0, "nothing is given up")
	assert_false(fm.abandoned)


func test_leave_match_asks_then_gives_the_seats_up() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	fm.meta["hostUid"] = "other"
	var b: OnlineBattleController = _battle(fm)
	await settle()
	b.ask_leave()
	assert_true(b.get_confirm().is_open())
	assert_string_contains(b.get_confirm().get_message_text(), "played by the computer")
	b.get_confirm().get_yes_button().pressed.emit()
	await settle(3)
	assert_eq(_net.sc.last("leave")["args"], ["match1"])
	assert_eq(OnlineHub.last_scene(), OnlineHub.ONLINE_SCENE)
	assert_false(b.get_pause_overlay().get_end_button().visible, "a guest cannot end the match for everyone")


func test_the_host_can_end_the_match_for_everyone_after_a_question() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	fm.meta["hostUid"] = fm.uid
	var b: OnlineBattleController = _battle(fm)
	await settle()
	b.open_pause()
	assert_true(b.get_pause_overlay().get_end_button().visible)
	b.ask_end()
	assert_string_contains(b.get_confirm().get_message_text(), "End this match for everyone")
	b.get_confirm().get_yes_button().pressed.emit()
	await settle(3)
	assert_true(fm.abandoned)
	assert_eq(OnlineHub.last_scene(), OnlineHub.ONLINE_SCENE)


func test_cancelling_the_leave_question_stays_in_the_match() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	var b: OnlineBattleController = _battle(fm)
	await settle()
	b.ask_leave()
	b.get_confirm().get_no_button().pressed.emit()
	await settle()
	assert_eq(_net.sc.count("leave"), 0)
	assert_eq(OnlineHub.last_scene(), "")


func test_the_players_list_opens_the_player_menu() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match(true)
	var b: OnlineBattleController = _battle(fm)
	await settle()
	b.open_players()
	var panel: PlayersPanel = b.get_players_panel()
	assert_true(panel.is_open())
	assert_eq(panel.row_count(), 3)
	var theirs: int = 1 if fm.my_seats.has(0) else 0
	(panel.get_row(theirs).find_child("Name", true, false) as Button).pressed.emit()
	assert_true(b.get_player_menu().is_open())
	assert_eq(b.get_player_menu().player_uid(), OTHER if theirs == 1 else ME)
	assert_true(b.get_player_menu().get_mute_button().visible, "in a match a player can be muted")
	assert_null(panel.get_row(2).find_child("Name", true, false) as Button, "a computer has no menu")


# --- the end of the match -------------------------------------------------------------------------------------------------

func _finished_match_but_one() -> Array:
	var seats: Array = [OnlineFakes.human_seat(ME, "HANA"), OnlineFakes.human_seat(OTHER, "ANNA")]
	var scratch: NetReplay = NetReplay.create(NetTestUtil.meta(seats))
	var log: Array[Dictionary] = NetTestUtil.play_through(scratch, 600)
	var entries: Array = []
	for item: Dictionary in log:
		entries.append(item["entry"])
	return [seats, entries]


func test_the_final_result_offers_back_to_online_and_no_new_match() -> void:
	var made: Array = _finished_match_but_one()
	var seats: Array = made[0]
	var entries: Array = made[1]
	var fm: OnlineFakes.FakeMatch = OnlineFakes.match_for(ME, seats)
	for i: int in range(entries.size() - 1):
		fm.replay.apply_entry(entries[i] as Dictionary)
	fm._set_stored_turn(fm.replay.expected_turn())
	var b: OnlineBattleController = _battle(fm)
	await settle()
	fm.push_remote([entries[entries.size() - 1]])
	await settle(6)
	assert_true(b.get_match_overlay().is_open(), "the normal results show first")
	assert_false(b.get_match_overlay().get_new_match_button().visible)
	assert_eq(b.get_match_overlay().get_title_button().text, "BACK TO ONLINE")
	b.get_match_overlay().get_title_button().pressed.emit()
	assert_eq(OnlineHub.last_scene(), OnlineHub.ONLINE_SCENE)
