class_name Entitlement
extends RefCounted
## Free vs full version (docs/ARCHITECTURE.md section 32). `Entitlement.is_full()` is the single
## question the UI asks. It is true when the Play purchase `full_unlock` is owned (Play Pass
## subscribers count: Play reports their entitlement as an owned purchase), or the debug override is
## on (debug builds only).
##
## It is an "autoload-style static": no autoload entry is needed. A small hub object carries the
## signals, the billing backend is created on `start()`, and the answer is cached in
## `user://entitlement.cfg` so the game works offline and unlocks at once on the next launch.
## (The cache is a plain file: a determined player can edit it. That is accepted for a $3.99 game;
## the next query to Play corrects it for anyone who is online.)
##
## Backends: BillingAndroid (Play Billing plugin, only when its singleton exists) and BillingFake
## (desktop, tests, plugin missing). The fake only "succeeds" in debug builds.
##
## UI flow: `purchase_full()` / `restore()` -> `hub().status_changed(status)` walks through
## PURCHASING -> SUCCESS | PENDING | ERROR (read `status_message()`); `hub().changed` fires whenever
## `is_full()` flips; `hub().price_changed(text)` when the store's price arrives.

const PRODUCT_ID: String = "full_unlock"
const CACHE_PATH: String = "user://entitlement.cfg"
const SECTION: String = "entitlement"

## Where the UI is in the buy / restore flow.
enum Status {
	IDLE,        ## nothing happening
	PURCHASING,  ## the purchase sheet is up / we are waiting for the store
	RESTORING,   ## a restore was asked for
	PENDING,     ## paid but not settled: the game is NOT unlocked yet
	SUCCESS,     ## the full game was just unlocked (or restored)
	CANCELLED,   ## the player backed out; not an error
	ERROR,       ## see status_message()
}


## The signals live on an object because a static class cannot have any.
class Hub extends RefCounted:
	signal changed
	signal status_changed(status: int)
	signal price_changed(text: String)
	## The purchase token of the owned full game became known (see Entitlement.purchase_token()).
	signal token_changed(token: String)


## Test hook: -1 = ask the engine, 0 = behave as a release build, 1 = behave as a debug build.
static var debug_build_override: int = -1
## Tests point the cache elsewhere (and the headless guard below lets them use it).
static var cache_path: String = CACHE_PATH
## Headless runs (the test suite) must not read or write the developer's real cache, and every
## test that is not about billing expects the full game; tests about the gates call
## reset_for_tests() to choose. Set true to let a headless run use `cache_path`.
static var persist_headless: bool = false
static var headless_default_full: bool = true

static var _hub: Hub = Hub.new()
static var _backend: BillingBackend = null
static var _loaded: bool = false
static var _purchased: bool = false
static var _debug_full: bool = false
static var _price: String = ""
static var _token: String = ""
static var _status: int = Status.IDLE
static var _message_key: String = ""
static var _watcher: Node = null


# --- the question -------------------------------------------------------------------------

static func is_full() -> bool:
	_ensure_loaded()
	return _purchased or (_debug_full and is_debug_build())


## True for the debug override only (the full game is on but not bought).
static func is_debug_full() -> bool:
	_ensure_loaded()
	return _debug_full and is_debug_build()


static func is_debug_build() -> bool:
	if debug_build_override >= 0:
		return debug_build_override == 1
	return OS.is_debug_build()


static func hub() -> Hub:
	return _hub


static func status() -> int:
	return _status


## The translated sentence that goes with the status (empty for IDLE / SUCCESS without detail).
static func status_message() -> String:
	return TranslationServer.translate(StringName(_message_key)) if _message_key != "" else ""


static func status_message_key() -> String:
	return _message_key


