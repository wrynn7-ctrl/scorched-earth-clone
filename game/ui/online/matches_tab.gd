class_name MatchesTab
extends OnlineTab
## "Your matches" (ARCHITECTURE section 48): invites first (JOIN / DISMISS), then the player's matches, the ones where
## it is their turn on top, then the ones waiting for others, open lobbies and finished matches. Each row shows the
## host's name, a mode badge (Love / Teams), what is going on in words plus a shape (your-turn dot), and when it last
## changed. A tap opens the match (or its lobby).
##
## `userMatches` entries carry no mode or teams, so the badge comes from a one-time read of each match's meta
## (cached; read again when the entry's `updated` changes).

const MAX_META_PER_PASS: int = 12

var _scroll: TouchScroll = null
var _box: VBoxContainer = null
var _you: Label = null
var _list: Array = []
var _invites: Array = []
var _meta: Dictionary = {}
var _fetching: bool = false
var _busy_ids: Dictionary = {}
var _connected: bool = false
var _empty: Label = null


func _init() -> void:
	super._init()
	name = "MatchesTab"
	_you = OnlineKit.label("", 13.0, NeonPalette.TEXT_DIM, false, true)
	_you.name = "You"
	add_child(_you)
	_scroll = TouchScroll.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_scroll)
	_box = VBoxContainer.new()
	_box.name = "Rows"
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_box)


func setup(session: NetSession) -> void:
	super.setup(session)
	if _connected:
		return
	_connected = true
	net.matches.changed.connect(_on_matches)
	net.friends.invites_changed.connect(_on_invites)


func activate() -> void:
	super.activate()
	_list = net.matches.list.duplicate()
	_invites = net.friends.invites.duplicate()
	_render()
	await _load()


func _load() -> void:
	var r: NetResult = await net.matches.refresh()
	if r.ok:
		_list = r.list()
	var inv: NetResult = await net.friends.list_invites()
	if inv.ok:
		_invites = inv.list()
	if not is_inside_tree():
		return
	_render()
	_fetch_meta()


func _on_matches(list: Array) -> void:
	_list = list
	_render()
	_fetch_meta()


func _on_invites(list: Array) -> void:
	_invites = list
	_render()


func apply_scale() -> void:
	super.apply_scale()
	_box.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))


# --- data -------------------------------------------------------------------------------------------------------

## Entries the player can act on now (their turn).
func turn_count() -> int:
	var n: int = 0
	for e: Variant in _list:
		var d: Dictionary = e as Dictionary
		if d.get("status", "") == NetProtocol.STATUS_PLAYING and d.get("yourTurn", false) == true:
			n += 1
	return n


func visible_invites() -> Array:
	return NetFriends.visible_invites(_invites, SettingsStore.love_found)


func match_entries() -> Array:
	return _list


## Reads the meta of matches whose badge is not known yet (a few per pass, one after the other).
func _fetch_meta() -> void:
	if _fetching:
		return
	_fetching = true
	var done: int = 0
	for e: Variant in _list:
		var d: Dictionary = e as Dictionary
		var id: String = d.get("matchId", "")
		var stamp: int = d.get("updated", 0)
		if id == "" or (_meta.has(id) and (_meta[id] as Dictionary).get("updated", -1) == stamp):
			continue
		if done >= MAX_META_PER_PASS or not is_inside_tree():
			break
		done += 1
		var r: NetResult = await net.lobby.fetch_meta(id)
		if r.ok and typeof(r.value) == TYPE_DICTIONARY:
			_meta[id] = {"updated": stamp, "meta": NetLobby.normalize_meta(r.dict())}
		else:
			_meta[id] = {"updated": stamp, "meta": {}}
	_fetching = false
	if done > 0 and is_inside_tree():
		_render()
		_note_hosted_lobby()


## Remembers a lobby the player hosts, so the Friends tab can offer INVITE.
func _note_hosted_lobby() -> void:
	OnlineHub.open_lobby_id = ""
	for e: Variant in _list:
		var d: Dictionary = e as Dictionary
		if d.get("status", "") != NetProtocol.STATUS_LOBBY:
			continue
		var m: Dictionary = meta_of(d.get("matchId", ""))
		if m.get("hostUid", "") == net.uid() and net.uid() != "":
			OnlineHub.open_lobby_id = d.get("matchId", "")


