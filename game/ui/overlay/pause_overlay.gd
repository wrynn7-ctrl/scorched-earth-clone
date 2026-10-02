class_name PauseOverlay
extends OverlayPanel
## Pause menu: RESUME / RESTART MATCH / QUIT TO TITLE plus the quick settings toggles.
## The settings write straight into ShowSettings (presentation-only switches).

signal resume_pressed
signal restart_pressed
signal quit_pressed

var _round_label: Label = null
var _preview_btn: Button = null


func _init() -> void:
	name = "PauseOverlay"
	add_title(tr("PAUSE_TITLE"))
	_round_label = add_label("", 14.0)
	add_button(tr("PAUSE_RESUME")).pressed.connect(func() -> void: resume_pressed.emit())
	add_toggle(tr("SET_HAPTICS"), ShowSettings.haptics, func(on: bool) -> void: ShowSettings.haptics = on).name = "Haptics"
	add_toggle(tr("SET_SHAKE"), ShowSettings.screen_shake, func(on: bool) -> void: ShowSettings.screen_shake = on).name = "Shake"
	add_toggle(tr("SET_REDUCE_FLASH"), ShowSettings.reduce_flashing, func(on: bool) -> void: ShowSettings.reduce_flashing = on).name = "ReduceFlashing"
	_preview_btn = add_toggle(tr("SET_PREVIEW"), ShowSettings.trajectory_preview != ShowSettings.PREVIEW_OFF, _on_preview)
	_preview_btn.name = "Preview"
	_refresh_preview_text()
	add_button(tr("PAUSE_RESTART")).pressed.connect(func() -> void: restart_pressed.emit())
	add_button(tr("PAUSE_QUIT")).pressed.connect(func() -> void: quit_pressed.emit())
	# Names for tests / debugging.
	_buttons[0].name = "Resume"
	_buttons[_buttons.size() - 2].name = "Restart"
	_buttons[_buttons.size() - 1].name = "Quit"


func open_for(round_number: int, rounds: int) -> void:
	_round_label.text = tr("OVERLAY_ROUND_OF") % [round_number, rounds]
	_sync_toggles()
	open()


func _sync_toggles() -> void:
	(_find("Haptics") as Button).set_pressed_no_signal(ShowSettings.haptics)
	(_find("Shake") as Button).set_pressed_no_signal(ShowSettings.screen_shake)
	(_find("ReduceFlashing") as Button).set_pressed_no_signal(ShowSettings.reduce_flashing)
	_preview_btn.set_pressed_no_signal(ShowSettings.trajectory_preview != ShowSettings.PREVIEW_OFF)
	for n: String in ["Haptics", "Shake", "ReduceFlashing"]:
		var b: Button = _find(n) as Button
		b.text = tr("SET_ON") if b.button_pressed else tr("SET_OFF")
	_refresh_preview_text()


func _find(n: String) -> Node:
	return _box.find_child(n, true, false)


func _on_preview(on: bool) -> void:
	ShowSettings.trajectory_preview = ShowSettings.PREVIEW_SHORT if on else ShowSettings.PREVIEW_OFF
	_refresh_preview_text()


## The preview setting reads "SHORT"/"OFF" rather than ON/OFF.
func _refresh_preview_text() -> void:
	_preview_btn.text = tr("SET_PREVIEW_SHORT") if ShowSettings.trajectory_preview == ShowSettings.PREVIEW_SHORT else tr("SET_OFF")