## The purchase token of the owned `full_unlock` purchase ("" when not owned, or the store has not told us yet). Online play
## sends it to the server so the server-side `full` flag (needed to host) can be set. Cached with the unlock, so it is there
## right after launch; a store query refreshes it. Not available for the debug override (nothing was bought), except that
## the fake store hands out its own test token in debug builds.
static func purchase_token() -> String:
	_ensure_loaded()
	if _token != "" and _purchased:
		return _token
	if _backend != null and is_full():
		return _backend.owned_token()
	return ""


## The store's localized price once known ("" until then).
static func price_text() -> String:
	return _price


static func backend_name() -> String:
	return _backend.backend_name() if _backend != null else "none"


# --- actions ------------------------------------------------------------------------------

## Connects to the store and refreshes ownership + price. Safe to call often (title, unlock screen).
static func start() -> void:
	_ensure_loaded()
	if _backend == null:
		_backend = _make_backend()
		_backend.ownership.connect(_on_ownership)
		_backend.price.connect(_on_price)
		_backend.outcome.connect(_on_outcome)
		_backend.purchase_token.connect(_on_token)
		_backend.start()
		_add_watcher()
	_backend.refresh()


## Re-reads the store (app resume, opening the unlock screen).
static func refresh() -> void:
	if _backend != null:
		_backend.refresh()


## Opens the purchase flow. Does nothing if the full game is already owned.
static func purchase_full() -> void:
	_ensure_loaded()
	if _purchased:
		_set_status(Status.SUCCESS, "")
		return
	start()
	_set_status(Status.PURCHASING, "")
	_backend.purchase()


## "Restore purchase": asks the store again.
static func restore() -> void:
	_ensure_loaded()
	start()
	_set_status(Status.RESTORING, "")
	_backend.restore()


## Debug builds only: pretend the full game is (not) owned. Ignored in release builds.
static func set_debug_full(on: bool) -> void:
	_ensure_loaded()
	if not is_debug_build():
		return
	var before: bool = is_full()
	_debug_full = on
	_save()
	if is_full() != before:
		_hub.changed.emit()


## Back to "nothing happening" (the unlock screen calls this when it opens or closes).
static func clear_status() -> void:
	if _status != Status.PENDING:
		_set_status(Status.IDLE, "")


# --- backend callbacks --------------------------------------------------------------------

static func _on_ownership(owned: bool) -> void:
	_set_purchased(owned)
	if not owned and _status == Status.PENDING:
		_set_status(Status.IDLE, "")  # the store no longer knows a pending payment (cancelled or expired)


static func _on_token(token: String) -> void:
	_ensure_loaded()
	if token == "" or token == _token:
		return
	_token = token
	_save()
	_hub.token_changed.emit(token)


static func _on_price(text: String) -> void:
	if text != _price:
		_price = text
		_hub.price_changed.emit(text)


static func _on_outcome(kind: int) -> void:
	match kind:
		BillingBackend.Outcome.SUCCESS:
			_set_purchased(true)
			_set_status(Status.SUCCESS, "ENT_SUCCESS")
		BillingBackend.Outcome.PENDING:
			_set_status(Status.PENDING, "ENT_PENDING")
		BillingBackend.Outcome.CANCELLED:
			_set_status(Status.CANCELLED, "ENT_CANCELLED")
		BillingBackend.Outcome.UNAVAILABLE:
			_set_status(Status.ERROR, "ENT_UNAVAILABLE")
		BillingBackend.Outcome.NETWORK:
			_set_status(Status.ERROR, "ENT_NETWORK")
		BillingBackend.Outcome.NOT_FOUND:
			_set_status(Status.ERROR, "ENT_NOT_FOUND")
		_:
			_set_status(Status.ERROR, "ENT_ERROR")


static func _set_purchased(owned: bool) -> void:
	_ensure_loaded()
	if owned == _purchased:
		return
	var before: bool = is_full()
	_purchased = owned
	if not owned:
		_token = ""  # a refund or an expired Play Pass takes the token with it
	_save()
	if is_full() != before:
		_hub.changed.emit()
	if owned and _status == Status.PENDING:
		_set_status(Status.IDLE, "")  # the pending payment went through (found by a refresh)


