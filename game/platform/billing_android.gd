class_name BillingAndroid
extends BillingBackend
## Google Play Billing through the vendored GodotGooglePlayBilling plugin (BillingClient, docs/BUILD.md).
## The full game is ONE non-consumable in-app product (Entitlement.PRODUCT_ID).
##
## Play Pass needs no code: Play Billing reports the one-time products of a Play Pass title as owned
## to subscribers, so `queryPurchases` returns `full_unlock` as PURCHASED and the game unlocks as for
## a buyer. (If Play Pass later stops covering the title the query stops returning it and the
## unlock goes away, which is what we want.)
##
## Flow: connect -> query product details (price) + query purchases (what is owned). Every
## PURCHASED purchase that is not acknowledged gets acknowledged (Play refunds unacknowledged
## purchases after 3 days). A PENDING purchase never unlocks; it is picked up by the next query
## (at startup and on every app resume) once the payment settles. A dropped connection reconnects
## with exponential backoff.
##
## The response handlers take plain Dictionaries so tests can feed them without the plugin.

const SINGLETON: String = "GodotGooglePlayBilling"
const RETRY_BASE_SEC: float = 2.0
const RETRY_MAX_SEC: float = 120.0

## What a caller is waiting for while the connection or the product details are not ready yet.
const WAIT_NONE: String = ""
const WAIT_PURCHASE: String = "purchase"

var _client: BillingClient = null
var _details_ready: bool = false
var _waiting: String = WAIT_NONE
var _restoring: bool = false
var _attempt: int = 0
var _retry_scheduled: bool = false
## Product ids of purchases we asked Play to acknowledge (so a refresh never asks twice at once).
var _acking: PackedStringArray = PackedStringArray()


## True when the plugin's Android singleton exists (an Android export with the plugin enabled).
static func plugin_present() -> bool:
	return Engine.has_singleton(SINGLETON)


## Seconds to wait before reconnect attempt number `attempt` (0 = first retry): 2, 4, 8 ... 120.
static func retry_delay(attempt: int) -> float:
	return minf(RETRY_MAX_SEC, RETRY_BASE_SEC * pow(2.0, float(maxi(attempt, 0))))


## Maps a BillingResponseCode to what the player should be told.
static func outcome_for_code(code: int) -> int:
	match code:
		BillingClient.BillingResponseCode.USER_CANCELED:
			return Outcome.CANCELLED
		BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE, BillingClient.BillingResponseCode.NETWORK_ERROR, \
		BillingClient.BillingResponseCode.SERVICE_DISCONNECTED, BillingClient.BillingResponseCode.SERVICE_TIMEOUT:
			return Outcome.NETWORK
		BillingClient.BillingResponseCode.BILLING_UNAVAILABLE, BillingClient.BillingResponseCode.FEATURE_NOT_SUPPORTED, \
		BillingClient.BillingResponseCode.ITEM_UNAVAILABLE:
			return Outcome.UNAVAILABLE
	return Outcome.ERROR


func backend_name() -> String:
	return "android"


func start() -> void:
	if _client == null:
		_client = BillingClient.new()
		_client.connected.connect(_on_connected)
		_client.disconnected.connect(_on_disconnected)
		_client.connect_error.connect(_on_connect_error)
		_client.query_product_details_response.connect(handle_product_details)
		_client.query_purchases_response.connect(handle_purchases)
		_client.on_purchase_updated.connect(handle_purchase_updated)
		_client.acknowledge_purchase_response.connect(_on_acknowledged)
	_connect()


func refresh() -> void:
	start()
	if _client.is_ready():
		_query_details()
		_query_purchases()


func purchase() -> void:
	start()
	_waiting = WAIT_PURCHASE
	if not _client.is_ready():
		return  # _connect() ran in start(); _on_connected continues, _on_connect_error reports
	if not _details_ready:
		_query_details()
		return
	_launch()


func restore() -> void:
	start()
	_restoring = true
	if _client.is_ready():
		_query_purchases()
	# Otherwise _on_connected queries the purchases (it checks _restoring).


# --- connection ---------------------------------------------------------------------------

func _connect() -> void:
	if _client.is_ready():
		return
	if _client.get_connection_state() == BillingClient.ConnectionState.CONNECTING:
		return
	_client.start_connection()


func _on_connected() -> void:
	_attempt = 0
	_query_details()
	_query_purchases()


func _on_disconnected() -> void:
	_details_ready = false
	_schedule_retry()


func _on_connect_error(code: int, _debug_message: String) -> void:
	_details_ready = false
	if _waiting != WAIT_NONE or _restoring:
		_waiting = WAIT_NONE
		_restoring = false
		outcome.emit(outcome_for_code(code))
	_schedule_retry()


## Backoff reconnect: at most one timer at a time, doubling up to RETRY_MAX_SEC.
func _schedule_retry() -> void:
	if _retry_scheduled:
		return
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null:
		return
	_retry_scheduled = true
	var delay: float = retry_delay(_attempt)
	_attempt += 1
	loop.create_timer(delay).timeout.connect(func() -> void:
		_retry_scheduled = false
		if _client != null:
			_connect())


func get_attempt() -> int:
	return _attempt


# --- queries ------------------------------------------------------------------------------

func _query_details() -> void:
	_client.query_product_details(PackedStringArray([Entitlement.PRODUCT_ID]), BillingClient.ProductType.INAPP)


func _query_purchases() -> void:
	_client.query_purchases(BillingClient.ProductType.INAPP)


