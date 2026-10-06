class_name OnlineSettings
extends OverlayPanel
## "Online account" in the Settings screen (ARCHITECTURE section 48): the online name, Sign in with Google (links the
## anonymous account so it survives a new phone), the notifications permission and "Delete my online data" with a double
## confirmation, after which the phone is signed out locally and starts over.
##
## It works without the Online screen having been opened: it makes the session and signs in when it needs to.

signal changed
signal closed_panel

var net: NetSession = null
var _status: Label = null
var _name_field: NameField = null
var _name_save: Button = null
var _google: Button = null
var _google_restore: Button = null
var _notify: Button = null
var _delete: Button = null
var _hint: Label = null
var _close: Button = null
var _confirm: OnlineConfirm = null
var _busy: bool = false
var _scroll: TouchScroll = null
var _grid: GridContainer = null


func _init() -> void:
	super._init()
	name = "OnlineSettings"
	_dim.color = Color(NeonPalette.BG_DEEP, 0.94)
	add_title(tr("NET_SET_TITLE"), NeonPalette.CYAN, 22.0).name = "Title"
	_status = add_label("", 13.0, NeonPalette.TEXT_DIM)
	_status.name = "Status"
	_scroll = TouchScroll.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 1
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)
	_target = _grid
	_build_rows()
	_target = _box
	_hint = add_label("", 13.0, NeonPalette.WARN)
	_hint.name = "Hint"
	_hint.visible = false
	_close = add_button(tr("NET_CLOSE"), 200.0)
	_close.name = "Close"
	_close.set_meta("ui_sound", "back")
	_close.pressed.connect(close)
	_confirm = OnlineConfirm.new()
	add_child(_confirm)


func _build_rows() -> void:
	# Online name: caption, the field and SAVE.
	var name_row := HBoxContainer.new()
	name_row.name = "NameRow"
	name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_child(name_row)
	var cap := Label.new()
	cap.text = tr("NET_SET_NAME")
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.custom_minimum_size.x = UiScale.dp(120.0)
	_font_dp[cap] = 15.0
	_labels.append(cap)
	name_row.add_child(cap)
	_name_field = NameField.new()
	_name_field.name = "NameField"
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_field.placeholder_text = tr("NET_NAME_PLACEHOLDER")
	_name_field.committed.connect(_on_name_committed)
	name_row.add_child(_name_field)
	_target = name_row
	_name_save = add_button(tr("NET_SET_SAVE"), 96.0)
	_name_save.name = "SaveName"
	_name_save.size_flags_horizontal = Control.SIZE_SHRINK_END
	_name_save.pressed.connect(save_name)
	_target = _grid
	_google = add_cycle(tr("NET_SET_GOOGLE"), tr("NET_SET_GOOGLE_SIGN_IN"), sign_in_google)
	_google.name = "Google"
	_btn_dp[_google] = [220.0, 13.0]
	_google_restore = add_cycle(tr("NET_SET_GOOGLE_RESTORE_CAPTION"), tr("NET_SET_GOOGLE_RESTORE"), restore_with_google)
	_google_restore.name = "GoogleRestore"
	_google_restore.get_parent().visible = false
	_btn_dp[_google_restore] = [220.0, 13.0]
	_notify = add_cycle(tr("NET_SET_NOTIFY"), tr("NET_SET_NOTIFY_ALLOW"), request_notifications)
	_notify.name = "Notifications"
	_btn_dp[_notify] = [220.0, 13.0]
	_delete = add_cycle(tr("NET_SET_DELETE"), tr("NET_SET_DELETE_BUTTON"), ask_delete)
	_delete.name = "Delete"
	_btn_dp[_delete] = [220.0, 13.0]


func apply_scale() -> void:
	super.apply_scale()
	if _scroll == null:
		return
	_grid.add_theme_constant_override("v_separation", roundi(UiScale.dp(8.0)))
	_name_field.apply_scale()
	_fit_scroll()


