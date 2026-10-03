extends GutTest
## ShowSettings + SettingsStore (user://settings.cfg) + the settings screen.

const PATH: String = "user://test_settings.cfg"


func before_each() -> void:
	SettingsStore.path = PATH
	SettingsStore.delete()
	ShowSettings.reset()


func after_each() -> void:
	SettingsStore.delete()
	SettingsStore.path = SettingsStore.DEFAULT_PATH
	ShowSettings.reset()
	UiScale.reset_overrides()


func _set_everything() -> void:
	ShowSettings.haptics = false
	ShowSettings.screen_shake = false
	ShowSettings.reduce_flashing = true
	ShowSettings.trajectory_preview = ShowSettings.PREVIEW_OFF
	ShowSettings.playback_speed = 2.0
	ShowSettings.set_text_size(130)
	ShowSettings.cpu_turn_speed = ShowSettings.CPU_SPEED_FAST


func test_settings_persist_across_instances() -> void:
	_set_everything()
	assert_true(SettingsStore.save())
	assert_true(FileAccess.file_exists(PATH))
	ShowSettings.reset()  # a "new process": defaults again
	assert_true(ShowSettings.haptics)
	assert_true(SettingsStore.load_into())
	assert_false(ShowSettings.haptics)
	assert_false(ShowSettings.screen_shake)
	assert_true(ShowSettings.reduce_flashing)
	assert_eq(ShowSettings.trajectory_preview, ShowSettings.PREVIEW_OFF)
	assert_eq(ShowSettings.playback_speed, 2.0)
	assert_eq(ShowSettings.text_size, 130)
	assert_eq(ShowSettings.cpu_turn_speed, ShowSettings.CPU_SPEED_FAST, "the CPU turn speed is saved too")
	assert_almost_eq(UiScale.text_scale, 1.3, 0.0001, "loading applies the text scale")


func test_missing_file_keeps_defaults() -> void:
	assert_false(SettingsStore.load_into())
	assert_true(ShowSettings.haptics)
	assert_eq(ShowSettings.text_size, 100)


func test_damaged_values_are_ignored_or_clamped() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("show", "haptics", "banana")
	cfg.set_value("show", "text_size", 900)
	cfg.set_value("show", "playback_speed", "fast")
	cfg.set_value("show", "trajectory_preview", 7)
	cfg.save(PATH)
	assert_true(SettingsStore.load_into())
	assert_true(ShowSettings.haptics, "a non-bool is ignored")
	assert_eq(ShowSettings.text_size, ShowSettings.TEXT_SIZE_MAX, "clamped")
	assert_eq(ShowSettings.playback_speed, 1.0)
	assert_eq(ShowSettings.trajectory_preview, ShowSettings.PREVIEW_SHORT, "anything but Off means the short preview")


func test_text_size_steps_clamp_and_scale_fonts() -> void:
	ShowSettings.set_text_size(95)
	assert_eq(ShowSettings.text_size, 100, "rounds to the 10% step")
	ShowSettings.set_text_size(10)
	assert_eq(ShowSettings.text_size, 80)
	ShowSettings.set_text_size(1000)
	assert_eq(ShowSettings.text_size, 150)
	UiScale.dpi_override = 320.0
	ShowSettings.set_text_size(100)
	var base: int = UiScale.font(16.0)
	ShowSettings.set_text_size(150)
	assert_almost_eq(float(UiScale.font(16.0)), float(base) * 1.5, 1.0)
	ShowSettings.set_text_size(80)
	assert_lt(UiScale.font(16.0), base)


func test_ensure_loaded_never_reads_the_real_file_in_headless_runs() -> void:
	_set_everything()
	SettingsStore.save()
	ShowSettings.reset()
	SettingsStore.forget_loaded()
	SettingsStore.ensure_loaded()
	assert_true(ShowSettings.haptics, "headless: untouched (the test suite must not depend on a developer's settings)")
	SettingsStore.allow_headless_load = true
	SettingsStore.forget_loaded()
	SettingsStore.ensure_loaded()
	SettingsStore.allow_headless_load = false
	assert_false(ShowSettings.haptics, "a normal run loads it once")
	SettingsStore.forget_loaded()


func test_settings_screen_edits_and_saves_every_change() -> void:
	var o := SettingsOverlay.new()
	add_child_autofree(o)
	o.open()
	assert_eq(o.get_size_text(), "100%")
	(o.get_toggle("Haptics")).button_pressed = false
	assert_false(ShowSettings.haptics)
	(o.get_toggle("Shake")).button_pressed = false
	(o.get_toggle("ReduceFlashing")).button_pressed = true
	o.get_preview_button().button_pressed = false
	o.get_speed_button().button_pressed = true
	o.get_larger_button().pressed.emit()
	o.get_larger_button().pressed.emit()
	assert_eq(ShowSettings.text_size, 120)
	assert_eq(o.get_size_text(), "120%")
	assert_almost_eq(UiScale.text_scale, 1.2, 0.0001)
	# What is on disk is what is on screen.
	ShowSettings.reset()
	SettingsStore.load_into()
	assert_false(ShowSettings.haptics)
	assert_false(ShowSettings.screen_shake)
	assert_true(ShowSettings.reduce_flashing)
	assert_eq(ShowSettings.trajectory_preview, ShowSettings.PREVIEW_OFF)
	assert_eq(ShowSettings.playback_speed, 2.0)
	assert_eq(ShowSettings.text_size, 120)


