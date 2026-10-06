class_name OnlineHub
extends RefCounted
## What the online screens share across scene changes: the one NetSession, the platform wrappers (push, Google
## sign-in, share, deep links), the hand-off to the battle scene, and what an incoming link or notification asked for.
## Static, like BattleConfig. Tests put fakes into these variables before building a screen.

## The signed-in session (created on first use, kept for the whole run).
static var session: NetSession = null
static var push: PushService = null
static var google: GoogleSignIn = null
static var share: ShareService = null
static var links: DeepLinks = null
static var _started: bool = false

## A deep link or notification waiting for an online screen: join this code / open this match.
static var pending_join_code: String = ""
static var pending_match_id: String = ""
## The lobby the player hosts right now ("" = none). The Friends tab offers INVITE while it is set.
static var open_lobby_id: String = ""
## Hand-off to the battle scene: the match to play (set before changing scenes, taken by the battle).
static var match_to_play: OnlineMatch = null
## Where the battle returns to (the Online home); kept here so tests can look at it.
const ONLINE_SCENE: String = "res://ui/online/online_screen.tscn"
const LOBBY_SCENE: String = "res://ui/online/lobby_screen.tscn"
const BATTLE_SCENE: String = "res://show/battle/battle_scene.tscn"
## The lobby (match id) the lobby scene shows, set before changing scenes.
static var lobby_to_show: String = ""


## The session, created on first use. `NetSession.create()` talks to the emulators unless the build says otherwise.
static func ensure_session() -> NetSession:
	if session == null:
		session = NetSession.create()
	return session


## Creates and starts the platform wrappers once. They are harmless no-ops on desktop and in tests.
static func start_services() -> void:
	if links == null:
		links = DeepLinks.new()
	if push == null:
		push = PushService.new()
	if google == null:
		google = GoogleSignIn.new()
	if share == null:
		share = ShareService.new()
	if not _started:
		_started = true
		google.start()
		links.start()
		push.start()


## Tests: put fakes in place (any may be null to get the real, inert one) and mark the services as started.
static func set_services(p: PushService, g: GoogleSignIn, s: ShareService, l: DeepLinks) -> void:
	push = p
	google = g
	share = s
	links = l
	_started = true


## Forgets everything (tests, and "delete my online data").
static func reset() -> void:
	if session != null:
		session.close()
	session = null
	push = null
	google = null
	share = null
	links = null
	_started = false
	pending_join_code = ""
	pending_match_id = ""
	open_lobby_id = ""
	match_to_play = null
	lobby_to_show = ""


## True once something asked an online screen to do something (a link, a tap on a notification).
static func has_route() -> bool:
	return pending_join_code != "" or pending_match_id != ""


## Picks up a link or notification that arrived while nobody was listening (cold start). Safe to call often.
static func collect_pending() -> void:
	if links != null:
		var code: String = links.take_pending_code()
		if code != "":
			pending_join_code = code
	if push != null:
		var payload: Dictionary = push.take_pending_payload()
		var id: String = PushService.match_id_of(payload)
		if id != "":
			pending_match_id = id


## Takes what was asked: {"join": code} or {"match": id} (a match wins when both are set), or {}.
static func take_route() -> Dictionary:
	collect_pending()
	if pending_match_id != "":
		var id: String = pending_match_id
		pending_match_id = ""
		return {"match": id}
	if pending_join_code != "":
		var code: String = pending_join_code
		pending_join_code = ""
		return {"join": code}
	return {}


# --- muted players (quick messages) ---------------------------------------------------------------------------------

static func is_muted(player_uid: String) -> bool:
	return player_uid != "" and SettingsStore.online_muted.has(player_uid)


static func set_muted(player_uid: String, on: bool) -> void:
	if player_uid == "":
		return
	var has: bool = SettingsStore.online_muted.has(player_uid)
	if on and not has:
		SettingsStore.online_muted.append(player_uid)
	elif not on and has:
		SettingsStore.online_muted.remove_at(SettingsStore.online_muted.find(player_uid))
	else:
		return
	SettingsStore.save()


## Hands a freshly opened match to the battle scene and goes there.
static func play(tree: SceneTree, om: OnlineMatch) -> void:
	match_to_play = om
	open_lobby_id = ""
	Transition.go(tree, BATTLE_SCENE)


static func go_online(tree: SceneTree) -> void:
	Transition.go(tree, ONLINE_SCENE)


static func go_lobby(tree: SceneTree, match_id: String) -> void:
	lobby_to_show = match_id
	Transition.go(tree, LOBBY_SCENE)
