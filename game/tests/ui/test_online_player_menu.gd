extends OnlineTestBase
## The player menu (tap a name): Add friend / Block / Report name with a reason picker and confirmations, and Mute in a
## match.

var _net: OnlineFakes.FakeNet = null


func before_each() -> void:
	super.before_each()
	_net = OnlineFakes.net()
	OnlineHub.session = _net


func _menu(info: Dictionary) -> PlayerMenu:
	var m := PlayerMenu.new()
	add_child_autofree(m)
	m.open_for(_net, info)
	return m


func _info(friend: bool = false, in_match: bool = false) -> Dictionary:
	return {"uid": "u1", "name": "ANNA", "friend": friend, "in_match": in_match}


func test_the_menu_is_named_after_the_player() -> void:
	var m: PlayerMenu = _menu(_info())
	assert_eq(m.get_title_text(), "ANNA")
	assert_true(m.is_open())


func test_add_friend_is_hidden_for_friends_and_for_myself() -> void:
	assert_false(_menu(_info(true)).get_add_button().visible)
	var me: PlayerMenu = _menu({"uid": OnlineFakes.ME, "name": "HANA", "friend": false, "in_match": false})
	assert_false(me.get_add_button().visible)
	assert_false(me.get_block_button().visible, "no block or report on myself")
	assert_false(me.get_report_button().visible)


func test_a_player_known_by_uid_gets_an_explanation_instead_of_a_request() -> void:
	var m: PlayerMenu = _menu(_info())
	m.get_add_button().pressed.emit()
	await settle()
	assert_eq(_net.sc.count("send_request"), 0)
	assert_string_contains(m.get_hint_text(), "ask for their friend code")


func test_add_friend_sends_a_request_when_the_code_is_known() -> void:
	var info: Dictionary = _info()
	info["friend_code"] = "EFGH2345"
	var m: PlayerMenu = _menu(info)
	var done: Array = []
	m.done.connect(func(kind: String, _uid: String) -> void: done.append(kind))
	m.get_add_button().pressed.emit()
	await settle()
	assert_eq(_net.sc.last("send_request")["args"], ["EFGH2345"])
	assert_eq(done, ["requested"])
	assert_false(m.is_open())


func test_add_friend_uses_the_uid_request_when_the_match_is_known() -> void:
	var info: Dictionary = _info(false, true)
	info["match_id"] = "m42"
	var m: PlayerMenu = _menu(info)
	var done: Array = []
	var toasts: Array = []
	m.done.connect(func(kind: String, _uid: String) -> void: done.append(kind))
	m.toast.connect(func(t: String) -> void: toasts.append(t))
	m.get_add_button().pressed.emit()
	await settle()
	assert_eq(_net.sc.last("request_by_uid")["args"], ["u1", "m42"])
	assert_eq(_net.sc.count("send_request"), 0)
	assert_eq(toasts, ["Request sent to ANNA"])
	assert_eq(done, ["requested"])
	assert_false(m.is_open())


func test_the_match_id_property_and_the_enclosing_lobby_or_battle_also_count() -> void:
	var by_property: PlayerMenu = _menu(_info())
	by_property.match_id = "m7"
	assert_eq(by_property.shared_match_id(), "m7")
	# A screen that holds the menu and knows its match (the lobby has `match_id`, the online battle has `om`).
	var lobby := Control.new()
	lobby.set_script(load("res://tests/ui/menu_host_stub.gd") as Script)
	lobby.set("match_id", "m9")
	add_child_autofree(lobby)
	var inside := PlayerMenu.new()
	lobby.add_child(inside)
	inside.open_for(_net, _info())
	assert_eq(inside.shared_match_id(), "m9")
	inside.get_add_button().pressed.emit()
	await settle()
	assert_eq(_net.sc.last("request_by_uid")["args"], ["u1", "m9"])
	var battle := Control.new()
	battle.set_script(load("res://tests/ui/menu_host_stub.gd") as Script)
	var om := OnlineMatch.new()
	om.match_id = "m5"
	battle.set("om", om)
	add_child_autofree(battle)
	var in_battle := PlayerMenu.new()
	battle.add_child(in_battle)
	in_battle.open_for(_net, _info(false, true))
	assert_eq(in_battle.shared_match_id(), "m5")


func test_a_blocked_pair_gets_the_neutral_unknown_code_text() -> void:
	_net.sc.replies["request_by_uid"] = NetResult.failure(NetError.Code.NOT_FOUND, "unknown_code")
	var info: Dictionary = _info(false, true)
	info["match_id"] = "m42"
	var m: PlayerMenu = _menu(info)
	m.get_add_button().pressed.emit()
	await settle()
	assert_true(m.is_open())
	assert_eq(m.get_hint_text(), "No match or player with that code.")


