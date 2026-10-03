extends GutTest
## Entitlement (free vs full): the cache, the fake store, pending / cancelled / failed purchases,
## restore, the release-build behaviour of the fake store, the debug override, and the Android
## backend's response handling (fed with hand-made plugin dictionaries).

const CACHE: String = "user://test_entitlement_a.cfg"
const OK: int = 0
const PURCHASED: int = 1
const PENDING: int = 2

var _changes: Array[int] = [0]
var _clients: Array[BillingClient] = []


func before_each() -> void:
	Entitlement.reset_for_tests(false, CACHE)
	_changes[0] = 0
	Entitlement.hub().changed.connect(func() -> void: _changes[0] += 1)


func after_each() -> void:
	for c: BillingClient in _clients:
		c.free()
	_clients.clear()
	Entitlement.forget_for_tests()
	if FileAccess.file_exists(CACHE):
		DirAccess.remove_absolute(CACHE)


func _purchase(state: int, ack: bool = false, product: String = Entitlement.PRODUCT_ID) -> Dictionary:
	return {"purchase_state": state, "is_acknowledged": ack, "purchase_token": "tok-1",
			"product_ids": PackedStringArray([product])}


func _ok(purchases: Array) -> Dictionary:
	return {"response_code": OK, "debug_message": "", "purchases": purchases}


# --- the fake store -------------------------------------------------------------------------

func test_free_until_something_is_bought() -> void:
	assert_false(Entitlement.is_full())
	assert_eq(Entitlement.PRODUCT_ID, "full_unlock")
	assert_eq(Entitlement.status(), Entitlement.Status.IDLE)


func test_fake_purchase_unlocks_and_emits_changed_once() -> void:
	Entitlement.purchase_full()
	assert_true(Entitlement.is_full())
	assert_eq(_changes[0], 1, "changed fired exactly once")
	assert_eq(Entitlement.status(), Entitlement.Status.SUCCESS)
	assert_eq(Entitlement.status_message(), "Full game unlocked.")
	Entitlement.purchase_full()  # already owned: nothing happens, no second signal
	assert_eq(_changes[0], 1)


func test_fake_purchase_takes_a_short_delay_in_debug_builds() -> void:
	BillingFake.delay_sec = 0.05
	Entitlement.debug_build_override = 1
	Entitlement.purchase_full()
	assert_false(Entitlement.is_full(), "not yet")
	assert_eq(Entitlement.status(), Entitlement.Status.PURCHASING)
	await wait_seconds(0.3)
	assert_true(Entitlement.is_full())
	assert_eq(_changes[0], 1)


func test_price_arrives_from_the_store() -> void:
	assert_eq(Entitlement.price_text(), "", "unknown until the store answers")
	var seen: Array[String] = []
	Entitlement.hub().price_changed.connect(func(t: String) -> void: seen.append(t))
	Entitlement.debug_build_override = 1
	Entitlement.start()
	assert_eq(Entitlement.price_text(), BillingFake.FAKE_PRICE)
	assert_eq(seen, [BillingFake.FAKE_PRICE] as Array[String])


# --- cache ----------------------------------------------------------------------------------

func test_the_unlock_is_cached_and_survives_a_restart() -> void:
	Entitlement.purchase_full()
	assert_true(FileAccess.file_exists(CACHE))
	# A new process: nothing in memory, the same cache file.
	Entitlement.forget_for_tests()
	Entitlement.cache_path = CACHE
	Entitlement.persist_headless = true
	assert_true(Entitlement.is_full(), "works offline from the cache")


func test_a_damaged_cache_means_free() -> void:
	var f: FileAccess = FileAccess.open(CACHE, FileAccess.WRITE)
	f.store_string("this is not a config file {{{")
	f.close()
	Entitlement.forget_for_tests()
	Entitlement.cache_path = CACHE
	Entitlement.persist_headless = true
	assert_false(Entitlement.is_full())


func test_a_cache_with_the_wrong_type_means_free() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(Entitlement.SECTION, "full", "yes")
	cfg.save(CACHE)
	Entitlement.forget_for_tests()
	Entitlement.cache_path = CACHE
	Entitlement.persist_headless = true
	assert_false(Entitlement.is_full())


func test_headless_runs_default_to_the_full_game_and_never_touch_the_real_cache() -> void:
	Entitlement.forget_for_tests()
	assert_true(Entitlement.is_full(), "tests that are not about billing expect the full game")
	Entitlement.cache_path = CACHE  # but without persist_headless nothing is written
	Entitlement.set_debug_full(true)
	assert_false(FileAccess.file_exists(CACHE), "a headless run writes no cache")


