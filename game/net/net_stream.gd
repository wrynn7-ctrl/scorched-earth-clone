class_name NetStream
extends Node
## One Server-Sent-Events subscription to a database path (REST streaming), kept alive for as long as it is open.
##
## Events (from the database's `put` and `patch`) arrive as `event_received(kind, path, data)` with ints already
## normalized; with `cache` on, the stream also keeps `value` (the whole node, updated by every event) and emits
## `value_changed(value)`. Keep-alives only reset the stall timer.
##
## Reconnects by itself, with exponential backoff (0.5 s doubling to 15 s, plus jitter), after a network error, a stall
## (no byte for STALL_SEC), a server `cancel` or an `auth_revoked` (the latter gets a fresh token first). The database
## resends the current data after every reconnect, so a subscriber that applies events idempotently catches up for free.
## A refusal (401/403, or `cancel`) is not retried: `denied(reason)` is emitted and the stream closes.
##
## Emitted `connected()` when the first data of a connection arrives and `disconnected()` when it goes away.

signal event_received(kind: String, path: String, data: Variant)
signal value_changed(value: Variant)
signal connected()
signal disconnected()
signal denied(reason: String)

enum State { IDLE, WAIT, TOKEN, CONNECTING, REQUESTING, STREAMING, CLOSED }

const STALL_SEC: float = 75.0
const BACKOFF_FIRST: float = 0.5
const BACKOFF_MAX: float = 15.0
const MAX_REDIRECTS: int = 3

var state: int = State.IDLE
var value: Variant = null
var path: String = ""
var is_connected_now: bool = false
## How many times the stream has (re)connected successfully; a test can wait for it to grow.
var connect_count: int = 0

var _db: NetDb = null
var _params: Variant = {}
var _cache: bool = true
var _client: HTTPClient = HTTPClient.new()
var _wait_left: float = 0.0
var _attempt: int = 0
var _stall_left: float = STALL_SEC
var _buf: PackedByteArray = PackedByteArray()
var _event: String = ""
var _data_lines: PackedStringArray = PackedStringArray()
var _redirect: String = ""
var _redirects: int = 0
var _denied_once: bool = false
var _token_epoch: int = 0
var _connect_started: bool = false
var _pending_request: String = ""


func setup(db: NetDb, db_path: String, params: Variant, cache: bool) -> void:
	_db = db
	path = db_path
	_params = params
	_cache = cache
	name = "NetStream_" + db_path.replace("/", "_")


func start() -> void:
	if state == State.IDLE:
		_begin(0.0)


func close() -> void:
	if state == State.CLOSED:
		return
	_drop_connection()
	state = State.CLOSED
	if is_inside_tree():
		queue_free()


## Test hook and "the network went away": closes the socket and reconnects after `hold_sec`.
func drop(hold_sec: float = 0.05) -> void:
	if state == State.CLOSED:
		return
	_drop_connection()
	_begin(hold_sec)


func _begin(delay: float) -> void:
	state = State.WAIT
	_wait_left = delay
	_connect_started = false


func _process(delta: float) -> void:
	match state:
		State.WAIT:
			_wait_left -= delta
			if _wait_left <= 0.0 and not _connect_started:
				_connect_started = true
				_connect()
		State.CONNECTING:
			_poll_connecting()
		State.REQUESTING:
			_poll_requesting()
		State.STREAMING:
			_poll_streaming(delta)


## Fetches a token (a coroutine), then opens the socket.
func _connect() -> void:
	state = State.TOKEN
	_token_epoch += 1
	var epoch: int = _token_epoch
	var token: String = await _db.auth.token()
	if state != State.TOKEN or epoch != _token_epoch:
		return
	if token == "":
		_retry_later()
		return
	var target: String = _redirect if _redirect != "" else _db.url(path, _current_params(), token)
	_redirect = ""
	var parts: Dictionary = _split_url(target)
	_client = HTTPClient.new()
	var tls: TLSOptions = TLSOptions.client() if (parts["tls"] as bool) else null
	var err: int = _client.connect_to_host(parts["host"] as String, parts["port"] as int, tls)
	if err != OK:
		_retry_later()
		return
	_pending_request = parts["request"] as String
	state = State.CONNECTING


