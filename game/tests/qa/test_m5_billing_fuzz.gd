@warning_ignore_start("integer_division")
extends GutTest
## M5 QA: the Play Billing response handlers (BillingAndroid, fed with hand-made plugin dictionaries) and
## the Entitlement behind them. Random answers from the "store" must never unlock the full game unless a
## PURCHASED purchase of our product is in the answer, a failed query must never take an unlock away, and a
## pending payment must never unlock. An oracle tracks the expected state through 4000 random responses.

const CACHE: String = "user://qa_m5_billing.cfg"
const OURS: String = "full_unlock"

var _backend: BillingAndroid = null


func before_each() -> void:
	Entitlement.reset_for_tests(false, CACHE)
	_backend = BillingAndroid.new()
	Entitlement.set_backend_for_tests(_backend)


func after_each() -> void:
	Entitlement.forget_for_tests()
	if FileAccess.file_exists(CACHE):
		DirAccess.remove_absolute(CACHE)


func _pick(rng: Rng, options: Array) -> Variant:
	return options[rng.range_int(0, options.size() - 1)]


func _random_code(rng: Rng) -> Variant:
	# Mostly OK, sometimes every other documented code, sometimes the odd number types a bridge could produce.
	match rng.range_int(0, 9):
		0, 1, 2, 3:
			return 0
		4:
			return _pick(rng, [1, 2, 3, 4, 5, 6, 7, 8, 12, -1, -2, -3, 99, -99])
		5:
			return 0.0
		6:
			return "0"
		7:
			return _pick(rng, [7.0, "7", 1.0, "abc", ""])
		_:
			return 0


func _random_product_ids(rng: Rng) -> Variant:
	return _pick(rng, [[OURS], PackedStringArray([OURS]), ["other"], [], [OURS, "x"], ["x", OURS], ["FULL_UNLOCK"],
			OURS, null, 5, [5], [null], {}, PackedStringArray(), PackedStringArray(["a", "b"]), [OURS, OURS]])


func _random_state(rng: Rng) -> Variant:
	return _pick(rng, [0, 1, 1, 1, 2, 2, 3, -1, 1.0, 2.0, "1", "2", 1.5, true, 99])


func _random_purchase(rng: Rng) -> Variant:
	if rng.range_int(0, 11) == 0:
		return _pick(rng, [null, 5, "full_unlock", [], [OURS], PackedStringArray([OURS])])
	var p: Dictionary = {}
	if rng.range_int(0, 9) != 0:
		p["product_ids"] = _random_product_ids(rng)
	if rng.range_int(0, 9) != 0:
		p["purchase_state"] = _random_state(rng)
	if rng.range_int(0, 1) == 0:
		p["is_acknowledged"] = _pick(rng, [true, false, 0, 1])
	if rng.range_int(0, 1) == 0:
		p["purchase_token"] = _pick(rng, ["tok", "", 5, "x".repeat(2000)])
	return p


func _random_response(rng: Rng, with_purchases: bool = true) -> Dictionary:
	var r: Dictionary = {}
	if rng.range_int(0, 14) != 0:
		r["response_code"] = _random_code(rng)
	if rng.range_int(0, 1) == 0:
		r["debug_message"] = _pick(rng, ["", "x", 5, null])
	if with_purchases and rng.range_int(0, 9) != 0:
		var list: Array = []
		for _i: int in range(rng.range_int(0, 4)):
			list.append(_random_purchase(rng))
		r["purchases"] = list if rng.range_int(0, 14) != 0 else _pick(rng, [null, "x", 5, {}, PackedStringArray()])
	return r


## int() the way the handlers read a value; null (not castable) counts as "UNSPECIFIED / ERROR".
func _as_int(v: Variant, fallback: int) -> int:
	if v == null or typeof(v) == TYPE_ARRAY or typeof(v) == TYPE_DICTIONARY or typeof(v) == TYPE_PACKED_STRING_ARRAY:
		return fallback
	return int(v)


func _is_ours(p: Variant) -> bool:
	if typeof(p) != TYPE_DICTIONARY:
		return false
	var ids: Variant = (p as Dictionary).get("product_ids", [])
	if typeof(ids) == TYPE_PACKED_STRING_ARRAY:
		return (ids as PackedStringArray).has(OURS)
	if typeof(ids) == TYPE_ARRAY:
		return (ids as Array).has(OURS)
	return false


## Counts (purchased, pending) purchases of our product in a response.
func _tally(r: Dictionary) -> Vector2i:
	var list: Variant = r.get("purchases", [])
	var owned: int = 0
	var pend: int = 0
	if typeof(list) == TYPE_ARRAY:
		for p: Variant in (list as Array):
			if not _is_ours(p):
				continue
			var st: int = _as_int((p as Dictionary).get("purchase_state", 0), 0)
			if st == BillingClient.PurchaseState.PURCHASED:
				owned += 1
			elif st == BillingClient.PurchaseState.PENDING:
				pend += 1
	return Vector2i(owned, pend)