## query_product_details_response: {response_code, debug_message, product_details: [...]}.
func handle_product_details(response: Dictionary) -> void:
	var code: int = int(response.get("response_code", BillingClient.BillingResponseCode.ERROR))
	_details_ready = false
	if code == BillingClient.BillingResponseCode.OK:
		for d: Variant in _array_of(response, "product_details"):
			if typeof(d) != TYPE_DICTIONARY:
				continue
			var details: Dictionary = d
			if details.get("product_id", "") == Entitlement.PRODUCT_ID:
				_details_ready = true
				var text: String = _formatted_price(details)
				if text != "":
					price.emit(text)
	if _waiting == WAIT_PURCHASE:
		if _details_ready:
			_launch()
		else:
			# Product missing in the Play Console, or the query failed: say so instead of hanging.
			_waiting = WAIT_NONE
			outcome.emit(Outcome.UNAVAILABLE if code == BillingClient.BillingResponseCode.OK else outcome_for_code(code))


static func _formatted_price(details: Dictionary) -> String:
	var offers: Variant = details.get("one_time_purchase_offer_details_list", null)
	if typeof(offers) == TYPE_ARRAY and not (offers as Array).is_empty():
		var first: Variant = (offers as Array)[0]
		if typeof(first) == TYPE_DICTIONARY:
			return str((first as Dictionary).get("formatted_price", ""))
	return ""


## `response[key]` as an Array ([] when missing or of another type).
static func _array_of(response: Dictionary, key: String) -> Array:
	var v: Variant = response.get(key, [])
	return v as Array if typeof(v) == TYPE_ARRAY else []


## query_purchases_response: {response_code, debug_message, purchases: [...]}.
func handle_purchases(response: Dictionary) -> void:
	var asked: bool = _restoring
	_restoring = false
	var code: int = int(response.get("response_code", BillingClient.BillingResponseCode.ERROR))
	if code != BillingClient.BillingResponseCode.OK:
		# A failed query must never take an unlock away: only a restore the player asked for reports it.
		if asked:
			outcome.emit(outcome_for_code(code))
		if code == BillingClient.BillingResponseCode.SERVICE_DISCONNECTED:
			_schedule_retry()
		return
	var owned: bool = false
	var pending: bool = false
	for p: Variant in _array_of(response, "purchases"):
		if typeof(p) != TYPE_DICTIONARY or not _is_ours(p as Dictionary):
			continue
		var purchase_dict: Dictionary = p
		var state: int = int(purchase_dict.get("purchase_state", BillingClient.PurchaseState.UNSPECIFIED_STATE))
		if state == BillingClient.PurchaseState.PURCHASED:
			owned = true
			_acknowledge(purchase_dict)
		elif state == BillingClient.PurchaseState.PENDING:
			pending = true
	if owned:
		ownership.emit(true)
		if asked:
			outcome.emit(Outcome.SUCCESS)
	elif pending:
		outcome.emit(Outcome.PENDING)
	else:
		ownership.emit(false)
		if asked:
			outcome.emit(Outcome.NOT_FOUND)


# --- buying -------------------------------------------------------------------------------

func _launch() -> void:
	_waiting = WAIT_NONE
	var result: Dictionary = _client.purchase(Entitlement.PRODUCT_ID)
	var code: int = int(result.get("response_code", BillingClient.BillingResponseCode.ERROR))
	if code == BillingClient.BillingResponseCode.OK:
		return  # the Play sheet is up; the answer arrives in on_purchase_updated
	if code == BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED:
		_restoring = true  # Play says we own it: ask for the purchase and unlock
		_query_purchases()
		return
	outcome.emit(outcome_for_code(code))


## on_purchase_updated: {response_code, debug_message, purchases?}.
func handle_purchase_updated(response: Dictionary) -> void:
	var code: int = int(response.get("response_code", BillingClient.BillingResponseCode.ERROR))
	if code == BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED:
		_restoring = true
		if _client != null:
			_query_purchases()
		return
	if code != BillingClient.BillingResponseCode.OK:
		outcome.emit(outcome_for_code(code))
		return
	var result: int = Outcome.ERROR
	for p: Variant in _array_of(response, "purchases"):
		if typeof(p) != TYPE_DICTIONARY or not _is_ours(p as Dictionary):
			continue
		var purchase_dict: Dictionary = p
		var state: int = int(purchase_dict.get("purchase_state", BillingClient.PurchaseState.UNSPECIFIED_STATE))
		if state == BillingClient.PurchaseState.PURCHASED:
			_acknowledge(purchase_dict)
			ownership.emit(true)
			result = Outcome.SUCCESS
			break
		if state == BillingClient.PurchaseState.PENDING:
			result = Outcome.PENDING  # not paid yet: do NOT unlock
	outcome.emit(result)


func _is_ours(purchase_dict: Dictionary) -> bool:
	var ids: Variant = purchase_dict.get("product_ids", [])
	if typeof(ids) == TYPE_PACKED_STRING_ARRAY:
		return (ids as PackedStringArray).has(Entitlement.PRODUCT_ID)
	if typeof(ids) == TYPE_ARRAY:
		return (ids as Array).has(Entitlement.PRODUCT_ID)
	return false


func _acknowledge(purchase_dict: Dictionary) -> void:
	if bool(purchase_dict.get("is_acknowledged", false)) or _client == null:
		return
	var token: String = str(purchase_dict.get("purchase_token", ""))
	if token == "" or _acking.has(token):
		return
	_acking.append(token)
	_client.acknowledge_purchase(token)


func _on_acknowledged(_response: Dictionary) -> void:
	# Success or not, the unlock stands. A failed acknowledge shows up again as an
	# unacknowledged purchase in the next query (app resume) and is retried then.
	_acking = PackedStringArray()
