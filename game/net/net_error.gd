class_name NetError
extends RefCounted
## Typed error codes of the whole net layer. Every async call returns a NetResult whose `code` is one of these;
## `reason` carries the backend's short reason string (for example `unknown_code`, `full_required`, `seat_taken`; the
## full list is in firebase/README.md) and is what the UI maps to text with tr().

enum Code {
	NONE,
	OFFLINE,            ## no connection (DNS, connect, TLS, dropped); safe to retry later
	TIMEOUT,            ## the server did not answer in time
	SERVER,             ## 5xx or an unexpected status
	BAD_RESPONSE,       ## the answer was not what the protocol promises
	SIGN_IN_REQUIRED,   ## no valid account (token missing, expired and not refreshable)
	PERMISSION,         ## the rules or a function refused (reason says why: full_required, not_host, ...)
	NOT_FOUND,          ## unknown code, match or user (a blocked pair looks like this too)
	INVALID,            ## bad argument (reason: bad_code, bad_seats, bad_timers, ...)
	PRECONDITION,       ## wrong state (not_in_lobby, seats_not_filled, own_code, ...)
	ALREADY_EXISTS,     ## already_friends, already_in_match, token_used
	EXHAUSTED,          ## match_full, too_many_matches, too_many_requests
	PROTOCOL_MISMATCH,  ## the match was made by a different game version: ask the player to update
	NAME_REJECTED,      ## NameFilter refused the name before anything was sent
	RATE_LIMITED,       ## quick messages: one per 3 s
	ILLEGAL_ACTION,     ## the simulation refuses the action (reason is the simulation's error key)
	STALE,              ## the action was legal when chosen but not any more, after catching up with the log
	DISPUTED,           ## the match is disputed (a tampered or diverging log); play has stopped
	CLOSED,             ## the OnlineMatch (or session) is closed
	UNAVAILABLE,        ## Google sign-in, push or similar is not available on this device
	CANCELLED,          ## the player backed out
	NOT_STARTED,        ## the match is still a lobby
}


static func name_of(code: int) -> String:
	var keys: Array = Code.keys()
	return (keys[code] as String) if code >= 0 and code < keys.size() else "UNKNOWN"


## Maps a callable function's error status (firebase/README.md) to a code.
static func from_function_status(status: String, reason: String) -> int:
	if reason == "protocol_mismatch":
		return Code.PROTOCOL_MISMATCH
	match status:
		"INVALID_ARGUMENT":
			return Code.INVALID
		"NOT_FOUND":
			return Code.NOT_FOUND
		"PERMISSION_DENIED":
			return Code.PERMISSION
		"FAILED_PRECONDITION":
			return Code.PRECONDITION
		"ALREADY_EXISTS":
			return Code.ALREADY_EXISTS
		"RESOURCE_EXHAUSTED":
			return Code.EXHAUSTED
		"UNAUTHENTICATED":
			return Code.SIGN_IN_REQUIRED
		"DEADLINE_EXCEEDED":
			return Code.TIMEOUT
		"UNAVAILABLE":
			return Code.OFFLINE
	return Code.SERVER


## Maps a plain HTTP status (no callable error body) to a code.
static func from_http_status(status: int, reason: String) -> int:
	if status == 401:
		var low: String = reason.to_lower()
		if low.contains("permission"):
			return Code.PERMISSION
		return Code.SIGN_IN_REQUIRED
	match status:
		400:
			return Code.INVALID
		403:
			return Code.PERMISSION
		404:
			return Code.NOT_FOUND
		409, 412:
			return Code.PRECONDITION
		429:
			return Code.EXHAUSTED
	return Code.SERVER if status >= 500 or status == 0 else Code.INVALID
