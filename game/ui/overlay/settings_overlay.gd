class_name SettingsOverlay
extends OverlayPanel
## The settings screen (title and pause menu): haptics, screen shake, reduce flashing,
## trajectory preview, playback speed and text size. Every change is written to ShowSettings
## and saved to user://settings.cfg straight away.

## Emitted after BACK (or the Android back button) closed the screen.
signal closed

var _toggles: Dictionary = {}
var _speed_btn: Button = null
var _cpu_btn: Button = null
var _scroll: TouchScroll = null
var _preview_btn: Button = null
var _size_value: Label = null
var _size_minus: Button = null
var _size_plus: Button = null
var _version_btn: Button = null
var _diag: DiagnosticsOverlay = null
var _unlock: UnlockScreen = null
var _full_btn: Button = null
var _version_taps: int = 0
var _last_tap_ms: int = 0
## "Sfx" / "Music" -> the volume slider, its value label and its ON/OFF button.
var _sliders: Dictionary = {}
var _slider_values: Dictionary = {}
var _slider_toggles: Dictionary = {}
var _ui_sounds_btn: Button = null
var _thumb_px: int = 0
var _dragging: bool = false
var _thumb_normal: Texture2D = null
var _thumb_hot: Texture2D = null
var _thumb_off: Texture2D = null

## Taps on the version number that open the hidden diagnostics (each within TAP_WINDOW_MS of the last).
const DIAG_TAPS: int = 5
const TAP_WINDOW_MS: int = 2000
## Names of the CPU turn speed levels, in ShowSettings.CPU_SPEED_* order.
const CPU_SPEED_KEYS: Array[String] = ["SET_CPU_NORMAL", "SET_CPU_FAST", "SET_CPU_INSTANT"]


