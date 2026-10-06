class_name PlayerMenu
extends OverlayPanel
## The menu behind a tap on a player's name (ARCHITECTURE section 48), in the lobby, in a match and in the friends
## list: ADD FRIEND, BLOCK, REPORT NAME and, in a match, MUTE MESSAGES. Blocking and reporting ask again before they
## send anything, and a report first asks why (a short reason list). The menu makes the calls itself and tells the
## screen what happened through `done`, so every screen shares one implementation.
##
## `info` = {uid, name, friend (bool), in_match (bool)}; `friend_code` (optional) lets ADD FRIEND send a request. A
## player met in a lobby or a match is known by uid only, and the backend takes friend requests by code, so then the
## button explains how to add them (ask for their code) instead of failing silently.

## What happened: "blocked", "reported", "requested", "muted" or "unmuted". The screen refreshes its lists.
signal done(kind: String, uid: String)
signal toast(text: String)

const REASONS: Array = [
	["offensive_name", "NET_REPORT_OFFENSIVE"],
	["impersonation", "NET_REPORT_IMPERSONATION"],
	["other", "NET_REPORT_OTHER"],
]

enum Step { MENU, REASON, CONFIRM_BLOCK, CONFIRM_REPORT }

var net: NetSession = null
var info: Dictionary = {}
var _step: int = Step.MENU
var _reason: String = ""
var _busy: bool = false
var _title: Label = null
var _hint: Label = null
var _menu: GridContainer = null
var _add: Button = null
var _block: Button = null
var _report: Button = null
var _mute: Button = null
var _close: Button = null
var _reasons: VBoxContainer = null
var _reason_buttons: Array[Button] = []
var _reason_back: Button = null
var _confirm: HBoxContainer = null
var _confirm_yes: Button = null
var _confirm_no: Button = null


func _init() -> void:
	super._init()
	name = "PlayerMenu"
	_title = add_title("", NeonPalette.CYAN, 22.0)
	_title.name = "Title"
	_hint = add_label("", 13.0, NeonPalette.TEXT_DIM)
	_hint.name = "Hint"
	_hint.visible = false
	_menu = begin_grid()
	_menu.name = "Menu"
	_add = add_button(tr("NET_PM_ADD_FRIEND"), 170.0)
	_add.name = "AddFriend"
	_add.pressed.connect(_on_add)
	_block = add_button(tr("NET_PM_BLOCK"), 170.0)
	_block.name = "Block"
	_block.pressed.connect(_go.bind(Step.CONFIRM_BLOCK))
	_report = add_button(tr("NET_PM_REPORT"), 170.0)
	_report.name = "Report"
	_report.pressed.connect(_go.bind(Step.REASON))
	_mute = add_button(tr("NET_PM_MUTE"), 170.0)
	_mute.name = "Mute"
	_mute.pressed.connect(_on_mute)
	_close = add_button(tr("NET_CLOSE"), 170.0)
	_close.name = "Close"
	_close.set_meta("ui_sound", "back")
	_close.pressed.connect(close)
	end_container()
	_reasons = VBoxContainer.new()
	_reasons.name = "Reasons"
	_box.add_child(_reasons)
	_target = _reasons
	for spec: Array in REASONS:
		var b: Button = add_button(tr(spec[1] as String), 260.0)
		b.name = "Reason_" + (spec[0] as String)
		b.pressed.connect(_pick_reason.bind(spec[0] as String))
		_reason_buttons.append(b)
	_reason_back = add_button(tr("NET_BACK"), 260.0)
	_reason_back.name = "ReasonBack"
	_reason_back.set_meta("ui_sound", "back")
	_reason_back.pressed.connect(_go.bind(Step.MENU))
	end_container()
	_confirm = begin_row()
	_confirm.name = "Confirm"
	_confirm_yes = add_button(tr("CONFIRM_OK"), 150.0)
	_confirm_yes.name = "Yes"
	_confirm_yes.pressed.connect(_on_confirm_yes)
	_confirm_no = add_button(tr("CONFIRM_NO"), 130.0)
	_confirm_no.name = "No"
	_confirm_no.set_meta("ui_sound", "back")
	_confirm_no.pressed.connect(_go.bind(Step.MENU))
	end_container()


## Opens the menu for the player described by `player_info` (see the class comment).
func open_for(session: NetSession, player_info: Dictionary) -> void:
	net = session
	info = player_info
	_busy = false
	_go(Step.MENU)
	open()
	if is_inside_tree():
		apply_scale()


func player_uid() -> String:
	return info.get("uid", "") as String


func player_name() -> String:
	var n: String = info.get("name", "") as String
	return n if n != "" else tr("NET_UNKNOWN_HOST")


