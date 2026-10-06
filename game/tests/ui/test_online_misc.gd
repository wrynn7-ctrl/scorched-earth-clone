extends OnlineTestBase
## Odds and ends of the online UI: the title's ONLINE button and its links, the notification permission being asked once,
## the saved online preferences, and the shared-phone turn banner in an online match.

const TITLE: String = "res://ui/title/title_screen.tscn"
const SCENE: String = "res://show/online/online_battle_scene.tscn"


func before_each() -> void:
	super.before_each()
	BattleConfig.autosave_path = "user://test_online_misc_save.crtl"
	SaveStore.delete(BattleConfig.autosave_path)


func after_each() -> void:
	SaveStore.delete(BattleConfig.autosave_path)
	BattleConfig.reset()
	super.after_each()


func _title() -> TitleScreen:
	var t: TitleScreen = (load(TITLE) as PackedScene).instantiate()
	add_child_autofree(t)
	return t


func test_the_title_has_an_online_button_next_to_start() -> void:
	phone()
	var t: TitleScreen = _title()
	await settle(3)
	var b: Button = t.get_online_button()
	assert_true(b.visible)
	assert_eq(b.text, "ONLINE")
	assert_gte(b.size.y, UiScale.touch() - 1.0)
	assert_eq(b.get_parent(), t.get_start_button().get_parent(), "side by side")
	assert_false(b.get_global_rect().intersects(t.get_start_button().get_global_rect()))
	b.pressed.emit()
	assert_eq(OnlineHub.last_scene(), OnlineHub.ONLINE_SCENE)


func test_online_never_touches_a_saved_match() -> void:
	var t: TitleScreen = _title()
	await settle(2)
	t.get_online_button().pressed.emit()
	assert_false(t.get_confirm_overlay().is_open(), "no question about the save: ONLINE leaves it alone")


func test_a_join_link_while_the_title_shows_goes_online_with_the_code() -> void:
	var fake: ShareFake = ShareFake.new()
	OnlineHub.set_services(PushService.new(PushFake.new()), GoogleSignIn.new(GoogleSignInFake.new()), ShareService.new(fake), DeepLinks.new(fake))
	var t: TitleScreen = _title()
	await settle(2)
	fake.simulate_link("craterline://join/K7M2QX")
	assert_eq(OnlineHub.pending_join_code, "K7M2QX")
	assert_eq(OnlineHub.last_scene(), OnlineHub.ONLINE_SCENE)
	assert_not_null(t)


func test_a_link_that_started_the_game_opens_online_by_itself() -> void:
	var fake: ShareFake = ShareFake.new()
	fake.simulate_launch_link("craterline://join/ABC234")
	var links: DeepLinks = DeepLinks.new(fake)
	links.start()
	OnlineHub.set_services(PushService.new(PushFake.new()), GoogleSignIn.new(GoogleSignInFake.new()), ShareService.new(fake), links)
	var t: TitleScreen = _title()
	await settle(3)
	assert_eq(OnlineHub.last_scene(), OnlineHub.ONLINE_SCENE)
	assert_eq(OnlineHub.pending_join_code, "ABC234")
	assert_not_null(t)


func test_a_notification_tap_while_the_title_shows_goes_online_to_that_match() -> void:
	var fake: PushFake = PushFake.new()
	var push: PushService = PushService.new(fake)
	push.start()
	OnlineHub.set_services(push, GoogleSignIn.new(GoogleSignInFake.new()), ShareService.new(ShareFake.new()), DeepLinks.new(ShareFake.new()))
	var t: TitleScreen = _title()
	await settle(2)
	fake.notification_opened.emit('{"type":"turn","matchId":"abc123"}')
	assert_eq(OnlineHub.pending_match_id, "abc123")
	assert_eq(OnlineHub.last_scene(), OnlineHub.ONLINE_SCENE)
	assert_not_null(t)


func test_the_title_stops_listening_when_it_goes_away() -> void:
	var fake: ShareFake = ShareFake.new()
	OnlineHub.set_services(PushService.new(PushFake.new()), GoogleSignIn.new(GoogleSignInFake.new()), ShareService.new(fake), DeepLinks.new(fake))
	var t: TitleScreen = _title()
	await settle(2)
	assert_eq(OnlineHub.links.get_signal_connection_list("join_requested").size(), 1)
	t.free()
	assert_eq(OnlineHub.links.get_signal_connection_list("join_requested").size(), 0)


