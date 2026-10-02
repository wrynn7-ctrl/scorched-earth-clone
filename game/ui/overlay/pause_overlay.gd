class_name PauseOverlay
extends OverlayPanel
## Pause menu: RESUME / SETTINGS / RESTART MATCH / QUIT TO TITLE. Restart asks for a second
## tap (it discards the autosave); the settings live on their own screen.

signal resume_pressed
signal restart_pressed
signal quit_pressed
signal settings_pressed

const CONFIRM_SECONDS: float = 3.0

var _round_label: Label = null
var _restart: Button = null
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
	var quit: Button = add_button(tr("PAUSE_QUIT"), 150.0)
	quit.name = "Quit"
	quit.pressed.connect(func() -> void: quit_pressed.emit())
	end_container()


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