# --- restore --------------------------------------------------------------------------------

func test_restore_finds_the_purchase() -> void:
	var fake := BillingFake.new()
	fake.store_owned = true
	Entitlement.set_backend_for_tests(fake)
	Entitlement.restore()
	assert_true(Entitlement.is_full())
	assert_eq(Entitlement.status(), Entitlement.Status.SUCCESS)
	assert_eq(_changes[0], 1)


func test_restore_without_a_purchase_says_so() -> void:
	Entitlement.debug_build_override = 1
	Entitlement.set_backend_for_tests(BillingFake.new())
	Entitlement.restore()
	assert_false(Entitlement.is_full())
	assert_eq(Entitlement.status(), Entitlement.Status.ERROR)
	assert_eq(Entitlement.status_message(), "No earlier purchase found for this Google account.")
	assert_eq(_changes[0], 0)


# --- pending, cancel, errors ----------------------------------------------------------------

func test_a_pending_purchase_does_not_unlock() -> void:
	Entitlement.debug_build_override = 1
	BillingFake.next_result = "pending"
	Entitlement.purchase_full()
	assert_false(Entitlement.is_full())
	assert_eq(Entitlement.status(), Entitlement.Status.PENDING)
	assert_string_contains(Entitlement.status_message(), "pending")
	assert_eq(_changes[0], 0)
	Entitlement.clear_status()
	assert_eq(Entitlement.status(), Entitlement.Status.PENDING, "a pending payment is not forgotten")
	# The payment settles later: the next refresh reports ownership and the unlock arrives.
	var fake: BillingBackend = BillingFake.new()
	Entitlement.set_backend_for_tests(fake)
	fake.ownership.emit(true)
	assert_true(Entitlement.is_full())
	assert_eq(Entitlement.status(), Entitlement.Status.IDLE)
	assert_eq(_changes[0], 1)


func test_a_pending_purchase_that_vanishes_clears_the_pending_state() -> void:
	Entitlement.debug_build_override = 1
	BillingFake.next_result = "pending"
	Entitlement.purchase_full()
	var fake: BillingBackend = BillingFake.new()
	Entitlement.set_backend_for_tests(fake)
	fake.ownership.emit(false)  # a successful query found nothing: the payment was cancelled
	assert_eq(Entitlement.status(), Entitlement.Status.IDLE)
	assert_false(Entitlement.is_full())


func test_cancel_is_not_an_error_and_does_not_unlock() -> void:
	Entitlement.debug_build_override = 1
	BillingFake.next_result = "cancel"
	Entitlement.purchase_full()
	assert_false(Entitlement.is_full())
	assert_eq(Entitlement.status(), Entitlement.Status.CANCELLED)
	assert_string_contains(Entitlement.status_message(), "not charged")


func test_network_and_other_errors_leave_the_game_locked() -> void:
	Entitlement.debug_build_override = 1
	BillingFake.next_result = "network"
	Entitlement.purchase_full()
	assert_eq(Entitlement.status(), Entitlement.Status.ERROR)
	assert_string_contains(Entitlement.status_message(), "Can't reach the store")
	BillingFake.next_result = "error"
	Entitlement.purchase_full()
	assert_eq(Entitlement.status(), Entitlement.Status.ERROR)
	assert_string_contains(Entitlement.status_message(), "Something went wrong")
	assert_false(Entitlement.is_full())
	# And the next try works.
	Entitlement.purchase_full()
	assert_true(Entitlement.is_full())


# --- release builds -------------------------------------------------------------------------

func test_the_fake_store_is_unavailable_in_release_builds() -> void:
	Entitlement.debug_build_override = 0
	Entitlement.purchase_full()
	assert_false(Entitlement.is_full(), "a shipped game never hands out the full version for free")
	assert_eq(Entitlement.status(), Entitlement.Status.ERROR)
	assert_eq(Entitlement.status_message(), "Store unavailable")
	Entitlement.restore()
	assert_false(Entitlement.is_full())
	assert_eq(Entitlement.status_message(), "Store unavailable")
	Entitlement.start()
	assert_eq(Entitlement.price_text(), "", "no price from a store that does not exist")


