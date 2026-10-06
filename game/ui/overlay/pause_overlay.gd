class_name PauseOverlay
extends OverlayPanel
## Pause menu: RESUME / SETTINGS / RESTART MATCH / QUIT TO TITLE. Restart asks for a second
## tap (it discards the autosave); the settings live on their own screen.

signal resume_pressed
signal restart_pressed
signal quit_pressed
signal settings_pressed
## Online matches only (see set_online): give the match up, and (host) end it for everyone.
signal leave_pressed
signal end_pressed
signal players_pressed

const CONFIRM_SECONDS: float = 3.0

var _round_label: Label = null
var _restart: Button = null
var _quit: Button = null
var _players: Button = null
var _leave: Button = null
var _end: Button = null
var _online_row: HBoxContainer = null
var _confirm_timer: SceneTreeTimer = null


func _init() -> void:
	super._init()
	name = "PauseOverlay"
	add_title(tr("PAUSE_TITLE"), NeonPalette.CYAN, 24.0)
	_round_label = add_label("", 13.0)
	begin_row()
	var resume: Button = add_button(tr("PAUSE_RESUME"), 150.0)
	resume.name = "Resume"
	resume.pressed.connect(func() -> void: resume_pressed.emit())
	var settings: Button = add_button(tr("PAUSE_SETTINGS"), 150.0)
	settings.name = "Settings"
	settings.pressed.connect(func() -> void: settings_pressed.emit())
	end_container()
	begin_row()
	_restart = add_button(tr("PAUSE_RESTART"), 150.0)
	_restart.name = "Restart"
	_restart.pressed.connect(_on_restart)
	_players = add_button(tr("NET_PAUSE_PLAYERS"), 150.0)
	_players.name = "Players"
	_players.visible = false
	_players.pressed.connect(func() -> void: players_pressed.emit())
	_quit = add_button(tr("PAUSE_QUIT"), 150.0)
	_quit.name = "Quit"
	_quit.pressed.connect(func() -> void: quit_pressed.emit())
	end_container()
	_online_row = begin_row()
	_online_row.name = "OnlineRow"
	_leave = add_button(tr("NET_PAUSE_LEAVE"), 150.0)
	_leave.name = "Leave"
	_leave.pressed.connect(func() -> void: leave_pressed.emit())
	_end = add_button(tr("NET_PAUSE_END"), 150.0)
	_end.name = "End"
	_end.pressed.connect(func() -> void: end_pressed.emit())
	end_container()
	_online_row.visible = false


## An online match: no restart, QUIT becomes "BACK TO ONLINE" (the match stays in Your matches), LEAVE MATCH gives the
## seats to the computer and, for the host, END MATCH ends it for everyone.
func set_online(on: bool, host: bool = false) -> void:
	_restart.visible = not on
	_players.visible = on
	_quit.text = tr("NET_BACK_TO_ONLINE") if on else tr("PAUSE_QUIT")
	_online_row.visible = on
	_end.visible = on and host


func get_players_button() -> Button:
	return _players


func get_quit_button() -> Button:
	return _quit


func get_leave_button() -> Button:
	return _leave


func get_end_button() -> Button:
	return _end


func open_for(round_number: int, rounds: int) -> void:
	_round_label.text = tr("OVERLAY_ROUND_OF") % [round_number, rounds]
	_reset_restart()
	open()


func close() -> void:
	_reset_restart()
	super.close()


func is_restart_armed() -> bool:
	return _restart.text == tr("PAUSE_RESTART_CONFIRM")


## First tap arms the button ("TAP AGAIN TO RESTART"), the second one restarts.
func _on_restart() -> void:
	if is_restart_armed():
		_reset_restart()
		restart_pressed.emit()
		return
	_restart.text = tr("PAUSE_RESTART_CONFIRM")
	_confirm_timer = get_tree().create_timer(CONFIRM_SECONDS, true, false, true)
	_confirm_timer.timeout.connect(_reset_restart)


func _reset_restart() -> void:
	if _restart != null:
		_restart.text = tr("PAUSE_RESTART")
