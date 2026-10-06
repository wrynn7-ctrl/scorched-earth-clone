class_name NetAccount
extends RefCounted
## The signed-in player's profile and account actions (docs/ARCHITECTURE.md section 44).
##
##   ensure_profile()      call on every start: creates the profile and friend code, stores the protocol, syncs the clock
##   set_name(raw)         NameFilter first (typed NAME_REJECTED, nothing is sent), then the database
##   fetch_public(uid)     {uid, name, hidden, display} of any player you may see (hidden names read "PLAYER ab12")
##   verify_purchase(tok)  asks the backend to verify the full-unlock purchase; refreshes `profile.full`
##   register_push_token / bind_push   FCM token -> users/{uid}/fcm/{hash}
##   link_google(gs)       Google sign-in sheet, then link the ID token to this (anonymous) account
##   delete_my_data()      removes everything online, then signs out (the Auth user is deleted too)

signal profile_changed(profile: Dictionary)

var profile: Dictionary = {}
var _config: NetConfig = null
var _auth: NetAuth = null
var _db: NetDb = null
var _fn: NetFunctions = null
var _clock: NetClock = null
var _names: Dictionary = {}
var _push: PushService = null
var _push_registered_hash: String = ""

signal _google_step()


func _init(config: NetConfig, auth: NetAuth, db: NetDb, functions: NetFunctions, clock: NetClock) -> void:
	_config = config
	_auth = auth
	_db = db
	_fn = functions
	_clock = clock


func friend_code() -> String:
	return profile.get("friendCode", "")


func is_full() -> bool:
	return profile.get("full", false) == true


## The name to show for the player themself ("" until ensure_profile ran).
func my_name() -> String:
	return public_name(profile.get("name", ""), profile.get("nameHidden", false) == true, _auth.uid)


## Creates or loads the profile. `value` is the profile Dictionary {friendCode, name, nameHidden, full, protocol, serverTime}.
func ensure_profile() -> NetResult:
	var res: NetResult = await _fn.call_function("ensureProfile", {"protocol": NetProtocol.VERSION})
	if not res.ok:
		return res
	var p: Dictionary = res.dict()
	if p.has("serverTime"):
		_clock.sync_to(p["serverTime"] as int)
	profile = p
	profile_changed.emit(profile)
	return NetResult.success(profile)


## Re-reads users/{uid} (the function re-checks names after a write, so a refused name changes here a moment later).
func refresh_profile() -> NetResult:
	var res: NetResult = await _db.get_value("users/%s" % _auth.uid)
	if not res.ok:
		return res
	if typeof(res.value) == TYPE_DICTIONARY:
		var fresh: Dictionary = res.dict().duplicate()
		fresh.erase("fcm")
		for k: Variant in fresh.keys():
			profile[k] = fresh[k]
		profile_changed.emit(profile)
	return NetResult.success(profile)


## Sets the display name. The text is cleaned and checked with NameFilter here; the backend re-checks it and may still
## replace it with "PLAYER" (call refresh_profile a moment later to see that).
func set_name(raw: String) -> NetResult:
	var clean: String = NameFilter.clean(raw)
	if clean == "":
		return NetResult.failure(NetError.Code.NAME_REJECTED, "empty")
	if not NameFilter.is_allowed(clean):
		return NetResult.failure(NetError.Code.NAME_REJECTED, "blocked")
	var res: NetResult = await _db.put("users/%s/name" % _auth.uid, clean)
	if not res.ok:
		return res
	profile["name"] = clean
	profile_changed.emit(profile)
	return NetResult.success(clean)


## Name and visibility of any player (cached for the session; pass refresh to re-read).
func fetch_public(uid: String, refresh: bool = false) -> NetResult:
	if not refresh and _names.has(uid):
		return NetResult.success(_names[uid])
	var name_res: NetResult = await _db.get_value("users/%s/name" % uid)
	if not name_res.ok:
		return name_res
	var hidden_res: NetResult = await _db.get_value("users/%s/nameHidden" % uid)
	var hidden: bool = hidden_res.ok and hidden_res.value == true
	var shown: String = str(name_res.value) if name_res.value != null else ""
	var entry: Dictionary = {"uid": uid, "name": shown, "hidden": hidden, "display": public_name(shown, hidden, uid)}
	_names[uid] = entry
	return NetResult.success(entry)


## What to show for a player name: hidden or empty names read "PLAYER" plus the first 4 characters of the uid
## (docs/ARCHITECTURE.md section 44).
static func public_name(player_name: String, hidden: bool, uid: String) -> String:
	if hidden or player_name.strip_edges() == "":
		return "PLAYER %s" % uid.substr(0, 4).to_upper() if uid != "" else "PLAYER"
	return player_name


func verify_purchase(purchase_token: String) -> NetResult:
	var res: NetResult = await _fn.call_function("verifyPurchase", {"purchaseToken": purchase_token})
	if res.ok and res.dict().get("full", false) == true:
		profile["full"] = true
		profile_changed.emit(profile)
	return res


