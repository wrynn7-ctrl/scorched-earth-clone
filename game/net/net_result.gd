class_name NetResult
extends RefCounted
## The answer of every async net call: `ok` with a `value`, or a typed failure.
##
##   var r: NetResult = await session.account.ensure_profile()
##   if not r.ok:
##       show(tr("NET_ERR_" + NetError.name_of(r.code)), r.reason)
##
## On a failure `value` may still hold the parsed error body (callers rarely need it).

var ok: bool = true
var value: Variant = null
var code: int = NetError.Code.NONE
var reason: String = ""
var details: Dictionary = {}
var http_status: int = 0


static func success(v: Variant = null) -> NetResult:
	var r := NetResult.new()
	r.value = v
	return r


static func failure(error_code: int, why: String = "", extra: Dictionary = {}, http: int = 0) -> NetResult:
	var r := NetResult.new()
	r.ok = false
	r.code = error_code
	r.reason = why
	r.details = extra
	r.http_status = http
	return r


## The value as a Dictionary ({} when it is something else).
func dict() -> Dictionary:
	return value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


func list() -> Array:
	return value as Array if typeof(value) == TYPE_ARRAY else []


func is_code(c: int) -> bool:
	return not ok and code == c


## True for failures that a later retry may fix (no network, timeout, server trouble).
func is_transient() -> bool:
	return not ok and (code == NetError.Code.OFFLINE or code == NetError.Code.TIMEOUT or code == NetError.Code.SERVER)


func _to_string() -> String:
	if ok:
		return "NetResult(ok)"
	return "NetResult(%s %s)" % [NetError.name_of(code), reason]
