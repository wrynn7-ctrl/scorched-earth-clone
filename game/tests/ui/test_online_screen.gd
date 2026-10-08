extends OnlineTestBase
## The Online home (ARCHITECTURE section 48) with a fake session: the connection gates (connecting, offline with RETRY,
## "please update the game"), the first-visit name setup and its NAME_REJECTED handling, the tabs, the locked HOST tab,
## and the routing of deep links and notification taps.

const SCREEN: String = "res://ui/online/online_screen.tscn"

var _net: OnlineFakes.FakeNet = null


func before_each() -> void:
	super.before_each()
	_net = OnlineFakes.net()
	OnlineHub.session = _net
	OnlineHub.set_services(PushService.new(PushFake.new()), GoogleSignIn.new(GoogleSignInFake.new()),
			ShareService.new(ShareFake.new()), DeepLinks.new(ShareFake.new()))


func _screen() -> OnlineScreen:
	var s: OnlineScreen = (load(SCREEN) as PackedScene).instantiate()
	add_child_autofree(s)
	return s


# --- gates --------------------------------------------------------------------------------------------------------

func test_a_signed_in_player_lands_on_the_matches_tab() -> void:
	var s: OnlineScreen = _screen()
	await settle()
	assert_eq(s.get_gate(), OnlineScreen.Gate.NONE)
	assert_eq(s.current_tab(), OnlineScreen.Tab.MATCHES)
	assert_true(s.get_tab_page(OnlineScreen.Tab.MATCHES).visible)
	assert_eq(_net.sc.count("start"), 1)


func test_offline_shows_retry_and_retry_signs_in() -> void:
	_net.start_result = NetResult.failure(NetError.Code.OFFLINE, "offline")
	_net.fake_account.profile = {}
	var s: OnlineScreen = _screen()
	await settle()
	assert_eq(s.get_gate(), OnlineScreen.Gate.OFFLINE)
	assert_string_contains(s.get_gate_text(), "internet connection")
	_net.start_result = null
	s._on_gate_primary()
	await settle()
	assert_eq(s.get_gate(), OnlineScreen.Gate.NONE, "the second try worked")
	assert_eq(_net.sc.count("start"), 2)


func test_a_protocol_mismatch_asks_for_an_update_and_offers_no_retry() -> void:
	_net.start_result = NetResult.failure(NetError.Code.PROTOCOL_MISMATCH, "protocol_mismatch", {"hostProtocol": 9, "yourProtocol": 1})
	var s: OnlineScreen = _screen()
	await settle()
	assert_eq(s.get_gate(), OnlineScreen.Gate.UPDATE)
	assert_string_contains(s.get_gate_text().to_lower(), "update")
	assert_false((s.find_child("Primary", true, false) as Button).visible, "nothing to retry")
	assert_true((s.find_child("Secondary", true, false) as Button).visible, "BACK stays")


func test_a_server_that_is_not_set_up_has_its_own_message() -> void:
	_net.start_result = NetResult.failure(NetError.Code.UNAVAILABLE, "not_configured")
	var s: OnlineScreen = _screen()
	await settle()
	assert_eq(s.get_gate(), OnlineScreen.Gate.SETUP)
	assert_string_contains(s.get_gate_message(), "isn't set up")


func test_the_tab_buttons_are_off_behind_a_gate() -> void:
	_net.start_result = NetResult.failure(NetError.Code.OFFLINE, "offline")
	var s: OnlineScreen = _screen()
	await settle()
	for i: int in range(4):
		assert_true(s.get_tab_button(i).disabled)


# --- the first visit: choosing a name -----------------------------------------------------------------------------

func test_the_first_visit_asks_for_a_name_and_sends_it_through_the_account() -> void:
	SettingsStore.online_named = false
	_net.fake_account.profile["name"] = ""
	var s: OnlineScreen = _screen()
	await settle()
	assert_eq(s.get_gate(), OnlineScreen.Gate.NAME)
	assert_true((s.find_child("NameField", true, false) as NameField).visible)
	var ok: bool = await s.submit_name("hana")
	assert_true(ok)
	assert_eq(_net.sc.last("set_name")["args"], ["hana"])
	assert_true(SettingsStore.online_named, "remembered")
	assert_eq(s.get_gate(), OnlineScreen.Gate.NONE)
	assert_eq(s.current_tab(), OnlineScreen.Tab.MATCHES)