func is_self() -> bool:
	return net != null and player_uid() != "" and player_uid() == net.uid()


func get_step() -> int:
	return _step


## Shows one step (menu, reason list, a confirmation) and hides the others.
func _go(step: int) -> void:
	_step = step
	var menu: bool = step == Step.MENU
	_menu.visible = menu
	_reasons.visible = step == Step.REASON
	_confirm.visible = step == Step.CONFIRM_BLOCK or step == Step.CONFIRM_REPORT
	_hint.visible = false
	var who: String = player_name()
	match step:
		Step.MENU:
			_title.text = who
			_refresh_menu()
		Step.REASON:
			_title.text = tr("NET_PM_REPORT_WHY") % who
		Step.CONFIRM_BLOCK:
			_title.text = tr("NET_PM_BLOCK_Q") % who
			_hint.text = tr("NET_PM_BLOCK_NOTE")
			_hint.visible = true
			_confirm_yes.text = tr("NET_PM_BLOCK")
		Step.CONFIRM_REPORT:
			_title.text = tr("NET_PM_REPORT_Q") % who
			_hint.text = tr("NET_PM_REPORT_NOTE")
			_hint.visible = true
			_confirm_yes.text = tr("NET_PM_REPORT_SEND")
	if is_inside_tree():
		apply_scale()


func _refresh_menu() -> void:
	var me: bool = is_self()
	var friend: bool = info.get("friend", false) == true
	var in_match: bool = info.get("in_match", false) == true
	var uid: String = player_uid()
	_add.visible = not friend and not me
	_block.visible = not me
	_report.visible = not me
	_mute.visible = in_match and not me
	_mute.text = tr("NET_PM_UNMUTE") if OnlineHub.is_muted(uid) else tr("NET_PM_MUTE")
	_hint.text = ""
	_hint.visible = false


func _on_add() -> void:
	var code: String = info.get("friend_code", "") as String
	if code == "":
		# Known by uid only: the backend takes requests by friend code.
		_hint.text = tr("NET_PM_ADD_HINT")
		_hint.visible = true
		return
	if _busy or net == null:
		return
	_busy = true
	var r: NetResult = await net.friends.send_request(code)
	_busy = false
	if r.ok:
		toast.emit(tr("NET_REQUEST_SENT") % (r.dict().get("name", "") as String))
		done.emit("requested", player_uid())
		close()
	else:
		_hint.text = OnlineText.error(r)
		_hint.visible = true


func _on_mute() -> void:
	var uid: String = player_uid()
	var now_muted: bool = not OnlineHub.is_muted(uid)
	OnlineHub.set_muted(uid, now_muted)
	toast.emit(tr("NET_PM_MUTED") % player_name() if now_muted else tr("NET_PM_UNMUTED") % player_name())
	done.emit("muted" if now_muted else "unmuted", uid)
	close()


func _pick_reason(reason: String) -> void:
	_reason = reason
	_go(Step.CONFIRM_REPORT)


func _on_confirm_yes() -> void:
	if _busy or net == null:
		return
	if _step == Step.CONFIRM_BLOCK:
		await _do_block()
	elif _step == Step.CONFIRM_REPORT:
		await _do_report()


func _do_block() -> void:
	_busy = true
	var r: NetResult = await net.friends.block(player_uid())
	_busy = false
	if r.ok:
		OnlineHub.set_muted(player_uid(), true)  # a blocked player's messages never show
		toast.emit(tr("NET_PM_BLOCKED") % player_name())
		done.emit("blocked", player_uid())
		close()
	else:
		_go(Step.MENU)
		_hint.text = OnlineText.error(r)
		_hint.visible = true


func _do_report() -> void:
	_busy = true
	var r: NetResult = await net.friends.report(player_uid(), _reason)
	_busy = false
	if r.ok:
		toast.emit(tr("NET_PM_REPORTED"))
		done.emit("reported", player_uid())
		close()
	else:
		_go(Step.MENU)
		_hint.text = OnlineText.error(r)
		_hint.visible = true


# --- test accessors ---------------------------------------------------------------------------------------------

func get_add_button() -> Button:
	return _add


func get_block_button() -> Button:
	return _block


func get_report_button() -> Button:
	return _report


func get_mute_button() -> Button:
	return _mute


func get_reason_button(reason: String) -> Button:
	return _reasons.get_node_or_null("Reason_" + reason) as Button


func get_confirm_yes() -> Button:
	return _confirm_yes


func get_hint_text() -> String:
	return _hint.text if _hint.visible else ""


func get_title_text() -> String:
	return _title.text


## A tap on the dimmed area outside the panel closes the menu.
func _gui_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if not _panel.get_global_rect().has_point((event as InputEventMouseButton).global_position):
			close()
