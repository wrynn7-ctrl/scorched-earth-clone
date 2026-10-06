class_name LobbyScreen
extends Control
## The match lobby (ARCHITECTURE sections 45 and 48). Everyone who joined sees the same seats; the host also edits them.
##
## Seats list humans with their names, CPU level chips, team chips (the same chips and START rules as the local setup)
## and a "this phone" marker for shared-phone seats. The host adds or removes CPUs and open seats, sets teams, friendly
## fire, rounds, money, wind and theme and the live/async timers; every edit is one `updateLobby` call and the screen
## re-reads the lobby. Joiners get a read-only view and "Waiting for the host". Anyone can invite friends from a picker or
## share the code. START (host) needs every human seat filled and usable teams; the match then opens in the battle scene
## for everybody (`lobby_started`).
##
## All decisions live in LobbyModel; this class only draws and sends.

signal updated
signal entered_match

const THEME: Theme = preload("res://ui/theme/neon_theme.tres")
const MONEY_KEYS: Array[String] = ["SETUP_LOW", "SETUP_NORMAL", "SETUP_HIGH"]
const WIND_KEYS: Array[String] = ["SETUP_OFF", "SETUP_LOW", "SETUP_NORMAL", "SETUP_HIGH"]
const LEVEL_COLORS: Array[Color] = [Color.WHITE, NeonPalette.GOOD, NeonPalette.CYAN, NeonPalette.WARN, NeonPalette.MAGENTA]

var net: NetSession = null
var match_id: String = ""
var _meta: Dictionary = {}
var _teams: PackedInt32Array = PackedInt32Array()
var _teams_dirty: bool = false
var _busy: bool = false
var _entering: bool = false
var _left: bool = false
var _watching: bool = false

var _sky: NeonSky = null
var _margin: MarginContainer = null
var _root: VBoxContainer = null
var _header: HBoxContainer = null
var _leave: Button = null
var _code_box: VBoxContainer = null
var _code_caption: Label = null
var _code_label: Label = null
var _copy: Button = null
var _share: Button = null
var _invite: Button = null
var _columns: HBoxContainer = null
var _seats_panel: PanelContainer = null
var _seats_caption: Label = null
var _seats_scroll: TouchScroll = null
var _seats_box: VBoxContainer = null
var _add_row: HBoxContainer = null
var _add_cpu: Button = null
var _add_human: Button = null
var _rules_panel: PanelContainer = null
var _rules_scroll: TouchScroll = null
var _rules_box: VBoxContainer = null
var _rules: Dictionary = {}
var _rules_note: Label = null
var _bottom: HBoxContainer = null
var _hint: Label = null
var _switch: Button = null
var _narrow: bool = false
var _view: int = 0
var _start: Button = null
var _toast: Toast = null
var _confirm: OnlineConfirm = null
var _menu: PlayerMenu = null
var _picker: FriendPicker = null
var _theme_picker: ThemePicker = null


func _init() -> void:
	ShotArgs.parse()
	SettingsStore.ensure_loaded()
	theme = THEME
	name = "LobbyScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	apply_scale()
	LayoutWatch.attach(self, apply_scale)
	OnlineHub.start_services()
	ShotHook.attach(self)
	if net == null and OnlineHub.lobby_to_show != "":
		await open_lobby(OnlineHub.ensure_session(), OnlineHub.lobby_to_show)


func _exit_tree() -> void:
	_unwatch()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _theme_picker != null and _theme_picker.is_open():
			_theme_picker.close()
		elif _picker != null and _picker.is_open():
			_picker.close()
		elif _menu != null and _menu.is_open():
			_menu.close()
		elif _confirm != null and _confirm.is_open():
			_confirm.close()
		else:
			ask_leave()


# ======================================================================================
# Build
# ======================================================================================

func _panel(panel_name: String) -> Array:
	var p := PanelContainer.new()
	p.name = panel_name
	var box := VBoxContainer.new()
	box.name = "Box"
	p.add_child(box)
	return [p, box]