func test_text_size_buttons_stop_at_the_limits() -> void:
	var o := SettingsOverlay.new()
	add_child_autofree(o)
	for _i: int in range(10):
		o.get_larger_button().pressed.emit()
	assert_eq(ShowSettings.text_size, 150)
	assert_true(o.get_larger_button().disabled)
	for _i: int in range(10):
		o.get_smaller_button().pressed.emit()
	assert_eq(ShowSettings.text_size, 80)
	assert_true(o.get_smaller_button().disabled)


func test_settings_screen_reflects_loaded_values() -> void:
	_set_everything()
	var o := SettingsOverlay.new()
	add_child_autofree(o)
	o.open()
	assert_false(o.get_toggle("Haptics").button_pressed)
	assert_true(o.get_toggle("ReduceFlashing").button_pressed)
	assert_eq(o.get_size_text(), "130%")
	assert_eq(o.get_speed_button().text, "2x")


func test_back_closes_and_signals() -> void:
	var o := SettingsOverlay.new()
	add_child_autofree(o)
	o.open()
	watch_signals(o)
	(o.find_child("Back", true, false) as Button).pressed.emit()
	assert_false(o.visible)
	assert_signal_emitted(o, "closed")


func test_title_opens_the_settings_screen() -> void:
	BattleConfig.autosave_path = "user://test_title_none.crtl"
	var t: TitleScreen = (load("res://ui/title/title_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(t)
	await wait_process_frames(2)
	assert_false(t.get_settings_overlay().visible)
	t.get_settings_button().pressed.emit()
	assert_true(t.get_settings_overlay().visible)
	BattleConfig.reset()


func test_cpu_turn_speed_option_cycles_and_saves() -> void:
	var o := SettingsOverlay.new()
	add_child_autofree(o)
	o.open()
	var b: Button = o.get_cpu_speed_button()
	assert_eq(b.text, "Normal")
	b.pressed.emit()
	assert_eq(ShowSettings.cpu_turn_speed, ShowSettings.CPU_SPEED_FAST)
	assert_eq(b.text, "Fast")
	b.pressed.emit()
	assert_eq(ShowSettings.cpu_turn_speed, ShowSettings.CPU_SPEED_INSTANT)
	assert_eq(b.text, "Instant")
	b.pressed.emit()
	assert_eq(ShowSettings.cpu_turn_speed, ShowSettings.CPU_SPEED_NORMAL, "wraps around")
	assert_eq(b.text, "Normal")
	b.pressed.emit()
	ShowSettings.reset()
	assert_true(SettingsStore.load_into())
	assert_eq(ShowSettings.cpu_turn_speed, ShowSettings.CPU_SPEED_FAST, "what is on disk is what was chosen")
	o.open()
	assert_eq(b.text, "Fast", "reopening shows the current value")


func test_damaged_cpu_turn_speed_is_clamped() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("show", "cpu_turn_speed", 17)
	cfg.save(PATH)
	assert_true(SettingsStore.load_into())
	assert_eq(ShowSettings.cpu_turn_speed, ShowSettings.CPU_SPEED_INSTANT)
	cfg.set_value("show", "cpu_turn_speed", "fast")
	cfg.save(PATH)
	ShowSettings.reset()
	SettingsStore.load_into()
	assert_eq(ShowSettings.cpu_turn_speed, ShowSettings.CPU_SPEED_NORMAL, "a non-number keeps the default")


func test_setup_prefs_share_the_file_with_the_show_settings() -> void:
	ShowSettings.haptics = false
	SetupPrefs.remember(4, 5, 0, 1, PackedInt32Array([0, 2, 4, 1, 0, 0, 0, 0]), true)
	assert_true(SettingsStore.save())
	ShowSettings.reset()
	assert_false(SetupPrefs.has_saved, "reset forgets the last setup")
	assert_true(SettingsStore.load_into())
	assert_false(ShowSettings.haptics)
	assert_true(SetupPrefs.has_saved)
	assert_eq(SetupPrefs.players, 4)
	assert_eq(SetupPrefs.rounds, 5)
	assert_eq(SetupPrefs.money_level, 0)
	assert_eq(SetupPrefs.wind_level, 1)
	assert_eq(SetupPrefs.controllers, PackedInt32Array([0, 2, 4, 1, 0, 0, 0, 0]))
	assert_true(SetupPrefs.watch)
	# Saving the display settings does not forget a setup that was never chosen.
	ShowSettings.reset()
	assert_true(SettingsStore.save())
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	assert_false(cfg.has_section("setup"), "no setup chosen: no [setup] section")