func test_the_debug_override_does_nothing_in_release_builds() -> void:
	Entitlement.debug_build_override = 0
	Entitlement.set_debug_full(true)
	assert_false(Entitlement.is_full())
	assert_false(Entitlement.is_debug_full())
	# Not even through a cache file somebody edited.
	var cfg := ConfigFile.new()
	cfg.set_value(Entitlement.SECTION, "full", false)
	cfg.set_value(Entitlement.SECTION, "debug_full", true)
	cfg.save(CACHE)
	Entitlement.forget_for_tests()
	Entitlement.cache_path = CACHE
	Entitlement.persist_headless = true
	Entitlement.debug_build_override = 0
	assert_false(Entitlement.is_full())


func test_the_debug_override_flips_full_and_is_remembered() -> void:
	Entitlement.debug_build_override = 1
	Entitlement.set_debug_full(true)
	assert_true(Entitlement.is_full())
	assert_true(Entitlement.is_debug_full())
	assert_eq(_changes[0], 1)
	Entitlement.set_debug_full(true)
	assert_eq(_changes[0], 1, "no signal without a change")
	Entitlement.forget_for_tests()
	Entitlement.cache_path = CACHE
	Entitlement.persist_headless = true
	Entitlement.debug_build_override = 1
	assert_true(Entitlement.is_full(), "the toggle survives a restart")
	Entitlement.set_debug_full(false)
	assert_false(Entitlement.is_full())


# --- the Android backend (fed with plugin-shaped dictionaries) --------------------------------

## A plugin-less BillingClient (every call is a no-op), freed after the test.
func _client() -> BillingClient:
	var c := BillingClient.new()
	_clients.append(c)
	return c


func _android() -> BillingAndroid:
	var b := BillingAndroid.new()
	Entitlement.set_backend_for_tests(b)
	return b


func test_play_reports_the_purchase_as_owned() -> void:
	var b: BillingAndroid = _android()
	b.handle_purchases(_ok([_purchase(PURCHASED, true)]))
	assert_true(Entitlement.is_full())
	assert_eq(_changes[0], 1)


func test_other_products_do_not_unlock() -> void:
	var b: BillingAndroid = _android()
	b.handle_purchases(_ok([_purchase(PURCHASED, true, "something_else")]))
	assert_false(Entitlement.is_full())


func test_a_pending_purchase_in_a_query_does_not_unlock_but_is_shown() -> void:
	var b: BillingAndroid = _android()
	b.handle_purchases(_ok([_purchase(PENDING)]))
	assert_false(Entitlement.is_full())
	assert_eq(Entitlement.status(), Entitlement.Status.PENDING)
	# Later the same purchase is PURCHASED: unlocked, and acknowledged.
	b._client = _client()
	b.handle_purchases(_ok([_purchase(PURCHASED)]))
	assert_true(Entitlement.is_full())
	assert_eq(Entitlement.status(), Entitlement.Status.IDLE)
	assert_true(b._acking.has("tok-1"), "unacknowledged purchases are acknowledged")


func test_acknowledged_purchases_are_not_acknowledged_again() -> void:
	var b: BillingAndroid = _android()
	b._client = _client()
	b.handle_purchases(_ok([_purchase(PURCHASED, true)]))
	assert_true(b._acking.is_empty())


func test_a_failed_query_never_takes_the_unlock_away() -> void:
	Entitlement.reset_for_tests(true, CACHE)
	var b: BillingAndroid = _android()
	b.handle_purchases({"response_code": BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE, "debug_message": "offline"})
	assert_true(Entitlement.is_full())
	b.handle_purchases({"response_code": BillingClient.BillingResponseCode.ERROR, "debug_message": ""})
	assert_true(Entitlement.is_full())


func test_a_successful_empty_query_after_a_refund_locks_again() -> void:
	Entitlement.reset_for_tests(true, CACHE)
	var b: BillingAndroid = _android()
	Entitlement.hub().changed.connect(func() -> void: pass)
	b.handle_purchases(_ok([]))
	assert_false(Entitlement.is_full())


func test_purchase_updated_success_unlocks() -> void:
	var b: BillingAndroid = _android()
	b.handle_purchase_updated(_ok([_purchase(PURCHASED)]))
	assert_true(Entitlement.is_full())
	assert_eq(Entitlement.status(), Entitlement.Status.SUCCESS)


func test_purchase_updated_pending_does_not_unlock() -> void:
	var b: BillingAndroid = _android()
	b.handle_purchase_updated(_ok([_purchase(PENDING)]))
	assert_false(Entitlement.is_full())
	assert_eq(Entitlement.status(), Entitlement.Status.PENDING)