func _current_params() -> Dictionary:
	if typeof(_params) == TYPE_CALLABLE:
		return (_params as Callable).call() as Dictionary
	return _params as Dictionary


func _poll_connecting() -> void:
	_client.poll()
	match _client.get_status():
		HTTPClient.STATUS_CONNECTED:
			var headers: PackedStringArray = PackedStringArray(["Accept: text/event-stream", "Cache-Control: no-cache"])
			if _client.request(HTTPClient.METHOD_GET, _pending_request, headers) != OK:
				_retry_later()
				return
			state = State.REQUESTING
		HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			_retry_later()


func _poll_requesting() -> void:
	_client.poll()
	var status: int = _client.get_status()
	if status == HTTPClient.STATUS_BODY or (status == HTTPClient.STATUS_CONNECTED and _client.has_response()):
		var code: int = _client.get_response_code()
		if code == 200:
			_buf = PackedByteArray()
			_event = ""
			_data_lines = PackedStringArray()
			_stall_left = STALL_SEC
			_redirects = 0
			_denied_once = false
			state = State.STREAMING
		elif code in [301, 302, 303, 307, 308] and _redirects < MAX_REDIRECTS:
			var headers: Dictionary = _client.get_response_headers_as_dictionary()
			var location: String = ""
			for k: Variant in headers.keys():
				if str(k).to_lower() == "location":
					location = str(headers[k])
			_drop_connection()
			if location == "":
				_retry_later()
			else:
				_redirects += 1
				_redirect = location
				_begin(0.0)
		elif code == 401 or code == 403:
			_drop_connection()
			_on_refused("http_%d" % code)
		else:
			_drop_connection()
			_retry_later()
	elif status == HTTPClient.STATUS_DISCONNECTED or status == HTTPClient.STATUS_CONNECTION_ERROR or status == HTTPClient.STATUS_CANT_CONNECT:
		_retry_later()


func _poll_streaming(delta: float) -> void:
	_client.poll()
	var status: int = _client.get_status()
	if status == HTTPClient.STATUS_BODY:
		var got: bool = false
		for _i: int in range(64):
			var chunk: PackedByteArray = _client.read_response_body_chunk()
			if chunk.is_empty():
				break
			got = true
			_buf.append_array(chunk)
		if got:
			_stall_left = STALL_SEC
			_consume()
			if state != State.STREAMING:
				return
	else:
		# The server closed the stream or the network is gone.
		_retry_later()
		return
	_stall_left -= delta
	if _stall_left <= 0.0:
		_retry_later()


## Splits complete lines off the byte buffer and feeds the SSE parser.
func _consume() -> void:
	var buf: PackedByteArray = _buf
	var start: int = 0
	var n: int = buf.size()
	var i: int = 0
	while i < n:
		if buf[i] == 10:
			var line: String = buf.slice(start, i).get_string_from_utf8()
			if line.ends_with("\r"):
				line = line.substr(0, line.length() - 1)
			start = i + 1
			_feed_line(line)
			if state != State.STREAMING:
				return  # a handler dropped the connection: the rest of the buffer belongs to a dead socket
		i += 1
	_buf = buf.slice(start)


func _feed_line(line: String) -> void:
	if line == "":
		if _event != "" or not _data_lines.is_empty():
			var kind: String = _event
			var data_text: String = "\n".join(_data_lines)
			_event = ""
			_data_lines = PackedStringArray()
			_dispatch(kind, data_text)
		return
	if line.begins_with(":"):
		return
	if line.begins_with("event:"):
		_event = line.substr(6).strip_edges()
	elif line.begins_with("data:"):
		_data_lines.append(line.substr(5).strip_edges(true, false))


