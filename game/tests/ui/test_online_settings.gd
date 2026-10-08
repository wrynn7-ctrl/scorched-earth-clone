extends OnlineTestBase
## Online account settings: the name, Sign in with Google (and when it says "unavailable"), the notifications button and
## "Delete my online data" with its double confirmation and local sign-out.

var _net: OnlineFakes.FakeNet = null
var _push_fake: PushFake = null
var _google_fake: GoogleSignInFake = null


func before_each() -> void:
	super.before_each()
	_net = OnlineFakes.net()
	_net.config.web_client_id = "1234.apps.googleusercontent.com"
	OnlineHub.session = _net
	_push_fake = PushFake.new()
	_google_fake = GoogleSignInFake.new()
	var push: PushService = PushService.new(_push_fake)
	push.start()
	var google: GoogleSignIn = GoogleSignIn.new(_google_fake)
	google.start()
	OnlineHub.set_services(push, google, ShareService.new(ShareFake.new()), DeepLinks.new(ShareFake.new()))


func _panel() -> OnlineSettings:
	var p := OnlineSettings.new()
	add_child_autofree(p)
	p.open_panel()
	await settle(3)
	return p


func test_the_panel_shows_who_is_signed_in_and_the_name() -> void:
	var p: OnlineSettings = await _panel()
	assert_string_contains(p.get_status_text(), "Signed in as ME")
	assert_eq(p.get_name_field().text, "ME")


func test_saving_a_name_goes_through_the_account_and_is_remembered() -> void:
	var p: OnlineSettings = await _panel()
	p.get_name_field().set_name_text("kai")
	p.save_name()
	await settle(3)
	assert_eq(_net.sc.last("set_name")["args"], ["KAI"])
	assert_true(SettingsStore.online_named)
	assert_string_contains(p.get_hint_text(), "Name saved")


func test_a_blocked_name_is_refused_with_a_message() -> void:
	var p: OnlineSettings = await _panel()
	p.get_name_field().text = "fuck"
	p.save_name()
	await settle(3)
	assert_string_contains(p.get_hint_text(), "isn't allowed")


func test_the_panel_signs_in_by_itself_when_the_title_never_opened_online() -> void:
	OnlineHub.session = null
	var net2: OnlineFakes.FakeNet = OnlineFakes.net()
	net2.fake_account.profile = {}
	net2.auth._refresh_token = ""
	OnlineHub.session = net2
	var p: OnlineSettings = await _panel()
	assert_eq(net2.sc.count("start"), 1)
	assert_string_contains(p.get_status_text(), "Signed in as")


func test_google_sign_in_links_the_account() -> void:
	var p: OnlineSettings = await _panel()
	assert_false(p.get_google_button().disabled)
	assert_eq(p.get_google_button().text, "SIGN IN WITH GOOGLE")
	p.sign_in_google()
	await settle(3)
	assert_eq(_net.sc.count("link_google"), 1)
	assert_string_contains(p.get_hint_text(), "linked")
	assert_true(p.get_google_button().disabled)
	assert_string_contains(p.get_google_button().text, "LINKED")


func test_cancelling_the_google_sheet_says_nothing() -> void:
	_net.sc.replies["link_google"] = NetResult.failure(NetError.Code.CANCELLED, "cancelled")
	var p: OnlineSettings = await _panel()
	p.sign_in_google()
	await settle(3)
	assert_eq(p.get_hint_text(), "")
	assert_false(p.get_google_button().disabled, "the player can try again")


func test_a_google_account_that_is_already_used_offers_to_switch_to_it() -> void:
	_net.sc.replies["link_google"] = NetResult.failure(NetError.Code.PRECONDITION, "google_already_linked")
	var p: OnlineSettings = await _panel()
	p.sign_in_google()
	await settle(3)
	assert_string_contains(p.get_hint_text(), "already has a Charred Horizons account")
	assert_true(p.get_google_restore_button().get_parent().visible)
	p.restore_with_google()
	await settle(3)
	assert_eq(_net.sc.count("restore_with_google"), 1)
	assert_eq(_net.sc.count("ensure_profile"), 1, "the new account's profile is loaded")
	assert_false(p.get_google_restore_button().get_parent().visible)


