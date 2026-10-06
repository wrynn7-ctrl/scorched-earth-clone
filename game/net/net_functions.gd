class_name NetFunctions
extends RefCounted
## Callable Cloud Functions over plain HTTP (firebase/README.md "Callable functions"):
##   POST <functions_url>/<name>   Authorization: Bearer <ID token>   body {"data": {...}}
##   answer {"result": {...}}  or  {"error": {"status": "NOT_FOUND", "message": "unknown_code", "details": ...}}
## A success gives `NetResult.value` = the `result`; a failure gives a typed `code` (NetError.from_function_status), the
## backend's short `reason` and the error `details` (for example {hostProtocol, yourProtocol} on protocol_mismatch).

var _config: NetConfig = null
var _http: NetHttp = null
var _auth: NetAuth = null
## The functions emulator answers 404 with plain text while it is still loading a function the first time. Retry that
## many times (250 ms apart) when the answer is such a non-JSON 404. Production sets this to 0.
var loading_retries: int = 0


func _init(config: NetConfig, http: NetHttp, auth: NetAuth) -> void:
	_config = config
	_http = http
	_auth = auth
	loading_retries = 0 if config.production else 40


func call_function(function_name: String, data: Dictionary = {}) -> NetResult:
	var token: String = await _auth.token()
	if token == "":
		return NetResult.failure(NetError.Code.SIGN_IN_REQUIRED, "sign_in_required")
	var url: String = _config.callable_url(function_name)
	var headers: PackedStringArray = PackedStringArray(["Authorization: Bearer " + token])
	var tries: int = 0
	while true:
		var res: NetResult = await _http.json_request(HTTPClient.METHOD_POST, url, {"data": data}, headers, false)
		tries += 1
		if res.ok:
			return _unwrap(res)
		if res.http_status == 404 and res.value == null and tries <= loading_retries:
			await NetHttp.wait_seconds(0.25)
			continue
		return _error_of(res)
	return NetResult.failure(NetError.Code.SERVER, "unreachable")


static func _unwrap(res: NetResult) -> NetResult:
	var body: Variant = res.value
	if typeof(body) != TYPE_DICTIONARY or not (body as Dictionary).has("result"):
		return NetResult.failure(NetError.Code.BAD_RESPONSE, "no_result", {}, res.http_status)
	return NetResult.success((body as Dictionary)["result"])


static func _error_of(res: NetResult) -> NetResult:
	var body: Variant = res.value
	if typeof(body) == TYPE_DICTIONARY and typeof((body as Dictionary).get("error", null)) == TYPE_DICTIONARY:
		var e: Dictionary = (body as Dictionary)["error"] as Dictionary
		var status: String = e.get("status", "")
		var reason: String = str(e.get("message", ""))
		var details: Dictionary = {}
		if typeof(e.get("details", null)) == TYPE_DICTIONARY:
			details = e["details"] as Dictionary
		var failed: NetResult = NetResult.failure(NetError.from_function_status(status, reason), reason, details, res.http_status)
		failed.value = body
		return failed
	return res
