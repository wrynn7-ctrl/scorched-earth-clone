class_name DeepLinks
extends RefCounted
## craterline://join/CODE links (docs/ARCHITECTURE.md section 49), and the match-code rules they depend on.
##
## Android hands a link to the game through the CraterlineShare plugin. A link that OPENED the game is kept until
## `take_pending_code()` is called (call it once the online screens are ready). A link that arrives while the game is
## running emits `join_requested(code)` when something is connected to it, and otherwise waits in the pending slot, so
## every link is delivered exactly once and no handler has to ask for it twice.
##
## Everything here degrades quietly: on desktop, in headless tests and in builds without the plugin, `available` is
## false, nothing is emitted and `take_pending_code()` returns "".

## Match codes (section 45) are 6 characters, friend codes (section 44) 8, from this alphabet: no 0/O/1/I.
const CODE_ALPHABET: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const MATCH_CODE_LENGTH: int = 6
const SCHEME: String = "craterline"
const JOIN_HOST: String = "join"
const MAX_URL_LENGTH: int = 256

## A valid join link arrived while the game was running and a handler is connected. `code` is normalized.
signal join_requested(code: String)

var available: bool = false
var _bridge: Object = null
var _pending_code: String = ""


## `bridge` is the CraterlineShare singleton (or ShareFake in tests). null = look the singleton up (Android only).
func _init(bridge: Object = null) -> void:
	_bridge = bridge if bridge != null else _engine_bridge()
	if _bridge != null and _bridge.has_signal("deep_link_received"):
		_bridge.connect("deep_link_received", _on_link)


## Reads a link that started the game. Safe to call more than once.
func start() -> void:
	available = _bridge != null
	if not available:
		return
	var url: Variant = _bridge.call("consume_pending_link")
	if typeof(url) == TYPE_STRING:
		_accept(url as String)


## The code of a link that is waiting for a handler ("" if none). Clears it.
func take_pending_code() -> String:
	var code: String = _pending_code
	_pending_code = ""
	return code


func has_pending() -> bool:
	return _pending_code != ""


## Picks up a link the plugin kept (call when the app is resumed; cheap). The signal normally makes this unnecessary.
func poll() -> void:
	if _bridge == null:
		return
	var url: Variant = _bridge.call("consume_pending_link")
	if typeof(url) == TYPE_STRING:
		_accept(url as String)


func _on_link(url: String) -> void:
	# The plugin keeps the link until it is consumed; take it so it is not delivered a second time.
	_bridge.call("consume_pending_link")
	_accept(url)


func _accept(url: String) -> void:
	var code: String = parse_join_link(url)
	if code == "":
		return
	if get_signal_connection_list("join_requested").is_empty():
		_pending_code = code
	else:
		join_requested.emit(code)


static func _engine_bridge() -> Object:
	if Engine.has_singleton(ShareService.SINGLETON):
		return Engine.get_singleton(ShareService.SINGLETON)
	return null


# --- parsing (pure, static, easy to test) ---------------------------------------------------------

## "craterline://join/ABC234" -> "ABC234". Anything else (wrong scheme or host, bad code, extra path) -> "".
## The scheme is case-insensitive, a trailing slash, query or fragment is ignored, the code may be lower case.
static func parse_join_link(url: String) -> String:
	var text: String = url.strip_edges()
	if text.length() == 0 or text.length() > MAX_URL_LENGTH:
		return ""
	var prefix: String = "%s://%s/" % [SCHEME, JOIN_HOST]
	if not text.to_lower().begins_with(prefix):
		return ""
	var rest: String = text.substr(prefix.length())
	for stop: String in ["?", "#"]:
		var cut: int = rest.find(stop)
		if cut >= 0:
			rest = rest.substr(0, cut)
	if rest.ends_with("/"):
		rest = rest.substr(0, rest.length() - 1)
	if rest.contains("/"):
		return ""
	return normalize_code(rest, MATCH_CODE_LENGTH, false)


## "craterline://join/ABC234", or "" if the code is not a valid match code.
static func build_join_link(code: String) -> String:
	var normalized: String = normalize_code(code, MATCH_CODE_LENGTH)
	if normalized == "":
		return ""
	return "%s://%s/%s" % [SCHEME, JOIN_HOST, normalized]


## Upper-cases `raw` and returns it when it is exactly `length` characters from CODE_ALPHABET, otherwise "".
## `forgiving` (for typed input) also drops spaces and hyphens, so "abc-234" works.
static func normalize_code(raw: String, length: int = MATCH_CODE_LENGTH, forgiving: bool = true) -> String:
	var code: String = raw.to_upper()
	if forgiving:
		code = code.strip_edges().replace(" ", "").replace("-", "")
	if code.length() != length:
		return ""
	for i: int in code.length():
		if CODE_ALPHABET.find(code[i]) < 0:
			return ""
	return code


static func is_valid_code(code: String, length: int = MATCH_CODE_LENGTH) -> bool:
	return normalize_code(code, length, false) == code and code != ""