func test_a_blocked_name_stays_on_the_gate_with_a_message() -> void:
	SettingsStore.online_named = false
	_net.fake_account.profile["name"] = ""
	var s: OnlineScreen = _screen()
	await settle()
	var ok: bool = await s.submit_name("fuck")
	assert_false(ok)
	assert_eq(s.get_gate(), OnlineScreen.Gate.NAME)
	assert_string_contains(s.get_gate_message(), "isn't allowed")
	assert_false(SettingsStore.online_named)


func test_an_empty_name_is_refused_with_its_own_message() -> void:
	SettingsStore.online_named = false
	_net.fake_account.profile["name"] = ""
	var s: OnlineScreen = _screen()
	await settle()
	var ok: bool = await s.submit_name("   ")
	assert_false(ok)
	assert_string_contains(s.get_gate_message(), "type a name")


func test_a_known_name_skips_the_name_setup() -> void:
	SettingsStore.online_named = true
	var s: OnlineScreen = _screen()
	await settle()
	assert_ne(s.get_gate(), OnlineScreen.Gate.NAME)


func test_a_profile_without_a_name_asks_again_even_when_the_flag_is_set() -> void:
	SettingsStore.online_named = true
	_net.fake_account.profile["name"] = ""
	var s: OnlineScreen = _screen()
	await settle()
	assert_eq(s.get_gate(), OnlineScreen.Gate.NAME)


# --- tabs ---------------------------------------------------------------------------------------------------------

func test_the_four_tabs_switch_pages() -> void:
	var s: OnlineScreen = _screen()
	await settle()
	s.show_tab(OnlineScreen.Tab.FRIENDS)
	assert_true(s.get_tab_page(OnlineScreen.Tab.FRIENDS).visible)
	assert_false(s.get_tab_page(OnlineScreen.Tab.MATCHES).visible)
	s.show_tab(OnlineScreen.Tab.JOIN)
	assert_true(s.get_tab_page(OnlineScreen.Tab.JOIN).visible)
	assert_true(s.get_tab_button(OnlineScreen.Tab.JOIN).button_pressed)


func test_a_free_player_sees_the_unlock_screen_with_the_host_reason_on_the_host_tab() -> void:
	Entitlement.reset_for_tests(false)
	var s: OnlineScreen = _screen()
	await settle()
	s.show_tab(OnlineScreen.Tab.HOST)
	assert_true(s.get_unlock_screen().is_open())
	assert_string_contains(s.get_unlock_screen().get_context_text(), "Hosting an online match needs the full game")
	assert_eq(s.current_tab(), OnlineScreen.Tab.MATCHES, "still on the page it came from")
	assert_true(LockBadge.of(s.get_tab_button(OnlineScreen.Tab.HOST)).visible, "a padlock marks the tab")


func test_a_full_player_opens_the_host_page() -> void:
	Entitlement.reset_for_tests(true)
	var s: OnlineScreen = _screen()
	await settle()
	s.show_tab(OnlineScreen.Tab.HOST)
	assert_false(s.get_unlock_screen().is_open())
	assert_eq(s.current_tab(), OnlineScreen.Tab.HOST)
	assert_false(LockBadge.of(s.get_tab_button(OnlineScreen.Tab.HOST)).visible)


func test_the_tab_buttons_show_counts() -> void:
	_net.fake_matches.list = [OnlineFakes.match_entry("m1", "playing", true, "ANNA"), OnlineFakes.match_entry("m2", "playing", true, "BO")]
	_net.fake_friends.requests = [OnlineFakes.request("u1", "CY")]
	var s: OnlineScreen = _screen()
	await settle()
	assert_eq(s.tab_text(OnlineScreen.Tab.MATCHES), "MATCHES (2)")
	s.show_tab(OnlineScreen.Tab.FRIENDS)
	await settle()
	assert_eq(s.tab_text(OnlineScreen.Tab.FRIENDS), "FRIENDS (1)")


# --- opening matches ----------------------------------------------------------------------------------------------

func test_opening_a_match_hands_it_to_the_battle_scene() -> void:
	var fm: OnlineFakes.FakeMatch = OnlineFakes.match_for(OnlineFakes.ME, [OnlineFakes.human_seat(OnlineFakes.ME, "ME"), OnlineFakes.cpu_seat()])
	_net.fake_match = fm
	var s: OnlineScreen = _screen()
	await settle()
	s.open_match("match1")
	await settle()
	assert_eq(OnlineHub.last_scene(), OnlineHub.BATTLE_SCENE)
	assert_eq(OnlineHub.match_to_play, fm)