func meta_of(match_id: String) -> Dictionary:
	if not _meta.has(match_id):
		return {}
	return (_meta[match_id] as Dictionary).get("meta", {}) as Dictionary


## "LOVE", "TEAMS" or "" for a match's meta.
static func mode_of(m: Dictionary) -> String:
	var settings: Dictionary = m.get("settings", {}) as Dictionary
	if settings.get("mode", 0) == SimConstants.MODE_LOVE:
		return "love"
	var teams: Array = NetJson.as_list(settings.get("teams", []))
	var seen: Array = []
	for t: Variant in teams:
		if not seen.has(t):
			seen.append(t)
	return "teams" if seen.size() >= 2 else ""


# --- drawing ----------------------------------------------------------------------------------------------------

func _render() -> void:
	if not is_inside_tree() and _box == null:
		return
	OnlineKit.clear(_box)
	_you.text = tr("NET_SIGNED_IN_AS") % net.account.my_name() if net != null and net.account.profile.has("name") else ""
	var invites: Array = visible_invites()
	if not invites.is_empty():
		_box.add_child(_section(tr("NET_INVITES") % invites.size()))
		for inv: Variant in invites:
			_box.add_child(_invite_row(inv as Dictionary))
	if not _list.is_empty():
		_box.add_child(_section(tr("NET_YOUR_MATCHES")))
		for e: Variant in _list:
			_box.add_child(_match_row(e as Dictionary))
	if _list.is_empty() and invites.is_empty():
		_empty = OnlineKit.label(tr("NET_NO_MATCHES"), 15.0, NeonPalette.TEXT_DIM, true)
		_empty.name = "Empty"
		_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_box.add_child(_empty)
	else:
		_empty = null
	badge_changed.emit(turn_count())
	apply_scale()


func _section(text: String) -> Label:
	var l: Label = OnlineKit.label(text, 13.0, NeonPalette.CYAN, false, true)
	l.name = "Section"
	return l


func _status_of(d: Dictionary) -> Dictionary:
	var status: String = d.get("status", "")
	if status == NetProtocol.STATUS_PLAYING:
		if d.get("yourTurn", false) == true:
			return {"text": tr("NET_STATUS_YOUR_TURN"), "kind": StatusGlyph.Kind.DOT, "color": NeonPalette.HOT}
		return {"text": tr("NET_STATUS_WAITING"), "kind": StatusGlyph.Kind.RING, "color": NeonPalette.CYAN}
	if status == NetProtocol.STATUS_LOBBY:
		return {"text": tr("NET_STATUS_LOBBY"), "kind": StatusGlyph.Kind.RING, "color": NeonPalette.WARN}
	if status == NetProtocol.STATUS_ABANDONED:
		return {"text": tr("NET_STATUS_ABANDONED"), "kind": StatusGlyph.Kind.CROSS, "color": NeonPalette.TEXT_DIM}
	return {"text": tr("NET_STATUS_OVER"), "kind": StatusGlyph.Kind.CHECK, "color": NeonPalette.GOOD}


func _match_row(d: Dictionary) -> RowLine:
	var id: String = d.get("matchId", "")
	var st: Dictionary = _status_of(d)
	var mine: bool = d.get("status", "") == NetProtocol.STATUS_PLAYING and d.get("yourTurn", false) == true
	var row := RowLine.new(mine, true)
	row.name = "Match_" + id
	row.set_meta("match_id", id)
	row.activated.connect(_on_match_tapped.bind(id, d.get("status", "") as String))
	var glyph := StatusGlyph.new(st["kind"] as int, st["color"] as Color)
	glyph.name = "Glyph"
	row.add_item(glyph)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_item(col, true)
	var host: String = d.get("hostName", "")
	var title: Label = OnlineKit.label(tr("NET_MATCH_OF") % (host if host != "" else tr("NET_UNKNOWN_HOST")), 16.0)
	title.name = "Title"
	col.add_child(title)
	var when: String = OnlineText.ago(net.clock.now_ms(), d.get("updated", 0))
	var sub: Label = OnlineKit.label("%s%s" % [st["text"], " · " + when if when != "" else ""], 13.0,
			NeonPalette.HOT if mine else NeonPalette.TEXT_DIM, false, true)
	sub.name = "Status"
	col.add_child(sub)
	var m: Dictionary = meta_of(id)
	var badges := HBoxContainer.new()
	badges.name = "Badges"
	badges.mouse_filter = Control.MOUSE_FILTER_PASS
	badges.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var mode: String = mode_of(m)
	if mode == "love":
		badges.add_child(OnlineKit.badge(tr("NET_BADGE_LOVE"), Color(1.0, 0.42, 0.68)))
	elif mode == "teams":
		badges.add_child(OnlineKit.badge(tr("NET_BADGE_TEAMS"), NeonPalette.CYAN))
	row.add_item(badges)
	var status: String = d.get("status", "")
	if status == NetProtocol.STATUS_OVER or status == NetProtocol.STATUS_ABANDONED:
		var rm: Button = OnlineKit.button(tr("NET_REMOVE_SHORT"), 84.0, 12.0)
		rm.name = "Dismiss"
		rm.pressed.connect(_on_dismiss_match.bind(id))
		row.add_item(rm)
	return row