func test_google_says_unavailable_without_the_plugin() -> void:
	_google_fake.available_flag = false
	OnlineHub.google.start()
	var p: OnlineSettings = await _panel()
	assert_eq(p.get_google_button().text, "UNAVAILABLE")
	assert_true(p.get_google_button().disabled)
	assert_eq(_google_fake.sign_in_calls, 0)


func test_google_says_unavailable_without_a_client_id() -> void:
	_net.config.web_client_id = ""
	var p: OnlineSettings = await _panel()
	assert_eq(p.get_google_button().text, "UNAVAILABLE")
	assert_true(p.get_google_button().disabled)


func test_the_notification_button_asks_for_the_permission() -> void:
	var p: OnlineSettings = await _panel()
	assert_eq(p.get_notify_button().text, "ALLOW")
	p.request_notifications()
	await settle(2)
	assert_eq(_push_fake.permission_requests, 1)
	assert_eq(p.get_notify_button().text, "ON")
	assert_true(p.get_notify_button().disabled)


func test_a_refused_notification_permission_explains() -> void:
	_push_fake.permission_answer = false
	var p: OnlineSettings = await _panel()
	p.request_notifications()
	await settle(2)
	assert_string_contains(p.get_hint_text(), "Notifications are off")
	assert_eq(p.get_notify_button().text, "ALLOW")


func test_notifications_say_unavailable_when_the_phone_has_no_push() -> void:
	_push_fake.available_flag = false
	OnlineHub.push.start()
	var p: OnlineSettings = await _panel()
	assert_eq(p.get_notify_button().text, "UNAVAILABLE")
	assert_true(p.get_notify_button().disabled)


func test_deleting_my_data_needs_two_confirmations() -> void:
	var p: OnlineSettings = await _panel()
	p.ask_delete()
	assert_true(p.get_confirm().is_open())
	assert_string_contains(p.get_confirm().get_message_text(), "Delete all your online data")
	p.get_confirm().get_no_button().pressed.emit()
	await settle()
	assert_eq(_net.sc.count("delete_my_data"), 0, "cancel at the first question")
	p.ask_delete()
	p.get_confirm().get_yes_button().pressed.emit()
	await settle()
	assert_true(p.get_confirm().is_open(), "a second question follows")
	assert_string_contains(p.get_confirm().get_message_text(), "cannot be undone")
	assert_eq(_net.sc.count("delete_my_data"), 0, "still nothing deleted")
	p.get_confirm().get_no_button().pressed.emit()
	await settle()
	assert_eq(_net.sc.count("delete_my_data"), 0, "cancel at the second question")


func test_confirming_twice_deletes_and_signs_out_locally() -> void:
	SettingsStore.online_named = true
	var p: OnlineSettings = await _panel()
	p.ask_delete()
	p.get_confirm().get_yes_button().pressed.emit()
	await settle()
	p.get_confirm().get_yes_button().pressed.emit()
	await settle(3)
	assert_eq(_net.sc.count("delete_my_data"), 1)
	assert_false(SettingsStore.online_named, "the next visit asks for a name again")
	assert_null(OnlineHub.session, "the session is gone")
	assert_string_contains(p.get_status_text(), "deleted")
	assert_string_contains(p.get_hint_text(), "signed out")
	assert_eq(_net.closed_count, 1)


func test_a_failed_delete_keeps_everything() -> void:
	_net.sc.replies["delete_my_data"] = NetResult.failure(NetError.Code.OFFLINE, "offline")
	SettingsStore.online_named = true
	var p: OnlineSettings = await _panel()
	p.delete_now()
	await settle(3)
	assert_true(SettingsStore.online_named)
	assert_eq(OnlineHub.session, _net)
	assert_string_contains(p.get_hint_text(), "No connection")


func test_the_settings_screen_has_the_row_and_hides_it_during_a_match() -> void:
	var so := SettingsOverlay.new()
	add_child_autofree(so)
	assert_true(so.get_online_button().is_visible_in_tree() or not so.visible)
	assert_true(so.get_online_button().get_parent().visible)
	so.set_in_match(true)
	assert_false(so.get_online_button().get_parent().visible)
	so.set_in_match(false)
	so.get_online_button().pressed.emit()
	await settle(3)
	assert_true(so.get_online_settings().is_open())
