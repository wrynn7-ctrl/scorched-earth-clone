class_name NetAuth
extends RefCounted
## Firebase Authentication over REST (Identity Toolkit and Secure Token), docs/ARCHITECTURE.md section 44.
##
##   ensure_signed_in()   restore the saved account (refreshing its token) or create an anonymous one
##   token()              a valid ID token, refreshed first when it expires within 5 minutes ("" if impossible)
##   link_google(id)      attach a Google account to the current anonymous one (keeps the uid and its matches)
##   sign_in_google(id)   sign in to the account that Google id belongs to (a new phone; the uid changes)
##   sign_out()           forget the account here (the refresh token is deleted from user://)
##
## The refresh token is kept in a ConfigFile (default user://net_auth.cfg), together with the backend it belongs to, so
## tokens of the emulator are never sent to production. Two instances may use two different files (the tests do).

signal signed_in(uid: String)
signal signed_out()
## The saved account no longer exists (deleted, or the emulator was reset): a fresh anonymous one replaced it.
signal account_replaced(old_uid: String, new_uid: String)

## Refresh when less than this is left on the token.
const REFRESH_MARGIN_MS: int = 300000
const DEFAULT_STORE: String = "user://net_auth.cfg"
const SECTION: String = "auth"

signal _refresh_finished()

var uid: String = ""
## True while the account has no Google (or other) provider linked.
var anonymous: bool = true
var email: String = ""
var store_path: String = DEFAULT_STORE
var _config: NetConfig = null
var _http: NetHttp = null
var _id_token: String = ""
var _refresh_token: String = ""
var _expires_at_ms: int = 0
var _refreshing: bool = false


func _init(config: NetConfig, http: NetHttp, path: String = DEFAULT_STORE) -> void:
	_config = config
	_http = http
	store_path = path


func is_signed_in() -> bool:
	return uid != "" and _refresh_token != ""


## Loads the saved account. Returns true when one exists for this backend (it still has to be refreshed).
func restore() -> bool:
	var cf := ConfigFile.new()
	if cf.load(store_path) != OK:
		return false
	if (cf.get_value(SECTION, "endpoint", "") as String) != _config.endpoint_key():
		return false
	var saved_uid: String = cf.get_value(SECTION, "uid", "")
	var saved_refresh: String = cf.get_value(SECTION, "refresh_token", "")
	if saved_uid == "" or saved_refresh == "":
		return false
	uid = saved_uid
	_refresh_token = saved_refresh
	anonymous = cf.get_value(SECTION, "anonymous", true)
	email = cf.get_value(SECTION, "email", "")
	_id_token = ""
	_expires_at_ms = 0
	return true


## Signed in afterwards (restored or new), or a typed failure. Idempotent.
func ensure_signed_in() -> NetResult:
	if is_signed_in() and _id_token != "" and not _expiring():
		return NetResult.success(uid)
	if is_signed_in() or restore():
		var old_uid: String = uid
		var refreshed: NetResult = await refresh()
		if refreshed.ok:
			signed_in.emit(uid)
			return NetResult.success(uid)
		if not _account_is_gone(refreshed):
			return refreshed
		# The account was deleted (or the backend reset): start over with a new anonymous one.
		_forget()
		var fresh: NetResult = await sign_up_anonymous()
		if fresh.ok:
			account_replaced.emit(old_uid, uid)
		return fresh
	return await sign_up_anonymous()


func sign_up_anonymous() -> NetResult:
	var res: NetResult = await _http.json_request(HTTPClient.METHOD_POST, _config.identity_endpoint("accounts:signUp"),
			{"returnSecureToken": true}, PackedStringArray(), false)
	if not res.ok:
		return _auth_failure(res)
	var applied: NetResult = _apply_sign_in(res.dict(), true)
	if applied.ok:
		signed_in.emit(uid)
	return applied


## A valid ID token ("" when the account cannot be refreshed). Concurrent callers share one refresh.
func token() -> String:
	if not is_signed_in():
		return ""
	if _id_token == "" or _expiring():
		var res: NetResult = await refresh()
		if not res.ok:
			return ""
	return _id_token


## Forces a refresh of the ID token.
func refresh() -> NetResult:
	if _refreshing:
		await _refresh_finished
		return NetResult.success(uid) if _id_token != "" and not _expiring() else NetResult.failure(NetError.Code.SIGN_IN_REQUIRED, "refresh_failed")
	if _refresh_token == "":
		return NetResult.failure(NetError.Code.SIGN_IN_REQUIRED, "no_account")
	_refreshing = true
	var body: String = "grant_type=refresh_token&refresh_token=" + _refresh_token.uri_encode()
	var res: NetResult = await _http.request(HTTPClient.METHOD_POST, _config.token_endpoint(),
			PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]), body, false)
	var out: NetResult = null
	if res.ok:
		var d: Dictionary = res.dict()
		if (d.get("id_token", "") as String) == "":
			out = NetResult.failure(NetError.Code.BAD_RESPONSE, "no_token")
		else:
			_id_token = d["id_token"]
			_refresh_token = d.get("refresh_token", _refresh_token)
			uid = d.get("user_id", uid)
			_expires_at_ms = NetClock.local_ms() + int(str(d.get("expires_in", "3600"))) * 1000
			_save()
			out = NetResult.success(uid)
	else:
		out = _auth_failure(res)
	_refreshing = false
	_refresh_finished.emit()
	return out