func _build() -> void:
	_sky = (load("res://show/sky.tscn") as PackedScene).instantiate()
	add_child(_sky)
	_margin = MarginContainer.new()
	_margin.name = "Margin"
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	_root = VBoxContainer.new()
	_root.name = "Root"
	_margin.add_child(_root)
	_build_header()
	_columns = HBoxContainer.new()
	_columns.name = "Columns"
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(_columns)
	_build_seats()
	_build_rules()
	_build_bottom()
	_toast = Toast.new()
	_toast.name = "Toast"
	add_child(_toast)
	_confirm = OnlineConfirm.new()
	add_child(_confirm)
	_menu = PlayerMenu.new()
	_menu.toast.connect(show_toast)
	add_child(_menu)
	_picker = FriendPicker.new()
	_picker.toast.connect(show_toast)
	add_child(_picker)
	_theme_picker = ThemePicker.new()
	_theme_picker.chosen.connect(func(id: String) -> void: set_rule("theme", id))
	add_child(_theme_picker)


func _build_header() -> void:
	_header = HBoxContainer.new()
	_header.name = "Header"
	_root.add_child(_header)
	_leave = OnlineKit.button(tr("NET_LOBBY_LEAVE"), 96.0, 13.0)
	_leave.name = "Leave"
	_leave.set_meta("ui_sound", "back")
	_leave.pressed.connect(ask_leave)
	_header.add_child(_leave)
	_code_box = VBoxContainer.new()
	_code_box.name = "CodeBox"
	_code_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_header.add_child(_code_box)
	_code_caption = OnlineKit.label(tr("NET_LOBBY_CODE"), 11.0, NeonPalette.TEXT_DIM, false, true)
	_code_caption.name = "CodeCaption"
	_code_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_box.add_child(_code_caption)
	_code_label = OnlineKit.label("······", 24.0, NeonPalette.HOT, false, true)
	_code_label.name = "Code"
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_box.add_child(_code_label)
	_copy = OnlineKit.button(tr("NET_COPY"), 84.0, 13.0)
	_copy.name = "Copy"
	_copy.pressed.connect(copy_code)
	_header.add_child(_copy)
	_share = OnlineKit.button(tr("NET_LOBBY_SHARE"), 96.0, 13.0)
	_share.name = "Share"
	_share.pressed.connect(share_code)
	_header.add_child(_share)
	_invite = OnlineKit.button(tr("NET_LOBBY_INVITE"), 130.0, 13.0)
	_invite.name = "Invite"
	_invite.pressed.connect(open_invite)
	_header.add_child(_invite)


func _build_seats() -> void:
	var made: Array = _panel("SeatsPanel")
	_seats_panel = made[0]
	var box: VBoxContainer = made[1]
	_seats_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seats_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_columns.add_child(_seats_panel)
	_seats_caption = OnlineKit.label("", 13.0, NeonPalette.CYAN, false, true)
	_seats_caption.name = "SeatsCaption"
	box.add_child(_seats_caption)
	_seats_scroll = TouchScroll.new()
	_seats_scroll.name = "Scroll"
	_seats_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_seats_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_seats_scroll)
	_seats_box = VBoxContainer.new()
	_seats_box.name = "Seats"
	_seats_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seats_scroll.add_child(_seats_box)
	_add_row = HBoxContainer.new()
	_add_row.name = "AddRow"
	box.add_child(_add_row)
	_add_cpu = OnlineKit.button(tr("NET_LOBBY_ADD_CPU"), 130.0, 13.0)
	_add_cpu.name = "AddCpu"
	_add_cpu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_cpu.pressed.connect(add_cpu)
	_add_row.add_child(_add_cpu)
	_add_human = OnlineKit.button(tr("NET_LOBBY_ADD_PLAYER"), 130.0, 13.0)
	_add_human.name = "AddPlayer"
	_add_human.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_human.pressed.connect(add_player)
	_add_row.add_child(_add_human)