func test_a_match_that_is_still_a_lobby_opens_its_lobby() -> void:
	_net.open_result = NetResult.failure(NetError.Code.NOT_STARTED, "not_started")
	var s: OnlineScreen = _screen()
	await settle()
	s.open_match("m7")
	await settle()
	assert_eq(OnlineHub.last_scene(), OnlineHub.LOBBY_SCENE)
	assert_eq(OnlineHub.lobby_to_show, "m7")


func test_a_match_of_another_version_asks_for_an_update() -> void:
	_net.open_result = NetResult.failure(NetError.Code.PROTOCOL_MISMATCH, "protocol_mismatch")
	var s: OnlineScreen = _screen()
	await settle()
	s.open_match("m7")
	await settle()
	assert_eq(s.get_gate(), OnlineScreen.Gate.UPDATE)


func test_a_failed_open_goes_back_to_the_pages_with_a_toast() -> void:
	_net.open_result = NetResult.failure(NetError.Code.PERMISSION, "not_a_member")
	var s: OnlineScreen = _screen()
	await settle()
	s.open_match("m7")
	await settle()
	assert_eq(s.get_gate(), OnlineScreen.Gate.NONE)
	assert_string_contains(s.get_toast().get_text(), "not in that match")


# --- deep links and notification taps -----------------------------------------------------------------------------

func test_a_join_link_while_the_screen_is_open_fills_the_join_tab() -> void:
	var s: OnlineScreen = _screen()
	await settle()
	OnlineHub.links._on_link("charredhorizons://join/K7M2QX")
	await settle()
	assert_eq(s.current_tab(), OnlineScreen.Tab.JOIN)
	assert_eq((s.get_tab_page(OnlineScreen.Tab.JOIN) as JoinTab).code(), "K7M2QX")


func test_a_join_link_that_started_the_game_is_followed_after_sign_in() -> void:
	OnlineHub.pending_join_code = "ABC234"
	var s: OnlineScreen = _screen()
	await settle()
	assert_eq(s.current_tab(), OnlineScreen.Tab.JOIN)
	assert_eq((s.get_tab_page(OnlineScreen.Tab.JOIN) as JoinTab).code(), "ABC234")
	assert_eq(OnlineHub.pending_join_code, "", "taken exactly once")


func test_a_notification_tap_opens_that_match() -> void:
	var fm: OnlineFakes.FakeMatch = OnlineFakes.match_for(OnlineFakes.ME, [OnlineFakes.human_seat(OnlineFakes.ME, "ME"), OnlineFakes.cpu_seat()])
	_net.fake_match = fm
	var s: OnlineScreen = _screen()
	await settle()
	OnlineHub.push._on_opened('{"type":"turn","matchId":"match1"}')
	await settle()
	assert_eq(_net.sc.last("open_match")["args"], ["match1"])
	assert_eq(OnlineHub.last_scene(), OnlineHub.BATTLE_SCENE)
	assert_not_null(s)


func test_a_tap_that_arrives_before_sign_in_waits_for_it() -> void:
	_net.start_result = NetResult.failure(NetError.Code.OFFLINE, "offline")
	var s: OnlineScreen = _screen()
	await settle()
	OnlineHub.push._on_opened('{"matchId":"abc"}')
	assert_eq(OnlineHub.pending_match_id, "abc", "kept until the pages show")
	assert_eq(_net.sc.count("open_match"), 0)
	assert_not_null(s)


func test_a_match_tap_wins_over_a_join_code() -> void:
	OnlineHub.pending_join_code = "ABC234"
	OnlineHub.pending_match_id = "m9"
	var route: Dictionary = OnlineHub.take_route()
	assert_eq(route, {"match": "m9"})
	assert_eq(OnlineHub.take_route(), {"join": "ABC234"})
	assert_eq(OnlineHub.take_route(), {})


func test_leaving_closes_the_session_and_goes_to_the_title() -> void:
	var s: OnlineScreen = _screen()
	await settle()
	s.go_back()
	assert_eq(OnlineHub.last_scene(), OnlineHub.TITLE_SCENE)
	assert_eq(_net.closed_count, 1)
