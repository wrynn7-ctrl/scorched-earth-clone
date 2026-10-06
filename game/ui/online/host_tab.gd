class_name HostTab
extends OnlineTab
## HOST (ARCHITECTURE sections 45 and 48): pick Classic or, once the secret was found, Love Edition, and CREATE LOBBY.
## Everything else (seats, CPUs, teams, rules, timers) is edited in the lobby. Only full owners can host; the Online
## screen shows the Unlock screen instead of this page for free players, and a backend `full_required` shows a line
## here (the purchase is not verified for online play yet).

const DEFAULT_ROUNDS: int = 3

var _box: VBoxContainer = null
var _classic: Button = null
var _love_button: Button = null
var _create: Button = null
var _message: Label = null
var _love: bool = false
var _busy: bool = false
var _mode_row: HBoxContainer = null


func _init() -> void:
	super._init()
	name = "HostTab"
	var scroll := TouchScroll.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_box = VBoxContainer.new()
	_box.name = "Form"
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)
	var caption: Label = OnlineKit.label(tr("NET_HOST_CAPTION"), 14.0, NeonPalette.CYAN, true)
	caption.name = "Caption"
	_box.add_child(caption)
	var about: Label = OnlineKit.label(tr("NET_HOST_ABOUT"), 13.0, NeonPalette.TEXT_DIM, true, true)
	about.name = "About"
	_box.add_child(about)
	_mode_row = HBoxContainer.new()
	_mode_row.name = "Modes"
	_box.add_child(_mode_row)
	var group := ButtonGroup.new()
	_classic = OnlineKit.button(tr("NET_MODE_CLASSIC"), 150.0, 14.0)
	_classic.name = "Classic"
	_classic.toggle_mode = true
	_classic.button_group = group
	_classic.button_pressed = true
	_classic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_classic.pressed.connect(set_love.bind(false))
	_mode_row.add_child(_classic)
	_love_button = OnlineKit.button(tr("NET_MODE_LOVE"), 150.0, 14.0)
	_love_button.name = "Love"
	_love_button.toggle_mode = true
	_love_button.button_group = group
	_love_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_love_button.icon = HeartShape.icon_texture(Color(1.0, 0.42, 0.68))
	_love_button.expand_icon = true
	_love_button.pressed.connect(set_love.bind(true))
	_mode_row.add_child(_love_button)
	_create = OnlineKit.button(tr("NET_CREATE_LOBBY"), 240.0, 18.0)
	_create.name = "Create"
	_create.theme_type_variation = &"FireButton"
	_create.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_create.pressed.connect(create)
	_box.add_child(_create)
	_message = OnlineKit.label("", 14.0, NeonPalette.WARN, true)
	_message.name = "Message"
	_box.add_child(_message)


func activate() -> void:
	super.activate()
	# Love Edition is only offered once the secret was found (ARCHITECTURE section 45).
	_love_button.visible = SettingsStore.love_found
	if not SettingsStore.love_found:
		set_love(false)


func apply_scale() -> void:
	super.apply_scale()
	_box.add_theme_constant_override("separation", roundi(UiScale.dp(10.0)))
	_mode_row.add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))
	_love_button.add_theme_constant_override("icon_max_width", roundi(UiScale.dp(20.0)))
	_create.add_theme_font_size_override("font_size", UiScale.hud_font(18.0))
	_create.custom_minimum_size.y = UiScale.dp(56.0)


func set_love(on: bool) -> void:
	_love = on and SettingsStore.love_found
	_classic.set_pressed_no_signal(not _love)
	_love_button.set_pressed_no_signal(_love)


func is_love() -> bool:
	return _love


## The lobby this page would create: settings, seats and timers for `NetLobby.create`.
func lobby_request() -> Dictionary:
	var settings: Dictionary
	if _love:
		settings = NetLobby.settings({"rounds": 1, "mode": SimConstants.MODE_LOVE, "theme": ThemeDefs.LOVE_THEME,
				"wind_max": 0})
	else:
		settings = NetLobby.settings({"rounds": DEFAULT_ROUNDS, "theme": ThemeDefs.DEFAULT_ID})
	var seats: Array = [NetLobby.seat_human(true), NetLobby.seat_human()]
	return {"settings": settings, "seats": seats, "timers": NetLobby.timers(60, 72, "auto")}


func create() -> void:
	if _busy:
		return
	_busy = true
	_create.disabled = true
	_message.text = ""
	var req: Dictionary = lobby_request()
	var r: NetResult = await net.lobby.create(req["settings"] as Dictionary, req["seats"] as Array, req["timers"] as Dictionary)
	_busy = false
	_create.disabled = false
	if r.ok:
		var id: String = r.dict().get("matchId", "")
		OnlineHub.open_lobby_id = id
		open_lobby.emit(id)
		return
	if check_update(r):
		return
	if r.reason == "full_required" and not Entitlement.is_full():
		unlock.emit("host")
		return
	_message.text = OnlineText.error(r)


func get_create_button() -> Button:
	return _create


func get_love_button() -> Button:
	return _love_button


func get_classic_button() -> Button:
	return _classic


func get_message() -> String:
	return _message.text