func _init() -> void:
	super._init()
	name = "SettingsOverlay"
	add_title(tr("SET_TITLE"), NeonPalette.CYAN, 24.0)
	# The toggles sit in a scroll area: with big text on a short phone screen they would not all fit.
	_scroll = TouchScroll.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(_scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(grid)
	_target = grid
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
	_cpu_btn = add_cycle(tr("SET_CPU_SPEED"), "", _on_cpu_speed)
	_cpu_btn.name = "CpuSpeed"
	_add_volume("Sfx", tr("SET_SFX"), ShowSettings.sfx_volume, ShowSettings.sfx_on, _on_sfx_volume, _on_sfx_on)
	_add_volume("Music", tr("SET_MUSIC"), ShowSettings.music_volume, ShowSettings.music_on, _on_music_volume, _on_music_on)
	_ui_sounds_btn = add_toggle(tr("SET_UI_SOUNDS"), ShowSettings.ui_sounds, _on_ui_sounds)
	_ui_sounds_btn.name = "UiSounds"
	# "Full game: [Restore purchase]" (an "Unlocked" label once owned). Opens the Unlock screen and asks Play.
	_full_btn = add_cycle(tr("SET_FULL_GAME"), tr("SET_RESTORE"), _on_restore_pressed)
	_full_btn.name = "Restore"
	_btn_dp[_full_btn] = [190.0, 13.0]
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
	_unlock = UnlockScreen.new()
	_unlock.closed.connect(_sync)  # a restore may have unlocked the game
	add_child(_unlock)
	_sync()


func open() -> void:
	_sync()
	super.open()
	_refit_settings_next_frame()


func get_scroll() -> TouchScroll:
	return _scroll


func apply_scale() -> void:
	super.apply_scale()
	if _scroll == null:
		return
	# Two columns when they fit the screen, one long (scrolling) column when text is very large.
	_style_sliders()
	var grid: GridContainer = _scroll.get_child(0)
	grid.columns = 2
	var frame: float = _panel.get_theme_stylebox("panel").get_minimum_size().x + UiScale.dp(32.0 + TouchScroll.BAR_DP + TouchScroll.GAP_DP)
	if grid.get_combined_minimum_size().x + frame > get_viewport_rect().size.x * 0.92:
		grid.columns = 1


## Sizes the toggle area to its content, but never so tall that the panel would leave the screen
## (a phone in landscape is ~320 dp high): what does not fit scrolls.
func _fit_scrolls() -> void:
	if _scroll == null:
		return
	var content: float = _scroll.get_child(0).get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = content
	var room: float = get_viewport_rect().size.y * 0.97 - _panel.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = clampf(content + minf(room, 0.0), minf(UiScale.dp(96.0), content), content)


## Container minimum sizes only settle after a frame, so measure again then.
func _refit_settings_next_frame() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if visible and is_inside_tree():
		_fit_scrolls()


func close() -> void:
	if _diag.visible:
		_diag.close()
	if _unlock.visible:
		_unlock.close()
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


func get_unlock_screen() -> UnlockScreen:
	return _unlock


func get_restore_button() -> Button:
	return _full_btn


## Restore purchase: the Unlock screen opens and asks the store straight away (it shows the result).
func _on_restore_pressed() -> void:
	_unlock.open_for("", true)


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
	_set_volume_controls("Sfx", ShowSettings.sfx_volume, ShowSettings.sfx_on)
	_set_volume_controls("Music", ShowSettings.music_volume, ShowSettings.music_on)
	_ui_sounds_btn.set_pressed_no_signal(ShowSettings.ui_sounds)
	_ui_sounds_btn.text = tr("SET_ON") if ShowSettings.ui_sounds else tr("SET_OFF")
	_refresh_texts()


func _refresh_texts() -> void:
	var owned: bool = Entitlement.is_full()
	_full_btn.text = tr("SET_FULL_OWNED") if owned else tr("SET_RESTORE")
	_full_btn.disabled = owned
	_preview_btn.text = tr("SET_PREVIEW_SHORT") if ShowSettings.trajectory_preview == ShowSettings.PREVIEW_SHORT else tr("SET_OFF")
	_speed_btn.text = tr("HUD_SPEED_FMT") % (2 if ShowSettings.playback_speed >= 1.5 else 1)
	_cpu_btn.text = tr(CPU_SPEED_KEYS[clampi(ShowSettings.cpu_turn_speed, 0, CPU_SPEED_KEYS.size() - 1)])
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


## One tap: Normal -> Fast -> Instant -> Normal.
func _on_cpu_speed() -> void:
	ShowSettings.cpu_turn_speed = (ShowSettings.cpu_turn_speed + 1) % CPU_SPEED_KEYS.size()
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


# --- sound --------------------------------------------------------------------------------

## A "Caption  [slider] 80%  [ON]" row in the settings grid: volume 0-100 plus a switch.
func _add_volume(key: String, caption: String, volume: int, on: bool, on_volume: Callable, on_toggle: Callable) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target.add_child(row)
	var label := Label.new()
	label.text = caption
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_font_dp[label] = 15.0
	_labels.append(label)
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = key + "Volume"
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = volume
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float) -> void:
		_set_value_text(key, int(v))
		on_volume.call(int(v))
		if not _dragging:
			_save())  # dragging saves once, when the finger lifts
	slider.drag_started.connect(func() -> void: _dragging = true)
	slider.drag_ended.connect(func(_changed: bool) -> void:
		_dragging = false
		_save()
		if key == "Sfx":
			AudioDirector.play_sfx("money_gain"))  # let the new level be heard
	row.add_child(slider)
	var value := Label.new()
	value.name = key + "Value"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_font_dp[value] = 14.0
	_labels.append(value)
	row.add_child(value)
	var b := Button.new()
	b.name = key + "Switch"
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.button_pressed = on
	b.toggled.connect(func(pressed: bool) -> void:
		b.text = tr("SET_ON") if pressed else tr("SET_OFF")
		slider.editable = pressed
		on_toggle.call(pressed))
	_btn_dp[b] = [84.0, 14.0]
	_buttons.append(b)
	row.add_child(b)
	_sliders[key] = slider
	_slider_values[key] = value
	_slider_toggles[key] = b
	_set_volume_controls(key, volume, on)