## The rows scroll in whatever height is left under the title and above CLOSE (a landscape phone is ~330 dp high).
func _fit_scroll() -> void:
	_scroll.custom_minimum_size = Vector2(minf(UiScale.dp(460.0), get_viewport_rect().size.x * 0.85), 0.0)
	var others: float = _panel.get_combined_minimum_size().y
	var avail: float = get_viewport_rect().size.y * 0.97 - others
	var content: float = _grid.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = clampf(content, minf(UiScale.dp(96.0), content), maxf(avail, UiScale.dp(96.0)))


func open_panel() -> void:
	_hint.visible = false
	open()
	apply_scale()
	_refresh()
	await _prepare()
	if is_inside_tree():
		_refresh()
		_sync_name_field()
		apply_scale()
		await get_tree().process_frame
		if is_inside_tree():
			_fit_scroll()


## Android Back: a question that is open is answered "no" first; the panel closes with the next Back.
func close_topmost() -> void:
	if _confirm != null and _confirm.is_open():
		_confirm.close()
	else:
		close()


func close() -> void:
	if _confirm != null and _confirm.is_open():
		_confirm.close()
	if is_open():
		super.close()
		closed_panel.emit()


## Makes the session if there is none and signs in, so the name and the account actions work from the title too.
func _prepare() -> void:
	OnlineHub.start_services()
	net = OnlineHub.ensure_session()
	if not net.auth.is_signed_in() or net.account.profile.is_empty():
		_status.text = tr("NET_GATE_CONNECTING_TEXT")
		var r: NetResult = await net.start()
		if not r.ok:
			_status.text = OnlineText.error(r)
			return


## Puts the account's name in the field (once when the panel opens, and after the account changed).
func _sync_name_field() -> void:
	var shown: String = net.account.profile.get("name", "") as String if net != null else ""
	_name_field.set_name_text(shown)


func _refresh() -> void:
	var signed: bool = net != null and net.auth.is_signed_in() and not net.account.profile.is_empty()
	if signed:
		_status.text = tr("NET_SIGNED_IN_AS") % net.account.my_name()
	elif net == null or not net.auth.is_signed_in():
		_status.text = tr("NET_SET_NOT_SIGNED_IN")
	_name_save.disabled = not signed or _busy
	_refresh_google(signed)
	_refresh_notifications()
	_delete.disabled = not signed or _busy


## Google sign-in needs the plugin on the phone AND a web client id in the build; otherwise it says "unavailable".
func google_ready() -> bool:
	return OnlineHub.google != null and OnlineHub.google.available and net != null and net.config.web_client_id.strip_edges() != ""


func _refresh_google(signed: bool) -> void:
	var linked: bool = signed and not net.auth.anonymous
	if linked:
		_google.text = tr("NET_SET_GOOGLE_LINKED") % (net.auth.email if net.auth.email != "" else "Google")
		_google.disabled = true
	elif not google_ready():
		_google.text = tr("NET_SET_UNAVAILABLE")
		_google.disabled = true
	else:
		_google.text = tr("NET_SET_GOOGLE_SIGN_IN")
		_google.disabled = not signed or _busy


func _refresh_notifications() -> void:
	var push: PushService = OnlineHub.push
	if push == null or not push.available:
		_notify.text = tr("NET_SET_UNAVAILABLE")
		_notify.disabled = true
	elif push.has_permission():
		_notify.text = tr("NET_SET_NOTIFY_ON")
		_notify.disabled = true
	else:
		_notify.text = tr("NET_SET_NOTIFY_ALLOW")
		_notify.disabled = false


func _say(text: String, warn: bool = true) -> void:
	_hint.text = text
	_hint.visible = text != ""
	_hint.add_theme_color_override("font_color", NeonPalette.WARN if warn else NeonPalette.GOOD)
	apply_scale()


# --- the name -----------------------------------------------------------------------------------------------------

func _on_name_committed(_player_name: String, blocked: bool) -> void:
	if blocked:
		_say(tr("NET_ERR_NAME_BLOCKED"))


func save_name() -> void:
	if _busy or net == null:
		return
	_busy = true
	_refresh()
	var r: NetResult = await net.account.set_name(_name_field.text)
	_busy = false
	if not is_inside_tree():
		return
	if r.ok:
		SettingsStore.online_named = true
		SettingsStore.save()
		_say(tr("NET_SET_NAME_SAVED"), false)
		changed.emit()
	else:
		_say(OnlineText.error(r))
	_refresh()