func _build_rules() -> void:
	var made: Array = _panel("RulesPanel")
	_rules_panel = made[0]
	var box: VBoxContainer = made[1]
	_columns.add_child(_rules_panel)
	var caption: Label = OnlineKit.label(tr("NET_LOBBY_RULES"), 13.0, NeonPalette.CYAN, false, true)
	caption.name = "RulesCaption"
	box.add_child(caption)
	_rules_scroll = TouchScroll.new()
	_rules_scroll.name = "Scroll"
	_rules_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rules_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_rules_scroll)
	_rules_box = VBoxContainer.new()
	_rules_box.name = "Rules"
	_rules_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rules_scroll.add_child(_rules_box)
	_rules_note = OnlineKit.label("", 12.0, NeonPalette.TEXT_DIM, true, true)
	_rules_note.name = "Note"
	_rules_box.add_child(_rules_note)
	for spec: Array in [["rounds", "NET_RULE_ROUNDS"], ["money", "NET_RULE_MONEY"], ["wind", "NET_RULE_WIND"],
			["theme", "NET_RULE_THEME"], ["friendly_fire", "SETUP_FRIENDLY_FIRE"], ["live", "NET_RULE_LIVE"],
			["async", "NET_RULE_ASYNC"], ["timeout", "NET_RULE_TIMEOUT"]]:
		_make_rule(spec[0] as String, tr(spec[1] as String))


func _make_rule(key: String, caption: String) -> void:
	var row := HBoxContainer.new()
	row.name = "Rule_" + key
	_rules_box.add_child(row)
	var l: Label = OnlineKit.label(caption, 13.0, NeonPalette.TEXT, false, true)
	l.name = "Caption"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	var b: Button = OnlineKit.button("", 92.0, 13.0)
	b.name = "Value"
	b.pressed.connect(_on_rule_pressed.bind(key))
	row.add_child(b)
	var v: Label = OnlineKit.label("", 13.0, NeonPalette.HOT, false, true)
	v.name = "ReadOnly"
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(v)
	_rules[key] = {"row": row, "button": b, "label": v}


func _build_bottom() -> void:
	_bottom = HBoxContainer.new()
	_bottom.name = "Bottom"
	_root.add_child(_bottom)
	_hint = OnlineKit.label("", 13.0, NeonPalette.WARN, true, true)
	_hint.name = "Hint"
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bottom.add_child(_hint)
	_switch = OnlineKit.button(tr("NET_LOBBY_SHOW_RULES"), 110.0, 13.0)
	_switch.name = "Switch"
	_switch.visible = false
	_switch.pressed.connect(toggle_view)
	_bottom.add_child(_switch)
	_start = OnlineKit.button(tr("NET_LOBBY_START"), 190.0, 20.0, false)
	_start.name = "Start"
	_start.theme_type_variation = &"FireButton"
	_start.pressed.connect(start_match)
	_bottom.add_child(_start)


func apply_scale() -> void:
	LayoutGuard.fit(self)
	UiScale.apply_edge_margins(_margin)
	_root.add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))
	_header.add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))
	_columns.add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))
	_bottom.add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))
	_add_row.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	_seats_box.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	_rules_box.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	_rules_panel.custom_minimum_size.x = 0.0
	_rules_panel.size_flags_stretch_ratio = 0.8
	_seats_panel.size_flags_stretch_ratio = 1.2
	OnlineKit.apply(self)
	_fit_columns()


## When the players and the rules do not fit side by side (a short phone with big text), they share the space and a
## button in the bottom bar switches between them.
func _fit_columns() -> void:
	_seats_panel.visible = true
	_rules_panel.visible = true
	var margins: Vector4 = UiScale.edge_margins()
	var need: float = _seats_panel.get_combined_minimum_size().x + _rules_panel.get_combined_minimum_size().x + UiScale.dp(8.0)
	var room: float = get_viewport_rect().size.x - margins.x - margins.z
	_narrow = need > room
	_switch.visible = _narrow
	if _narrow:
		_seats_panel.visible = _view == 0
		_rules_panel.visible = _view == 1
	_switch.text = tr("NET_LOBBY_SHOW_RULES") if _view == 0 else tr("NET_LOBBY_SHOW_PLAYERS")


func toggle_view() -> void:
	_view = 1 - _view
	_fit_columns()


func is_narrow() -> bool:
	return _narrow


func get_switch_button() -> Button:
	return _switch


# ======================================================================================
# Opening and watching
# ======================================================================================