## Deletes everything online, then signs out locally. After success the next `ensure_signed_in` creates a new account.
func delete_my_data() -> NetResult:
	var res: NetResult = await _fn.call_function("deleteMyData", {})
	if res.ok:
		_db.close_all_streams()
		_auth.sign_out()
		profile = {}
		_names.clear()
	return res


# --- push token (FCM) -------------------------------------------------------------------------------------------

## The database key of a push token: the first 32 hex characters of its SHA-256 (the token itself is the value).
static func push_key(push_token: String) -> String:
	return push_token.sha256_text().substr(0, 32)


func register_push_token(push_token: String) -> NetResult:
	if push_token.length() < 20:
		return NetResult.failure(NetError.Code.INVALID, "bad_token")
	var key: String = push_key(push_token)
	var res: NetResult = await _db.put("users/%s/fcm/%s" % [_auth.uid, key], push_token)
	if res.ok:
		_push_registered_hash = key
	return res


func unregister_push_token(push_token: String) -> NetResult:
	return await _db.delete("users/%s/fcm/%s" % [_auth.uid, push_key(push_token)])


## Registers the token now (when there is one) and whenever FCM hands out a new one.
func bind_push(push: PushService) -> void:
	_push = push
	if not push.token_changed.is_connected(_on_push_token):
		push.token_changed.connect(_on_push_token)
	if push.token != "":
		register_push_token(push.token)


func _on_push_token(push_token: String) -> void:
	if _auth.is_signed_in():
		register_push_token(push_token)


# --- Google ---------------------------------------------------------------------------------------------------------

## Shows the Google sheet, then links the Google account to this one (uid and matches stay). Failure codes: CANCELLED
## (not an error to show), UNAVAILABLE (reason: unavailable, config, no_account), OFFLINE, and from NetAuth.link_google
## PRECONDITION `google_already_linked` (the player already has an account with that Google identity: offer
## `restore_with_google`). `value` = {email}.
func link_google(sign_in: GoogleSignIn) -> NetResult:
	var token: Dictionary = await _google_token(sign_in)
	if not (token["ok"] as bool):
		return token["result"] as NetResult
	var res: NetResult = await _auth.link_google(token["id_token"] as String)
	if res.ok:
		return NetResult.success({"email": _auth.email})
	return res


## For a new phone: signs in to the account the Google identity already owns. The uid changes; call ensure_profile after.
func restore_with_google(sign_in: GoogleSignIn) -> NetResult:
	var token: Dictionary = await _google_token(sign_in)
	if not (token["ok"] as bool):
		return token["result"] as NetResult
	var res: NetResult = await _auth.sign_in_google(token["id_token"] as String)
	if res.ok:
		profile = {}
		_names.clear()
		return NetResult.success({"email": _auth.email})
	return res


## Runs the sign-in sheet and waits for its answer: {ok, id_token} or {ok: false, result: NetResult}.
func _google_token(sign_in: GoogleSignIn) -> Dictionary:
	var box: Dictionary = {"done": false, "id_token": "", "error": 0, "detail": ""}
	var on_ok: Callable = func(id_token: String, _email: String, _display: String) -> void:
		box["done"] = true
		box["id_token"] = id_token
		_google_step.emit()
	var on_fail: Callable = func(error: int, detail: String) -> void:
		box["done"] = true
		box["error"] = error
		box["detail"] = detail
		_google_step.emit()
	sign_in.succeeded.connect(on_ok)
	sign_in.failed.connect(on_fail)
	sign_in.sign_in(_config.web_client_id)
	if not (box["done"] as bool):
		await _google_step
	sign_in.succeeded.disconnect(on_ok)
	sign_in.failed.disconnect(on_fail)
	if (box["id_token"] as String) != "":
		return {"ok": true, "id_token": box["id_token"]}
	return {"ok": false, "result": google_failure(box["error"] as int, box["detail"] as String)}


static func google_failure(error: int, detail: String) -> NetResult:
	match error:
		GoogleSignIn.Error.CANCELLED:
			return NetResult.failure(NetError.Code.CANCELLED, "cancelled")
		GoogleSignIn.Error.NETWORK:
			return NetResult.failure(NetError.Code.OFFLINE, "network")
		GoogleSignIn.Error.NO_ACCOUNT:
			return NetResult.failure(NetError.Code.UNAVAILABLE, "no_account")
		GoogleSignIn.Error.CONFIG:
			return NetResult.failure(NetError.Code.UNAVAILABLE, "config", {"detail": detail})
		GoogleSignIn.Error.BUSY:
			return NetResult.failure(NetError.Code.PRECONDITION, "busy")
		GoogleSignIn.Error.UNAVAILABLE:
			return NetResult.failure(NetError.Code.UNAVAILABLE, "unavailable")
	return NetResult.failure(NetError.Code.SERVER, "google_error", {"detail": detail})
