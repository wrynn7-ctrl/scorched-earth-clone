class_name FriendsTab
extends OnlineTab
## Friends (ARCHITECTURE section 48): the player's own friend code with a COPY button, add a friend by code, incoming
## requests (ACCEPT / DECLINE), the friend list (INVITE when a lobby is open, REMOVE, BLOCK; a tap on the name opens
## the player menu) and the blocked list (UNBLOCK). Removing and blocking ask first.

## Friend codes have 8 characters (ARCHITECTURE section 44).
const FRIEND_CODE_LENGTH: int = 8

var _scroll: TouchScroll = null
var _box: VBoxContainer = null
var _code_label: Label = null
var _copy: Button = null
var _add_field: CodeField = null
var _add_button: Button = null
var _add_msg: Label = null
var _friends: Array = []
var _requests: Array = []
var _blocks: Array = []
var _block_names: Dictionary = {}
var _invited: Dictionary = {}
var _connected: bool = false
var _busy: bool = false


func _init() -> void:
	super._init()
	name = "FriendsTab"
	_scroll = TouchScroll.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_scroll)
	_box = VBoxContainer.new()
	_box.name = "Sections"
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_box)
	_build_static()


func setup(session: NetSession) -> void:
	super.setup(session)
	if _connected:
		return
	_connected = true
	net.friends.friends_changed.connect(_on_friends)
	net.friends.requests_changed.connect(_on_requests)
	_refresh_code()


## The parts that do not change with the lists: my code, and the add-a-friend row.
func _build_static() -> void:
	var mine: Label = OnlineKit.label(tr("NET_MY_CODE"), 13.0, NeonPalette.CYAN, false, true)
	mine.name = "MyCodeCaption"
	_box.add_child(mine)
	var row := HBoxContainer.new()
	row.name = "MyCodeRow"
	_box.add_child(row)
	_code_label = OnlineKit.label("", 26.0, NeonPalette.HOT)
	_code_label.name = "MyCode"
	_code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_code_label)
	_copy = OnlineKit.button(tr("NET_COPY"), 110.0, 14.0)
	_copy.name = "Copy"
	_copy.pressed.connect(copy_code)
	row.add_child(_copy)
	var add_caption: Label = OnlineKit.label(tr("NET_ADD_FRIEND"), 13.0, NeonPalette.CYAN, false, true)
	add_caption.name = "AddCaption"
	_box.add_child(add_caption)
	var add_row := HBoxContainer.new()
	add_row.name = "AddRow"
	_box.add_child(add_row)
	_add_field = CodeField.new(FRIEND_CODE_LENGTH)
	_add_field.name = "AddField"
	_add_field.placeholder_text = tr("NET_FRIEND_CODE_HINT")
	_add_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_field.code_changed.connect(func(_c: String) -> void: _refresh_add())
	_add_field.submitted_code.connect(func(_c: String) -> void: add_friend())
	add_row.add_child(_add_field)
	_add_button = OnlineKit.button(tr("NET_ADD"), 96.0, 14.0)
	_add_button.name = "Add"
	_add_button.pressed.connect(add_friend)
	add_row.add_child(_add_button)
	_add_msg = OnlineKit.label("", 13.0, NeonPalette.TEXT_DIM, true, true)
	_add_msg.name = "AddMessage"
	_box.add_child(_add_msg)
	var lists := VBoxContainer.new()
	lists.name = "Lists"
	lists.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(lists)
	_refresh_add()


func activate() -> void:
	super.activate()
	_friends = net.friends.friends.duplicate()
	_requests = net.friends.requests.duplicate()
	_refresh_code()
	_render()
	await _load()


func _load() -> void:
	var fr: NetResult = await net.friends.list_friends()
	if fr.ok:
		_friends = fr.list()
	var rq: NetResult = await net.friends.list_requests()
	if rq.ok:
		_requests = rq.list()
	var bl: NetResult = await net.friends.list_blocks()
	if bl.ok:
		_blocks = bl.list()
		for uid: Variant in _blocks:
			if not _block_names.has(uid):
				var who: NetResult = await net.account.fetch_public(uid as String)
				_block_names[uid] = (who.dict().get("display", "") as String) if who.ok else ""
	if is_inside_tree():
		_render()


