extends GutTest
## The purchase token of the owned full game (ARCHITECTURE section 53): Entitlement hands it to online play, BillingAndroid
## reads it from the Play results, BillingFake answers with "test-full", and it never outlives the unlock.

const CACHE: String = "user://test_purchase_token.cfg"
const PURCHASED: int = 1
const PENDING: int = 2

var _clients: Array[BillingClient] = []


func before_each() -> void:
	Entitlement.reset_for_tests(false, CACHE)


func after_each() -> void:
	for c: BillingClient in _clients:
		c.free()
	_clients.clear()
	Entitlement.forget_for_tests()
	if FileAccess.file_exists(CACHE):
		DirAccess.remove_absolute(CACHE)


func _purchase(state: int, token: Variant = "tok-77", product: String = Entitlement.PRODUCT_ID) -> Dictionary:
	return {"purchase_state": state, "is_acknowledged": true, "purchase_token": token,
			"product_ids": PackedStringArray([product])}


func _ok(purchases: Array) -> Dictionary:
	return {"response_code": 0, "debug_message": "", "purchases": purchases}


func _android() -> BillingAndroid:
	var b := BillingAndroid.new()
	Entitlement.set_backend_for_tests(b)
	return b


# --- BillingFake --------------------------------------------------------------------------------------------------

func test_nothing_owned_means_no_token() -> void:
	assert_eq(Entitlement.purchase_token(), "")


func test_a_fake_purchase_gives_the_test_token_before_the_unlock_signal() -> void:
	var order: Array[String] = []
	Entitlement.hub().token_changed.connect(func(t: String) -> void: order.append("token " + t))
	Entitlement.hub().changed.connect(func() -> void: order.append("changed"))
	Entitlement.purchase_full()
	assert_true(Entitlement.is_full())
	assert_eq(Entitlement.purchase_token(), "test-full")
	assert_eq(order, ["token test-full", "changed"], "a listener of `changed` already finds the token")


func test_the_fake_store_has_no_token_in_a_release_build() -> void:
	Entitlement.debug_build_override = 0
	var fake := BillingFake.new()
	fake.store_owned = true
	assert_eq(fake.owned_token(), "")


func test_the_debug_override_on_the_fake_store_still_has_the_test_token() -> void:
	# Nothing was bought, but a desktop developer on the emulator can still host.
	Entitlement.debug_build_override = 1
	Entitlement.set_debug_full(true)
	assert_true(Entitlement.is_full())
	assert_eq(Entitlement.purchase_token(), "", "no store yet")
	Entitlement.start()
	assert_eq(Entitlement.purchase_token(), BillingFake.FAKE_TOKEN)


func test_restore_on_the_fake_store_announces_the_token() -> void:
	var seen: Array[String] = []
	Entitlement.hub().token_changed.connect(func(t: String) -> void: seen.append(t))
	var fake := BillingFake.new()
	fake.store_owned = true
	Entitlement.set_backend_for_tests(fake)
	Entitlement.restore()
	assert_eq(seen, ["test-full"])


# --- BillingAndroid -----------------------------------------------------------------------------------------------

func test_a_query_with_the_owned_purchase_gives_its_token() -> void:
	var b: BillingAndroid = _android()
	b.handle_purchases(_ok([_purchase(PURCHASED)]))
	assert_true(Entitlement.is_full())
	assert_eq(Entitlement.purchase_token(), "tok-77")
	assert_eq(b.owned_token(), "tok-77")


func test_a_purchase_result_gives_its_token() -> void:
	var b: BillingAndroid = _android()
	b.handle_purchase_updated({"response_code": 0, "purchases": [_purchase(PURCHASED, "tok-new")]})
	assert_eq(Entitlement.purchase_token(), "tok-new")


func test_a_pending_purchase_has_no_token_and_does_not_unlock() -> void:
	var b: BillingAndroid = _android()
	b.handle_purchases(_ok([_purchase(PENDING)]))
	assert_eq(Entitlement.purchase_token(), "")
	assert_eq(b.owned_token(), "")


func test_another_product_gives_no_token() -> void:
	var b: BillingAndroid = _android()
	b.handle_purchases(_ok([_purchase(PURCHASED, "tok-other", "something_else")]))
	assert_eq(Entitlement.purchase_token(), "")


func test_a_missing_or_odd_token_is_ignored_without_errors() -> void:
	var b: BillingAndroid = _android()
	for odd: Variant in [null, 7, [], {}, ""]:
		b.handle_purchases(_ok([_purchase(PURCHASED, odd)]))
	assert_true(Entitlement.is_full(), "the unlock itself does not depend on the token")
	assert_eq(Entitlement.purchase_token(), "")


func test_a_refund_takes_the_token_away() -> void:
	var b: BillingAndroid = _android()
	b.handle_purchases(_ok([_purchase(PURCHASED)]))
	assert_eq(Entitlement.purchase_token(), "tok-77")
	b.handle_purchases(_ok([]))
	assert_false(Entitlement.is_full())
	assert_eq(Entitlement.purchase_token(), "")
	assert_eq(b.owned_token(), "")


func test_a_failed_query_keeps_the_token() -> void:
	var b: BillingAndroid = _android()
	b.handle_purchases(_ok([_purchase(PURCHASED)]))
	b.handle_purchases({"response_code": BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE, "debug_message": "offline"})
	assert_eq(Entitlement.purchase_token(), "tok-77")


func test_the_token_is_cached_with_the_unlock() -> void:
	var b: BillingAndroid = _android()
	b.handle_purchases(_ok([_purchase(PURCHASED)]))
	Entitlement.forget_for_tests()
	Entitlement.persist_headless = true
	Entitlement.cache_path = CACHE
	assert_true(Entitlement.is_full(), "restored from the cache")
	assert_eq(Entitlement.purchase_token(), "tok-77", "no store query needed after a restart")


func test_a_cached_token_without_the_unlock_is_not_used() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(Entitlement.SECTION, "full", false)
	cfg.set_value(Entitlement.SECTION, "token", "stale")
	cfg.save(CACHE)
	Entitlement.forget_for_tests()
	Entitlement.persist_headless = true
	Entitlement.cache_path = CACHE
	assert_false(Entitlement.is_full())
	assert_eq(Entitlement.purchase_token(), "")