func _invite_row(inv: Dictionary) -> RowLine:
	var id: String = inv.get("matchId", "")
	var row := RowLine.new(true, false)
	row.name = "Invite_" + id
	row.set_meta("match_id", id)
	var glyph := StatusGlyph.new(StatusGlyph.Kind.DOT, NeonPalette.WARN)
	row.add_item(glyph)
	var from: String = inv.get("fromName", "")
	var l: Label = OnlineKit.label(tr("NET_INVITE_FROM") % (from if from != "" else tr("NET_UNKNOWN_HOST")), 15.0)
	l.name = "Text"
	row.add_item(l, true)
	if (inv.get("mode", 0) as int) == SimConstants.MODE_LOVE:
		row.add_item(OnlineKit.badge(tr("NET_BADGE_LOVE"), Color(1.0, 0.42, 0.68)))
	var join: Button = OnlineKit.button(tr("NET_JOIN_SHORT"), 84.0, 13.0)
	join.name = "Join"
	join.pressed.connect(_on_join_invite.bind(inv))
	row.add_item(join)
	var dismiss: Button = OnlineKit.button(tr("NET_DISMISS"), 96.0, 12.0)
	dismiss.name = "Dismiss"
	dismiss.pressed.connect(_on_dismiss_invite.bind(id))
	row.add_item(dismiss)
	return row


# --- actions ----------------------------------------------------------------------------------------------------

func _on_match_tapped(id: String, status: String) -> void:
	if status == NetProtocol.STATUS_LOBBY:
		open_lobby.emit(id)
	else:
		open_match.emit(id)


func _on_dismiss_match(id: String) -> void:
	var r: NetResult = await net.matches.dismiss(id)
	if r.ok:
		_list = _list.filter(func(e: Variant) -> bool: return (e as Dictionary).get("matchId", "") != id)
		_render()
	else:
		toast.emit(OnlineText.error(r))


func _on_dismiss_invite(id: String) -> void:
	var r: NetResult = await net.friends.dismiss_invite(id)
	if r.ok:
		_invites = _invites.filter(func(e: Variant) -> bool: return (e as Dictionary).get("matchId", "") != id)
		_render()
	else:
		toast.emit(OnlineText.error(r))


func _on_join_invite(inv: Dictionary) -> void:
	var id: String = inv.get("matchId", "")
	if _busy_ids.has(id):
		return
	_busy_ids[id] = true
	var r: NetResult = await net.lobby.join(inv.get("code", "") as String)
	_busy_ids.erase(id)
	if r.ok:
		net.friends.dismiss_invite(id)
		open_lobby.emit(r.dict().get("matchId", id) as String)
		return
	if check_update(r):
		return
	toast.emit(OnlineText.error(r))


# --- test accessors ---------------------------------------------------------------------------------------------

func get_rows() -> Array[RowLine]:
	var out: Array[RowLine] = []
	for c: Node in _box.get_children():
		if c is RowLine and (c as RowLine).name.begins_with("Match_"):
			out.append(c as RowLine)
	return out


func get_invite_rows() -> Array[RowLine]:
	var out: Array[RowLine] = []
	for c: Node in _box.get_children():
		if c is RowLine and (c as RowLine).name.begins_with("Invite_"):
			out.append(c as RowLine)
	return out


func get_scroll() -> TouchScroll:
	return _scroll


func get_empty_label() -> Label:
	return _empty


func get_you_text() -> String:
	return _you.text