## Shows the lobby `id`: reads it once, then follows it live.
func open_lobby(session: NetSession, id: String) -> void:
	net = session
	match_id = id
	OnlineHub.open_lobby_id = id
	OnlineHub.lobby_to_show = id
	_watch()
	var r: NetResult = await net.lobby.fetch_meta(id)
	if not is_inside_tree():
		return
	if not r.ok or typeof(r.value) != TYPE_DICTIONARY:
		show_toast(OnlineText.error(r) if not r.ok else tr("NET_ERR_NOT_FOUND"))
		_go_online()
		return
	apply_meta(NetLobby.normalize_meta(r.dict()))


func _watch() -> void:
	if _watching:
		return
	_watching = true
	net.lobby.lobby_changed.connect(_on_changed)
	net.lobby.lobby_started.connect(_on_started)
	net.lobby.lobby_abandoned.connect(_on_abandoned)
	net.lobby.watch(match_id)


func _unwatch() -> void:
	if not _watching or net == null:
		return
	_watching = false
	if net.lobby.lobby_changed.is_connected(_on_changed):
		net.lobby.lobby_changed.disconnect(_on_changed)
	if net.lobby.lobby_started.is_connected(_on_started):
		net.lobby.lobby_started.disconnect(_on_started)
	if net.lobby.lobby_abandoned.is_connected(_on_abandoned):
		net.lobby.lobby_abandoned.disconnect(_on_abandoned)
	net.lobby.unwatch()


func _on_changed(meta: Dictionary) -> void:
	if meta.get("status", "") == NetProtocol.STATUS_LOBBY or _meta.is_empty():
		apply_meta(meta)


func _on_started(_meta_value: Dictionary) -> void:
	await enter_match()


func _on_abandoned(_meta_value: Dictionary) -> void:
	if _left or _entering:
		return
	show_toast(tr("NET_LOBBY_CLOSED"))
	_go_online()


# ======================================================================================
# The data
# ======================================================================================

func my_uid() -> String:
	return net.uid() if net != null else ""


func is_host() -> bool:
	return LobbyModel.is_host(_meta, my_uid())


func get_meta_copy() -> Dictionary:
	return _meta.duplicate(true)


func get_teams() -> PackedInt32Array:
	return _teams


## Takes a lobby state (from a stream or a fresh read) and redraws everything.
func apply_meta(meta: Dictionary) -> void:
	var seat_count: int = LobbyModel.seats_of(meta).size()
	_meta = meta
	if not is_host() or not _teams_dirty or _teams.size() != seat_count:
		_teams = LobbyModel.teams_of(meta)
		_teams_dirty = false
	_render()
	updated.emit()


func _render() -> void:
	if _meta.is_empty():
		return
	var host: bool = is_host()
	var love: bool = LobbyModel.is_love(_meta)
	_code_label.text = str(_meta.get("code", "······"))
	_render_seats(host, love)
	_render_rules(host, love)
	_render_bottom(host)
	_add_cpu.visible = host and not love and LobbyModel.seats_of(_meta).size() < LobbyModel.MAX_SEATS
	_add_human.visible = host and not love and LobbyModel.seats_of(_meta).size() < LobbyModel.MAX_SEATS
	_add_row.visible = _add_cpu.visible or _add_human.visible
	_invite.visible = true
	OnlineKit.apply(self)
	_fit_columns()


func _render_seats(host: bool, love: bool) -> void:
	if _add_row.get_parent() != null:
		_add_row.get_parent().remove_child(_add_row)
	OnlineKit.clear(_seats_box)
	var seats: Array = LobbyModel.seats_of(_meta)
	var open_n: int = LobbyModel.open_count(_meta)
	_seats_caption.text = tr("NET_LOBBY_SEATS") % [seats.size() - open_n, seats.size()]
	var mine: Array[int] = LobbyModel.seats_held_by(_meta, my_uid())
	for i: int in range(seats.size()):
		_seats_box.add_child(_seat_row(i, seats[i] as Dictionary, host, love, mine))
	_seats_box.add_child(_add_row)  # the add buttons are the last entries of the list: the rows get the room


