class_name NetMatches
extends RefCounted
## The "Your matches" list: `userMatches/{uid}`, kept by the backend (docs/ARCHITECTURE.md section 45).
##
## Each entry: {matchId, updated, yourTurn, status, hostName}. `sorted()` puts matches where it is your turn first, then
## the other running ones, lobbies, and finished ones last (newest first inside each group).
## `watch()` streams the list and emits `changed(list)`; `refresh()` reads it once.

signal changed(list: Array)

var list: Array = []
var _auth: NetAuth = null
var _db: NetDb = null
var _stream: NetStream = null


func _init(auth: NetAuth, db: NetDb) -> void:
	_auth = auth
	_db = db


func refresh() -> NetResult:
	var res: NetResult = await _db.get_value("userMatches/%s" % _auth.uid)
	if not res.ok:
		return res
	list = sorted(res.value)
	return NetResult.success(list)


func watch() -> void:
	unwatch()
	_stream = _db.stream("userMatches/%s" % _auth.uid)
	_stream.value_changed.connect(func(v: Variant) -> void:
		list = sorted(v)
		changed.emit(list))


func unwatch() -> void:
	if _stream != null and is_instance_valid(_stream):
		_stream.close()
	_stream = null


## Removes a finished match from the list (the backend only allows it for over/abandoned matches).
func dismiss(match_id: String) -> NetResult:
	return await _db.delete("userMatches/%s/%s" % [_auth.uid, match_id])


## Raw `userMatches` node -> sorted Array of entries with `matchId` filled in.
static func sorted(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var d: Dictionary = raw as Dictionary
	for match_id: Variant in d.keys():
		if typeof(d[match_id]) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = (d[match_id] as Dictionary).duplicate()
		e["matchId"] = str(match_id)
		out.append(e)
	out.sort_custom(_before)
	return out


static func _group(e: Dictionary) -> int:
	var status: String = e.get("status", "")
	if status == NetProtocol.STATUS_PLAYING:
		return 0 if e.get("yourTurn", false) == true else 1
	if status == NetProtocol.STATUS_LOBBY:
		return 2
	return 3


static func _before(a: Dictionary, b: Dictionary) -> bool:
	var ga: int = _group(a)
	var gb: int = _group(b)
	if ga != gb:
		return ga < gb
	return (a.get("updated", 0) as int) > (b.get("updated", 0) as int)
