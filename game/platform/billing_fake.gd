class_name BillingFake
extends BillingBackend
## The stand-in store for desktop, the test suite and devices where the Play Billing plugin is
## missing. In a debug build a purchase "succeeds" after a short delay, so the whole unlock flow
## (loading, pending, success, error) can be tried without Google Play. In a release build it
## reports "Store unavailable": a shipped game must never hand out the full version for free.

const FAKE_PRICE: String = "$3.99"

## Seconds a debug purchase takes. 0 = answer at once (tests).
static var delay_sec: float = 0.6
## What the next debug purchase does: "success", "pending", "cancel", "network" or "error".
## Tests use it to exercise every branch; it resets to "success" after one use.
static var next_result: String = "success"

## True once a debug purchase succeeded: what a later restore() finds "in the store".
var store_owned: bool = false
var _busy: bool = false


func backend_name() -> String:
	return "fake"


func start() -> void:
	if Entitlement.is_debug_build():
		price.emit(FAKE_PRICE)


func refresh() -> void:
	if Entitlement.is_debug_build():
		price.emit(FAKE_PRICE)
		# A real store would confirm ownership here; only say so when we know it.
		if store_owned:
			ownership.emit(true)


func purchase() -> void:
	if not Entitlement.is_debug_build():
		outcome.emit(Outcome.UNAVAILABLE)
		return
	if _busy:
		return
	_busy = true
	var result: String = next_result
	next_result = "success"
	_after_delay(func() -> void: _finish(result))


func restore() -> void:
	if not Entitlement.is_debug_build():
		outcome.emit(Outcome.UNAVAILABLE)
		return
	_after_delay(func() -> void:
		if store_owned:
			ownership.emit(true)
			outcome.emit(Outcome.SUCCESS)
		else:
			outcome.emit(Outcome.NOT_FOUND))


func _finish(result: String) -> void:
	_busy = false
	match result:
		"pending":
			outcome.emit(Outcome.PENDING)
		"cancel":
			outcome.emit(Outcome.CANCELLED)
		"network":
			outcome.emit(Outcome.NETWORK)
		"error":
			outcome.emit(Outcome.ERROR)
		_:
			store_owned = true
			ownership.emit(true)
			outcome.emit(Outcome.SUCCESS)


func _after_delay(action: Callable) -> void:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if delay_sec <= 0.0 or loop == null:
		action.call()
		return
	loop.create_timer(delay_sec).timeout.connect(action)
