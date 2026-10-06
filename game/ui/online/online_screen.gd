class_name OnlineScreen
extends Control
## The Online home (ARCHITECTURE section 48), reached from the title's ONLINE button.
##
## One top bar (BACK and the four tabs: MATCHES, FRIENDS, JOIN, HOST) over the pages. Before the pages show, a "gate"
## takes the middle of the screen while the account is not ready: connecting, offline (RETRY), "please update the
## game", the first-visit name setup, or "opening match...". Everything the pages want (open a match, ask a yes/no
## question, a player menu, the Unlock screen) comes up as a signal and is handled here, so the pages stay small and
## testable with a fake session.
##
## Deep links and notification taps wait in OnlineHub until a screen like this one takes them (`_follow_route`).

signal signed_in
signal gate_changed(gate: int)

const TITLE_SCENE: String = "res://ui/title/title_screen.tscn"
const THEME: Theme = preload("res://ui/theme/neon_theme.tres")

enum Tab { MATCHES, FRIENDS, JOIN, HOST }
enum Gate { NONE, SIGNING_IN, OFFLINE, UPDATE, SETUP, NAME, OPENING }

const TAB_KEYS: Array[String] = ["NET_TAB_MATCHES", "NET_TAB_FRIENDS", "NET_TAB_JOIN", "NET_TAB_HOST"]
const TAB_NAMES: Array[String] = ["Matches", "Friends", "Join", "Host"]

var net: NetSession = null
var _sky: NeonSky = null
var _margin: MarginContainer = null
var _root: VBoxContainer = null
var _bar: HBoxContainer = null
var _back: Button = null
var _tab_buttons: Array[Button] = []
var _counts: Array[int] = [0, 0, 0, 0]
var _stack: MarginContainer = null
var _pages: Control = null
var _tabs: Array[OnlineTab] = []
var _tab: int = -1
var _gate: int = Gate.NONE
var _gate_center: CenterContainer = null
var _gate_panel: PanelContainer = null
var _gate_title: Label = null
var _gate_text: Label = null
var _name_field: NameField = null
var _gate_message: Label = null
var _gate_row: HBoxContainer = null
var _gate_primary: Button = null
var _gate_secondary: Button = null
var _toast: Toast = null
var _confirm: OnlineConfirm = null
var _menu: PlayerMenu = null
var _unlock: UnlockScreen = null
var _busy_name: bool = false
var _opening: bool = false
var _signing: bool = false
var _links_connected: bool = false


func _init() -> void:
	ShotArgs.parse()
	SettingsStore.ensure_loaded()
	theme = THEME
	name = "OnlineScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	apply_scale()
	LayoutWatch.attach(self, apply_scale)
	Entitlement.hub().changed.connect(_refresh_host_lock)
	_connect_routes()
	_refresh_host_lock()
	ShotHook.attach(self)
	if net == null:
		await start_online()


func _exit_tree() -> void:
	_disconnect_routes()
	if Entitlement.hub().changed.is_connected(_refresh_host_lock):
		Entitlement.hub().changed.disconnect(_refresh_host_lock)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_request()


# ======================================================================================
# Build
# ======================================================================================

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
	_build_bar()
	_stack = MarginContainer.new()
	_stack.name = "Stack"
	_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_child(_stack)
	var pages := VBoxContainer.new()
	pages.name = "Pages"
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stack.add_child(pages)
	_pages = pages
	for t: OnlineTab in [MatchesTab.new(), FriendsTab.new(), JoinTab.new(), HostTab.new()]:
		_tabs.append(t)
		t.visible = false
		pages.add_child(t)
		t.toast.connect(show_toast)
		t.open_match.connect(open_match)
		t.open_lobby.connect(open_lobby)
		t.player_menu.connect(open_player_menu)
		t.confirm.connect(ask)
		t.unlock.connect(open_unlock)
		t.update_needed.connect(func() -> void: show_gate(Gate.UPDATE))
	_tabs[Tab.MATCHES].badge_changed.connect(_set_count.bind(Tab.MATCHES))
	_tabs[Tab.FRIENDS].badge_changed.connect(_set_count.bind(Tab.FRIENDS))
	_build_gate()
	_toast = Toast.new()
	_toast.name = "Toast"
	add_child(_toast)
	_confirm = OnlineConfirm.new()
	add_child(_confirm)
	_menu = PlayerMenu.new()
	_menu.toast.connect(show_toast)
	_menu.done.connect(_on_menu_done)
	add_child(_menu)
	_unlock = UnlockScreen.new()
	add_child(_unlock)
	_unlock.closed.connect(_on_unlock_closed)


