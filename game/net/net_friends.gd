class_name NetFriends
extends RefCounted
## Friends, requests, blocks, reports and invites (docs/ARCHITECTURE.md section 44). Everything that changes the social
## graph is a callable function (the rules refuse client writes); the lists are read straight from the database.
##
## Lists are plain Arrays of Dictionaries:
##   friends   [{uid, name, display, since}]          requests  [{uid, name, at}]       blocks  [uid]
##   invites   [{matchId, fromUid, fromName, at, code, mode}]  (newest first)
## `watch()` keeps `requests`, `invites` and `friends` current through streams and emits the *_changed signals.

signal friends_changed(list: Array)
signal requests_changed(list: Array)
signal invites_changed(list: Array)

const REPORT_REASON_NAME: String = "offensive_name"

var friends: Array = []
var requests: Array = []
var invites: Array = []
var _auth: NetAuth = null
var _db: NetDb = null
var _fn: NetFunctions = null
var _account: NetAccount = null
var _streams: Array[NetStream] = []


func _init(auth: NetAuth, db: NetDb, functions: NetFunctions, account: NetAccount) -> void:
	_auth = auth
	_db = db
	_fn = functions
	_account = account


## Sends a friend request by friend code (8 characters, any case, spaces and hyphens allowed).
## `value` = {status: "sent" | "friends", name, friendUid?}. Reasons: bad_code, unknown_code, own_code, already_friends,
## too_many_requests.
func send_request(friend_code: String) -> NetResult:
	var code: String = DeepLinks.normalize_code(friend_code, 8)
	if code == "":
		return NetResult.failure(NetError.Code.INVALID, "bad_code")
	return await _fn.call_function("sendFriendRequest", {"code": code})


## Sends a friend request to a player met in a shared match (the "Add friend" button on a name in a lobby or a battle).
## Both players must be members of `match_id`. Same `value` as `send_request`. Reasons: `unknown_code` (also for a blocked
## pair, and for a target who is not in the match), `not_a_member` (you are not), `already_friends`, `too_many_requests`,
## `self`.
func request_by_uid(target_uid: String, match_id: String) -> NetResult:
	if target_uid == "" or match_id == "":
		return NetResult.failure(NetError.Code.INVALID, "bad_targetUid" if target_uid == "" else "bad_matchId")
	return await _fn.call_function("sendFriendRequestToUid", {"targetUid": target_uid, "matchId": match_id})


func respond(from_uid: String, accept: bool) -> NetResult:
	return await _fn.call_function("respondFriendRequest", {"fromUid": from_uid, "accept": accept})


func remove_friend(friend_uid: String) -> NetResult:
	return await _fn.call_function("removeFriend", {"friendUid": friend_uid})


func block(target_uid: String) -> NetResult:
	return await _fn.call_function("block", {"targetUid": target_uid})


func unblock(target_uid: String) -> NetResult:
	return await _fn.call_function("unblock", {"targetUid": target_uid})


## Reports a player's name. Three different reporters hide it. `value` = {hidden, duplicate}.
func report(target_uid: String, reason: String = REPORT_REASON_NAME) -> NetResult:
	return await _fn.call_function("reportName", {"targetUid": target_uid, "reason": reason})


func list_friends() -> NetResult:
	var res: NetResult = await _db.get_value("friends/%s" % _auth.uid)
	if not res.ok:
		return res
	var out: Array = []
	var raw: Dictionary = res.dict()
	for uid: Variant in raw.keys():
		var entry: Dictionary = raw[uid] as Dictionary if typeof(raw[uid]) == TYPE_DICTIONARY else {}
		var who: NetResult = await _account.fetch_public(str(uid))
		var shown: Dictionary = who.dict() if who.ok else {}
		out.append({"uid": str(uid), "name": shown.get("name", ""), "display": shown.get("display", NetAccount.public_name("", true, str(uid))),
				"since": entry.get("since", 0)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["display"] as String).naturalnocasecmp_to(b["display"] as String) < 0)
	friends = out
	return NetResult.success(out)


func list_requests() -> NetResult:
	var res: NetResult = await _db.get_value("friendRequests/%s" % _auth.uid)
	if not res.ok:
		return res
	requests = requests_from(res.value)
	return NetResult.success(requests)


func list_blocks() -> NetResult:
	var res: NetResult = await _db.get_value("blocks/%s" % _auth.uid)
	if not res.ok:
		return res
	var out: Array = []
	for uid: Variant in res.dict().keys():
		out.append(str(uid))
	return NetResult.success(out)


func list_invites() -> NetResult:
	var res: NetResult = await _db.get_value("invites/%s" % _auth.uid)
	if not res.ok:
		return res
	invites = invites_from(res.value)
	return NetResult.success(invites)


## The recipient dismisses an invite.
func dismiss_invite(match_id: String) -> NetResult:
	return await _db.delete("invites/%s/%s" % [_auth.uid, match_id])


## Love invites are only shown by a client that has the Love Edition (`love_found`); others treat them as unknown.
static func visible_invites(list: Array, love_found: bool) -> Array:
	var out: Array = []
	for inv: Variant in list:
		var d: Dictionary = inv as Dictionary
		if (d.get("mode", 0) as int) == SimConstants.MODE_LOVE and not love_found:
			continue
		out.append(d)
	return out


static func requests_from(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var d: Dictionary = raw as Dictionary
	for uid: Variant in d.keys():
		var entry: Dictionary = d[uid] as Dictionary if typeof(d[uid]) == TYPE_DICTIONARY else {}
		out.append({"uid": str(uid), "name": entry.get("name", ""), "at": entry.get("at", 0)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["at"] as int) < (b["at"] as int))
	return out


static func invites_from(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var d: Dictionary = raw as Dictionary
	for match_id: Variant in d.keys():
		if typeof(d[match_id]) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = (d[match_id] as Dictionary).duplicate()
		entry["matchId"] = str(match_id)
		out.append(entry)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.get("at", 0) as int) > (b.get("at", 0) as int))
	return out


## Starts streams on the request and invite lists (and re-reads the friends when a request is accepted elsewhere).
func watch() -> void:
	unwatch()
	var req: NetStream = _db.stream("friendRequests/%s" % _auth.uid)
	req.value_changed.connect(func(v: Variant) -> void:
		requests = requests_from(v)
		requests_changed.emit(requests))
	var inv: NetStream = _db.stream("invites/%s" % _auth.uid)
	inv.value_changed.connect(func(v: Variant) -> void:
		invites = invites_from(v)
		invites_changed.emit(invites))
	var fr: NetStream = _db.stream("friends/%s" % _auth.uid)
	fr.value_changed.connect(func(_v: Variant) -> void:
		var res: NetResult = await list_friends()
		if res.ok:
			friends_changed.emit(friends))
	_streams = [req, inv, fr]


func unwatch() -> void:
	for s: NetStream in _streams:
		if is_instance_valid(s):
			s.close()
	_streams.clear()
