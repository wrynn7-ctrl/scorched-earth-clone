extends GutTest
## BillingAndroid: the unlock is granted before the acknowledge, and wrong-typed or missing plugin
## fields never raise script errors (a malformed purchase simply is not a purchase).

const CACHE: String = "user://test_billing_defensive.cfg"
const OURS: String = "full_unlock"

var _log: Array[String] = []
var _clients: Array[BillingClient] = []
var _b: BillingAndroid = null


func before_each() -> void:
	_log.clear()
	Entitlement.reset_for_tests(false, CACHE)
	_b = BillingAndroid.new()
	Entitlement.set_backend_for_tests(_b)


func after_each() -> void:
	Entitlement.forget_for_tests()
	for c: BillingClient in _clients:
		c.free()
	_clients.clear()
	if FileAccess.file_exists(CACHE):
		DirAccess.remove_absolute(CACHE)


func _with_client() -> void:
	var c := BillingClient.new()
	_clients.append(c)
	_b._client = c


func _purchase(extra: Dictionary = {}) -> Dictionary:
	var p: Dictionary = {"product_ids": [OURS], "purchase_state": BillingClient.PurchaseState.PURCHASED,
			"is_acknowledged": false, "purchase_token": "tok-9"}
	p.merge(extra, true)
	return p


func _watch() -> void:
	_b.ownership.connect(func(owned: bool) -> void:
		_log.append("ownership %s (acking %d)" % [str(owned), _b._acking.size()]))


func test_ownership_is_granted_before_the_acknowledge_in_a_query() -> void:
	_with_client()
	_watch()
	_b.handle_purchases({"response_code": 0, "purchases": [_purchase()]})
	assert_eq(_log, ["ownership true (acking 0)"], "granted while nothing was being acknowledged yet")
	assert_true(_b._acking.has("tok-9"), "and then acknowledged")
	assert_true(Entitlement.is_full())


func test_ownership_is_granted_before_the_acknowledge_after_a_purchase() -> void:
	_with_client()
	_watch()
	_b.handle_purchase_updated({"response_code": 0, "purchases": [_purchase()]})
	assert_eq(_log, ["ownership true (acking 0)"])
	assert_true(_b._acking.has("tok-9"))


func test_wrong_typed_fields_do_not_raise_and_do_not_unlock() -> void:
	_with_client()
	var bad_states: Array = ["yes", null, [], {}, "PURCHASED", INF, NAN]
	for st: Variant in bad_states:
		_b.handle_purchases({"response_code": 0, "purchases": [_purchase({"purchase_state": st})]})
		_b.handle_purchase_updated({"response_code": 0, "purchases": [_purchase({"purchase_state": st})]})
	assert_false(Entitlement.is_full(), "no malformed state unlocks")
	for code: Variant in [null, [], {}, NAN, INF]:
		_b.handle_purchases({"response_code": code, "purchases": [_purchase()]})
		_b.handle_purchase_updated({"response_code": code})
		_b.handle_product_details({"response_code": code, "product_details": [{"product_id": [1]}]})
	assert_false(Entitlement.is_full(), "a malformed response code is an error, never an unlock")


func test_a_malformed_purchase_is_not_a_purchase() -> void:
	_with_client()
	for p: Dictionary in [{}, {"product_ids": "full_unlock"}, {"product_ids": [OURS]}, _purchase({"purchase_state": "yes"}),
			_purchase({"purchase_state": []}), _purchase({"product_ids": null})]:
		Entitlement.reset_for_tests(false, CACHE)
		_b = BillingAndroid.new()
		Entitlement.set_backend_for_tests(_b)
		_b.handle_purchases({"response_code": 0, "purchases": [p]})
		assert_false(Entitlement.is_full(), "not unlocked by %s" % str(p))


func test_odd_acknowledge_fields_do_not_raise() -> void:
	_with_client()
	_b.handle_purchases({"response_code": 0, "purchases": [_purchase({"is_acknowledged": "yes", "purchase_token": 5})]})
	assert_true(Entitlement.is_full(), "the unlock stands")
	assert_true(_b._acking.is_empty(), "no token, nothing to acknowledge")
	_b.handle_purchases({"response_code": 0, "purchases": [_purchase({"is_acknowledged": null, "purchase_token": []})]})
	assert_true(Entitlement.is_full())
	_b.handle_purchases({"response_code": 0, "purchases": [_purchase({"is_acknowledged": "yes"})]})
	assert_true(_b._acking.has("tok-9"), "a string is not a real true: acknowledging is harmless")