func _build_bar() -> void:
	_bar = HBoxContainer.new()
	_bar.name = "Bar"
	_root.add_child(_bar)
	_back = OnlineKit.button(tr("NET_BACK"), 84.0, 13.0)
	_back.name = "Back"
	_back.set_meta("ui_sound", "back")
	_back.pressed.connect(go_back)
	_bar.add_child(_back)
	var group := ButtonGroup.new()
	for i: int in range(TAB_KEYS.size()):
		var b: Button = OnlineKit.button(tr(TAB_KEYS[i]), 96.0, 13.0)
		b.name = "Tab" + TAB_NAMES[i]
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(show_tab.bind(i))
		_bar.add_child(b)
		_tab_buttons.append(b)
	_bar.visible = true


func _build_gate() -> void:
	_gate_center = CenterContainer.new()
	_gate_center.name = "Gate"
	_gate_center.visible = false
	_stack.add_child(_gate_center)
	_gate_panel = PanelContainer.new()
	_gate_panel.name = "GatePanel"
	_gate_panel.add_theme_stylebox_override("panel", OnlineKit.plate(Color(NeonPalette.CYAN, 0.85)))
	_gate_center.add_child(_gate_panel)
	var box := VBoxContainer.new()
	box.name = "Box"
	_gate_panel.add_child(box)
	_gate_title = OnlineKit.label("", 22.0, NeonPalette.CYAN, true)
	_gate_title.name = "Title"
	_gate_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_gate_title)
	_gate_text = OnlineKit.label("", 15.0, NeonPalette.TEXT, true)
	_gate_text.name = "Text"
	_gate_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_gate_text)
	_name_field = NameField.new()
	_name_field.name = "NameField"
	_name_field.placeholder_text = tr("NET_NAME_PLACEHOLDER")
	_name_field.visible = false
	_name_field.committed.connect(_on_name_committed)
	box.add_child(_name_field)
	_gate_message = OnlineKit.label("", 14.0, NeonPalette.WARN, true)
	_gate_message.name = "Message"
	_gate_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_gate_message)
	_gate_row = HBoxContainer.new()
	_gate_row.name = "Buttons"
	_gate_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_gate_row)
	_gate_primary = OnlineKit.button("", 170.0, 16.0)
	_gate_primary.name = "Primary"
	_gate_primary.theme_type_variation = &"FireButton"
	_gate_primary.pressed.connect(_on_gate_primary)
	_gate_row.add_child(_gate_primary)
	_gate_secondary = OnlineKit.button("", 130.0, 14.0)
	_gate_secondary.name = "Secondary"
	_gate_secondary.pressed.connect(go_back)
	_gate_row.add_child(_gate_secondary)


func apply_scale() -> void:
	LayoutGuard.fit(self)
	UiScale.apply_edge_margins(_margin)
	_root.add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))
	_bar.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	OnlineKit.apply(_bar)
	for t: OnlineTab in _tabs:
		t.apply_scale()
	_gate_panel.custom_minimum_size.x = minf(UiScale.dp(420.0), get_viewport_rect().size.x * 0.9)
	_gate_panel.get_child(0).add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))
	_gate_row.add_theme_constant_override("separation", roundi(UiScale.dp(10.0)))
	OnlineKit.apply(_gate_panel)
	_name_field.apply_scale()
	LockBadge.of(_tab_buttons[Tab.HOST]).apply_scale()


