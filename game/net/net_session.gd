class_name NetSession
extends RefCounted
## The online layer's front door: one signed-in player talking to one backend. It wires the pieces together so the UI
## has a single object to hold.
##
##   var net := NetSession.create()                 # NetConfig.current(), tokens in user://net_auth.cfg
##   var r: NetResult = await net.start()           # anonymous sign-in (or restore) + ensureProfile; r.value = profile
##   await net.account.set_name("Hana")
##   var m: NetResult = await net.open_match(match_id)   # m.value = OnlineMatch (see online_match.gd)
##   ...
##   net.close()                                    # streams and matches closed
##
## Pieces: config, clock, http, auth, db, functions, account, friends, lobby, matches. Everything async returns a
## NetResult (never throws); see NetError for the codes.

signal started(profile: Dictionary)

var config: NetConfig = null
var clock: NetClock = NetClock.new()
var http: NetHttp = NetHttp.new()
var auth: NetAuth = null
var db: NetDb = null
var functions: NetFunctions = null
var account: NetAccount = null
var friends: NetFriends = null
var lobby: NetLobby = null
var matches: NetMatches = null
var _open_matches: Array[OnlineMatch] = []


## `store_path` is where the sign-in is remembered (tests pass a different file per simulated phone).
static func create(cfg: NetConfig = null, store_path: String = NetAuth.DEFAULT_STORE) -> NetSession:
	var s := NetSession.new()
	s.config = cfg if cfg != null else NetConfig.current()
	s.auth = NetAuth.new(s.config, s.http, store_path)
	s.db = NetDb.new(s.config, s.http, s.auth)
	s.functions = NetFunctions.new(s.config, s.http, s.auth)
	s.account = NetAccount.new(s.config, s.auth, s.db, s.functions, s.clock)
	s.friends = NetFriends.new(s.auth, s.db, s.functions, s.account)
	s.lobby = NetLobby.new(s.auth, s.db, s.functions)
	s.matches = NetMatches.new(s.auth, s.db)
	return s


func uid() -> String:
	return auth.uid


## Signs in (restoring the saved account when there is one) and loads the profile. Call on every start of the online part.
## Failure codes: OFFLINE/TIMEOUT (try again later), UNAVAILABLE `anonymous_disabled` (backend not set up),
## SIGN_IN_REQUIRED.
func start() -> NetResult:
	if not config.is_configured():
		return NetResult.failure(NetError.Code.UNAVAILABLE, "not_configured")
	var signed: NetResult = await auth.ensure_signed_in()
	if not signed.ok:
		return signed
	var profile: NetResult = await account.ensure_profile()
	if profile.ok:
		started.emit(account.profile)
	return profile


## Opens a running match: replay, streams, heartbeat. `value` = the OnlineMatch. Failure codes include
## PROTOCOL_MISMATCH (details {hostProtocol, yourProtocol}), NOT_STARTED (still a lobby), NOT_FOUND, PERMISSION.
func open_match(match_id: String) -> NetResult:
	var m := OnlineMatch.new()
	var res: NetResult = await m.open(self, match_id)
	if not res.ok:
		return res
	_open_matches.append(m)
	m.closed.connect(func() -> void: _open_matches.erase(m))
	return NetResult.success(m)


## Closes every open match and stream. The account stays signed in.
func close() -> void:
	for m: OnlineMatch in _open_matches.duplicate():
		m.close()
	_open_matches.clear()
	friends.unwatch()
	lobby.unwatch()
	matches.unwatch()
	db.close_all_streams()


func sign_out() -> void:
	close()
	auth.sign_out()
