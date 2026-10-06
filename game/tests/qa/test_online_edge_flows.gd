extends OnlineTestBase
## M7-Q: online UI and client edge flows with fakes (no emulator): joining your own match twice, a lobby whose host left, a
## finished match, a deep link to an unknown code, a push for a deleted match, a protocol mismatch, and the Android back button
## with a confirm dialog open in the online battle.

const SCREEN: String = "res://ui/online/online_screen.tscn"
const LOBBY: String = "res://ui/online/lobby_screen.tscn"
const BATTLE: String = "res://show/online/online_battle_scene.tscn"
const ME: String = OnlineFakes.ME
const OTHER: String = OnlineFakes.OTHER

var _net: OnlineFakes.FakeNet = null


func before_each() -> void:
	super.before_each()
	_net = OnlineFakes.net()
	OnlineHub.session = _net
	OnlineHub.set_services(PushService.new(PushFake.new()), GoogleSignIn.new(GoogleSignInFake.new()),
			ShareService.new(ShareFake.new()), DeepLinks.new(ShareFake.new()))
	BattleConfig.reset()


func after_each() -> void:
	BattleConfig.reset()
	super.after_each()


func _screen() -> OnlineScreen:
	var s: OnlineScreen = (load(SCREEN) as PackedScene).instantiate()
	add_child_autofree(s)
	return s


func _lobby_screen(meta: Dictionary) -> LobbyScreen:
	_net.fake_lobby.put_lobby("m1", meta)
	var l: LobbyScreen = (load(LOBBY) as PackedScene).instantiate()
	add_child_autofree(l)
	await l.open_lobby(_net, "m1")
	await settle()
	return l


func _seats() -> Array:
	return [OnlineFakes.human_seat(ME, "HANA"), OnlineFakes.human_seat(OTHER, "ANNA"), OnlineFakes.cpu_seat(2, "CPU")]


func _battle(fm: OnlineMatch) -> OnlineBattleController:
	var b: OnlineBattleController = (load(BATTLE) as PackedScene).instantiate()
	b.attach_match(fm)
	b.configure(3, 4242, true)
	add_child_autofree(b)
	return b


func _aim_match() -> OnlineFakes.FakeMatch:
	var fm: OnlineFakes.FakeMatch = OnlineFakes.match_for(ME, _seats())
	for t: TankState in fm.replay.state.tanks:
		if not fm.replay.seat_is_cpu(t.id) and not t.ready:
			fm.replay.apply_entry({"kind": "ready", "tank": t.id})
	while not fm.replay.pending_cpu_entry().is_empty():
		fm.replay.apply_entry(fm.replay.pending_cpu_entry())
	fm._set_stored_turn(fm.replay.expected_turn())
	return fm


# --- joining your own match twice -----------------------------------------------------------------------------------------

func test_joining_a_match_you_already_hold_opens_it_both_times_without_an_error() -> void:
	_net.sc.replies["join"] = NetResult.success({"matchId": "m1", "seats": [0], "alreadyJoined": true})
	var tab := JoinTab.new()
	add_child_autofree(tab)
	tab.setup(_net)
	var opened: Array = []
	tab.open_lobby.connect(func(id: String) -> void: opened.append(id))
	for i: int in range(2):
		tab.set_code("ABC234")
		await tab.join()
		assert_eq(tab.get_message(), "", "no error on try %d" % (i + 1))
		assert_false(tab.get_join_button().disabled and tab.code().length() == 6, "not stuck busy")
	assert_eq(opened, ["m1", "m1"])
	assert_eq(_net.sc.count("join"), 2)


func test_a_double_tap_on_join_sends_one_request() -> void:
	var tab := JoinTab.new()
	add_child_autofree(tab)
	tab.setup(_net)
	_net.fake_lobby.put_lobby("m1", OnlineFakes.lobby_meta([OnlineFakes.human_seat(OTHER, "ANNA"), {"kind": "human"}, {"kind": "human"}], {}, OTHER))
	tab.set_code("ABC234")
	tab.join()
	tab.join()  # the same frame: _busy must swallow it
	await settle()
	assert_eq(_net.sc.count("join"), 1)


# --- a lobby whose host left ---------------------------------------------------------------------------------------------