# ======================================================================================
# Signing in
# ======================================================================================

## Creates the session and signs in (or restores). The gate shows progress, offline and update states.
func start_online() -> void:
	if _signing:
		return
	_signing = true
	OnlineHub.start_services()
	if net == null:
		net = OnlineHub.ensure_session()
	show_gate(Gate.SIGNING_IN)
	for t: OnlineTab in _tabs:
		t.setup(net)
	var r: NetResult = await net.start()
	_signing = false
	if not is_inside_tree():
		return
	_handle_sign_in(r)


func _handle_sign_in(r: NetResult) -> void:
	if r.ok:
		_on_signed_in()
		return
	if r.is_code(NetError.Code.PROTOCOL_MISMATCH):
		show_gate(Gate.UPDATE)
	elif r.is_code(NetError.Code.UNAVAILABLE):
		show_gate(Gate.SETUP, OnlineText.error(r))
	elif r.is_transient():
		show_gate(Gate.OFFLINE)
	else:
		show_gate(Gate.OFFLINE, OnlineText.error(r))


func _on_signed_in() -> void:
	if OnlineHub.push != null:
		net.account.bind_push(OnlineHub.push)
		OnlineHub.push.ensure_channel(tr("NET_PUSH_CHANNEL"), tr("NET_PUSH_CHANNEL_DESC"))
	net.friends.watch()
	net.matches.watch()
	if needs_name():
		show_gate(Gate.NAME)
		return
	_enter_pages()


## First visit (or after "delete my online data"): the player has not chosen a name yet.
func needs_name() -> bool:
	if not SettingsStore.online_named:
		return true
	return (net.account.profile.get("name", "") as String).strip_edges() == ""


func _enter_pages() -> void:
	show_gate(Gate.NONE)
	signed_in.emit()
	_refresh_host_lock()
	var route: Dictionary = OnlineHub.take_route()
	var start_tab: int = Tab.MATCHES
	if route.has("join"):
		start_tab = Tab.JOIN
	show_tab(start_tab)
	if not route.is_empty():
		_follow_route(route)


# ======================================================================================
# Gate (connecting, offline, update, name, opening)
# ======================================================================================

func get_gate() -> int:
	return _gate


## Shows one gate state in the middle of the screen (or none: the pages).
func show_gate(gate: int, detail: String = "") -> void:
	_gate = gate
	var on: bool = gate != Gate.NONE
	_gate_center.visible = on
	_pages.visible = not on
	_name_field.visible = gate == Gate.NAME
	_gate_message.text = detail if gate != Gate.NAME else ""
	for b: Button in _tab_buttons:
		b.disabled = on
	var primary: String = ""
	var secondary: String = tr("NET_BACK")
	match gate:
		Gate.SIGNING_IN:
			_gate_title.text = tr("NET_GATE_CONNECTING")
			_gate_text.text = tr("NET_GATE_CONNECTING_TEXT")
		Gate.OFFLINE:
			_gate_title.text = tr("NET_GATE_OFFLINE")
			_gate_text.text = tr("NET_GATE_OFFLINE_TEXT")
			primary = tr("NET_RETRY")
		Gate.UPDATE:
			_gate_title.text = tr("NET_GATE_UPDATE")
			_gate_text.text = tr("NET_GATE_UPDATE_TEXT")
		Gate.SETUP:
			_gate_title.text = tr("NET_GATE_SETUP")
			_gate_text.text = tr("NET_GATE_SETUP_TEXT")
			primary = tr("NET_RETRY")
		Gate.NAME:
			_gate_title.text = tr("NET_GATE_NAME")
			_gate_text.text = tr("NET_GATE_NAME_TEXT")
			primary = tr("NET_GATE_NAME_OK")
			_name_field.set_name_text("")
		Gate.OPENING:
			_gate_title.text = tr("NET_GATE_OPENING")
			_gate_text.text = tr("NET_GATE_OPENING_TEXT")
			secondary = ""
	_gate_primary.text = primary
	_gate_primary.visible = primary != ""
	_gate_secondary.text = secondary
	_gate_secondary.visible = secondary != ""
	_gate_primary.disabled = false
	if is_inside_tree():
		apply_scale()
	gate_changed.emit(gate)