func test_the_notification_permission_is_asked_once_when_a_lobby_is_made_or_joined() -> void:
	var fake: PushFake = PushFake.new()
	var push: PushService = PushService.new(fake)
	push.start()
	OnlineHub.set_services(push, null, null, null)
	OnlineHub.ask_push_permission_once()
	OnlineHub.ask_push_permission_once()
	assert_eq(fake.permission_requests, 1)


func test_no_permission_question_when_push_is_not_available() -> void:
	var fake: PushFake = PushFake.new()
	fake.available_flag = false
	var push: PushService = PushService.new(fake)
	push.start()
	OnlineHub.set_services(push, null, null, null)
	OnlineHub.ask_push_permission_once()
	assert_eq(fake.permission_requests, 0)


func test_online_preferences_are_saved_and_cleaned_on_load() -> void:
	SettingsStore.online_named = true
	SettingsStore.online_muted = PackedStringArray(["a", "b"])
	assert_true(SettingsStore.save())
	SettingsStore.online_named = false
	SettingsStore.online_muted = PackedStringArray()
	assert_true(SettingsStore.load_into(PREFS))
	assert_true(SettingsStore.online_named)
	assert_eq(SettingsStore.online_muted, PackedStringArray(["a", "b"]))
	var cfg := ConfigFile.new()
	cfg.load(PREFS)
	var junk: Array = ["x".repeat(65), "", 5, "ok"]
	for i: int in range(300):
		junk.append("u%d" % i)
	cfg.set_value("online", "muted", junk)
	cfg.set_value("online", "named", "yes")
	cfg.save(PREFS)
	SettingsStore.load_into(PREFS)
	assert_false(SettingsStore.online_named, "a wrong type counts as not set")
	assert_true(SettingsStore.online_muted.has("ok"))
	assert_false(SettingsStore.online_muted.has(""))
	assert_lte(SettingsStore.online_muted.size(), 200)


func test_unmuting_removes_the_entry() -> void:
	OnlineHub.set_muted("p1", true)
	OnlineHub.set_muted("p1", true)
	assert_eq(SettingsStore.online_muted.size(), 1, "no duplicates")
	OnlineHub.set_muted("p1", false)
	assert_false(OnlineHub.is_muted("p1"))
	assert_false(OnlineHub.is_muted(""))


func test_a_phone_with_two_seats_gets_the_turn_banner_for_each_of_its_seats() -> void:
	var seats: Array = [OnlineFakes.human_seat(OnlineFakes.ME, "HANA"), OnlineFakes.human_seat(OnlineFakes.ME, "HANA 2"), OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA")]
	var fm: OnlineFakes.FakeMatch = OnlineFakes.match_for(OnlineFakes.ME, seats)
	fm.replay.apply_entry({"kind": "ready", "tank": 0})
	fm.replay.apply_entry({"kind": "ready", "tank": 1})
	fm.replay.apply_entry({"kind": "ready", "tank": 2})
	fm._set_stored_turn(fm.replay.expected_turn())
	var b: OnlineBattleController = (load(SCENE) as PackedScene).instantiate()
	b.attach_match(fm)
	b.configure(3, 1, false)
	add_child_autofree(b)
	await settle(2)
	b.get_hud().hide_big_turn()
	# Tank 0 plays and passes: tank 1 is another seat of this phone -> its own banner, in its own name.
	assert_eq(b.get_state().current_tank, 0)
	b.pass_turn()
	await wait_seconds(1.0)
	assert_eq(b.get_state().current_tank, 1)
	assert_true(b.may_act(), "the same phone plays the next seat")
	assert_true(b.get_hud().get_big_banner().visible, "hand over the phone")
	assert_string_contains(b.get_hud().get_big_banner().get_text(), "HANA 2")
	# Then the other player's seat: no banner for somebody else's turn.
	b.get_hud().hide_big_turn()
	b.pass_turn()
	await wait_seconds(1.0)
	assert_eq(b.get_state().current_tank, 2)
	assert_false(b.get_hud().get_big_banner().visible)
	assert_false(b.may_act())