func _seat_row(i: int, seat: Dictionary, host: bool, love: bool, mine: Array[int]) -> RowLine:
	var open: bool = LobbyModel.is_open(seat)
	var cpu: bool = LobbyModel.is_cpu(seat)
	var uid: String = str(seat.get("uid", ""))
	var is_mine: bool = mine.has(i)
	var row := RowLine.new(is_mine, false)
	row.name = "Seat%d" % i
	row.set_meta("seat", i)
	var emblem := EmblemIcon.new()
	emblem.name = "Emblem"
	emblem.set_index(i)
	OnlineKit.min_size(emblem, 30.0, 30.0)
	row.add_item(emblem)
	var glyph := StatusGlyph.new(StatusGlyph.Kind.RING if open else StatusGlyph.Kind.CHECK,
			NeonPalette.WARN if open else NeonPalette.GOOD)
	glyph.name = "Glyph"
	row.add_item(glyph)
	var col := HBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_item(col, true)
	var shown: String = str(seat.get("name", ""))
	if open:
		shown = tr("NET_LOBBY_OPEN_SEAT")
	elif shown == "":
		shown = tr("HUD_PLAYER_N") % (i + 1)
	if not open and not cpu and not is_mine and uid != "":
		var nb: Button = OnlineKit.button(shown, 100.0, 15.0)
		nb.name = "Name"
		nb.flat = true
		nb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		nb.pressed.connect(open_player_menu.bind(uid, shown))
		col.add_child(nb)
	else:
		var nl: Label = OnlineKit.label(shown, 15.0, NeonPalette.TEXT_DIM if open else NeonPalette.TEXT)
		nl.name = "Name"
		nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		col.add_child(nl)
	if is_mine:
		var badge_text: String = tr("NET_LOBBY_THIS_PHONE") if mine.size() > 1 else tr("NET_LOBBY_YOU")
		var badge: PanelContainer = OnlineKit.badge(badge_text, NeonPalette.CYAN)
		badge.name = "Mine"
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_item(badge)
	if cpu and not host:
		var lbadge: PanelContainer = OnlineKit.badge(CpuNames.full_name(seat.get("level", 2) as int), LEVEL_COLORS[clampi(seat.get("level", 2) as int, 0, 4)])
		lbadge.name = "Level"
		lbadge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_item(lbadge)
	if cpu and host:
		var lb: Button = OnlineKit.button(CpuNames.level_word(seat.get("level", 2) as int), 72.0, 12.0)
		lb.name = "Level"
		lb.add_theme_color_override("font_color", LEVEL_COLORS[clampi(seat.get("level", 2) as int, 0, 4)])
		lb.pressed.connect(cycle_cpu_level.bind(i))
		row.add_item(lb)
	if open and host and not love:
		var mb: Button = OnlineKit.button(tr("NET_LOBBY_PLAY_HERE"), 72.0, 11.0)
		mb.name = "PlayHere"
		mb.pressed.connect(play_here.bind(i))
		row.add_item(mb)
	if not love:
		var chip := TeamChip.new()
		chip.name = "Team"
		chip.set_team(_teams[i] if i < _teams.size() else TeamStyle.NONE)
		chip.set_meta(OnlineKit.META_MIN, Vector2(48.0, 48.0))
		chip.set_meta(OnlineKit.META_FONT, 15.0)
		chip.set_meta(OnlineKit.META_DENSE, true)
		if host:
			chip.pressed.connect(cycle_team.bind(i))
		else:
			chip.disabled = true
		row.add_item(chip)
	if host and not love and (cpu or open) and LobbyModel.seats_of(_meta).size() > LobbyModel.MIN_SEATS:
		var rm: Button = OnlineKit.button(tr("NET_REMOVE_SEAT"), 48.0, 15.0)
		rm.name = "Remove"
		rm.accessibility_name = tr("NET_LOBBY_REMOVE_SEAT_TIP")
		rm.tooltip_text = tr("NET_LOBBY_REMOVE_SEAT_TIP")
		rm.pressed.connect(remove_seat.bind(i))
		row.add_item(rm)
	return row