func _on_gate_primary() -> void:
	match _gate:
		Gate.OFFLINE, Gate.SETUP:
			if net != null and net.auth.is_signed_in() and not net.account.profile.is_empty():
				_on_signed_in()
			else:
				await start_online()
		Gate.NAME:
			await submit_name(_name_field.text)


func get_gate_text() -> String:
	return _gate_text.text


func get_gate_message() -> String:
	return _gate_message.text


## The typed name goes to the account. NAME_REJECTED (empty or blocked) stays on the gate with a message.
func submit_name(raw: String) -> bool:
	if _busy_name or net == null:
		return false
	_busy_name = true
	_gate_primary.disabled = true
	var r: NetResult = await net.account.set_name(raw)
	_busy_name = false
	if not is_inside_tree():
		return false
	_gate_primary.disabled = false
	if not r.ok:
		if check_update(r):
			return false
		_gate_message.text = OnlineText.error(r)
		return false
	SettingsStore.online_named = true
	SettingsStore.save()
	_enter_pages()
	return true


func _on_name_committed(player_name: String, blocked: bool) -> void:
	if blocked:
		_gate_message.text = tr("NET_ERR_NAME_BLOCKED")
	elif player_name == "" and _gate == Gate.NAME:
		_gate_message.text = ""


## A failed call means "update the game": shows that gate and returns true.
func check_update(r: NetResult) -> bool:
	if r.is_code(NetError.Code.PROTOCOL_MISMATCH):
		show_gate(Gate.UPDATE)
		return true
	return false


# ======================================================================================
# Tabs
# ======================================================================================

func get_tab_page(tab: int) -> OnlineTab:
	return _tabs[tab]


func get_tab_button(tab: int) -> Button:
	return _tab_buttons[tab]


func current_tab() -> int:
	return _tab


func show_tab(tab: int) -> void:
	if tab == Tab.HOST and not Entitlement.is_full():
		_tab_buttons[Tab.HOST].set_pressed_no_signal(false)
		if _tab >= 0:
			_tab_buttons[_tab].set_pressed_no_signal(true)
		open_unlock("host")
		return
	if _gate != Gate.NONE and _gate != Gate.OPENING:
		return
	if _tab >= 0 and _tab != tab:
		_tabs[_tab].visible = false
		_tabs[_tab].deactivate()
	_tab = tab
	for i: int in range(_tabs.size()):
		_tabs[i].visible = i == tab
		_tab_buttons[i].set_pressed_no_signal(i == tab)
	_tabs[tab].activate()


## The HOST tab shows a padlock while the full game is not owned (the lock word is in its tooltip).
func _refresh_host_lock() -> void:
	var locked: bool = not Entitlement.is_full()
	LockBadge.mark(_tab_buttons[Tab.HOST], locked, tr("NET_HOST_LOCKED"), tr("NET_TAB_HOST"))
	_update_tab_text(Tab.HOST)


func _set_count(count: int, tab: int) -> void:
	_counts[tab] = count
	_update_tab_text(tab)


func _update_tab_text(tab: int) -> void:
	var text: String = tr(TAB_KEYS[tab])
	if _counts[tab] > 0:
		text = "%s (%d)" % [text, _counts[tab]]
	_tab_buttons[tab].text = text
	_tab_buttons[tab].accessibility_name = text


func tab_text(tab: int) -> String:
	return _tab_buttons[tab].text


# ======================================================================================
# What the pages ask for
# ======================================================================================

func show_toast(text: String) -> void:
	_toast.show_message(text)


func get_toast() -> Toast:
	return _toast


## A yes/no question; `on_yes` runs after YES.
func ask(text: String, on_yes: Callable) -> void:
	_confirm.ask(text, on_yes, tr("NET_CONFIRM_YES"))


