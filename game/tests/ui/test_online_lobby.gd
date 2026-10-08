extends OnlineTestBase
## The lobby screen with a fake lobby server: host and joiner views, START validation, the host's edits (CPUs, teams,
## rules, timers) as `updateLobby` calls, shared-phone seats, invites, sharing, and what happens when the match starts.

const SCREEN: String = "res://ui/online/lobby_screen.tscn"

var _net: OnlineFakes.FakeNet = null


func before_each() -> void:
	super.before_each()
	_net = OnlineFakes.net()
	OnlineHub.session = _net
	OnlineHub.set_services(PushService.new(PushFake.new()), GoogleSignIn.new(GoogleSignInFake.new()),
			ShareService.new(ShareFake.new()), DeepLinks.new(ShareFake.new()))


func _lobby(seats: Array, overrides: Dictionary = {}, host: String = OnlineFakes.ME) -> LobbyScreen:
	_net.fake_lobby.put_lobby("lobby1", OnlineFakes.lobby_meta(seats, overrides, host))
	OnlineHub.lobby_to_show = "lobby1"
	var s: LobbyScreen = (load(SCREEN) as PackedScene).instantiate()
	add_child_autofree(s)
	await settle(4)
	return s


func _two_humans_and_cpu() -> Array:
	return [OnlineFakes.human_seat(OnlineFakes.ME, "HANA"), {"kind": "human"}, OnlineFakes.cpu_seat(2, "CPU 3")]


func _meta(s: LobbyScreen) -> Dictionary:
	return _net.fake_lobby.metas["lobby1"]


# --- views --------------------------------------------------------------------------------------------------------

func test_the_host_sees_edit_controls_and_the_code() -> void:
	var s: LobbyScreen = await _lobby(_two_humans_and_cpu())
	assert_true(s.is_host())
	assert_eq(s.get_code_text(), "ABC234")
	assert_true(s.get_rule_button("rounds").visible)
	assert_false(s.get_rule_label("rounds").visible)
	assert_true(s.get_add_cpu_button().visible)
	assert_eq(s.seat_row_count(), 4, "three seats and the add row")
	assert_not_null(s.get_seat_row(2).find_child("Level", true, false), "the CPU level chip")


