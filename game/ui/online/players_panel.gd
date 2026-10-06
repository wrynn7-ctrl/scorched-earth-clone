class_name PlayersPanel
extends OverlayPanel
## "Who is in this match" (opened from the pause menu of an online match): one row per seat with the tank's emblem, the
## name, the team letter and, for people, whether they are online (a filled dot) or away (a ring). A tap on another
## person's name opens the player menu (add friend, block, report, mute). Computers and your own seats have no menu.

signal player_tapped(info: Dictionary)

var _scroll: TouchScroll = null
var _rows: VBoxContainer = null
var _close: Button = null


func _init() -> void:
	super._init()
	name = "PlayersPanel"
	add_title(tr("NET_PLAYERS_TITLE"), NeonPalette.CYAN, 22.0).name = "Title"
	_scroll = TouchScroll.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rows)
	_close = add_button(tr("NET_CLOSE"), 200.0)
	_close.name = "Close"
	_close.set_meta("ui_sound", "back")
	_close.pressed.connect(close)


## `seats`: the match's seats ({kind, uid?, name?, level?}); `mine`: tank indexes of this phone; `teams`: team per tank
## (empty = no teams); `online`: Callable(uid) -> bool; `friends`: the friends list (to say who is one).
func open_for(seats: Array, mine: Array[int], teams: PackedInt32Array, online: Callable, friends: Array) -> void:
	OnlineKit.clear(_rows)
	var friend_uids: Dictionary = {}
	for f: Variant in friends:
		friend_uids[(f as Dictionary).get("uid", "")] = true
	for i: int in range(seats.size()):
		var seat: Dictionary = seats[i] as Dictionary
		var cpu: bool = seat.get("kind", "") == "cpu"
		var uid: String = str(seat.get("uid", ""))
		var is_mine: bool = mine.has(i)
		var row := RowLine.new(is_mine, false)
		row.name = "Seat%d" % i
		var emblem := EmblemIcon.new()
		emblem.set_index(i)
		OnlineKit.min_size(emblem, 30.0, 30.0)
		row.add_item(emblem)
		var shown: String = PlayerNames.label(i)
		if cpu:
			var l: Label = OnlineKit.label("%s · %s" % [shown, CpuNames.full_name(seat.get("level", 2) as int)], 15.0)
			l.name = "Name"
			row.add_item(l, true)
		elif is_mine:
			var l2: Label = OnlineKit.label(shown, 15.0)
			l2.name = "Name"
			row.add_item(l2, true)
			row.add_item(OnlineKit.badge(tr("NET_LOBBY_YOU") if mine.size() == 1 else tr("NET_LOBBY_THIS_PHONE"), NeonPalette.CYAN))
		else:
			var nb: Button = OnlineKit.button(shown, 100.0, 15.0)
			nb.name = "Name"
			nb.flat = true
			nb.alignment = HORIZONTAL_ALIGNMENT_LEFT
			nb.pressed.connect(func() -> void:
				close()
				player_tapped.emit({"uid": uid, "name": shown, "friend": friend_uids.has(uid), "in_match": true}))
			row.add_item(nb, true)
			var here: bool = online.is_valid() and online.call(uid) == true
			var g := StatusGlyph.new(StatusGlyph.Kind.DOT if here else StatusGlyph.Kind.RING,
					NeonPalette.GOOD if here else NeonPalette.TEXT_DIM)
			g.name = "Presence"
			g.tooltip_text = tr("NET_PLAYERS_ONLINE") if here else tr("NET_PLAYERS_AWAY")
			row.add_item(g)
			var pl: Label = OnlineKit.label(tr("NET_PLAYERS_ONLINE") if here else tr("NET_PLAYERS_AWAY"), 11.0,
					NeonPalette.GOOD if here else NeonPalette.TEXT_DIM, false, true)
			pl.name = "PresenceText"
			row.add_item(pl)
		if i < teams.size() and TeamStyle.is_team(teams[i]):
			var badge := TeamBadge.new()
			badge.set_team(teams[i])
			badge.set_badge_size(UiScale.dp(22.0))
			row.add_item(badge)
		_rows.add_child(row)
	open()
	if is_inside_tree():
		apply_scale()


func apply_scale() -> void:
	super.apply_scale()
	_rows.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	_scroll.custom_minimum_size = Vector2(minf(UiScale.dp(440.0), get_viewport_rect().size.x * 0.85), get_viewport_rect().size.y * 0.5)
	OnlineKit.apply(_rows)


func row_count() -> int:
	return _rows.get_child_count()


func get_row(i: int) -> RowLine:
	return _rows.get_node_or_null("Seat%d" % i) as RowLine


## A tap on the dimmed area outside the panel closes it.
func _gui_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if not _panel.get_global_rect().has_point((event as InputEventMouseButton).global_position):
			close()