## Links a Google ID token (from GoogleSignIn.succeeded) to the current account. The uid stays the same.
## Failure reasons: google_already_linked (that Google account already belongs to another player: offer
## sign_in_google instead), invalid_idp_response, sign_in_required.
func link_google(google_id_token: String) -> NetResult:
	var current: String = await token()
	if current == "":
		return NetResult.failure(NetError.Code.SIGN_IN_REQUIRED, "no_account")
	return await _sign_in_with_idp(google_id_token, current)


## Signs in to the account that owns this Google identity. The uid becomes that account's (the local anonymous account
## is abandoned), so call it only after the player agreed.
func sign_in_google(google_id_token: String) -> NetResult:
	var old_uid: String = uid
	var res: NetResult = await _sign_in_with_idp(google_id_token, "")
	if res.ok and old_uid != uid:
		signed_in.emit(uid)
	return res


func _sign_in_with_idp(google_id_token: String, current_token: String) -> NetResult:
	if google_id_token.strip_edges() == "":
		return NetResult.failure(NetError.Code.INVALID, "empty_id_token")
	var payload: Dictionary = {
		"postBody": "id_token=%s&providerId=google.com" % google_id_token.uri_encode(),
		"requestUri": "http://localhost",
		"returnIdpCredential": true,
		"returnSecureToken": true,
	}
	if current_token != "":
		payload["idToken"] = current_token
	var res: NetResult = await _http.json_request(HTTPClient.METHOD_POST, _config.identity_endpoint("accounts:signInWithIdp"),
			payload, PackedStringArray(), false)
	if not res.ok:
		return _auth_failure(res)
	var d: Dictionary = res.dict()
	if d.get("needConfirmation", false) == true or d.has("errorMessage"):
		return NetResult.failure(NetError.Code.PRECONDITION, "google_already_linked")
	var applied: NetResult = _apply_sign_in(d, false)
	if applied.ok:
		anonymous = false
		email = d.get("email", "")
		_save()
	return applied


func sign_out() -> void:
	var was: bool = uid != ""
	_forget()
	if was:
		signed_out.emit()


func _apply_sign_in(d: Dictionary, is_anonymous: bool) -> NetResult:
	var id_token: String = d.get("idToken", "")
	var refresh_token: String = d.get("refreshToken", "")
	var local_id: String = d.get("localId", "")
	if id_token == "" or refresh_token == "" or local_id == "":
		return NetResult.failure(NetError.Code.BAD_RESPONSE, "incomplete_sign_in")
	_id_token = id_token
	_refresh_token = refresh_token
	uid = local_id
	anonymous = is_anonymous
	_expires_at_ms = NetClock.local_ms() + int(str(d.get("expiresIn", "3600"))) * 1000
	_save()
	return NetResult.success(uid)


func _expiring() -> bool:
	return NetClock.local_ms() > _expires_at_ms - REFRESH_MARGIN_MS


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value(SECTION, "endpoint", _config.endpoint_key())
	cf.set_value(SECTION, "uid", uid)
	cf.set_value(SECTION, "refresh_token", _refresh_token)
	cf.set_value(SECTION, "anonymous", anonymous)
	cf.set_value(SECTION, "email", email)
	cf.save(store_path)


func _forget() -> void:
	uid = ""
	_id_token = ""
	_refresh_token = ""
	_expires_at_ms = 0
	anonymous = true
	email = ""
	if FileAccess.file_exists(store_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(store_path))


## Identity Toolkit errors are `{"error": {"message": "FEDERATED_USER_ID_ALREADY_LINKED"}}`: the reason becomes a lower
## case key. Network trouble and server errors pass through unchanged.
func _auth_failure(res: NetResult) -> NetResult:
	if res.is_transient() or res.http_status == 0:
		return res
	var raw: String = res.reason.get_slice(" ", 0)
	var why: String = raw.to_lower()
	var code: int = NetError.Code.SIGN_IN_REQUIRED
	match raw:
		"FEDERATED_USER_ID_ALREADY_LINKED", "CREDENTIAL_ALREADY_IN_USE", "EMAIL_EXISTS":
			why = "google_already_linked"
			code = NetError.Code.PRECONDITION
		"INVALID_IDP_RESPONSE", "INVALID_ID_TOKEN":
			why = "invalid_idp_response"
			code = NetError.Code.INVALID
		"OPERATION_NOT_ALLOWED":
			why = "anonymous_disabled"
			code = NetError.Code.UNAVAILABLE
	var failed: NetResult = NetResult.failure(code, why, res.details, res.http_status)
	failed.value = res.value
	return failed


func _account_is_gone(res: NetResult) -> bool:
	return res.reason in ["invalid_refresh_token", "user_not_found", "user_disabled", "token_expired"]