static func _set_status(status_value: int, key: String) -> void:
	_status = status_value
	_message_key = key
	_hub.status_changed.emit(status_value)


# --- cache --------------------------------------------------------------------------------

static func _headless_guard() -> bool:
	return DisplayServer.get_name() == "headless" and not persist_headless


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if _headless_guard():
		_purchased = headless_default_full
		return
	var cfg := ConfigFile.new()
	if cfg.load(cache_path) != OK:
		return
	var full: Variant = cfg.get_value(SECTION, "full", false)
	_purchased = full as bool if typeof(full) == TYPE_BOOL else false
	var token: Variant = cfg.get_value(SECTION, "token", "")
	_token = token as String if typeof(token) == TYPE_STRING and _purchased else ""
	var dbg: Variant = cfg.get_value(SECTION, "debug_full", false)
	_debug_full = dbg as bool if typeof(dbg) == TYPE_BOOL else false


static func _save() -> void:
	if _headless_guard():
		return
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "full", _purchased)
	cfg.set_value(SECTION, "token", _token)
	cfg.set_value(SECTION, "debug_full", _debug_full)
	cfg.save(cache_path)


# --- backend choice, app resume -----------------------------------------------------------

static func _make_backend() -> BillingBackend:
	if BillingAndroid.plugin_present():
		return BillingAndroid.new()
	return BillingFake.new()


## A tiny node that refreshes ownership when the app returns to the foreground (a pending payment
## may have settled, a refund may have happened).
class Watcher extends Node:
	func _notification(what: int) -> void:
		if what == NOTIFICATION_APPLICATION_RESUMED:
			Entitlement.refresh()


static func _add_watcher() -> void:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null or _watcher != null:
		return
	var w := Watcher.new()
	w.name = "EntitlementWatcher"
	_watcher = w
	# Deferred: start() may run while a scene is still being built (the root is busy then). Passed
	# by id because a test may free the node before the call runs.
	_attach_watcher.call_deferred(w.get_instance_id())


static func _attach_watcher(id: int) -> void:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	var w: Node = instance_from_id(id) as Node
	if w == null or w != _watcher or loop == null or loop.root == null:
		return
	loop.root.add_child(w)


# --- tests --------------------------------------------------------------------------------

## Test hook: a clean entitlement in a known state, an in-memory fake store (no delay) and the
## cache at `path` (deleted first). Call forget_for_tests() in after_each.
static func reset_for_tests(full: bool = false, path: String = "user://test_entitlement.cfg") -> void:
	forget_for_tests()
	cache_path = path
	persist_headless = true
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	_loaded = true
	_purchased = full
	BillingFake.delay_sec = 0.0
	BillingFake.next_result = "success"


## Test hook: back to the pristine process state (full in headless runs, nothing cached).
static func forget_for_tests() -> void:
	if _watcher != null and is_instance_valid(_watcher):
		if _watcher.is_inside_tree():
			_watcher.queue_free()
		else:
			_watcher.free()
	_watcher = null
	_backend = null
	_hub = Hub.new()
	_loaded = false
	_purchased = false
	_debug_full = false
	_price = ""
	_token = ""
	_status = Status.IDLE
	_message_key = ""
	debug_build_override = -1
	cache_path = CACHE_PATH
	persist_headless = false
	headless_default_full = true
	BillingFake.delay_sec = 0.6
	BillingFake.next_result = "success"


## Test hook: replaces the backend (a BillingFake with a fixed behaviour, or a BillingAndroid fed by hand).
static func set_backend_for_tests(backend: BillingBackend) -> void:
	_backend = backend
	_backend.ownership.connect(_on_ownership)
	_backend.price.connect(_on_price)
	_backend.outcome.connect(_on_outcome)
	_backend.purchase_token.connect(_on_token)
