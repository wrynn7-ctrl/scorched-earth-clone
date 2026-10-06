extends OnlineTestBase
## The pages of the Online home with a fake session: the match list (order, badges, taps, invites), Friends (code, add by
## code, requests, list actions, blocks), Join (code filtering, shared-phone seats) and Host (what a new lobby asks for).

var _net: OnlineFakes.FakeNet = null


func before_each() -> void:
	super.before_each()
	_net = OnlineFakes.net()
	OnlineHub.session = _net


func _tab(tab: OnlineTab) -> OnlineTab:
	add_child_autofree(tab)
	tab.setup(_net)
	tab.apply_scale()
	return tab


func _signals(tab: OnlineTab, name: String) -> Array:
	var got: Array = []
	tab.connect(name, func(a: Variant = null, _b: Variant = null) -> void: got.append(a))
	return got


# --- MATCHES ------------------------------------------------------------------------------------------------------

func _matches_with(list: Array) -> MatchesTab:
	_net.fake_matches.list = list
	var t: MatchesTab = _tab(MatchesTab.new()) as MatchesTab
	t.activate()
	await settle()
	return t


func test_matches_show_your_turn_first_then_waiting_then_finished() -> void:
	var t: MatchesTab = await _matches_with([
		OnlineFakes.match_entry("over1", "over", false, "OLD", 50),
		OnlineFakes.match_entry("wait1", "playing", false, "BO", 40),
		OnlineFakes.match_entry("turn1", "playing", true, "ANNA", 10),
		OnlineFakes.match_entry("lobby1", "lobby", false, "CY", 30),
	])
	var ids: Array[String] = []
	for r: RowLine in t.get_rows():
		ids.append(r.get_meta("match_id") as String)
	assert_eq(ids, ["turn1", "wait1", "lobby1", "over1"] as Array[String])


func test_a_row_shows_the_host_what_is_going_on_and_when() -> void:
	var t: MatchesTab = await _matches_with([OnlineFakes.match_entry("turn1", "playing", true, "ANNA", 1000000000 - 5 * 60000)])
	var row: RowLine = t.get_rows()[0]
	assert_eq((row.find_child("Title", true, false) as Label).text, "ANNA's match")
	var status: String = (row.find_child("Status", true, false) as Label).text
	assert_string_contains(status, "YOUR TURN")
	assert_string_contains(status, "5 min ago")
	assert_not_null(row.find_child("Glyph", true, false), "the your-turn dot is a shape, not only a colour")


func test_waiting_and_finished_rows_say_so_in_words() -> void:
	var t: MatchesTab = await _matches_with([
		OnlineFakes.match_entry("w", "playing", false, "BO"),
		OnlineFakes.match_entry("o", "over", false, "CY"),
		OnlineFakes.match_entry("a", "abandoned", false, "DI")])
	var texts: Array[String] = []
	for r: RowLine in t.get_rows():
		texts.append((r.find_child("Status", true, false) as Label).text)
	assert_string_contains(texts[0], "WAITING")
	assert_string_contains(texts[1], "FINISHED")
	assert_string_contains(texts[2], "ABANDONED")


func test_love_and_team_matches_get_a_badge() -> void:
	var love: Dictionary = OnlineFakes.lobby_meta([OnlineFakes.human_seat("a", "A"), OnlineFakes.human_seat("b", "B")], {"mode": 1})
	var teams: Dictionary = OnlineFakes.lobby_meta([OnlineFakes.human_seat("a", "A"), OnlineFakes.human_seat("b", "B"), OnlineFakes.cpu_seat(), OnlineFakes.cpu_seat()], {"teams": [0, 0, 1, 1]})
	var plain: Dictionary = OnlineFakes.lobby_meta([OnlineFakes.human_seat("a", "A"), OnlineFakes.human_seat("b", "B")])
	_net.fake_lobby.put_lobby("love1", love)
	_net.fake_lobby.put_lobby("teams1", teams)
	_net.fake_lobby.put_lobby("plain1", plain)
	var t: MatchesTab = await _matches_with([
		OnlineFakes.match_entry("love1", "playing", false, "A", 3),
		OnlineFakes.match_entry("teams1", "playing", false, "A", 2),
		OnlineFakes.match_entry("plain1", "playing", false, "A", 1)])
	await settle()
	var badges: Dictionary = {}
	for r: RowLine in t.get_rows():
		var holder: Node = r.find_child("Badges", true, false)
		var text: String = ""
		for b: Node in holder.get_children():
			text += (b.find_child("Text", true, false) as Label).text
		badges[r.get_meta("match_id")] = text
	assert_eq(badges["love1"], "LOVE")
	assert_eq(badges["teams1"], "TEAMS")
	assert_eq(badges["plain1"], "")


