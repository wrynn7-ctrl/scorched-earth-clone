class_name PushService
extends RefCounted
## Push notifications (Firebase Cloud Messaging) through the CraterlinePush plugin (docs/ARCHITECTURE.md sections 47, 49).
##
## `available` is true only on an Android build that has the plugin AND was built with google-services.json AND runs on a
## device with Google Play services. Everywhere else (desktop, headless tests, dev builds without the Firebase config) it
## stays false and every method is a harmless no-op, so callers never need a platform check.
##
## Typical use, once the player is signed in:
##   push.token_changed.connect(...)          # register `token` with the backend (users/{uid}/fcm)
##   push.notification_opened.connect(...)    # open the match named in the payload ("matchId")
##   push.start()                             # reads a tap that launched the game, then asks FCM for the token
## and when the player first creates or joins a match: push.request_permission() (Android 13+ asks; older asks nothing).
##
## A notification tap is delivered exactly once: to `notification_opened` when something is connected to it, otherwise it
## waits for `take_pending_payload()` (the cold start case, where nobody is connected yet).

const SINGLETON: String = "CraterlinePush"
## Payload keys are plain strings; the server puts the match in "matchId" (section 47).
const KEY_MATCH_ID: String = "matchId"
const MAX_ID_LENGTH: int = 64

## FCM gave us a (new) token. Register it with the backend.
signal token_changed(token: String)
## FCM could not give a token (no network, no Play services, push not built in).
signal token_failed(reason: String)
## The answer to request_permission().
signal permission_result(granted: bool)
## The player tapped a notification; `payload` holds its data keys (String -> String), at least one.
signal notification_opened(payload: Dictionary)

var available: bool = false
var token: String = ""
var _bridge: Object = null
var _pending_payload: Dictionary = {}


## `bridge` is the CraterlinePush singleton (or PushFake in tests). null = look the singleton up (Android only).
func _init(bridge: Object = null) -> void:
	_bridge = bridge if bridge != null else _engine_bridge()
	if _bridge == null:
		return
	if _bridge.has_signal("token_changed"):
		_bridge.connect("token_changed", _on_token)
	if _bridge.has_signal("token_error"):
		_bridge.connect("token_error", _on_token_error)
	if _bridge.has_signal("permission_result"):
		_bridge.connect("permission_result", _on_permission)
	if _bridge.has_signal("notification_opened"):
		_bridge.connect("notification_opened", _on_opened)


static func _engine_bridge() -> Object:
	if Engine.has_singleton(SINGLETON):
		return Engine.get_singleton(SINGLETON)
	return null


## Checks availability, picks up a launch tap and asks FCM for the token. Safe to call again (it refreshes).
func start() -> void:
	available = _bridge != null and _bridge.call("is_available") == true
	if not available:
		return
	poll()
	refresh_token()


func refresh_token() -> void:
	if available:
		_bridge.call("refresh_token")


## True when notifications may be shown (always true below Android 13, and false when unavailable).
func has_permission() -> bool:
	return available and _bridge.call("has_notification_permission") == true


## Android 13+ shows the system permission dialog; the answer arrives as `permission_result`. Unavailable: answers false.
func request_permission() -> void:
	if not available:
		permission_result.emit(false)
		return
	_bridge.call("request_notification_permission")


## Names the "Turns" notification channel for the player's language (pass tr() text).
func ensure_channel(channel_name: String, description: String) -> void:
	if available:
		_bridge.call("ensure_channel", channel_name, description)


## Picks up a tap the plugin kept (call when the app is resumed; cheap). The signal normally makes this unnecessary.
func poll() -> void:
	if _bridge == null:
		return
	var json: Variant = _bridge.call("consume_launch_payload")
	if typeof(json) == TYPE_STRING:
		_accept(parse_payload(json as String))


## The payload of a tap that is waiting for a handler ({} if none). Clears it.
func take_pending_payload() -> Dictionary:
	var payload: Dictionary = _pending_payload
	_pending_payload = {}
	return payload


func has_pending() -> bool:
	return not _pending_payload.is_empty()


## The match a payload points at, or "" when it has none (or something that is not a plausible id).
static func match_id_of(payload: Dictionary) -> String:
	var value: Variant = payload.get(KEY_MATCH_ID, "")
	if typeof(value) != TYPE_STRING:
		return ""
	var id: String = value as String
	if id.is_empty() or id.length() > MAX_ID_LENGTH:
		return ""
	for i: int in id.length():
		var c: String = id[i]
		var ok: bool = (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "-" or c == "_"
		if not ok:
			return ""
	return id


## The plugin sends the payload as a JSON object of strings. Anything else (garbage, arrays, nested values) -> {}.
static func parse_payload(json: String) -> Dictionary:
	if json.strip_edges() == "":
		return {}
	# JSON.new().parse() reports a problem through its return code; JSON.parse_string() would also log an engine error.
	var parser: JSON = JSON.new()
	if parser.parse(json) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = {}
	var source: Dictionary = parser.data
	for key: Variant in source.keys():
		var text: String = _scalar_text(source[key])
		if typeof(key) == TYPE_STRING and text != "":
			out[key] = text
	return out


## Strings, numbers and booleans become text ("3.0" -> "3"); nested values and null become "" (dropped).
static func _scalar_text(value: Variant) -> String:
	match typeof(value):
		TYPE_STRING:
			return value as String
		TYPE_BOOL:
			return str(value)
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			var f: float = value as float
			return str(int(f)) if is_finite(f) and f == floorf(f) and absf(f) < 1e15 else str(f)
	return ""


func _on_token(value: String) -> void:
	if value == "":
		return
	var changed: bool = value != token
	token = value
	if changed:
		token_changed.emit(value)


func _on_token_error(reason: String) -> void:
	token_failed.emit(reason)


func _on_permission(granted: bool) -> void:
	permission_result.emit(granted)


func _on_opened(json: String) -> void:
	# The plugin keeps the payload until it is consumed; take it so it is not delivered a second time.
	_bridge.call("consume_launch_payload")
	_accept(parse_payload(json))


func _accept(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	if get_signal_connection_list("notification_opened").is_empty():
		_pending_payload = payload
	else:
		notification_opened.emit(payload)
