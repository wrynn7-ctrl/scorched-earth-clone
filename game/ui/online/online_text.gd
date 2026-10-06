class_name OnlineText
extends RefCounted
## Player-facing text for the online layer: NetResult failures, the time since a match changed, and the codes players
## type. Static, so translation goes through the server like ErrorText does. The net layer itself has no UI text;
## this is where its typed codes and backend reasons become `tr()` strings.

## Backend reasons (firebase/README.md) the UI says something specific about.
const REASON_KEYS: Dictionary = {
	"unknown_code": "NET_ERR_UNKNOWN_CODE",
	"bad_code": "NET_ERR_BAD_CODE",
	"match_full": "NET_ERR_MATCH_FULL",
	"not_enough_seats": "NET_ERR_NOT_ENOUGH_SEATS",
	"not_joinable": "NET_ERR_NOT_JOINABLE",
	"already_in_match": "NET_ERR_ALREADY_IN_MATCH",
	"own_code": "NET_ERR_OWN_CODE",
	"self": "NET_ERR_OWN_CODE",
	"already_friends": "NET_ERR_ALREADY_FRIENDS",
	"too_many_requests": "NET_ERR_TOO_MANY_REQUESTS",
	"too_many_matches": "NET_ERR_TOO_MANY_MATCHES",
	"full_required": "NET_ERR_FULL_REQUIRED",
	"not_host": "NET_ERR_NOT_HOST",
	"not_friends": "NET_ERR_NOT_FRIENDS",
	"not_a_member": "NET_ERR_NOT_A_MEMBER",
	"seats_not_filled": "NET_ERR_SEATS_NOT_FILLED",
	"not_in_lobby": "NET_ERR_NOT_IN_LOBBY",
	"google_already_linked": "NET_ERR_GOOGLE_LINKED",
	"seat_taken": "NET_ERR_SEAT_TAKEN",
	"bad_teams": "NET_ERR_BAD_TEAMS",
	"love_needs_two_humans": "NET_ERR_LOVE_TWO",
	"love_has_no_teams": "NET_ERR_LOVE_NO_TEAMS",
	"unknown_user": "NET_ERR_UNKNOWN_USER",
	"no_request": "NET_ERR_NO_REQUEST",
	"anonymous_disabled": "NET_ERR_SERVER_SETUP",
	"not_configured": "NET_ERR_SERVER_SETUP",
	"no_account": "NET_ERR_NO_GOOGLE_ACCOUNT",
	"config": "NET_ERR_GOOGLE_CONFIG",
	"unavailable": "NET_ERR_GOOGLE_UNAVAILABLE",
	"not_your_turn": "ERR_NOT_YOUR_TURN",
	"contention": "NET_ERR_CONTENTION",
	"match_over": "NET_ERR_MATCH_OVER",
}
## The fallback by code.
const CODE_KEYS: Dictionary = {
	NetError.Code.OFFLINE: "NET_ERR_OFFLINE",
	NetError.Code.TIMEOUT: "NET_ERR_OFFLINE",
	NetError.Code.SERVER: "NET_ERR_SERVER",
	NetError.Code.SIGN_IN_REQUIRED: "NET_ERR_SIGN_IN",
	NetError.Code.PERMISSION: "NET_ERR_PERMISSION",
	NetError.Code.NOT_FOUND: "NET_ERR_NOT_FOUND",
	NetError.Code.PROTOCOL_MISMATCH: "NET_ERR_UPDATE",
	NetError.Code.NAME_REJECTED: "NET_ERR_NAME_BLOCKED",
	NetError.Code.RATE_LIMITED: "NET_ERR_RATE_LIMITED",
	NetError.Code.DISPUTED: "NET_ERR_DISPUTED",
	NetError.Code.UNAVAILABLE: "NET_ERR_UNAVAILABLE",
	NetError.Code.NOT_STARTED: "NET_ERR_NOT_STARTED",
	NetError.Code.STALE: "NET_ERR_CONTENTION",
}
const GENERIC_KEY: String = "NET_ERR_GENERIC"


## What to tell the player about a failed NetResult.
static func error(r: NetResult) -> String:
	if r.reason != "" and REASON_KEYS.has(r.reason):
		return TranslationServer.translate(StringName(REASON_KEYS[r.reason] as String))
	if r.code == NetError.Code.NAME_REJECTED and r.reason == "empty":
		return TranslationServer.translate(&"NET_ERR_NAME_EMPTY")
	return code_text(r.code)


static func code_text(code: int) -> String:
	return TranslationServer.translate(StringName(CODE_KEYS.get(code, GENERIC_KEY) as String))


## Every string key this class can produce (the strings test checks them against strings.csv).
static func all_keys() -> PackedStringArray:
	var out := PackedStringArray()
	for k: Variant in REASON_KEYS.values():
		if not out.has(k as String):
			out.append(k as String)
	for k: Variant in CODE_KEYS.values():
		if not out.has(k as String):
			out.append(k as String)
	for k: String in [GENERIC_KEY, "NET_ERR_NAME_EMPTY", "NET_AGO_NOW", "NET_AGO_MIN", "NET_AGO_HOUR", "NET_AGO_DAY"]:
		if not out.has(k):
			out.append(k)
	return out


## "just now", "5 min ago", "3 h ago", "2 d ago" for a server-time stamp.
static func ago(now_ms: int, then_ms: int) -> String:
	if then_ms <= 0:
		return ""
	var sec: int = maxi(0, (now_ms - then_ms) / 1000)
	if sec < 60:
		return TranslationServer.translate(&"NET_AGO_NOW")
	if sec < 3600:
		return TranslationServer.translate(&"NET_AGO_MIN") % (sec / 60)
	if sec < 86400:
		return TranslationServer.translate(&"NET_AGO_HOUR") % (sec / 3600)
	return TranslationServer.translate(&"NET_AGO_DAY") % (sec / 86400)


## What a typed code field keeps: upper case, only characters of the unambiguous alphabet (no 0/O/1/I), at most
## `max_len`. Anything else is dropped, so the player never has to wonder whether it was a zero or an O.
static func filter_code(raw: String, max_len: int) -> String:
	var out: String = ""
	for ch: String in raw.to_upper():
		if DeepLinks.CODE_ALPHABET.contains(ch):
			out += ch
			if out.length() >= max_len:
				break
	return out


## "ABCD2345" -> "ABCD 2345" for reading aloud and copying by eye.
static func spaced(code: String) -> String:
	if code.length() <= 4:
		return code
	return "%s %s" % [code.substr(0, 4), code.substr(4)]