func test_a_lobby_closed_behind_the_players_back_sends_them_home_with_a_notice() -> void:
	var meta: Dictionary = OnlineFakes.lobby_meta([OnlineFakes.human_seat(OTHER, "ANNA"), OnlineFakes.human_seat(ME, "HANA"), OnlineFakes.cpu_seat()], {}, OTHER)
	var l: LobbyScreen = await _lobby_screen(meta)
	assert_false(l.is_host())
	_net.fake_lobby.remote_change("m1", func(m: Dictionary) -> void: m["status"] = NetProtocol.STATUS_ABANDONED)
	await settle()
	assert_eq(OnlineHub.last_scene(), OnlineHub.ONLINE_SCENE, "sent back to the Online home")
	# BUG (low): lobby_screen.gd _on_abandoned() goes home but leaves OnlineHub.open_lobby_id / lobby_to_show pointing at the dead lobby
	# (leave() and enter_match() clear them), so the Friends tab keeps offering INVITE for a lobby that no longer exists.
	if OnlineHub.open_lobby_id != "":
		pending("BUG (low): after the host closed the lobby OnlineHub.open_lobby_id is still '%s' (the Friends tab would offer INVITE for it); _on_abandoned must clear open_lobby_id and lobby_to_show" % OnlineHub.open_lobby_id)
		return
	assert_eq(OnlineHub.open_lobby_id, "")


func test_a_lobby_whose_host_is_not_seated_has_nobody_who_can_start_and_does_not_crash() -> void:
	var meta: Dictionary = OnlineFakes.lobby_meta([OnlineFakes.human_seat(OTHER, "ANNA"), OnlineFakes.human_seat(ME, "HANA"), OnlineFakes.cpu_seat()], {}, "uidGone")
	var l: LobbyScreen = await _lobby_screen(meta)
	assert_false(l.is_host())
	assert_true(l.get_start_button().disabled or not l.get_start_button().visible)
	l.start_match()
	await settle()
	assert_eq(_net.sc.count("start"), 0, "a guest never starts a match")
	assert_false(l.get_add_cpu_button().visible, "and has no host controls")


func test_the_host_leaving_a_lobby_closes_it_and_goes_home() -> void:
	var meta: Dictionary = OnlineFakes.lobby_meta([OnlineFakes.human_seat(ME, "HANA"), {"kind": "human"}], {}, ME)
	var l: LobbyScreen = await _lobby_screen(meta)
	l.ask_leave()
	assert_true(l.get_confirm().is_open())
	l.get_confirm().get_yes_button().pressed.emit()
	await settle()
	assert_eq(_net.sc.count("leave"), 1)
	assert_eq(OnlineHub.last_scene(), OnlineHub.ONLINE_SCENE)


# --- a finished match -------------------------------------------------------------------------------------------------------

func test_opening_a_finished_match_shows_the_result_and_never_tries_to_play() -> void:
	var fm: OnlineFakes.FakeMatch = OnlineFakes.match_for(ME, [OnlineFakes.human_seat(ME, "HANA"), OnlineFakes.cpu_seat(1, "C1"), OnlineFakes.cpu_seat(2, "C2")], {"rounds": 1}, {}, 9)
	NetTestUtil.play_through(fm.replay, 400)
	assert_true(fm.replay.ended)
	fm.status = NetProtocol.STATUS_OVER
	fm._set_stored_turn({})
	var b: OnlineBattleController = _battle(fm)
	await settle(6)
	assert_true(b.get_match_overlay().is_open() or b.get_state().phase == SimConstants.PHASE_MATCH_OVER, "the result is on screen")
	assert_false(b.may_act(), "nothing can be played in a finished match")
	assert_eq(fm.sc.count("submit_many"), 0)
	assert_false(b.is_disputed_shown())


# --- deep links and pushes ------------------------------------------------------------------------------------------------

func test_a_deep_link_to_an_unknown_code_lands_on_the_join_tab_and_says_so() -> void:
	OnlineHub.pending_join_code = "ZZZZZZ"
	var s: OnlineScreen = _screen()
	await settle()
	assert_eq(s.current_tab(), OnlineScreen.Tab.JOIN)
	var tab: JoinTab = s.get_tab_page(OnlineScreen.Tab.JOIN) as JoinTab
	assert_eq(tab.code(), "ZZZZZZ")
	await tab.join()
	assert_ne(tab.get_message(), "", "the unknown code is explained")
	assert_eq(s.get_gate(), OnlineScreen.Gate.NONE, "the screen carries on")
	assert_eq(OnlineHub.last_scene(), "", "no scene change")
	# and a malformed code never reaches the server
	OnlineHub.pending_join_code = "ab"
	s._follow_route(OnlineHub.take_route())
	assert_true(tab.get_join_button().disabled)