func test_a_joiner_sees_a_read_only_view_and_waits_for_the_host() -> void:
	var s: LobbyScreen = await _lobby([OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA"), OnlineFakes.human_seat(OnlineFakes.ME, "HANA"), OnlineFakes.cpu_seat()], {}, OnlineFakes.OTHER)
	assert_false(s.is_host())
	assert_false(s.get_rule_button("rounds").visible)
	assert_true(s.get_rule_label("rounds").visible)
	assert_eq(s.get_rule_label("rounds").text, "3")
	assert_false(s.get_add_cpu_button().visible)
	assert_false(s.get_start_button().visible)
	assert_string_contains(s.get_hint_text(), "Waiting for the host")
	assert_true(s.get_seat_row(2).find_child("Team", true, false).disabled, "chips cannot be changed by a joiner")
	assert_null(s.get_seat_row(2).find_child("Remove", true, false))


func test_my_seat_is_marked_and_a_shared_phone_says_this_phone() -> void:
	var s: LobbyScreen = await _lobby([OnlineFakes.human_seat(OnlineFakes.ME, "HANA"), OnlineFakes.human_seat(OnlineFakes.ME, "HANA 2"), OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA")])
	var badge0: Node = s.get_seat_row(0).find_child("Mine", true, false)
	assert_eq((badge0.find_child("Text", true, false) as Label).text, "THIS PHONE")
	assert_not_null(s.get_seat_row(1).find_child("Mine", true, false))
	assert_null(s.get_seat_row(2).find_child("Mine", true, false))
	var alone: LobbyScreen = await _lobby(_two_humans_and_cpu())
	assert_eq((alone.get_seat_row(0).find_child("Mine", true, false).find_child("Text", true, false) as Label).text, "YOU")


func test_open_seats_say_waiting_with_a_ring_and_filled_seats_a_check() -> void:
	var s: LobbyScreen = await _lobby(_two_humans_and_cpu())
	assert_eq((s.get_seat_row(1).find_child("Name", true, false) as Label).text, "Waiting for a player…")
	assert_eq((s.get_seat_row(1).find_child("Glyph", true, false) as StatusGlyph).kind, StatusGlyph.Kind.RING)
	assert_eq((s.get_seat_row(0).find_child("Glyph", true, false) as StatusGlyph).kind, StatusGlyph.Kind.CHECK)


func test_tapping_another_players_name_opens_the_player_menu() -> void:
	var s: LobbyScreen = await _lobby([OnlineFakes.human_seat(OnlineFakes.ME, "HANA"), OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA")])
	(s.get_seat_row(1).find_child("Name", true, false) as Button).pressed.emit()
	assert_true(s.get_player_menu().is_open())
	assert_eq(s.get_player_menu().player_uid(), OnlineFakes.OTHER)
	assert_null(s.get_seat_row(0).find_child("Name", true, false) as Button, "my own name is not a menu")


# --- START --------------------------------------------------------------------------------------------------------

func test_start_waits_for_every_human_seat_to_be_filled() -> void:
	var s: LobbyScreen = await _lobby(_two_humans_and_cpu())
	assert_true(s.get_start_button().disabled)
	assert_string_contains(s.get_hint_text(), "Waiting for 1 more")
	_net.fake_lobby.remote_change("lobby1", func(m: Dictionary) -> void:
		(m["seats"] as Array)[1] = OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA"))
	await settle()
	assert_false(s.get_start_button().disabled)
	assert_eq(s.get_hint_text(), "")


func test_start_needs_usable_teams() -> void:
	var s: LobbyScreen = await _lobby([OnlineFakes.human_seat(OnlineFakes.ME, "A"), OnlineFakes.human_seat(OnlineFakes.OTHER, "B"), OnlineFakes.cpu_seat()])
	assert_false(s.get_start_button().disabled)
	s.cycle_team(0)
	await settle()
	assert_true(s.get_start_button().disabled, "only one seat has a team")
	assert_string_contains(s.get_hint_text(), "Give every player a team")
	assert_eq(_net.sc.count("update"), 0, "an unusable list is not sent")
	s.cycle_team(1)
	s.cycle_team(2)
	await settle()
	assert_true(s.get_start_button().disabled, "everyone is in team A")
	assert_string_contains(s.get_hint_text(), "at least two teams")
	s.cycle_team(2)  # C? A -> B
	await settle()
	assert_false(s.get_start_button().disabled, "A, A, B is fine")
	assert_eq((_meta(s)["settings"] as Dictionary)["teams"], [0, 0, 1])


func test_pressing_start_starts_the_match_and_opens_the_battle() -> void:
	var s: LobbyScreen = await _lobby([OnlineFakes.human_seat(OnlineFakes.ME, "HANA"), OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA")])
	var fm: OnlineFakes.FakeMatch = OnlineFakes.match_for(OnlineFakes.ME, [OnlineFakes.human_seat(OnlineFakes.ME, "HANA"), OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA")])
	_net.fake_match = fm
	s.start_match()
	await settle(4)
	assert_eq(_net.sc.count("start"), 1)
	assert_eq(OnlineHub.last_scene(), OnlineHub.BATTLE_SCENE)
	assert_eq(OnlineHub.match_to_play, fm)
	assert_eq(OnlineHub.open_lobby_id, "")


func test_a_joiner_goes_to_the_battle_when_the_host_starts() -> void:
	var seats: Array = [OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA"), OnlineFakes.human_seat(OnlineFakes.ME, "HANA")]
	var s: LobbyScreen = await _lobby(seats, {}, OnlineFakes.OTHER)
	_net.fake_match = OnlineFakes.match_for(OnlineFakes.ME, seats)
	_net.fake_lobby.remote_change("lobby1", func(m: Dictionary) -> void: m["status"] = "playing")
	await settle(4)
	assert_eq(OnlineHub.last_scene(), OnlineHub.BATTLE_SCENE)
	assert_not_null(s)


func test_a_refused_start_shows_why() -> void:
	var s: LobbyScreen = await _lobby([OnlineFakes.human_seat(OnlineFakes.ME, "HANA"), OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA")])
	_net.sc.replies["start"] = NetResult.failure(NetError.Code.PRECONDITION, "seats_not_filled")
	s.start_match()
	await settle(3)
	assert_string_contains(s.get_toast().get_text(), "Not every player has joined")
	assert_eq(OnlineHub.last_scene(), "")


# --- host edits ---------------------------------------------------------------------------------------------------

func test_adding_and_removing_a_cpu() -> void:
	var s: LobbyScreen = await _lobby(_two_humans_and_cpu())
	s.add_cpu()
	await settle(3)
	var seats: Array = LobbyModel.seats_of(_meta(s))
	assert_eq(seats.size(), 4)
	assert_eq((seats[3] as Dictionary)["kind"], "cpu")
	s.remove_seat(3)
	await settle(3)
	assert_eq(LobbyModel.seats_of(_meta(s)).size(), 3)
	assert_eq(s.seat_row_count(), 4)


func test_the_cpu_level_chip_cycles_and_a_held_seat_cannot_be_removed() -> void:
	var s: LobbyScreen = await _lobby([OnlineFakes.human_seat(OnlineFakes.ME, "HANA"), OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA"), OnlineFakes.cpu_seat(4, "CPU 3")])
	s.cycle_cpu_level(2)
	await settle(3)
	assert_eq((LobbyModel.seats_of(_meta(s))[2] as Dictionary)["level"], 1, "Expert wraps to Easy")
	assert_null(s.get_seat_row(1).find_child("Remove", true, false), "ANNA holds her seat")
	s.remove_seat(1)
	await settle(2)
	assert_eq(LobbyModel.seats_of(_meta(s)).size(), 3)


func test_the_table_never_goes_below_two_seats_or_above_eight() -> void:
	var s: LobbyScreen = await _lobby([OnlineFakes.human_seat(OnlineFakes.ME, "HANA"), OnlineFakes.cpu_seat()])
	s.remove_seat(1)
	await settle(2)
	assert_eq(LobbyModel.seats_of(_meta(s)).size(), 2)
	for i: int in range(8):
		s.add_cpu()
		await settle(2)
	assert_eq(LobbyModel.seats_of(_meta(s)).size(), 8)
	assert_false(s.get_add_cpu_button().visible)


func test_changing_the_seat_count_resends_the_teams_so_the_server_accepts_it() -> void:
	var s: LobbyScreen = await _lobby([OnlineFakes.human_seat(OnlineFakes.ME, "A"), OnlineFakes.human_seat(OnlineFakes.OTHER, "B"), OnlineFakes.cpu_seat(), OnlineFakes.cpu_seat()], {"teams": [0, 0, 1, 1]})
	s.add_cpu()
	await settle(3)
	assert_eq(_net.sc.count("update"), 1)
	assert_false(_net.sc.last("update")["args"][1].is_empty(), "settings carry the teams")
	assert_eq(LobbyModel.seats_of(_meta(s)).size(), 5, "the fake server (which checks the team list) accepted it")
	assert_eq(s.get_teams().size(), 5)


func test_removing_a_seat_removes_its_team_entry() -> void:
	var s: LobbyScreen = await _lobby([OnlineFakes.human_seat(OnlineFakes.ME, "A"), OnlineFakes.human_seat(OnlineFakes.OTHER, "B"), OnlineFakes.cpu_seat(), OnlineFakes.cpu_seat()], {"teams": [0, 1, 0, 1]})
	s.remove_seat(2)
	await settle(3)
	assert_eq((_meta(s)["settings"] as Dictionary)["teams"], [0, 1, 1])


func test_rules_cycle_through_their_choices() -> void:
	var s: LobbyScreen = await _lobby(_two_humans_and_cpu())
	s.get_rule_button("rounds").pressed.emit()
	await settle(3)
	assert_eq((_meta(s)["settings"] as Dictionary)["rounds"], 5, "3 -> 5")
	s.get_rule_button("money").pressed.emit()
	await settle(3)
	assert_eq((_meta(s)["settings"] as Dictionary)["start_money"], 25000)
	s.get_rule_button("wind").pressed.emit()
	await settle(3)
	assert_eq((_meta(s)["settings"] as Dictionary)["wind_max"], 0, "100 wraps to OFF")
	assert_eq(s.get_rule_button("wind").text, "OFF")


func test_the_theme_is_chosen_in_the_picker() -> void:
	var s: LobbyScreen = await _lobby(_two_humans_and_cpu())
	s.get_rule_button("theme").pressed.emit()
	assert_true(s.get_theme_picker().is_open())
	s.get_theme_picker().get_option("ice_circuit").pressed.emit()
	await settle(3)
	assert_eq((_meta(s)["settings"] as Dictionary)["theme"], "ice_circuit")


func test_the_timers_use_the_presets() -> void:
	var s: LobbyScreen = await _lobby(_two_humans_and_cpu())
	s.get_rule_button("live").pressed.emit()
	await settle(3)
	assert_eq((_meta(s)["timers"] as Dictionary)["liveSec"], 120, "60 -> 120")
	s.get_rule_button("live").pressed.emit()
	await settle(3)
	assert_eq((_meta(s)["timers"] as Dictionary)["liveSec"], 30)
	s.get_rule_button("async").pressed.emit()
	await settle(3)
	assert_eq((_meta(s)["timers"] as Dictionary)["asyncHours"], 24, "72 -> 24")
	s.get_rule_button("timeout").pressed.emit()
	await settle(3)
	assert_eq((_meta(s)["timers"] as Dictionary)["asyncTimeout"], "end")
	assert_eq(s.get_rule_button("timeout").text, "END MATCH")


func test_friendly_fire_shows_with_teams_and_toggles() -> void:
	var s: LobbyScreen = await _lobby([OnlineFakes.human_seat(OnlineFakes.ME, "A"), OnlineFakes.human_seat(OnlineFakes.OTHER, "B"), OnlineFakes.cpu_seat()])
	assert_false(s.is_rule_visible("friendly_fire"))
	s.cycle_team(0)
	s.cycle_team(1)
	s.cycle_team(1)
	s.cycle_team(2)
	await settle(3)
	assert_true(s.is_rule_visible("friendly_fire"))
	s.get_rule_button("friendly_fire").pressed.emit()
	await settle(3)
	assert_eq((_meta(s)["settings"] as Dictionary)["friendly_fire"], false)


func test_a_failed_edit_shows_the_reason_and_reloads_the_lobby() -> void:
	var s: LobbyScreen = await _lobby(_two_humans_and_cpu())
	_net.sc.replies["update"] = NetResult.failure(NetError.Code.PERMISSION, "not_host")
	s.get_rule_button("rounds").pressed.emit()
	await settle(3)
	assert_string_contains(s.get_toast().get_text(), "Only the host")
	assert_eq(s.get_rule_button("rounds").text, "3")


func test_an_open_seat_can_be_claimed_for_this_phone() -> void:
	var s: LobbyScreen = await _lobby(_two_humans_and_cpu())
	s.play_here(1)
	await settle(3)
	var seats: Array = LobbyModel.seats_of(_meta(s))
	assert_eq((seats[1] as Dictionary)["uid"], OnlineFakes.ME)
	assert_eq(LobbyModel.open_count(_meta(s)), 0)


func test_the_host_can_add_an_open_player_seat() -> void:
	var s: LobbyScreen = await _lobby(_two_humans_and_cpu())
	s.add_player()
	await settle(3)
	assert_eq(LobbyModel.open_count(_meta(s)), 2)


# --- love ---------------------------------------------------------------------------------------------------------

func test_a_love_lobby_is_two_humans_without_teams_cpus_or_rules() -> void:
	var s: LobbyScreen = await _lobby([OnlineFakes.human_seat(OnlineFakes.ME, "A"), {"kind": "human"}], {"mode": 1, "rounds": 1, "start_money": 0, "wind_max": 30, "theme": "love_theme"})
	assert_false(s.get_add_cpu_button().visible)
	assert_false(s.get_add_player_button().visible)
	assert_null(s.get_seat_row(0).find_child("Team", true, false))
	assert_false(s.is_rule_visible("rounds"))
	assert_false(s.is_rule_visible("theme"))
	assert_true(s.is_rule_visible("live"), "the timers still apply")


# --- leaving, inviting, sharing -----------------------------------------------------------------------------------

func test_leaving_asks_first_and_the_host_closes_the_lobby() -> void:
	var s: LobbyScreen = await _lobby(_two_humans_and_cpu())
	s.ask_leave()
	assert_true(s.get_confirm().is_open())
	assert_string_contains(s.get_confirm().get_message_text(), "Close this lobby")
	s.get_confirm().get_yes_button().pressed.emit()
	await settle(3)
	assert_eq(_net.sc.last("leave")["args"], ["lobby1"])
	assert_eq(OnlineHub.last_scene(), OnlineHub.ONLINE_SCENE)


func test_a_joiner_leaves_with_a_different_question() -> void:
	var s: LobbyScreen = await _lobby([OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA"), OnlineFakes.human_seat(OnlineFakes.ME, "HANA")], {}, OnlineFakes.OTHER)
	s.ask_leave()
	assert_string_contains(s.get_confirm().get_message_text(), "Leave this lobby")


func test_cancelling_the_leave_question_stays() -> void:
	var s: LobbyScreen = await _lobby(_two_humans_and_cpu())
	s.ask_leave()
	s.get_confirm().get_no_button().pressed.emit()
	await settle()
	assert_eq(_net.sc.count("leave"), 0)
	assert_eq(OnlineHub.last_scene(), "")


func test_the_host_closing_the_lobby_sends_joiners_back() -> void:
	var s: LobbyScreen = await _lobby([OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA"), OnlineFakes.human_seat(OnlineFakes.ME, "HANA")], {}, OnlineFakes.OTHER)
	_net.fake_lobby.remote_change("lobby1", func(m: Dictionary) -> void: m["status"] = "abandoned")
	await settle(3)
	assert_eq(OnlineHub.last_scene(), OnlineHub.ONLINE_SCENE)
	assert_string_contains(s.get_toast().get_text(), "closed the lobby")


func test_a_lobby_the_host_closed_is_forgotten_by_the_hub() -> void:
	var s: LobbyScreen = await _lobby([OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA"), OnlineFakes.human_seat(OnlineFakes.ME, "HANA")], {}, OnlineFakes.OTHER)
	assert_eq(OnlineHub.open_lobby_id, "lobby1", "while it is open the Friends tab may invite into it")
	_net.fake_lobby.remote_change("lobby1", func(m: Dictionary) -> void: m["status"] = "abandoned")
	await settle(3)
	assert_eq(OnlineHub.open_lobby_id, "")
	assert_eq(OnlineHub.lobby_to_show, "")
	assert_not_null(s)


func test_leaving_forgets_the_lobby() -> void:
	var s: LobbyScreen = await _lobby(_two_humans_and_cpu())
	s.ask_leave()
	s.get_confirm().get_yes_button().pressed.emit()
	await settle(3)
	assert_eq(OnlineHub.open_lobby_id, "")
	assert_eq(OnlineHub.lobby_to_show, "")


func test_a_started_match_is_not_a_lobby_any_more() -> void:
	var seats: Array = [OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA"), OnlineFakes.human_seat(OnlineFakes.ME, "HANA")]
	var s: LobbyScreen = await _lobby(seats, {}, OnlineFakes.OTHER)
	_net.fake_match = OnlineFakes.match_for(OnlineFakes.ME, seats)
	_net.fake_lobby.remote_change("lobby1", func(m: Dictionary) -> void: m["status"] = "playing")
	await settle(4)
	assert_eq(OnlineHub.last_scene(), OnlineHub.BATTLE_SCENE)
	assert_eq(OnlineHub.open_lobby_id, "")
	assert_eq(OnlineHub.lobby_to_show, "")
	assert_not_null(s)


func test_the_lobby_hands_its_match_to_the_player_menu() -> void:
	var s: LobbyScreen = await _lobby([OnlineFakes.human_seat(OnlineFakes.ME, "HANA"), OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA")])
	(s.get_seat_row(1).find_child("Name", true, false) as Button).pressed.emit()
	assert_eq(s.get_player_menu().info.get("match_id", ""), "lobby1", "passed explicitly, not found by walking the tree")


func test_invite_friends_from_the_picker() -> void:
	_net.fake_friends.friends = [OnlineFakes.friend("f1", "ANNA"), OnlineFakes.friend("f2", "BO")]
	var s: LobbyScreen = await _lobby(_two_humans_and_cpu())
	s.get_invite_button().pressed.emit()
	await settle(3)
	assert_true(s.get_picker().is_open())
	assert_eq(s.get_picker().row_count(), 2)
	(s.get_picker().get_row("f1").find_child("Invite", true, false) as Button).pressed.emit()
	await settle(3)
	assert_eq(_net.sc.last("invite")["args"], ["f1", "lobby1"])
	assert_eq((s.get_picker().get_row("f1").find_child("Invite", true, false) as Button).text, "INVITED")
	assert_false((s.get_picker().get_row("f1").find_child("Invite", true, false) as Button).disabled == false)


func test_the_picker_says_so_when_there_are_no_friends() -> void:
	var s: LobbyScreen = await _lobby(_two_humans_and_cpu())
	s.open_invite()
	await settle(3)
	assert_string_contains(s.get_picker().get_empty_text(), "No friends yet")


func test_share_code_uses_the_share_sheet_with_the_code_in_the_text() -> void:
	var fake: ShareFake = ShareFake.new()
	OnlineHub.set_services(null, null, ShareService.new(fake), null)
	var s: LobbyScreen = await _lobby(_two_humans_and_cpu())
	s.share_code()
	assert_eq(fake.share_calls, 1)
	assert_string_contains(fake.last_text, "ABC234")
	assert_string_contains(fake.last_text, "charredhorizons://join/ABC234")


func test_share_falls_back_to_the_clipboard_with_a_message() -> void:
	OnlineHub.set_services(null, null, ShareService.new(null), null)
	var s: LobbyScreen = await _lobby(_two_humans_and_cpu())
	s.share_code()
	assert_string_contains(s.get_toast().get_text(), "Invite copied")


func test_the_lobby_stream_updates_the_view() -> void:
	var s: LobbyScreen = await _lobby(_two_humans_and_cpu())
	_net.fake_lobby.remote_change("lobby1", func(m: Dictionary) -> void:
		(m["seats"] as Array)[1] = OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA"))
	await settle()
	assert_eq((s.get_seat_row(1).find_child("Name", true, false) as Button).text, "ANNA")


func test_the_lobby_that_cannot_be_read_goes_back_with_a_message() -> void:
	_net.sc.replies["fetch_meta"] = NetResult.failure(NetError.Code.PERMISSION, "not_a_member")
	OnlineHub.lobby_to_show = "gone"
	var s: LobbyScreen = (load(SCREEN) as PackedScene).instantiate()
	add_child_autofree(s)
	await settle(4)
	assert_eq(OnlineHub.last_scene(), OnlineHub.ONLINE_SCENE)
	assert_string_contains(s.get_toast().get_text(), "not in that match")