func test_other_uid_request_failures_show_their_reason() -> void:
	var info: Dictionary = _info(false, true)
	info["match_id"] = "m42"
	_net.sc.replies["request_by_uid"] = NetResult.failure(NetError.Code.ALREADY_EXISTS, "already_friends")
	var m: PlayerMenu = _menu(info)
	m.get_add_button().pressed.emit()
	await settle()
	assert_eq(m.get_hint_text(), "You are already friends.")
	_net.sc.replies["request_by_uid"] = NetResult.failure(NetError.Code.EXHAUSTED, "too_many_requests")
	m.get_add_button().pressed.emit()
	await settle()
	assert_eq(m.get_hint_text(), "That player has too many waiting requests.")


func test_blocking_asks_first_and_then_blocks_and_mutes() -> void:
	var m: PlayerMenu = _menu(_info(true, true))
	m.get_block_button().pressed.emit()
	assert_eq(m.get_step(), PlayerMenu.Step.CONFIRM_BLOCK)
	assert_eq(m.get_title_text(), "Block ANNA?")
	assert_eq(_net.sc.count("block"), 0)
	var done: Array = []
	m.done.connect(func(kind: String, uid: String) -> void: done.append([kind, uid]))
	m.get_confirm_yes().pressed.emit()
	await settle()
	assert_eq(_net.sc.last("block")["args"], ["u1"])
	assert_eq(done, [["blocked", "u1"]])
	assert_true(OnlineHub.is_muted("u1"), "a blocked player's messages never show")
	assert_false(m.is_open())


func test_cancelling_the_block_goes_back_to_the_menu() -> void:
	var m: PlayerMenu = _menu(_info())
	m.get_block_button().pressed.emit()
	m.find_child("No", true, false).pressed.emit()
	assert_eq(m.get_step(), PlayerMenu.Step.MENU)
	assert_eq(_net.sc.count("block"), 0)


func test_a_failed_block_shows_the_reason() -> void:
	_net.sc.replies["block"] = NetResult.failure(NetError.Code.OFFLINE, "offline")
	var m: PlayerMenu = _menu(_info())
	m.get_block_button().pressed.emit()
	m.get_confirm_yes().pressed.emit()
	await settle()
	assert_true(m.is_open())
	assert_string_contains(m.get_hint_text(), "No connection")


func test_reporting_picks_a_reason_then_confirms() -> void:
	var m: PlayerMenu = _menu(_info())
	m.get_report_button().pressed.emit()
	assert_eq(m.get_step(), PlayerMenu.Step.REASON)
	assert_eq(_net.sc.count("report"), 0)
	m.get_reason_button("impersonation").pressed.emit()
	assert_eq(m.get_step(), PlayerMenu.Step.CONFIRM_REPORT)
	assert_eq(_net.sc.count("report"), 0, "still nothing sent")
	var toasts: Array = []
	m.toast.connect(func(t: String) -> void: toasts.append(t))
	m.get_confirm_yes().pressed.emit()
	await settle()
	assert_eq(_net.sc.last("report")["args"], ["u1", "impersonation"])
	assert_eq(toasts, ["Thanks. The name was reported."])
	assert_false(m.is_open())


func test_every_reason_is_a_valid_backend_reason() -> void:
	var rx := RegEx.new()
	rx.compile("^[a-z_]{1,32}$")
	for spec: Array in PlayerMenu.REASONS:
		assert_not_null(rx.search(spec[0] as String), spec[0] as String)


func test_mute_is_only_for_players_in_a_match_and_toggles() -> void:
	assert_false(_menu(_info(false, false)).get_mute_button().visible)
	var m: PlayerMenu = _menu(_info(false, true))
	assert_true(m.get_mute_button().visible)
	assert_eq(m.get_mute_button().text, "MUTE MESSAGES")
	m.get_mute_button().pressed.emit()
	assert_true(OnlineHub.is_muted("u1"))
	var m2: PlayerMenu = _menu(_info(false, true))
	assert_eq(m2.get_mute_button().text, "UNMUTE MESSAGES")
	m2.get_mute_button().pressed.emit()
	assert_false(OnlineHub.is_muted("u1"))


func test_menu_buttons_are_touch_sized() -> void:
	phone()
	var m: PlayerMenu = _menu(_info(false, true))
	await settle(3)
	for b: Button in [m.get_add_button(), m.get_block_button(), m.get_report_button(), m.get_mute_button()]:
		assert_gte(b.size.y, UiScale.touch() - 1.0, b.name)