func test_tapping_a_running_match_opens_it_and_a_lobby_opens_its_lobby() -> void:
	var t: MatchesTab = await _matches_with([
		OnlineFakes.match_entry("run1", "playing", true, "ANNA", 9),
		OnlineFakes.match_entry("lob1", "lobby", false, "BO", 8)])
	var opened: Array = _signals(t, "open_match")
	var lobbies: Array = _signals(t, "open_lobby")
	t.get_rows()[0].tap()
	t.get_rows()[1].tap()
	assert_eq(opened, ["run1"])
	assert_eq(lobbies, ["lob1"])


func test_a_finished_match_can_be_dismissed() -> void:
	var t: MatchesTab = await _matches_with([OnlineFakes.match_entry("o", "over", false, "CY")])
	(t.get_rows()[0].find_child("Dismiss", true, false) as Button).pressed.emit()
	await settle()
	assert_eq(_net.sc.last("matches_dismiss")["args"], ["o"])
	assert_eq(t.get_rows().size(), 0)
	assert_not_null(t.get_empty_label(), "the empty hint shows again")


func test_the_page_reports_how_many_turns_wait_for_you() -> void:
	_net.fake_matches.list = [OnlineFakes.match_entry("a", "playing", true, "X"), OnlineFakes.match_entry("b", "playing", true, "Y"), OnlineFakes.match_entry("c", "playing", false, "Z")]
	var t: MatchesTab = _tab(MatchesTab.new()) as MatchesTab
	var counts: Array = _signals(t, "badge_changed")
	t.activate()
	await settle()
	assert_eq(counts.back(), 2)


func test_an_empty_list_says_how_to_get_a_match() -> void:
	var t: MatchesTab = await _matches_with([])
	assert_not_null(t.get_empty_label())
	assert_string_contains(t.get_empty_label().text, "No matches yet")


