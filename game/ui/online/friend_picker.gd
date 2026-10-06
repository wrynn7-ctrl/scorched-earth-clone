class_name FriendPicker
extends OverlayPanel
## "Invite friends" in a lobby (ARCHITECTURE section 48): a scrolling list of the player's friends, each with an INVITE
## button that turns into INVITED. Every member of the lobby may invite. The list is read when the picker opens.

signal invited(uid: String)
signal toast(text: String)

var net: NetSession = null
var match_id: String = ""
var _scroll: TouchScroll = null
var _rows: VBoxContainer = null
var _empty: Label = null
var _close: Button = null
var _invited: Dictionary = {}
var _friends: Array = []
var _loading: bool = false


func _init() -> void:
	super._init()
	name = "FriendPicker"
	add_title(tr("NET_INVITE_TITLE"), NeonPalette.CYAN, 22.0).name = "Title"
	_scroll = TouchScroll.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rows)
	_empty = add_label("", 14.0, NeonPalette.TEXT_DIM)
	_empty.name = "Empty"
	_close = add_button(tr("NET_CLOSE"), 200.0)
	_close.name = "Close"
	_close.set_meta("ui_sound", "back")
	_close.pressed.connect(close)


func open_for(session: NetSession, id: String) -> void:
	net = session
	match_id = id
	_friends = net.friends.friends.duplicate()
	_render()
	open()
	if is_inside_tree():
		apply_scale()
	await _load()


func _load() -> void:
	if _loading:
		return
	_loading = true
	var r: NetResult = await net.friends.list_friends()
	_loading = false
	if r.ok:
		_friends = r.list()
	if is_inside_tree():
		_render()
		apply_scale()


func apply_scale() -> void:
	super.apply_scale()
	_rows.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	var h: float = get_viewport_rect().size.y * 0.42
	_scroll.custom_minimum_size = Vector2(minf(UiScale.dp(420.0), get_viewport_rect().size.x * 0.8), h)
	OnlineKit.apply(_rows)


func _render() -> void:
	OnlineKit.clear(_rows)
	_empty.text = tr("NET_INVITE_NONE") if _friends.is_empty() else ""
	_empty.visible = _friends.is_empty()
	for f: Variant in _friends:
		var d: Dictionary = f as Dictionary
		var uid: String = d.get("uid", "")
		var row := RowLine.new(false, false)
		row.name = "Friend_" + uid
		row.set_meta("uid", uid)
		var l: Label = OnlineKit.label(d.get("display", "") as String, 15.0)
		l.name = "Name"
		row.add_item(l, true)
		var already: bool = _invited.has(uid)
		var b: Button = OnlineKit.button(tr("NET_INVITED") if already else tr("NET_INVITE"), 110.0, 13.0)
		b.name = "Invite"
		b.disabled = already
		b.pressed.connect(invite.bind(uid))
		row.add_item(b)
		_rows.add_child(row)
	OnlineKit.apply(_rows)


## Sends the invite. A failure goes to the toast (not_friends, already_in_match, ...).
func invite(uid: String) -> void:
	if _invited.has(uid) or net == null:
		return
	_invited[uid] = true
	_render()
	var r: NetResult = await net.lobby.invite(uid, match_id)
	if r.ok:
		invited.emit(uid)
		toast.emit(tr("NET_INVITE_SENT"))
	else:
		_invited.erase(uid)
		toast.emit(OnlineText.error(r))
	if is_inside_tree():
		_render()


func get_row(uid: String) -> RowLine:
	return _rows.get_node_or_null("Friend_" + uid) as RowLine


func row_count() -> int:
	return _rows.get_child_count()


func get_empty_text() -> String:
	return _empty.text if _empty.visible else ""


## A tap on the dimmed area outside the panel closes the picker.
func _gui_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if not _panel.get_global_rect().has_point((event as InputEventMouseButton).global_position):
			close()