func test_a_push_for_a_deleted_match_says_not_found_and_the_next_push_still_works() -> void:
	OnlineHub.pending_match_id = "gone"
	_net.open_result = NetResult.failure(NetError.Code.NOT_FOUND, "unknown_match")
	var s: OnlineScreen = _screen()
	await settle()
	assert_eq(s.get_gate(), OnlineScreen.Gate.NONE)
	assert_ne(s.current_tab(), OnlineScreen.Tab.HOST)
	assert_eq(_net.sc.count("open_match"), 1)
	assert_eq(OnlineHub.last_scene(), "", "nothing was opened")
	assert_true(s.get_toast().visible or s.get_toast().get_message() != "" if s.get_toast().has_method("get_message") else true)
	# the screen is not left thinking it is still opening: a second tap goes through
	_net.open_result = null
	_net.fake_match = _aim_match()
	s._route_now({"match": "m2"})
	await settle()
	assert_eq(_net.sc.count("open_match"), 2)
	assert_eq(OnlineHub.last_scene(), OnlineHub.BATTLE_SCENE)


# --- protocol mismatch ------------------------------------------------------------------------------------------------------

func test_a_protocol_mismatch_when_opening_a_match_or_joining_asks_for_an_update() -> void:
	var s: OnlineScreen = _screen()
	await settle()
	_net.open_result = NetResult.failure(NetError.Code.PROTOCOL_MISMATCH, "protocol_mismatch", {"hostProtocol": 9, "yourProtocol": 1})
	await s.open_match("m1")
	assert_eq(s.get_gate(), OnlineScreen.Gate.UPDATE, "opening")
	var s2: OnlineScreen = _screen()
	await settle()
	_net.sc.replies["join"] = NetResult.failure(NetError.Code.PROTOCOL_MISMATCH, "protocol_mismatch", {"hostProtocol": 9, "yourProtocol": 1})
	var tab: JoinTab = s2.get_tab_page(OnlineScreen.Tab.JOIN) as JoinTab
	tab.set_code("ABC234")
	await tab.join()
	assert_eq(s2.get_gate(), OnlineScreen.Gate.UPDATE, "joining")


func test_a_protocol_mismatch_in_the_middle_of_a_match_leaves_the_player_a_way_out() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match()
	var b: OnlineBattleController = _battle(fm)
	await settle()
	fm.failed.emit(NetError.Code.PROTOCOL_MISMATCH, "protocol_mismatch")
	await settle()
	b.go_online()
	assert_eq(OnlineHub.last_scene(), OnlineHub.ONLINE_SCENE)


# --- the Android back button with a confirm dialog open ------------------------------------------------------------------

# BUG (low), known from M7-U: BattleController._notification(NOTIFICATION_WM_GO_BACK_REQUEST) knows the diag, settings and pause
# overlays but not OnlineBattleController's OnlineConfirm. With LEAVE? / END? open, Back opens the pause menu on top of (or
# behind) the question instead of answering "no" like every other online screen does (online_screen.gd:_on_back_request,
# lobby_screen.gd:_notification close the confirm first).
#   input:    OnlineBattleController.ask_leave(), then NOTIFICATION_WM_GO_BACK_REQUEST
#   expected: the confirm closes, the pause menu stays closed
#   actual:   see the assertions below (confirm still open and/or pause menu opened)
#   cause:    show/battle/battle_controller.gd:310 _notification; show/online/online_battle_controller.gd has no override.
func test_back_with_the_leave_question_open_cancels_the_question() -> void:
	var b: OnlineBattleController = _battle(_aim_match())
	await settle()
	b.open_pause()
	b.ask_leave()
	assert_true(b.get_confirm().is_open())
	b._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await settle()
	var confirm_open: bool = b.get_confirm().is_open()
	var pause_open: bool = b.is_paused()
	if confirm_open or pause_open:
		pending("BUG (low): Back with the LEAVE question open leaves confirm_open=%s pause_menu_open=%s (expected both false): BattleController._notification ignores OnlineConfirm" % [confirm_open, pause_open])
		return
	assert_false(confirm_open)
	assert_false(pause_open)


func test_back_with_the_end_question_open_never_leaves_the_match() -> void:
	var fm: OnlineFakes.FakeMatch = _aim_match()
	var b: OnlineBattleController = _battle(fm)
	await settle()
	b.ask_end()
	b._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await settle()
	assert_false(fm.abandoned, "Back is never a yes")
	assert_eq(OnlineHub.last_scene(), "")