func _on_friends(list: Array) -> void:
	_friends = list
	_render()


func _on_requests(list: Array) -> void:
	_requests = list
	_render()


func _refresh_code() -> void:
	if net == null:
		return
	var code: String = net.account.friend_code()
	_code_label.text = OnlineText.spaced(code) if code != "" else "…"
	_copy.disabled = code == ""


func apply_scale() -> void:
	super.apply_scale()
	_box.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	_add_field.apply_scale()
	_add_field.custom_minimum_size.y = UiScale.touch()


# --- my code and add ------------------------------------------------------------------------------------------

func copy_code() -> void:
	var code: String = net.account.friend_code()
	if code == "":
		return
	DisplayServer.clipboard_set(code)
	toast.emit(tr("NET_CODE_COPIED"))


func _refresh_add() -> void:
	_add_button.disabled = _busy or _add_field.code().length() != FRIEND_CODE_LENGTH


func add_friend() -> void:
	var code: String = _add_field.code()
	if code.length() != FRIEND_CODE_LENGTH or _busy:
		return
	_busy = true
	_refresh_add()
	_add_msg.text = ""
	var r: NetResult = await net.friends.send_request(code)
	_busy = false
	if r.ok:
		var d: Dictionary = r.dict()
		var who: String = d.get("name", "")
		if d.get("status", "") == "friends":
			_add_msg.text = tr("NET_NOW_FRIENDS") % who
			_load()
		else:
			_add_msg.text = tr("NET_REQUEST_SENT") % who
		_add_field.set_code("")
	else:
		_add_msg.text = OnlineText.error(r)
	_refresh_add()


# --- lists ------------------------------------------------------------------------------------------------------

func _lists() -> VBoxContainer:
	return _box.get_node("Lists") as VBoxContainer


func _render() -> void:
	var lists: VBoxContainer = _lists()
	OnlineKit.clear(lists)
	lists.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	if not _requests.is_empty():
		lists.add_child(_section(tr("NET_REQUESTS") % _requests.size(), "RequestsHeader"))
		for r: Variant in _requests:
			lists.add_child(_request_row(r as Dictionary))
	lists.add_child(_section(tr("NET_FRIENDS") % _friends.size(), "FriendsHeader"))
	if _friends.is_empty():
		var none: Label = OnlineKit.label(tr("NET_NO_FRIENDS"), 14.0, NeonPalette.TEXT_DIM, true)
		none.name = "NoFriends"
		lists.add_child(none)
	for f: Variant in _friends:
		lists.add_child(_friend_row(f as Dictionary))
	if not _blocks.is_empty():
		lists.add_child(_section(tr("NET_BLOCKED") % _blocks.size(), "BlockedHeader"))
		for uid: Variant in _blocks:
			lists.add_child(_blocked_row(uid as String))
	badge_changed.emit(_requests.size())
	apply_scale()


func _section(text: String, node_name: String) -> Label:
	var l: Label = OnlineKit.label(text, 13.0, NeonPalette.CYAN, false, true)
	l.name = node_name
	return l


func _name_button(text: String, uid: String, friend: bool) -> Button:
	var b: Button = OnlineKit.button(text, 120.0, 15.0)
	b.name = "Name"
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: player_menu.emit({"uid": uid, "name": text, "friend": friend, "in_match": false}))
	return b


func _request_row(r: Dictionary) -> RowLine:
	var uid: String = r.get("uid", "")
	var who: String = r.get("name", "")
	if who == "":
		who = tr("NET_UNKNOWN_HOST")
	var row := RowLine.new(true, false)
	row.name = "Request_" + uid
	row.set_meta("uid", uid)
	row.add_item(_name_button(who, uid, false), true)
	var accept: Button = OnlineKit.button(tr("NET_ACCEPT"), 96.0, 13.0)
	accept.name = "Accept"
	accept.pressed.connect(respond.bind(uid, true))
	row.add_item(accept)
	var decline: Button = OnlineKit.button(tr("NET_DECLINE"), 96.0, 13.0)
	decline.name = "Decline"
	decline.pressed.connect(respond.bind(uid, false))
	row.add_item(decline)
	return row