func _set_volume_controls(key: String, volume: int, on: bool) -> void:
	var slider: HSlider = _sliders[key]
	slider.set_value_no_signal(volume)
	slider.editable = on
	var b: Button = _slider_toggles[key]
	b.set_pressed_no_signal(on)
	b.text = tr("SET_ON") if on else tr("SET_OFF")
	_set_value_text(key, volume)


func _set_value_text(key: String, volume: int) -> void:
	(_slider_values[key] as Label).text = "%d%%" % volume


func _on_sfx_volume(v: int) -> void:
	ShowSettings.sfx_volume = v
	AudioDirector.apply_settings()


func _on_sfx_on(on: bool) -> void:
	ShowSettings.sfx_on = on
	AudioDirector.apply_settings()
	_save()


func _on_music_volume(v: int) -> void:
	ShowSettings.music_volume = v
	AudioDirector.apply_settings()


func _on_music_on(on: bool) -> void:
	ShowSettings.music_on = on
	AudioDirector.apply_settings()
	_save()


func _on_ui_sounds(on: bool) -> void:
	ShowSettings.ui_sounds = on
	AudioDirector.apply_settings()
	_save()


## Touch-sized sliders: the thumb is TOUCH dp (48) across and the whole row is at least that tall; the value
## sits next to the slider as text so the level never depends on the thumb position alone.
func _style_sliders() -> void:
	if _sliders.is_empty():
		return
	var px: int = roundi(maxf(UiScale.touch(), UiScale.dp(UiScale.MIN_TOUCH_DP)))
	if px != _thumb_px:
		_thumb_px = px
		_build_thumbs(px)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(NeonPalette.CYAN, 0.18)
	track.set_corner_radius_all(roundi(UiScale.dp(4.0)))
	track.content_margin_top = UiScale.dp(4.0)
	track.content_margin_bottom = UiScale.dp(4.0)
	var fill: StyleBoxFlat = track.duplicate()
	fill.bg_color = Color(NeonPalette.CYAN, 0.75)
	for key: String in _sliders:
		var s: HSlider = _sliders[key]
		s.custom_minimum_size = Vector2(UiScale.dp(110.0), float(px))
		s.add_theme_stylebox_override("slider", track)
		s.add_theme_stylebox_override("grabber_area", fill)
		s.add_theme_stylebox_override("grabber_area_highlight", fill)
		s.add_theme_icon_override("grabber", _thumb_normal)
		s.add_theme_icon_override("grabber_highlight", _thumb_hot)
		s.add_theme_icon_override("grabber_disabled", _thumb_off)
		(_slider_values[key] as Label).custom_minimum_size.x = UiScale.dp(46.0)


func _build_thumbs(px: int) -> void:
	_thumb_normal = _thumb(px, NeonPalette.CYAN)
	_thumb_hot = _thumb(px, Color(0.85, 1.0, 1.0))
	_thumb_off = _thumb(px, Color(NeonPalette.TEXT_DIM, 0.6))


## A round glowing disc, `px` across (a radial gradient: bright core, solid body, soft edge).
static func _thumb(px: int, color: Color) -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.78, 0.9, 1.0])
	g.colors = PackedColorArray([Color.WHITE, color, color, Color(color, 0.0), Color(color, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = px
	t.height = px
	return t


func get_slider(key: String) -> HSlider:
	return _sliders[key] as HSlider


func get_slider_switch(key: String) -> Button:
	return _slider_toggles[key] as Button


func get_slider_value_text(key: String) -> String:
	return (_slider_values[key] as Label).text


func get_ui_sounds_button() -> Button:
	return _ui_sounds_btn


func get_toggle(key: String) -> Button:
	return _toggles[key] as Button


func get_speed_button() -> Button:
	return _speed_btn


func get_cpu_speed_button() -> Button:
	return _cpu_btn


func get_preview_button() -> Button:
	return _preview_btn


func get_size_text() -> String:
	return _size_value.text


func get_smaller_button() -> Button:
	return _size_minus


func get_larger_button() -> Button:
	return _size_plus