func _dispatch(kind: String, data_text: String) -> void:
	var parsed: Dictionary = NetJson.try_parse(data_text)
	if not (parsed["ok"] as bool):
		return
	_attempt = 0
	if not is_connected_now:
		is_connected_now = true
		connect_count += 1
		connected.emit()
	match kind:
		"put", "patch":
			var payload: Variant = parsed["value"]
			if typeof(payload) != TYPE_DICTIONARY:
				return
			var d: Dictionary = payload as Dictionary
			var p: String = d.get("path", "/")
			var data: Variant = d.get("data", null)
			if _cache:
				_apply(kind, p, data)
			event_received.emit(kind, p, data)
			if _cache:
				value_changed.emit(value)
		"keep-alive":
			pass
		"cancel":
			_drop_connection()
			_on_refused("cancelled")
		"auth_revoked":
			# The token expired while connected: reconnect at once with a fresh one.
			_drop_connection()
			_refresh_then_retry()


## put replaces the node at `p`; patch merges the children of `data` into it.
func _apply(kind: String, p: String, data: Variant) -> void:
	var parts: PackedStringArray = _path_parts(p)
	if kind == "put":
		value = _set_path(value, parts, 0, data)
		return
	if typeof(data) != TYPE_DICTIONARY:
		return
	var d: Dictionary = data as Dictionary
	for k: Variant in d.keys():
		var sub: PackedStringArray = parts.duplicate()
		for piece: String in str(k).split("/", false):
			sub.append(piece)
		value = _set_path(value, sub, 0, d[k])


static func _path_parts(p: String) -> PackedStringArray:
	return p.split("/", false)


## Returns `node` with `data` stored at parts[depth..]; null data removes the key. Containers are Dictionaries (an Array
## from a snapshot is converted to one, keyed "0", "1", ...: use NetJson.as_list to read it back).
static func _set_path(node: Variant, parts: PackedStringArray, depth: int, data: Variant) -> Variant:
	if depth >= parts.size():
		return data
	var dict: Dictionary
	if typeof(node) == TYPE_DICTIONARY:
		dict = node as Dictionary
	elif typeof(node) == TYPE_ARRAY:
		dict = {}
		var a: Array = node as Array
		for i: int in range(a.size()):
			if a[i] != null:
				dict[str(i)] = a[i]
	else:
		dict = {}
	var key: String = parts[depth]
	var child: Variant = _set_path(dict.get(key, null), parts, depth + 1, data)
	if child == null:
		dict.erase(key)
	else:
		dict[key] = child
	return dict if not dict.is_empty() else null


func _on_refused(reason: String) -> void:
	if reason == "http_401" and not _denied_once:
		# Possibly just an expired token: refresh once and try again before giving up.
		_denied_once = true
		_mark_disconnected()
		_refresh_then_retry()
		return
	_mark_disconnected()
	state = State.CLOSED
	denied.emit(reason)
	if is_inside_tree():
		queue_free()


func _refresh_then_retry() -> void:
	state = State.TOKEN
	await _db.auth.refresh()
	if state == State.TOKEN:
		_begin(0.0)


func _retry_later() -> void:
	_drop_connection()
	_attempt += 1
	var wait: float = minf(BACKOFF_FIRST * pow(2.0, float(_attempt - 1)), BACKOFF_MAX) + randf() * 0.3
	_begin(wait)


func _drop_connection() -> void:
	_client.close()
	_buf = PackedByteArray()
	_mark_disconnected()


func _mark_disconnected() -> void:
	if is_connected_now:
		is_connected_now = false
		disconnected.emit()


static func _split_url(url: String) -> Dictionary:
	var tls: bool = url.begins_with("https://")
	var rest: String = url.substr(8 if tls else 7)
	var slash: int = rest.find("/")
	var authority: String = rest if slash < 0 else rest.substr(0, slash)
	var request: String = "/" if slash < 0 else rest.substr(slash)
	var host: String = authority
	var port: int = 443 if tls else 80
	var colon: int = authority.rfind(":")
	if colon >= 0 and authority.find("]") < colon:
		host = authority.substr(0, colon)
		port = authority.substr(colon + 1).to_int()
	return {"tls": tls, "host": host, "port": port, "request": request}