func _render_rules(host: bool, love: bool) -> void:
	var s: Dictionary = LobbyModel.settings_of(_meta)
	var t: Dictionary = LobbyModel.timers_of(_meta)
	var values: Dictionary = {
		"rounds": str(s.get("rounds", 3)),
		"money": _choice_text(LobbyModel.MONEY_CHOICES, MONEY_KEYS, s.get("start_money", 10000) as int),
		"wind": _choice_text(LobbyModel.WIND_CHOICES, WIND_KEYS, s.get("wind_max", 100) as int),
		"theme": tr(ThemeDefs.name_key(ThemeDefs.sanitize(s.get("theme", ThemeDefs.DEFAULT_ID)))),
		"friendly_fire": tr("SET_ON") if s.get("friendly_fire", true) == true else tr("SET_OFF"),
		"live": tr("NET_RULE_SECONDS") % int(t["liveSec"]),
		"async": tr("NET_RULE_HOURS") % int(t["asyncHours"]),
		"timeout": tr("NET_RULE_TIMEOUT_AUTO") if t["asyncTimeout"] == "auto" else tr("NET_RULE_TIMEOUT_END"),
	}
	var teams_on: bool = LobbyModel.teams_on(_teams)
	for key: String in _rules.keys():
		var r: Dictionary = _rules[key]
		var shown: bool = true
		if love and key in ["rounds", "money", "wind", "theme", "friendly_fire"]:
			shown = false
		if key == "friendly_fire" and not teams_on:
			shown = false
		(r["row"] as Control).visible = shown
		(r["button"] as Button).visible = host
		(r["button"] as Button).text = values[key] as String
		(r["button"] as Button).accessibility_name = values[key] as String
		(r["label"] as Label).visible = not host
		(r["label"] as Label).text = values[key] as String
	_rules_note.text = tr("NET_RULE_LOVE_NOTE") if love else (tr("NET_RULE_JOINER_NOTE") if not host else "")
	_rules_note.visible = _rules_note.text != ""


func _choice_text(values: Array[int], keys: Array[String], value: int) -> String:
	var i: int = values.find(value)
	return tr(keys[i]) if i >= 0 else str(value)


func _render_bottom(host: bool) -> void:
	_start.visible = host
	if host:
		var chk: Dictionary = LobbyModel.start_check(_meta, my_uid(), _teams)
		_start.disabled = not (chk["ok"] as bool) or _busy
		var key: String = LobbyModel.start_hint_key(chk["reason"] as String)
		_hint.text = tr(key) % LobbyModel.open_count(_meta) if key == "NET_LOBBY_NEED_PLAYERS" else (tr(key) if key != "" else "")
	else:
		_hint.text = tr("NET_LOBBY_WAIT_HOST")
		_hint.add_theme_color_override("font_color", NeonPalette.CYAN)
	if host:
		_hint.add_theme_color_override("font_color", NeonPalette.WARN)


# ======================================================================================
# Host edits
# ======================================================================================

func _on_rule_pressed(key: String) -> void:
	if not is_host():
		return
	var s: Dictionary = LobbyModel.settings_of(_meta)
	var t: Dictionary = LobbyModel.timers_of(_meta)
	match key:
		"rounds":
			set_rule("rounds", LobbyModel.cycle(LobbyModel.ROUND_CHOICES, s.get("rounds", 3)))
		"money":
			set_rule("start_money", LobbyModel.cycle(LobbyModel.MONEY_CHOICES, s.get("start_money", 10000)))
		"wind":
			set_rule("wind_max", LobbyModel.cycle(LobbyModel.WIND_CHOICES, s.get("wind_max", 100)))
		"theme":
			_theme_picker.open_for(ThemeDefs.sanitize(s.get("theme", ThemeDefs.DEFAULT_ID)), true)
		"friendly_fire":
			set_rule("friendly_fire", not (s.get("friendly_fire", true) == true))
		"live":
			set_timers(int(LobbyModel.cycle(LobbyModel.LIVE_PRESETS, t["liveSec"])), int(t["asyncHours"]), str(t["asyncTimeout"]))
		"async":
			set_timers(int(t["liveSec"]), int(LobbyModel.cycle(LobbyModel.ASYNC_PRESETS, t["asyncHours"])), str(t["asyncTimeout"]))
		"timeout":
			set_timers(int(t["liveSec"]), int(t["asyncHours"]), str(LobbyModel.cycle(LobbyModel.ASYNC_TIMEOUTS, t["asyncTimeout"])))


