class_name NetHttp
extends RefCounted
## One JSON request over HTTPRequest, with a timeout, retry on NETWORK errors only (never on an HTTP error answer), and
## the answer mapped to a NetResult with a typed code.
##
## Retries: GET, PUT, PATCH and DELETE are safe to repeat (a lost answer just repeats the same write; the rules refuse a
## duplicate log entry and the client then looks at the log). A POST (callable functions) is repeated only when the
## request provably never left the phone (could not resolve or connect).
##
## `transport` can be replaced in tests: a Callable (method: int, url: String, headers: PackedStringArray, body: String,
## timeout_sec: float) -> Dictionary {result: int, code: int, headers: PackedStringArray, body: PackedByteArray}.
## It may be a coroutine. `HTTPRequest.RESULT_*` values are used for `result`.

var timeout_sec: float = 15.0
var max_attempts: int = 3
## First wait between attempts; doubles each time (300 ms, 600 ms, ...).
var backoff_ms: int = 300
var transport: Callable = Callable()
## Counts every request that went out (retries included); handy in tests.
var sent: int = 0


## `body` is sent as is; use `json_request` for JSON. `idempotent` decides what a retry may do (see above).
func request(method: int, url: String, headers: PackedStringArray = PackedStringArray(), body: String = "",
		idempotent: bool = true) -> NetResult:
	var attempt: int = 0
	while true:
		attempt += 1
		sent += 1
		var raw: Dictionary = await _send(method, url, headers, body)
		var res: NetResult = interpret(raw)
		if res.ok or attempt >= max_attempts or not _may_retry(res, raw, idempotent):
			return res
		await wait_seconds(float(backoff_ms * (1 << (attempt - 1))) / 1000.0)
	return NetResult.failure(NetError.Code.SERVER, "unreachable")


## JSON in, JSON out. `payload` null sends no body.
func json_request(method: int, url: String, payload: Variant = null, headers: PackedStringArray = PackedStringArray(),
		idempotent: bool = true) -> NetResult:
	var h: PackedStringArray = headers.duplicate()
	var body: String = ""
	if payload != null:
		h.append("Content-Type: application/json")
		body = NetJson.stringify(payload)
	return await request(method, url, h, body, idempotent)


func _send(method: int, url: String, headers: PackedStringArray, body: String) -> Dictionary:
	if transport.is_valid():
		return await transport.call(method, url, headers, body, timeout_sec) as Dictionary
	return await engine_transport(method, url, headers, body, timeout_sec)


## The real thing: a throw-away HTTPRequest node under the scene root.
static func engine_transport(method: int, url: String, headers: PackedStringArray, body: String, timeout: float) -> Dictionary:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return {"result": HTTPRequest.RESULT_CANT_CONNECT, "code": 0, "headers": PackedStringArray(), "body": PackedByteArray()}
	var node := HTTPRequest.new()
	node.timeout = timeout
	tree.root.add_child(node)
	var err: int = node.request(url, headers, method as HTTPClient.Method, body)
	if err != OK:
		node.queue_free()
		return {"result": HTTPRequest.RESULT_CANT_CONNECT, "code": 0, "headers": PackedStringArray(), "body": PackedByteArray()}
	var out: Array = await node.request_completed
	node.queue_free()
	return {"result": out[0], "code": out[1], "headers": out[2], "body": out[3]}


## Turns a transport answer into a NetResult.
static func interpret(raw: Dictionary) -> NetResult:
	var result: int = raw.get("result", HTTPRequest.RESULT_CANT_CONNECT)
	if result != HTTPRequest.RESULT_SUCCESS:
		var code: int = NetError.Code.TIMEOUT if result == HTTPRequest.RESULT_TIMEOUT else NetError.Code.OFFLINE
		return NetResult.failure(code, "network_%d" % result, {"result": result})
	var status: int = raw.get("code", 0)
	var text: String = (raw.get("body", PackedByteArray()) as PackedByteArray).get_string_from_utf8()
	var parsed: Dictionary = NetJson.try_parse(text)
	if status >= 200 and status < 300:
		if not (parsed["ok"] as bool):
			return NetResult.failure(NetError.Code.BAD_RESPONSE, "not_json", {}, status)
		return _with_status(NetResult.success(parsed["value"]), status)
	var why: String = error_reason(parsed["value"]) if (parsed["ok"] as bool) else ""
	var failed: NetResult = NetResult.failure(NetError.from_http_status(status, why), why, {}, status)
	failed.value = parsed["value"]
	return failed


static func _with_status(r: NetResult, status: int) -> NetResult:
	r.http_status = status
	return r


## The short reason in an error body: RTDB `{"error": "Permission denied"}`, Identity Toolkit and callables
## `{"error": {"message": "..."}}`.
static func error_reason(body: Variant) -> String:
	if typeof(body) != TYPE_DICTIONARY:
		return ""
	var e: Variant = (body as Dictionary).get("error", "")
	if typeof(e) == TYPE_DICTIONARY:
		var m: Variant = (e as Dictionary).get("message", "")
		return str(m)
	return str(e)


func _may_retry(res: NetResult, raw: Dictionary, idempotent: bool) -> bool:
	if res.code != NetError.Code.OFFLINE and res.code != NetError.Code.TIMEOUT:
		return false
	if idempotent:
		return true
	var result: int = raw.get("result", 0)
	return result == HTTPRequest.RESULT_CANT_CONNECT or result == HTTPRequest.RESULT_CANT_RESOLVE


## A timer that works from any RefCounted (ignores pausing and the time scale).
static func wait_seconds(seconds: float) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or seconds <= 0.0:
		return
	await tree.create_timer(seconds, true, false, true).timeout