func get_confirm() -> OnlineConfirm:
	return _confirm


func open_player_menu(info: Dictionary) -> void:
	_menu.open_for(net, info)


func get_player_menu() -> PlayerMenu:
	return _menu


func _on_menu_done(kind: String, _uid: String) -> void:
	if kind == "blocked" or kind == "requested":
		for t: OnlineTab in _tabs:
			if t is FriendsTab and t.is_active():
				t.activate()


func open_unlock(kind: String) -> void:
	_unlock.open_for(kind)


func get_unlock_screen() -> UnlockScreen:
	return _unlock


## After unlocking, the HOST tab opens by itself.
func _on_unlock_closed() -> void:
	_refresh_host_lock()
	if _unlock.get_kind() == "host" and Entitlement.is_full() and _gate == Gate.NONE:
		show_tab(Tab.HOST)


## Opens a running match (the battle scene) or, when it is still a lobby, its lobby.
func open_match(match_id: String) -> void:
	if _opening or net == null:
		return
	_opening = true
	show_gate(Gate.OPENING)
	var r: NetResult = await net.open_match(match_id)
	_opening = false
	if not is_inside_tree():
		return
	if r.ok:
		OnlineHub.play(get_tree(), r.value as OnlineMatch)
		return
	if r.is_code(NetError.Code.NOT_STARTED):
		open_lobby(match_id)
		return
	if check_update(r):
		return
	show_gate(Gate.NONE)
	show_tab(maxi(_tab, Tab.MATCHES))
	show_toast(OnlineText.error(r))


func open_lobby(match_id: String) -> void:
	OnlineHub.ask_push_permission_once()
	OnlineHub.go_lobby(get_tree(), match_id)


# ======================================================================================
# Deep links and notification taps
# ======================================================================================

func _connect_routes() -> void:
	OnlineHub.start_services()
	if OnlineHub.links != null and not OnlineHub.links.join_requested.is_connected(_on_join_link):
		OnlineHub.links.join_requested.connect(_on_join_link)
	if OnlineHub.push != null and not OnlineHub.push.notification_opened.is_connected(_on_push_tap):
		OnlineHub.push.notification_opened.connect(_on_push_tap)
	_links_connected = true


func _disconnect_routes() -> void:
	if not _links_connected:
		return
	if OnlineHub.links != null and OnlineHub.links.join_requested.is_connected(_on_join_link):
		OnlineHub.links.join_requested.disconnect(_on_join_link)
	if OnlineHub.push != null and OnlineHub.push.notification_opened.is_connected(_on_push_tap):
		OnlineHub.push.notification_opened.disconnect(_on_push_tap)
	_links_connected = false


func _on_join_link(code: String) -> void:
	_route_now({"join": code})


func _on_push_tap(payload: Dictionary) -> void:
	var id: String = PushService.match_id_of(payload)
	if id != "":
		_route_now({"match": id})


## A link or tap arrived while the screen is up: act now if the pages are showing, else keep it for after sign-in.
func _route_now(route: Dictionary) -> void:
	if _gate == Gate.NONE and net != null:
		_follow_route(route)
		return
	if route.has("join"):
		OnlineHub.pending_join_code = route["join"] as String
	elif route.has("match"):
		OnlineHub.pending_match_id = route["match"] as String


func _follow_route(route: Dictionary) -> void:
	if route.has("match"):
		open_match(route["match"] as String)
	elif route.has("join"):
		show_tab(Tab.JOIN)
		(_tabs[Tab.JOIN] as JoinTab).set_code(route["join"] as String)


# ======================================================================================
# Leaving
# ======================================================================================

func go_back() -> void:
	if net != null:
		net.close()  # streams off: nothing keeps the radio busy on the title
	OnlineHub.go_title(get_tree())


func _on_back_request() -> void:
	if _unlock != null and _unlock.is_open():
		_unlock.close()
	elif _menu != null and _menu.is_open():
		_menu.close()
	elif _confirm != null and _confirm.is_open():
		_confirm.close()
	else:
		go_back()
