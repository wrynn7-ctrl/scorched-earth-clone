extends OnlineTestBase
## The server-side full flag (ARCHITECTURE section 53): a full owner's purchase token goes to `verifyPurchase` once after
## sign-in, in the background, and a failure shows the "needs the full game on this account" strip with RETRY.

const SCREEN: String = "res://ui/online/online_screen.tscn"

var _net: OnlineFakes.FakeNet = null


## A store that reports nothing by itself (a refresh does not reach Play in tests).
class QuietBilling:
	extends BillingBackend


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


## Owns the full game through Play, with this purchase token.
func _own(token: String = "tok-77") -> BillingAndroid:
	var b := BillingAndroid.new()
	Entitlement.set_backend_for_tests(b)
	b.handle_purchases({"response_code": 0, "purchases": [{"purchase_state": BillingClient.PurchaseState.PURCHASED,
			"is_acknowledged": true, "purchase_token": token, "product_ids": PackedStringArray([Entitlement.PRODUCT_ID])}]})
	return b


func test_a_full_owner_sends_the_token_once_and_the_profile_becomes_full() -> void:
	_own()
	var s: OnlineScreen = _screen()
	await settle()
	assert_eq(_net.sc.count("verify_purchase"), 1)
	assert_eq(_net.sc.last("verify_purchase")["args"], ["tok-77"])
	assert_true(_net.account.is_full(), "the profile reads full afterwards")
	assert_false(s.get_full_notice().visible)
	assert_eq(s.get_gate(), OnlineScreen.Gate.NONE)
	s.show_tab(OnlineScreen.Tab.FRIENDS)
	s.show_tab(OnlineScreen.Tab.MATCHES)
	await settle()
	assert_eq(_net.sc.count("verify_purchase"), 1, "not again while the screen stays")


func test_a_server_that_already_knows_sends_nothing() -> void:
	_own()
	_net.account.profile["full"] = true
	_screen()
	await settle()
	assert_eq(_net.sc.count("verify_purchase"), 0)


func test_a_free_player_sends_nothing() -> void:
	var s: OnlineScreen = _screen()
	await settle()
	assert_eq(_net.sc.count("verify_purchase"), 0)
	assert_false(s.get_full_notice().visible)


func test_a_failure_shows_the_message_with_retry_and_does_not_block_anything() -> void:
	_own()
	_net.sc.replies["verify_purchase"] = NetResult.failure(NetError.Code.ALREADY_EXISTS, "token_used")
	var s: OnlineScreen = _screen()
	await settle()
	assert_true(s.get_full_notice().visible)
	var label: Label = s.get_full_notice().find_child("Text", true, false) as Label
	assert_string_contains(label.text, "needs the full game on this account")
	assert_eq(s.get_full_retry_button().text, "RETRY")
	assert_eq(s.get_gate(), OnlineScreen.Gate.NONE, "no gate: the other tabs keep working")
	for i: int in range(4):
		assert_false(s.get_tab_button(i).disabled)
	s.show_tab(OnlineScreen.Tab.FRIENDS)
	assert_eq(s.current_tab(), OnlineScreen.Tab.FRIENDS)
	assert_eq(_net.sc.count("verify_purchase"), 1, "tried once; no automatic repeat")


func test_retry_verifies_again_and_clears_the_message_on_success() -> void:
	_own()
	_net.sc.replies["verify_purchase"] = NetResult.failure(NetError.Code.OFFLINE, "offline")
	var s: OnlineScreen = _screen()
	await settle()
	assert_true(s.get_full_notice().visible)
	_net.sc.replies.erase("verify_purchase")
	s.get_full_retry_button().pressed.emit()
	await settle()
	assert_eq(_net.sc.count("verify_purchase"), 2)
	assert_false(s.get_full_notice().visible)
	assert_true(_net.account.is_full())
	assert_false(s.get_full_retry_button().disabled)


func test_a_failed_retry_keeps_the_message() -> void:
	_own()
	_net.sc.replies["verify_purchase"] = NetResult.failure(NetError.Code.SERVER, "server")
	var s: OnlineScreen = _screen()
	await settle()
	s.get_full_retry_button().pressed.emit()
	await settle()
	assert_eq(_net.sc.count("verify_purchase"), 2)
	assert_true(s.get_full_notice().visible)
	assert_false(s.get_full_retry_button().disabled, "RETRY can be pressed again")


func test_a_cached_unlock_waits_for_the_store_to_report_the_token() -> void:
	Entitlement.reset_for_tests(true)
	var store := QuietBilling.new()
	Entitlement.set_backend_for_tests(store)
	var s: OnlineScreen = _screen()
	await settle()
	assert_eq(_net.sc.count("verify_purchase"), 0, "no token yet: nothing to send")
	assert_false(s.get_full_notice().visible, "and no alarm either")
	store.purchase_token.emit("tok-late")
	await settle()
	assert_eq(_net.sc.last("verify_purchase")["args"], ["tok-late"])
	assert_true(_net.account.is_full())


func test_the_debug_override_uses_the_fake_stores_test_token() -> void:
	Entitlement.reset_for_tests(false)
	Entitlement.debug_build_override = 1
	Entitlement.set_debug_full(true)
	_screen()
	await settle()
	assert_eq(_net.sc.last("verify_purchase")["args"], ["test-full"])


func test_buying_while_the_screen_is_open_verifies_at_once() -> void:
	var s: OnlineScreen = _screen()
	await settle()
	assert_eq(_net.sc.count("verify_purchase"), 0)
	Entitlement.purchase_full()
	await settle()
	assert_eq(_net.sc.last("verify_purchase")["args"], ["test-full"])
	assert_true(_net.account.is_full())
	assert_false(s.get_full_notice().visible)


func test_the_notice_text_and_button_use_existing_strings() -> void:
	var s: OnlineScreen = _screen()
	await settle()
	var label: Label = s.get_full_notice().find_child("Text", true, false) as Label
	assert_eq(label.text, tr("NET_ERR_FULL_REQUIRED"))
	assert_ne(label.text, "NET_ERR_FULL_REQUIRED", "the key exists in strings.csv")