func _friend_row(f: Dictionary) -> RowLine:
	var uid: String = f.get("uid", "")
	var who: String = f.get("display", "")
	var row := RowLine.new(false, false)
	row.name = "Friend_" + uid
	row.set_meta("uid", uid)
	row.add_item(_name_button(who, uid, true), true)
	var lobby: String = OnlineHub.open_lobby_id
	if lobby != "":
		var invited: bool = _invited.has(uid)
		var inv: Button = OnlineKit.button(tr("NET_INVITED") if invited else tr("NET_INVITE"), 96.0, 13.0)
		inv.name = "Invite"
		inv.disabled = invited
		inv.pressed.connect(invite_friend.bind(uid))
		row.add_item(inv)
	var rm: Button = OnlineKit.button(tr("NET_REMOVE"), 88.0, 12.0)
	rm.name = "Remove"
	rm.pressed.connect(func() -> void: confirm.emit(tr("NET_CONFIRM_REMOVE") % who, remove_friend.bind(uid)))
	row.add_item(rm)
	var bl: Button = OnlineKit.button(tr("NET_BLOCK"), 88.0, 12.0)
	bl.name = "Block"
	bl.pressed.connect(func() -> void: confirm.emit(tr("NET_CONFIRM_BLOCK") % who, block.bind(uid)))
	row.add_item(bl)
	return row


func _blocked_row(uid: String) -> RowLine:
	var row := RowLine.new(false, false)
	row.name = "Blocked_" + uid
	row.set_meta("uid", uid)
	var shown: String = _block_names.get(uid, "") as String
	var l: Label = OnlineKit.label(shown if shown != "" else tr("NET_BLOCKED_PLAYER"), 15.0, NeonPalette.TEXT_DIM)
	l.name = "Text"
	row.add_item(l, true)
	var ub: Button = OnlineKit.button(tr("NET_UNBLOCK"), 110.0, 13.0)
	ub.name = "Unblock"
	ub.pressed.connect(unblock.bind(uid))
	row.add_item(ub)
	return row


# --- actions (public: the tests drive them) ----------------------------------------------------------------------

func respond(uid: String, accept: bool) -> void:
	var r: NetResult = await net.friends.respond(uid, accept)
	if not r.ok:
		toast.emit(OnlineText.error(r))
		return
	_requests = _requests.filter(func(e: Variant) -> bool: return (e as Dictionary).get("uid", "") != uid)
	if accept:
		toast.emit(tr("NET_NOW_FRIENDS") % "")
		await _load()
	_render()


func invite_friend(uid: String) -> void:
	if OnlineHub.open_lobby_id == "":
		return
	var r: NetResult = await net.lobby.invite(uid, OnlineHub.open_lobby_id)
	if r.ok:
		_invited[uid] = true
		toast.emit(tr("NET_INVITE_SENT"))
		_render()
	else:
		toast.emit(OnlineText.error(r))


func remove_friend(uid: String) -> void:
	var r: NetResult = await net.friends.remove_friend(uid)
	if r.ok:
		_friends = _friends.filter(func(e: Variant) -> bool: return (e as Dictionary).get("uid", "") != uid)
		_render()
	else:
		toast.emit(OnlineText.error(r))


func block(uid: String) -> void:
	var r: NetResult = await net.friends.block(uid)
	if r.ok:
		_friends = _friends.filter(func(e: Variant) -> bool: return (e as Dictionary).get("uid", "") != uid)
		await _load()
		_render()
	else:
		toast.emit(OnlineText.error(r))


func unblock(uid: String) -> void:
	var r: NetResult = await net.friends.unblock(uid)
	if r.ok:
		_blocks = _blocks.filter(func(e: Variant) -> bool: return (e as String) != uid)
		_render()
	else:
		toast.emit(OnlineText.error(r))


# --- test accessors ---------------------------------------------------------------------------------------------

func get_code_text() -> String:
	return _code_label.text


func get_add_field() -> CodeField:
	return _add_field


func get_add_button() -> Button:
	return _add_button


func get_add_message() -> String:
	return _add_msg.text


func get_copy_button() -> Button:
	return _copy


func get_scroll() -> TouchScroll:
	return _scroll


func rows_named(prefix: String) -> Array[RowLine]:
	var out: Array[RowLine] = []
	for c: Node in _lists().get_children():
		if c is RowLine and (c as RowLine).name.begins_with(prefix):
			out.append(c as RowLine)
	return out