# --- Google -------------------------------------------------------------------------------------------------------

func sign_in_google() -> void:
	if _busy or net == null or not google_ready():
		return
	_busy = true
	_refresh()
	var r: NetResult = await net.account.link_google(OnlineHub.google)
	_busy = false
	if not is_inside_tree():
		return
	_google_restore.get_parent().visible = false
	if r.ok:
		_say(tr("NET_SET_GOOGLE_DONE"), false)
		changed.emit()
	elif r.is_code(NetError.Code.CANCELLED):
		_say("")  # the player closed the Google sheet: nothing to report
	elif r.reason == "google_already_linked":
		_say(tr("NET_SET_GOOGLE_TAKEN"))
		_google_restore.get_parent().visible = true
	else:
		_say(OnlineText.error(r))
	_refresh()
	apply_scale()


## "I already have an account with this Google identity" (a new phone): switch to that account.
func restore_with_google() -> void:
	if _busy or net == null or not google_ready():
		return
	_busy = true
	var r: NetResult = await net.account.restore_with_google(OnlineHub.google)
	if r.ok:
		r = await net.account.ensure_profile()
	_busy = false
	if not is_inside_tree():
		return
	if r.ok:
		_google_restore.get_parent().visible = false
		SettingsStore.online_named = (net.account.profile.get("name", "") as String) != ""
		SettingsStore.save()
		_sync_name_field()
		_say(tr("NET_SET_GOOGLE_RESTORED"), false)
		changed.emit()
	elif not r.is_code(NetError.Code.CANCELLED):
		_say(OnlineText.error(r))
	_refresh()


# --- notifications ------------------------------------------------------------------------------------------------

func request_notifications() -> void:
	var push: PushService = OnlineHub.push
	if push == null or not push.available or push.has_permission():
		return
	push.permission_result.connect(_on_permission, CONNECT_ONE_SHOT)
	push.request_permission()


func _on_permission(granted: bool) -> void:
	_say("" if granted else tr("NET_SET_NOTIFY_DENIED"), not granted)
	_refresh()


# --- delete my online data ----------------------------------------------------------------------------------------

## Two questions in a row; only the second YES deletes.
func ask_delete() -> void:
	if _busy or net == null:
		return
	_confirm.ask(tr("NET_SET_DELETE_Q1"), _ask_delete_again, tr("NET_SET_DELETE_CONTINUE"))


func _ask_delete_again() -> void:
	_confirm.ask(tr("NET_SET_DELETE_Q2"), delete_now, tr("NET_SET_DELETE_YES"))


## Deletes everything online, signs out on this phone and forgets the local online flags.
func delete_now() -> void:
	if _busy or net == null:
		return
	_busy = true
	_refresh()
	var r: NetResult = await net.account.delete_my_data()
	_busy = false
	if not is_inside_tree():
		return
	if not r.ok:
		_say(OnlineText.error(r))
		_refresh()
		return
	SettingsStore.online_named = false
	SettingsStore.save()
	OnlineHub.reset()  # the session is gone: the next ONLINE visit signs in to a brand new account
	net = null
	_refresh()
	_status.text = tr("NET_SET_DELETED")
	_name_field.set_name_text("")
	_say(tr("NET_SET_DELETED_NOTE"), false)
	changed.emit()


# --- test accessors -----------------------------------------------------------------------------------------------

func get_status_text() -> String:
	return _status.text


func get_hint_text() -> String:
	return _hint.text if _hint.visible else ""


func get_name_field() -> NameField:
	return _name_field


func get_save_button() -> Button:
	return _name_save


func get_google_button() -> Button:
	return _google


func get_google_restore_button() -> Button:
	return _google_restore


func get_notify_button() -> Button:
	return _notify


func get_delete_button() -> Button:
	return _delete


func get_confirm() -> OnlineConfirm:
	return _confirm


func is_busy() -> bool:
	return _busy