func test_random_store_answers_follow_the_unlock_oracle() -> void:
	var rng: Rng = Rng.derive(31337, 11)
	var full: bool = false
	var unlocks: int = 0
	var bad: Array[String] = []
	var kinds: Dictionary = {"purchases": 0, "updated": 0, "details": 0}
	for step: int in range(4000):
		var kind: int = rng.range_int(0, 2)
		var r: Dictionary = _random_response(rng, kind != 2)
		var code: int = _as_int(r.get("response_code", BillingClient.BillingResponseCode.ERROR), BillingClient.BillingResponseCode.ERROR)
		var t: Vector2i = _tally(r)
		match kind:
			0:
				kinds["purchases"] += 1
				_backend.handle_purchases(r)
				if code == BillingClient.BillingResponseCode.OK:
					if t.x > 0:
						full = true
					elif t.y == 0:
						full = false  # the store says "nothing owned": a successful query is allowed to revoke
			1:
				kinds["updated"] += 1
				_backend.handle_purchase_updated(r)
				if code == BillingClient.BillingResponseCode.OK and t.x > 0:
					full = true
			_:
				kinds["details"] += 1
				_backend.handle_product_details(r)
		if Entitlement.is_full() != full:
			bad.append("step %d (%s): is_full %s, oracle %s, response %s" % [step, ["purchases", "updated", "details"][kind],
					str(Entitlement.is_full()), str(full), str(r)])
			full = Entitlement.is_full()  # resync so one divergence does not flood the report
		unlocks += 1 if full else 0
		if bad.size() > 8:
			break
	gut.p("BILLING FUZZ  4000 random answers %s, full for %d of them" % [str(kinds), unlocks])
	assert_eq(bad.size(), 0, "Entitlement diverged from the oracle:\n  " + "\n  ".join(bad.slice(0, 8)))
	assert_gt(unlocks, 100, "the fuzz reached the unlocked state")
	assert_lt(unlocks, 3900, "and the locked state")


func test_pending_and_failed_answers_never_unlock_and_failed_queries_never_revoke() -> void:
	var pending: Dictionary = {"response_code": 0, "purchases": [{"product_ids": [OURS], "purchase_state": 2, "is_acknowledged": false, "purchase_token": "t"}]}
	_backend.handle_purchases(pending)
	assert_false(Entitlement.is_full(), "a pending payment does not unlock")
	_backend.handle_purchase_updated(pending)
	assert_false(Entitlement.is_full())
	assert_eq(Entitlement.status(), Entitlement.Status.PENDING)
	var bought: Dictionary = {"response_code": 0, "purchases": [{"product_ids": [OURS], "purchase_state": 1, "is_acknowledged": true}]}
	_backend.handle_purchases(bought)
	assert_true(Entitlement.is_full())
	for code: int in [-3, -2, -1, 1, 2, 3, 4, 5, 6, 8, 12]:
		_backend.handle_purchases({"response_code": code, "purchases": []})
		assert_true(Entitlement.is_full(), "failed query code %d must not revoke" % code)
	_backend.handle_purchases({"purchases": []})
	assert_true(Entitlement.is_full(), "an answer without a response code is a failure, not 'owns nothing'")
	_backend.handle_purchases({"response_code": 0, "purchases": []})
	assert_false(Entitlement.is_full(), "a successful query that lists nothing is a refund")
	# Somebody else's purchase never counts, whatever its state.
	_backend.handle_purchases({"response_code": 0, "purchases": [{"product_ids": ["remove_ads"], "purchase_state": 1}]})
	assert_false(Entitlement.is_full())
	_backend.handle_purchases({"response_code": 0, "purchases": [{"product_ids": [OURS], "purchase_state": 0}]})
	assert_false(Entitlement.is_full(), "an unspecified state is not a purchase")


func test_the_cache_file_follows_the_live_answer_after_garbage_responses() -> void:
	_backend.handle_purchases({"response_code": 0, "purchases": [{"product_ids": [OURS], "purchase_state": 1, "is_acknowledged": true}]})
	assert_true(Entitlement.is_full())
	for junk: Dictionary in [{}, {"response_code": 6}, {"response_code": "x"}, {"purchases": "x"}, {"response_code": 0, "purchases": 5}]:
		_backend.handle_purchases(junk)
		_backend.handle_purchase_updated(junk)
		_backend.handle_product_details(junk)
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(CACHE), OK)
	var cached: bool = cfg.get_value(Entitlement.SECTION, "full", false) as bool
	var live: bool = Entitlement.is_full()
	assert_eq(cached, live, "the cache file follows the live answer")