func test_purchase_updated_errors_map_to_messages() -> void:
	var b: BillingAndroid = _android()
	b.handle_purchase_updated({"response_code": BillingClient.BillingResponseCode.USER_CANCELED, "debug_message": ""})
	assert_eq(Entitlement.status(), Entitlement.Status.CANCELLED)
	b.handle_purchase_updated({"response_code": BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE, "debug_message": ""})
	assert_eq(Entitlement.status_message_key(), "ENT_NETWORK")
	b.handle_purchase_updated({"response_code": BillingClient.BillingResponseCode.BILLING_UNAVAILABLE, "debug_message": ""})
	assert_eq(Entitlement.status_message_key(), "ENT_UNAVAILABLE")
	b.handle_purchase_updated({"response_code": BillingClient.BillingResponseCode.DEVELOPER_ERROR, "debug_message": ""})
	assert_eq(Entitlement.status_message_key(), "ENT_ERROR")
	assert_false(Entitlement.is_full())


func test_already_owned_triggers_a_requery_instead_of_an_error() -> void:
	var b: BillingAndroid = _android()
	b.handle_purchase_updated({"response_code": BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED, "debug_message": ""})
	assert_eq(Entitlement.status(), Entitlement.Status.IDLE, "no error shown")
	# The query that follows reports the purchase.
	b.handle_purchases(_ok([_purchase(PURCHASED, true)]))
	assert_true(Entitlement.is_full())


func test_restore_through_the_android_backend() -> void:
	var b: BillingAndroid = _android()
	b._restoring = true
	b.handle_purchases(_ok([]))
	assert_eq(Entitlement.status_message_key(), "ENT_NOT_FOUND")
	b._restoring = true
	b.handle_purchases(_ok([_purchase(PURCHASED, true)]))
	assert_true(Entitlement.is_full())
	assert_eq(Entitlement.status(), Entitlement.Status.SUCCESS)


func test_product_details_give_the_localized_price() -> void:
	var b: BillingAndroid = _android()
	b.handle_product_details({"response_code": OK, "debug_message": "", "product_details": [{
		"product_id": Entitlement.PRODUCT_ID,
		"one_time_purchase_offer_details_list": [{"formatted_price": "3,99 €", "price_amount_micros": 3990000}],
	}]})
	assert_eq(Entitlement.price_text(), "3,99 €")


func test_a_missing_product_reports_unavailable_to_a_waiting_buyer() -> void:
	var b: BillingAndroid = _android()
	b._waiting = BillingAndroid.WAIT_PURCHASE
	b.handle_product_details({"response_code": OK, "debug_message": "", "product_details": []})
	assert_eq(Entitlement.status_message_key(), "ENT_UNAVAILABLE")


func test_reconnect_backoff_doubles_up_to_two_minutes() -> void:
	assert_eq(BillingAndroid.retry_delay(0), 2.0)
	assert_eq(BillingAndroid.retry_delay(1), 4.0)
	assert_eq(BillingAndroid.retry_delay(2), 8.0)
	assert_eq(BillingAndroid.retry_delay(5), 64.0)
	assert_eq(BillingAndroid.retry_delay(6), 120.0)
	assert_eq(BillingAndroid.retry_delay(40), 120.0, "capped")
	assert_eq(BillingAndroid.retry_delay(-3), 2.0)


func test_a_disconnect_schedules_one_retry_and_a_connect_resets_the_backoff() -> void:
	var b: BillingAndroid = _android()
	b._client = _client()
	b._on_disconnected()
	b._on_disconnected()
	assert_eq(b.get_attempt(), 1, "one timer at a time")
	b._on_connected()
	assert_eq(b.get_attempt(), 0)


func test_a_connect_error_tells_a_waiting_buyer() -> void:
	var b: BillingAndroid = _android()
	b._client = _client()
	b._waiting = BillingAndroid.WAIT_PURCHASE
	b._on_connect_error(BillingClient.BillingResponseCode.BILLING_UNAVAILABLE, "no play store")
	assert_eq(Entitlement.status_message_key(), "ENT_UNAVAILABLE")


func test_the_plugin_is_absent_on_desktop() -> void:
	assert_false(BillingAndroid.plugin_present())
	Entitlement.forget_for_tests()
	Entitlement.persist_headless = false
	Entitlement.start()
	assert_eq(Entitlement.backend_name(), "fake", "desktop and tests use the fake store")