## One rule (rounds, start_money, wind_max, theme, friendly_fire) through `updateLobby`.
func set_rule(key: String, value: Variant) -> void:
	if not is_host():
		return
	await _send(null, {key: value}, null)


func set_timers(live_sec: int, async_hours: int, async_timeout: String) -> void:
	if not is_host():
		return
	await _send(null, null, NetLobby.timers(live_sec, async_hours, async_timeout))


func add_cpu() -> void:
	if not is_host():
		return
	var specs: Array = LobbyModel.add_cpu(_meta, SimConstants.CTRL_NORMAL)
	_teams = LobbyModel.fit_teams(_teams, specs.size())
	await _send(specs, {}, null)


func add_player() -> void:
	if not is_host():
		return
	var specs: Array = LobbyModel.add_human(_meta, false)
	_teams = LobbyModel.fit_teams(_teams, specs.size())
	await _send(specs, {}, null)


func remove_seat(index: int) -> void:
	if not is_host():
		return
	var specs: Array = LobbyModel.remove_seat(_meta, index)
	if specs.size() == LobbyModel.seats_of(_meta).size():
		return
	var kept := PackedInt32Array()
	for i: int in range(_teams.size()):
		if i != index:
			kept.append(_teams[i])
	_teams = kept
	await _send(specs, {}, null)


func cycle_cpu_level(index: int) -> void:
	if not is_host():
		return
	var seats: Array = LobbyModel.seats_of(_meta)
	if index < 0 or index >= seats.size() or not LobbyModel.is_cpu(seats[index]):
		return
	var level: int = LobbyModel.next_level((seats[index] as Dictionary).get("level", 2) as int)
	await _send(LobbyModel.set_cpu_level(_meta, index, level), null, null)


## An open human seat becomes one of this phone's seats (shared phone): the host plays it too.
func play_here(index: int) -> void:
	if not is_host():
		return
	await _send(LobbyModel.set_seat_mine(_meta, index, true), null, null)


func cycle_team(index: int) -> void:
	if not is_host() or index < 0 or index >= _teams.size():
		return
	_teams[index] = TeamStyle.next(_teams[index])
	_teams_dirty = true
	if LobbyModel.teams_error(_teams) == "":
		var settings: Dictionary = {"teams": LobbyModel.teams_param(_teams)}
		await _send(null, settings, null)
	else:
		_render()  # not usable yet: only shown here, START says why
		updated.emit()


## Sends one `updateLobby` and redraws from the answer. `seats` / `settings` / `timers` may be null (unchanged). Changing
## the seats always sends the teams too, so the server never sees teams of the wrong length.
func _send(seats: Variant, settings: Variant, timers: Variant) -> bool:
	if _busy or net == null:
		return false
	_busy = true
	var sent_settings: Variant = settings
	if seats != null:
		var d: Dictionary = (settings as Dictionary).duplicate() if typeof(settings) == TYPE_DICTIONARY else {}
		if not d.has("teams"):
			d["teams"] = LobbyModel.teams_param(_teams)
		sent_settings = d
	var r: NetResult = await net.lobby.update(match_id, sent_settings, seats, timers)
	_busy = false
	if not is_inside_tree():
		return false
	if not r.ok:
		_teams_dirty = false
		show_toast(OnlineText.error(r))
		await reload()
		return false
	if typeof(sent_settings) == TYPE_DICTIONARY and (sent_settings as Dictionary).has("teams"):
		_teams_dirty = false
	await reload()
	return true


## Reads the lobby again (after an edit, and when a stream event may have been missed).
func reload() -> void:
	var r: NetResult = await net.lobby.fetch_meta(match_id)
	if r.ok and typeof(r.value) == TYPE_DICTIONARY and is_inside_tree():
		apply_meta(NetLobby.normalize_meta(r.dict()))


# ======================================================================================
# Start, leave, invite, share
# ======================================================================================

func start_match() -> void:
	if _busy or _entering or net == null:
		return
	var chk: Dictionary = LobbyModel.start_check(_meta, my_uid(), _teams)
	if not (chk["ok"] as bool):
		return
	_busy = true
	_start.disabled = true
	var r: NetResult = await net.lobby.start(match_id)
	_busy = false
	if not is_inside_tree():
		return
	if not r.ok:
		show_toast(OnlineText.error(r))
		await reload()
		return
	await enter_match()


