extends GutTest
## The sound part of the settings screen: volume sliders with a touch-sized thumb, switches, persistence.

const PATH: String = "user://test_settings_audio_ui.cfg"

var _ad: Node = null


func before_each() -> void:
	_ad = get_tree().root.get_node("AudioDirector")
	SettingsStore.path = PATH
	SettingsStore.delete()
	ShowSettings.reset()
	_ad.reset_for_tests()
	_ad.apply_settings()


func after_each() -> void:
	SettingsStore.delete()
	SettingsStore.path = SettingsStore.DEFAULT_PATH
	ShowSettings.reset()
	_ad.reset_for_tests()
	_ad.apply_settings()
	UiScale.reset_overrides()


func _open() -> SettingsOverlay:
	var o := SettingsOverlay.new()
	add_child_autofree(o)
	o.open()
	return o


func test_sound_controls_show_the_current_values() -> void:
	ShowSettings.sfx_volume = 40
	ShowSettings.music_on = false
	ShowSettings.ui_sounds = false
	var o: SettingsOverlay = _open()
	assert_eq(o.get_slider("Sfx").value, 40.0)
	assert_eq(o.get_slider_value_text("Sfx"), "40%", "the level is written out, not only drawn")
	assert_eq(o.get_slider_switch("Sfx").text, "ON")
	assert_eq(o.get_slider_switch("Music").text, "OFF")
	assert_false(o.get_slider("Music").editable, "an off channel's slider is dimmed and locked")
	assert_eq(o.get_ui_sounds_button().text, "OFF")


func test_moving_a_slider_changes_the_setting_the_bus_and_the_file() -> void:
	var o: SettingsOverlay = _open()
	o.get_slider("Sfx").value = 30.0
	o.get_slider("Music").value = 55.0
	assert_eq(ShowSettings.sfx_volume, 30)
	assert_eq(ShowSettings.music_volume, 55)
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")), linear_to_db(0.3), 0.01)
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), linear_to_db(0.55), 0.01)
	assert_eq(o.get_slider_value_text("Sfx"), "30%")
	ShowSettings.reset()
	assert_true(SettingsStore.load_into())
	assert_eq(ShowSettings.sfx_volume, 30, "what is on disk is what is on screen")
	assert_eq(ShowSettings.music_volume, 55)


func test_dragging_saves_once_when_the_finger_lifts() -> void:
	var o: SettingsOverlay = _open()
	var s: HSlider = o.get_slider("Music")
	s.drag_started.emit()
	s.value = 10.0
	s.value = 20.0
	assert_false(FileAccess.file_exists(PATH), "nothing is written while dragging")
	s.drag_ended.emit(true)
	assert_true(FileAccess.file_exists(PATH))
	ShowSettings.reset()
	SettingsStore.load_into()
	assert_eq(ShowSettings.music_volume, 20)


func test_switches_mute_the_buses_and_persist() -> void:
	var o: SettingsOverlay = _open()
	o.get_slider_switch("Sfx").button_pressed = false
	o.get_slider_switch("Music").button_pressed = false
	o.get_ui_sounds_button().button_pressed = false
	assert_false(ShowSettings.sfx_on)
	assert_false(ShowSettings.music_on)
	assert_false(ShowSettings.ui_sounds)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("UI")))
	assert_false(o.get_slider("Sfx").editable)
	ShowSettings.reset()
	SettingsStore.load_into()
	assert_false(ShowSettings.sfx_on)
	assert_false(ShowSettings.music_on)
	assert_false(ShowSettings.ui_sounds)
	o.get_slider_switch("Sfx").button_pressed = true
	assert_true(o.get_slider("Sfx").editable)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))


func test_reopening_shows_values_changed_elsewhere() -> void:
	var o: SettingsOverlay = _open()
	ShowSettings.sfx_volume = 12
	ShowSettings.sfx_on = false
	o.close()
	o.open()
	assert_eq(o.get_slider("Sfx").value, 12.0)
	assert_eq(o.get_slider_switch("Sfx").text, "OFF")


func test_the_thumb_and_the_row_are_at_least_48_dp() -> void:
	for dpi: float in [160.0, 320.0, 480.0]:
		UiScale.dpi_override = dpi
		var o: SettingsOverlay = _open()
		o.apply_scale()
		var min_px: float = UiScale.dp(48.0)
		for key: String in ["Sfx", "Music"]:
			var s: HSlider = o.get_slider(key)
			var thumb: Texture2D = s.get_theme_icon("grabber")
			assert_gte(float(thumb.get_width()), min_px - 1.0, "%s thumb at %d dpi" % [key, dpi])
			assert_gte(float(thumb.get_height()), min_px - 1.0)
			assert_gte(s.custom_minimum_size.y, min_px - 1.0, "%s row height" % key)
			assert_gte(s.get_combined_minimum_size().y, min_px - 1.0)
			assert_gte(o.get_slider_switch(key).custom_minimum_size.y, min_px - 1.0, "switch height")
		o.queue_free()
		await wait_process_frames(1)


func test_pressing_the_ui_sounds_switch_is_itself_silent_when_it_turns_them_off() -> void:
	var o: SettingsOverlay = _open()
	_ad.record_log = true
	o.get_ui_sounds_button().button_pressed = false
	# toggling emits `pressed` only on a real tap, not through button_pressed; the tap sound is checked elsewhere
	assert_eq(_ad.stats["played"], 0)