func test_invites_can_be_joined_or_dismissed_and_love_invites_hide_without_the_edition() -> void:
	_net.fake_lobby.put_lobby("inv1", OnlineFakes.lobby_meta([OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA"), {"kind": "human"}], {}, OnlineFakes.OTHER))
	_net.fake_lobby.metas["inv1"]["code"] = "XYZ789"
	_net.fake_friends.invites = [OnlineFakes.invite("inv1", "ANNA"), OnlineFakes.invite("inv2", "BO", "LOV234", 1)]
	var t: MatchesTab = await _matches_with([])
	assert_eq(t.get_invite_rows().size(), 1, "the love invite is hidden: this player has not found the Love Edition")
	var lobbies: Array = _signals(t, "open_lobby")
	(t.get_invite_rows()[0].find_child("Join", true, false) as Button).pressed.emit()
	await settle()
	assert_eq(_net.sc.last("join")["args"][0], "XYZ789")
	assert_eq(lobbies, ["inv1"])
	SettingsStore.love_found = true
	t.activate()
	await settle()
	assert_eq(t.visible_invites().size(), 1)


func test_dismissing_an_invite_removes_it() -> void:
	_net.fake_friends.invites = [OnlineFakes.invite("inv1", "ANNA")]
	var t: MatchesTab = await _matches_with([])
	(t.get_invite_rows()[0].find_child("Dismiss", true, false) as Button).pressed.emit()
	await settle()
	assert_eq(_net.sc.last("dismiss_invite")["args"], ["inv1"])
	assert_eq(t.get_invite_rows().size(), 0)


func test_joining_from_an_invite_with_another_version_asks_for_an_update() -> void:
	_net.sc.replies["join"] = NetResult.failure(NetError.Code.PROTOCOL_MISMATCH, "protocol_mismatch")
	_net.fake_friends.invites = [OnlineFakes.invite("inv1", "ANNA")]
	var t: MatchesTab = await _matches_with([])
	var updates: Array = _signals(t, "update_needed")
	(t.get_invite_rows()[0].find_child("Join", true, false) as Button).pressed.emit()
	await settle()
	assert_eq(updates.size(), 1)


func test_a_hosted_lobby_is_remembered_so_friends_can_be_invited() -> void:
	_net.fake_lobby.put_lobby("mine", OnlineFakes.lobby_meta([OnlineFakes.human_seat(OnlineFakes.ME, "ME"), {"kind": "human"}]))
	await _matches_with([OnlineFakes.match_entry("mine", "lobby", false, "ME")])
	await settle()
	assert_eq(OnlineHub.open_lobby_id, "mine")


# --- FRIENDS ------------------------------------------------------------------------------------------------------

func _friends_with(friends: Array = [], requests: Array = [], blocks: Array = []) -> FriendsTab:
	_net.fake_friends.friends = friends
	_net.fake_friends.requests = requests
	_net.fake_friends.blocks = blocks
	var t: FriendsTab = _tab(FriendsTab.new()) as FriendsTab
	t.activate()
	await settle()
	return t


func test_my_friend_code_is_shown_in_two_groups_and_copied() -> void:
	var t: FriendsTab = await _friends_with()
	assert_eq(t.get_code_text(), "ABCD 2345")
	var toasts: Array = _signals(t, "toast")
	t.copy_code()
	assert_eq(toasts, ["Code copied"])


func test_the_add_field_keeps_only_unambiguous_capitals_and_needs_eight() -> void:
	var t: FriendsTab = await _friends_with()
	t.get_add_field().text = "ab0o1i-cd"
	t.get_add_field().text_changed.emit("ab0o1i-cd")
	assert_eq(t.get_add_field().text, "ABCD")
	assert_true(t.get_add_button().disabled)
	t.get_add_field().set_code("efgh2345xyz")
	assert_eq(t.get_add_field().text, "EFGH2345", "at most eight")
	assert_false(t.get_add_button().disabled)


func test_adding_a_friend_by_code_reports_the_result() -> void:
	var t: FriendsTab = await _friends_with()
	t.get_add_field().set_code("EFGH2345")
	t.add_friend()
	await settle()
	assert_eq(_net.sc.last("send_request")["args"], ["EFGH2345"])
	assert_string_contains(t.get_add_message(), "Request sent to ANNA")
	assert_eq(t.get_add_field().text, "", "the field is cleared")


func test_adding_with_a_code_that_does_not_exist_says_so() -> void:
	_net.sc.replies["send_request"] = NetResult.failure(NetError.Code.NOT_FOUND, "unknown_code")
	var t: FriendsTab = await _friends_with()
	t.get_add_field().set_code("EFGH2345")
	t.add_friend()
	await settle()
	assert_string_contains(t.get_add_message(), "No match or player with that code")


func test_a_request_that_crosses_an_existing_one_becomes_a_friendship() -> void:
	_net.sc.replies["send_request"] = NetResult.success({"status": "friends", "name": "ANNA"})
	var t: FriendsTab = await _friends_with()
	t.get_add_field().set_code("EFGH2345")
	t.add_friend()
	await settle()
	assert_string_contains(t.get_add_message(), "now friends with ANNA")


func test_requests_are_accepted_or_declined() -> void:
	var t: FriendsTab = await _friends_with([], [OnlineFakes.request("u1", "ANNA"), OnlineFakes.request("u2", "BO")])
	assert_eq(t.rows_named("Request_").size(), 2)
	(t.rows_named("Request_u1")[0].find_child("Accept", true, false) as Button).pressed.emit()
	await settle()
	assert_eq(_net.sc.last("respond")["args"], ["u1", true])
	(t.rows_named("Request_u2")[0].find_child("Decline", true, false) as Button).pressed.emit()
	await settle()
	assert_eq(_net.sc.last("respond")["args"], ["u2", false])
	assert_eq(t.rows_named("Request_").size(), 0)


func test_the_friend_list_offers_invite_only_when_a_lobby_is_open() -> void:
	var t: FriendsTab = await _friends_with([OnlineFakes.friend("f1", "ANNA")])
	assert_null(t.rows_named("Friend_f1")[0].find_child("Invite", true, false))
	OnlineHub.open_lobby_id = "lobby1"
	t.activate()
	await settle()
	var inv: Button = t.rows_named("Friend_f1")[0].find_child("Invite", true, false) as Button
	assert_not_null(inv)
	inv.pressed.emit()
	await settle()
	assert_eq(_net.sc.last("invite")["args"], ["f1", "lobby1"])
	assert_eq((t.rows_named("Friend_f1")[0].find_child("Invite", true, false) as Button).text, "INVITED")


func test_removing_and_blocking_ask_first() -> void:
	var t: FriendsTab = await _friends_with([OnlineFakes.friend("f1", "ANNA"), OnlineFakes.friend("f2", "BO")])
	var asked: Array[Dictionary] = []
	t.confirm.connect(func(text: String, on_yes: Callable) -> void: asked.append({"text": text, "yes": on_yes}))
	(t.rows_named("Friend_f1")[0].find_child("Remove", true, false) as Button).pressed.emit()
	assert_eq(_net.sc.count("remove_friend"), 0, "nothing happens before the answer")
	assert_string_contains(asked[0]["text"] as String, "Remove ANNA")
	(asked[0]["yes"] as Callable).call()
	await settle()
	assert_eq(_net.sc.last("remove_friend")["args"], ["f1"])
	(t.rows_named("Friend_f2")[0].find_child("Block", true, false) as Button).pressed.emit()
	assert_string_contains(asked[1]["text"] as String, "Block BO")
	(asked[1]["yes"] as Callable).call()
	await settle()
	assert_eq(_net.sc.last("block")["args"], ["f2"])
	assert_eq(t.rows_named("Blocked_").size(), 1, "the blocked list shows them")


func test_a_blocked_player_can_be_unblocked() -> void:
	var t: FriendsTab = await _friends_with([], [], ["x1"])
	assert_eq(t.rows_named("Blocked_").size(), 1)
	(t.rows_named("Blocked_x1")[0].find_child("Unblock", true, false) as Button).pressed.emit()
	await settle()
	assert_eq(_net.sc.last("unblock")["args"], ["x1"])
	assert_eq(t.rows_named("Blocked_").size(), 0)


func test_tapping_a_name_opens_the_player_menu() -> void:
	var t: FriendsTab = await _friends_with([OnlineFakes.friend("f1", "ANNA")])
	var infos: Array = _signals(t, "player_menu")
	(t.rows_named("Friend_f1")[0].find_child("Name", true, false) as Button).pressed.emit()
	assert_eq((infos[0] as Dictionary)["uid"], "f1")
	assert_eq((infos[0] as Dictionary)["name"], "ANNA")
	assert_true((infos[0] as Dictionary)["friend"])


func test_the_requests_badge_counts_waiting_requests() -> void:
	_net.fake_friends.requests = [OnlineFakes.request("u1", "A"), OnlineFakes.request("u2", "B")]
	var t: FriendsTab = _tab(FriendsTab.new()) as FriendsTab
	var counts: Array = _signals(t, "badge_changed")
	t.activate()
	await settle()
	assert_eq(counts.back(), 2)


# --- JOIN ---------------------------------------------------------------------------------------------------------

func _join() -> JoinTab:
	var t: JoinTab = _tab(JoinTab.new()) as JoinTab
	t.activate()
	return t


func test_the_join_code_is_uppercased_filtered_and_capped_at_six() -> void:
	var t: JoinTab = _join()
	var f: CodeField = t.get_field()
	f.text = "ab0o1i-c d"
	f.text_changed.emit(f.text)
	assert_eq(t.code(), "ABCD", "0, O, 1, I, the dash and the space are dropped")
	f.text = "abcdefgh"
	f.text_changed.emit(f.text)
	assert_eq(t.code(), "ABCDEF")
	assert_false(t.get_join_button().disabled)
	f.text = "abc"
	f.text_changed.emit(f.text)
	assert_true(t.get_join_button().disabled)


func test_joining_sends_the_code_and_opens_the_lobby() -> void:
	_net.fake_lobby.put_lobby("lob", OnlineFakes.lobby_meta([OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA"), {"kind": "human"}], {}, OnlineFakes.OTHER))
	var t: JoinTab = _join()
	var lobbies: Array = _signals(t, "open_lobby")
	t.set_code("abc234")
	t.join()
	await settle()
	assert_eq(_net.sc.last("join")["args"], ["ABC234", 1, []])
	assert_eq(lobbies, ["lob"])


func test_an_unknown_or_full_code_shows_a_message_and_stays() -> void:
	var t: JoinTab = _join()
	t.set_code("zzzzzz")
	t.join()
	await settle()
	assert_string_contains(t.get_message(), "No match or player with that code")
	_net.sc.replies["join"] = NetResult.failure(NetError.Code.EXHAUSTED, "match_full")
	t.join()
	await settle()
	assert_string_contains(t.get_message(), "full")


func test_a_blocked_pair_looks_like_an_unknown_code() -> void:
	_net.sc.replies["join"] = NetResult.failure(NetError.Code.NOT_FOUND, "unknown_code")
	var t: JoinTab = _join()
	t.set_code("abc234")
	t.join()
	await settle()
	assert_string_contains(t.get_message(), "No match or player with that code")


func test_another_player_on_this_phone_joins_with_a_seat_count_and_names() -> void:
	_net.fake_lobby.put_lobby("lob", OnlineFakes.lobby_meta([OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA"), {"kind": "human"}, {"kind": "human"}], {}, OnlineFakes.OTHER))
	var t: JoinTab = _join()
	t.add_phone_seat()
	assert_eq(t.seat_count(), 2)
	t.get_seat_fields()[0].set_name_text("zed")
	t.set_code("abc234")
	t.join()
	await settle()
	var args: Array = _net.sc.last("join")["args"]
	assert_eq(args[1], 2)
	assert_eq(args[2], ["", "ZED"], "the first seat keeps the account name")


func test_at_most_four_seats_can_share_one_phone() -> void:
	var t: JoinTab = _join()
	for i: int in range(6):
		t.add_phone_seat()
	assert_eq(t.seat_count(), JoinTab.MAX_SEATS)
	assert_false(t.get_add_seat_button().visible)


func test_a_protocol_mismatch_on_join_asks_for_an_update() -> void:
	_net.sc.replies["join"] = NetResult.failure(NetError.Code.PROTOCOL_MISMATCH, "protocol_mismatch")
	var t: JoinTab = _join()
	var updates: Array = _signals(t, "update_needed")
	t.set_code("abc234")
	t.join()
	await settle()
	assert_eq(updates.size(), 1)


# --- HOST ---------------------------------------------------------------------------------------------------------

func test_hosting_creates_a_lobby_with_the_host_and_one_open_seat() -> void:
	Entitlement.reset_for_tests(true)
	var t: HostTab = _tab(HostTab.new()) as HostTab
	t.activate()
	var lobbies: Array = _signals(t, "open_lobby")
	t.create()
	await settle()
	var args: Array = _net.sc.last("create")["args"]
	assert_eq((args[0] as Dictionary)["rounds"], 3)
	assert_eq((args[0] as Dictionary)["mode"], 0)
	assert_eq((args[1] as Array).size(), 2)
	assert_true(((args[1] as Array)[0] as Dictionary).get("mine", false))
	assert_eq(lobbies.size(), 1)
	assert_eq(OnlineHub.open_lobby_id, lobbies[0])


func test_love_edition_is_only_offered_after_the_secret_was_found() -> void:
	var t: HostTab = _tab(HostTab.new()) as HostTab
	t.activate()
	assert_false(t.get_love_button().visible)
	SettingsStore.love_found = true
	t.activate()
	assert_true(t.get_love_button().visible)
	t.set_love(true)
	var req: Dictionary = t.lobby_request()
	assert_eq((req["settings"] as Dictionary)["mode"], SimConstants.MODE_LOVE)
	assert_eq((req["settings"] as Dictionary)["theme"], ThemeDefs.LOVE_THEME)
	assert_eq((req["seats"] as Array).size(), 2)
	assert_false((req["settings"] as Dictionary).has("teams"))


func test_a_refused_hosting_by_a_free_player_opens_the_unlock_screen() -> void:
	Entitlement.reset_for_tests(false)
	_net.sc.replies["create"] = NetResult.failure(NetError.Code.PERMISSION, "full_required")
	var t: HostTab = _tab(HostTab.new()) as HostTab
	var unlocks: Array = _signals(t, "unlock")
	t.create()
	await settle()
	assert_eq(unlocks, ["host"])


func test_a_full_player_whose_purchase_the_server_does_not_know_gets_a_message() -> void:
	Entitlement.reset_for_tests(true)
	_net.sc.replies["create"] = NetResult.failure(NetError.Code.PERMISSION, "full_required")
	var t: HostTab = _tab(HostTab.new()) as HostTab
	t.create()
	await settle()
	assert_string_contains(t.get_message(), "full game on this account")


func test_a_protocol_mismatch_on_create_asks_for_an_update() -> void:
	_net.sc.replies["create"] = NetResult.failure(NetError.Code.PROTOCOL_MISMATCH, "protocol_mismatch")
	var t: HostTab = _tab(HostTab.new()) as HostTab
	var updates: Array = _signals(t, "update_needed")
	t.create()
	await settle()
	assert_eq(updates.size(), 1)
