class_name SettingsOverlay
extends OverlayPanel
## The settings screen (title and pause menu): haptics, screen shake, reduce flashing,
## trajectory preview, playback speed and text size. Every change is written to ShowSettings
## and saved to user://settings.cfg straight away.

## Emitted after BACK (or the Android back button) closed the screen.
signal closed

var _toggles: Dictionary = {}
var _speed_btn: Button = null
var _preview_btn: Button = null
var _size_value: Label = null
var _size_minus: Button = null
var _size_plus: Button = null
var _version_btn: Button = null
var _diag: DiagnosticsOverlay = null
var _version_taps: int = 0
var _last_tap_ms: int = 0

## Taps on the version number that open the hidden diagnostics (each within TAP_WINDOW_MS of the last).
const DIAG_TAPS: int = 5
const TAP_WINDOW_MS: int = 2000


func _init() -> void:
	super._init()
	name = "SettingsOverlay"
	add_title(tr("SET_TITLE"), NeonPalette.CYAN, 24.0)
	begin_grid()
	_toggles["Haptics"] = add_toggle(tr("SET_HAPTICS"), ShowSettings.haptics, func(on: bool) -> void:
		ShowSettings.haptics = on
		_save())
	(_toggles["Haptics"] as Button).name = "Haptics"
	_toggles["Shake"] = add_toggle(tr("SET_SHAKE"), ShowSettings.screen_shake, func(on: bool) -> void:
		ShowSettings.screen_shake = on
		_save())
	(_toggles["Shake"] as Button).name = "Shake"
	_toggles["ReduceFlashing"] = add_toggle(tr("SET_REDUCE_FLASH"), ShowSettings.reduce_flashing, func(on: bool) -> void:
		ShowSettings.reduce_flashing = on
		_save())
	(_toggles["ReduceFlashing"] as Button).name = "ReduceFlashing"
	_preview_btn = add_toggle(tr("SET_PREVIEW"), ShowSettings.trajectory_preview != ShowSettings.PREVIEW_OFF, _on_preview)
	_preview_btn.name = "Preview"
	_speed_btn = add_toggle(tr("SET_SPEED"), ShowSettings.playback_speed >= 1.5, _on_speed)
	_speed_btn.name = "Speed"
	var step: Dictionary = add_stepper(tr("SET_TEXT_SIZE"), "", _on_text_step)
	_size_minus = step["minus"]
	_size_plus = step["plus"]
	_size_value = step["value"]
	_size_minus.name = "TextSmaller"
	_size_plus.name = "TextLarger"
	_size_value.name = "TextSizeValue"
	end_container()
	# BACK and the (hidden-diagnostics) version number share a row to keep the panel short.
	begin_row()
	add_button(tr("SET_BACK"), 160.0).pressed.connect(close)
	_buttons[_buttons.size() - 1].name = "Back"
	_version_btn = add_button(tr("SET_VERSION_FMT") % BuildInfo.VERSION, 140.0)
	_version_btn.name = "Version"
	_version_btn.flat = true
	_version_btn.add_theme_color_override("font_color", NeonPalette.TEXT_DIM)
	_btn_dp[_version_btn] = [140.0, 12.0]
	_version_btn.pressed.connect(tap_version)
	end_container()
	_diag = DiagnosticsOverlay.new()
	add_child(_diag)
	_sync()


func open() -> void:
	_sync()
	super.open()


func close() -> void:
	if _diag.visible:
		_diag.close()
	if visible:
		super.close()
		closed.emit()


## One tap on the version number; DIAG_TAPS quick taps in a row open the diagnostics screen.
func tap_version() -> void:
	var now: int = Time.get_ticks_msec()
	_version_taps = _version_taps + 1 if now - _last_tap_ms <= TAP_WINDOW_MS else 1
	_last_tap_ms = now
	if _version_taps >= DIAG_TAPS:
		_version_taps = 0
		_diag.open()


func get_version_button() -> Button:
	return _version_btn


func get_diagnostics() -> DiagnosticsOverlay:
	return _diag


## Hides without emitting `closed` (the pause menu is being torn down).
func close_silently() -> void:
	super.close()


## Re-reads ShowSettings into the controls (after a load or a reset).
func _sync() -> void:
	(_toggles["Haptics"] as Button).set_pressed_no_signal(ShowSettings.haptics)
	(_toggles["Shake"] as Button).set_pressed_no_signal(ShowSettings.screen_shake)
	(_toggles["ReduceFlashing"] as Button).set_pressed_no_signal(ShowSettings.reduce_flashing)
	for key: String in ["Haptics", "Shake", "ReduceFlashing"]:
		var b: Button = _toggles[key]
		b.text = tr("SET_ON") if b.button_pressed else tr("SET_OFF")
	_preview_btn.set_pressed_no_signal(ShowSettings.trajectory_preview != ShowSettings.PREVIEW_OFF)
	_speed_btn.set_pressed_no_signal(ShowSettings.playback_speed >= 1.5)
	_refresh_texts()


func _refresh_texts() -> void:
	_preview_btn.text = tr("SET_PREVIEW_SHORT") if ShowSettings.trajectory_preview == ShowSettings.PREVIEW_SHORT else tr("SET_OFF")
	_speed_btn.text = tr("HUD_SPEED_FMT") % (2 if ShowSettings.playback_speed >= 1.5 else 1)
	_size_value.text = "%d%%" % ShowSettings.text_size
	_size_minus.disabled = ShowSettings.text_size <= ShowSettings.TEXT_SIZE_MIN
	_size_plus.disabled = ShowSettings.text_size >= ShowSettings.TEXT_SIZE_MAX


func _on_preview(on: bool) -> void:
	ShowSettings.trajectory_preview = ShowSettings.PREVIEW_SHORT if on else ShowSettings.PREVIEW_OFF
	_refresh_texts()
	_save()


func _on_speed(on: bool) -> void:
	ShowSettings.playback_speed = 2.0 if on else 1.0
	_refresh_texts()
	_save()


func _on_text_step(direction: int) -> void:
	ShowSettings.set_text_size(ShowSettings.text_size + direction * ShowSettings.TEXT_SIZE_STEP)
	_refresh_texts()
	_save()
	apply_scale()
	if is_inside_tree():
		UiScale.notify_changed(get_tree())


func _save() -> void:
	SettingsStore.save()


func get_toggle(key: String) -> Button:
	return _toggles[key] as Button


func get_speed_button() -> Button:
	return _speed_btn


func get_preview_button() -> Button:
	return _preview_btn


func get_size_text() -> String:
	return _size_value.text


func get_smaller_button() -> Button:
	return _size_minus


func get_larger_button() -> Button:
	return _size_plus