## The match started (the host pressed START, or `lobby_started` reached a joiner): open it and play.
func enter_match() -> void:
	if _entering or net == null:
		return
	_entering = true
	_unwatch()
	var r: NetResult = await net.open_match(match_id)
	if not is_inside_tree():
		return
	if r.ok:
		OnlineHub.open_lobby_id = ""
		OnlineHub.lobby_to_show = ""
		entered_match.emit()
		OnlineHub.play(get_tree(), r.value as OnlineMatch)
		return
	_entering = false
	show_toast(tr("NET_ERR_UPDATE") if r.is_code(NetError.Code.PROTOCOL_MISMATCH) else OnlineText.error(r))
	_go_online()


func ask_leave() -> void:
	var text: String = tr("NET_LOBBY_CLOSE_Q") if is_host() else tr("NET_LOBBY_LEAVE_Q")
	_confirm.ask(text, leave, tr("NET_LOBBY_LEAVE") if not is_host() else tr("NET_LOBBY_CLOSE"))


## Leaves the lobby (the host closes it) and goes back to the Online home.
func leave() -> void:
	_left = true
	_unwatch()
	if net != null and match_id != "":
		await net.lobby.leave(match_id)
	OnlineHub.open_lobby_id = ""
	OnlineHub.lobby_to_show = ""
	_go_online()


func _go_online() -> void:
	if is_inside_tree():
		OnlineHub.go_online(get_tree())


func copy_code() -> void:
	var code: String = str(_meta.get("code", ""))
	if code == "":
		return
	DisplayServer.clipboard_set(code)
	show_toast(tr("NET_CODE_COPIED"))


## The Android share sheet ("Join my Craterline match: CODE"); the clipboard where there is none.
func share_code() -> void:
	var code: String = str(_meta.get("code", ""))
	if code == "" or OnlineHub.share == null:
		return
	var result: int = OnlineHub.share.share_invite(tr("NET_SHARE_TITLE"), tr("NET_SHARE_TEXT"), code)
	if result == ShareService.Result.COPIED:
		show_toast(tr("NET_SHARE_COPIED"))


func open_invite() -> void:
	_picker.open_for(net, match_id)


func open_player_menu(uid: String, shown: String) -> void:
	var friend: bool = false
	for f: Variant in net.friends.friends:
		if (f as Dictionary).get("uid", "") == uid:
			friend = true
	_menu.open_for(net, {"uid": uid, "name": shown, "friend": friend, "in_match": false})


func show_toast(text: String) -> void:
	_toast.show_message(text)


# --- test accessors ---------------------------------------------------------------------------------------------

func get_start_button() -> Button:
	return _start


func get_hint_text() -> String:
	return _hint.text


func get_seat_row(i: int) -> RowLine:
	return _seats_box.get_node_or_null("Seat%d" % i) as RowLine


func seat_row_count() -> int:
	return _seats_box.get_child_count()


func get_rule_button(key: String) -> Button:
	return (_rules[key] as Dictionary)["button"] as Button


func get_rule_label(key: String) -> Label:
	return (_rules[key] as Dictionary)["label"] as Label


func is_rule_visible(key: String) -> bool:
	return ((_rules[key] as Dictionary)["row"] as Control).visible


func get_add_cpu_button() -> Button:
	return _add_cpu


func get_add_player_button() -> Button:
	return _add_human


func get_code_text() -> String:
	return _code_label.text


func get_invite_button() -> Button:
	return _invite


func get_share_button() -> Button:
	return _share


func get_picker() -> FriendPicker:
	return _picker


func get_confirm() -> OnlineConfirm:
	return _confirm


func get_player_menu() -> PlayerMenu:
	return _menu


func get_theme_picker() -> ThemePicker:
	return _theme_picker


func get_seats_scroll() -> TouchScroll:
	return _seats_scroll


func get_rules_scroll() -> TouchScroll:
	return _rules_scroll


func get_toast() -> Toast:
	return _toast


func get_leave_button() -> Button:
	return _leave


func is_busy() -> bool:
	return _busy
