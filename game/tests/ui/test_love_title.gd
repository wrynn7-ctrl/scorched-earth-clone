extends GutTest
## The secret (docs/ARCHITECTURE.md section 37): seven taps on the title logo within about three seconds reveal the Love
## Edition button, which then stays. Six taps, or slow taps, do nothing. Nothing else on the title changes.

const TITLE: String = "res://ui/title/title_screen.tscn"
const PREFS: String = "user://test_love_title_prefs.cfg"
const SAVE: String = "user://test_love_title_save.crtl"


func before_each() -> void:
	SettingsStore.path = PREFS
	SettingsStore.delete()
	SettingsStore.love_found = false
	ShotArgs.love_found = false
	SaveStore.delete(SAVE)
	BattleConfig.autosave_path = SAVE
	AudioDirector.reset_for_tests()
	AudioDirector.record_log = true


func after_each() -> void:
	SettingsStore.delete()
	SettingsStore.path = SettingsStore.DEFAULT_PATH
	SettingsStore.love_found = false
	SaveStore.delete(SAVE)
	ShowSettings.reset()
	UiScale.reset_overrides()
	BattleConfig.reset()
	AudioDirector.reset_for_tests()


func _title() -> TitleScreen:
	var t: TitleScreen = (load(TITLE) as PackedScene).instantiate()
	add_child_autofree(t)
	return t


func _tap(t: TitleScreen, n: int, gap_ms: int, start_ms: int = 10000) -> bool:
	var revealed: bool = false
	for i: int in range(n):
		revealed = t.tap_logo(start_ms + i * gap_ms) or revealed
	return revealed


func test_the_button_is_hidden_and_the_title_gives_no_hint() -> void:
	var t: TitleScreen = _title()
	await wait_process_frames(2)
	assert_false(t.get_love_button().visible)
	assert_false(t.is_love_revealed())
	# Every visible text on the title is the usual one: nothing mentions the logo or a secret.
	for l: Node in t.find_children("*", "Label", true, false):
		assert_false((l as Label).text.to_lower().contains("tap"), (l as Label).text)
	for b: Node in t.find_children("*", "Button", true, false):
		if (b as Button).visible:
			assert_false((b as Button).text.to_lower().contains("love"))


func test_seven_quick_taps_reveal_the_button_and_it_persists() -> void:
	var t: TitleScreen = _title()
	await wait_process_frames(2)
	assert_false(_tap(t, 6, 200), "six taps are not enough")
	assert_false(t.get_love_button().visible)
	assert_true(t.tap_logo(10000 + 6 * 200), "the seventh reveals it")
	assert_true(t.get_love_button().visible)
	assert_true(t.get_love_button().text == "LOVE EDITION")
	assert_true(SettingsStore.love_found)
	assert_true(FileAccess.file_exists(PREFS), "stored for good")
	assert_not_null(t.get_love_burst(), "a small heart sparkle played")
	assert_true(t.get_love_burst().is_playing())
	assert_true(AudioDirector.played_log.has("love_found"), "and a soft chime")
	# A fresh process: the flag comes back from the settings file and the button is simply there.
	SettingsStore.love_found = false
	assert_true(SettingsStore.load_into())
	assert_true(SettingsStore.love_found)
	var again: TitleScreen = _title()
	await wait_process_frames(2)
	assert_true(again.get_love_button().visible, "the button stays")
	assert_not_null(again.get_love_button().icon, "a drawn heart icon")


func test_slow_taps_do_not_count() -> void:
	var t: TitleScreen = _title()
	await wait_process_frames(2)
	assert_false(_tap(t, 7, 600), "seven taps spread over 3.6 s")
	assert_false(t.get_love_button().visible)
	assert_false(SettingsStore.love_found)
	assert_false(FileAccess.file_exists(PREFS))
	# ...but a quick run after the slow ones does, because old taps expire.
	assert_true(_tap(t, 7, 150, 20000))


func test_exactly_inside_the_window_counts_and_just_outside_does_not() -> void:
	var t: TitleScreen = _title()
	await wait_process_frames(2)
	assert_true(_tap(t, 7, TitleScreen.LOVE_WINDOW_MS / 6), "7 taps spanning exactly the window")
	SettingsStore.love_found = false
	var t2: TitleScreen = _title()
	await wait_process_frames(2)
	assert_false(_tap(t2, 7, TitleScreen.LOVE_WINDOW_MS / 6 + 20), "a hair too slow")


func test_real_input_events_on_the_logo_count_and_other_input_does_not() -> void:
	var t: TitleScreen = _title()
	await wait_process_frames(2)
	var holder: Control = t.get_logo_holder()
	assert_eq(holder.mouse_filter, Control.MOUSE_FILTER_STOP)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	for i: int in range(6):
		holder.gui_input.emit(ev)
	assert_eq(t.logo_taps_pending(), 6)
	ev.button_index = MOUSE_BUTTON_RIGHT
	holder.gui_input.emit(ev)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	holder.gui_input.emit(release)
	assert_eq(t.logo_taps_pending(), 6, "only left presses count")
	ev.button_index = MOUSE_BUTTON_LEFT
	holder.gui_input.emit(ev)
	assert_true(t.get_love_button().visible)


func test_the_logo_taps_leave_the_rest_of_the_title_alone() -> void:
	var t: TitleScreen = _title()
	await wait_process_frames(2)
	var start_before: bool = t.get_start_button().visible
	_tap(t, 3, 100)
	assert_eq(t.get_start_button().visible, start_before)
	assert_false(t.get_settings_overlay().is_open())
	assert_false(t.get_confirm_overlay().is_open())
	assert_false(t.get_unlock_screen().is_open())
	# Only the logo's own rectangle takes input: the buttons keep theirs.
	for b: Button in [t.get_start_button(), t.get_settings_button(), t.get_skins_button()]:
		assert_false(b.get_global_rect().intersects(t.get_logo_holder().get_global_rect()), "the logo and %s do not overlap" % b.name)


func test_after_the_discovery_more_taps_do_nothing() -> void:
	var t: TitleScreen = _title()
	await wait_process_frames(2)
	assert_true(_tap(t, 7, 100))
	assert_false(t.tap_logo(99999), "already found")
	assert_eq(t.logo_taps_pending(), 0)


func test_the_love_button_opens_the_love_setup() -> void:
	SettingsStore.love_found = true
	var t: TitleScreen = _title()
	await wait_process_frames(2)
	assert_true(t.get_love_button().visible)
	assert_gte(t.get_love_button().custom_minimum_size.y, UiScale.touch() - 0.01, "48 dp tap target")
	t.get_love_button().pressed.emit()
	await wait_process_frames(3)
	var cur: Node = get_tree().current_scene
	assert_true(cur is LoveSetupScreen, "the love setup")
	if cur != null:
		cur.queue_free()
		await wait_process_frames(2)


func test_an_autosave_is_confirmed_before_a_love_match_replaces_it() -> void:
	SettingsStore.love_found = true
	var s := MatchSettings.new()
	s.seed = 3
	var m: MatchSession = MatchSession.create(s)
	m.save(SAVE)
	var t: TitleScreen = _title()
	await wait_process_frames(2)
	assert_true(t.has_save())
	t.get_love_button().pressed.emit()
	assert_true(t.get_confirm_overlay().is_open(), "same question as START")


func test_continue_resumes_a_love_match() -> void:
	var s := MatchSettings.new()
	s.mode = SimConstants.MODE_LOVE
	s.seed = 12
	var m: MatchSession = MatchSession.create(s)
	assert_true(m.save(SAVE))
	var t: TitleScreen = _title()
	await wait_process_frames(2)
	assert_true(t.has_save())
	BattleConfig.instant = true
	t.get_continue_button().pressed.emit()
	await wait_process_frames(3)
	var cur: Node = get_tree().current_scene
	assert_true(cur is BattleController)
	if cur is BattleController:
		assert_true((cur as BattleController).is_love_mode(), "continues as a love match")
		assert_eq((cur as BattleController).get_state().phase, SimConstants.PHASE_AIM)
		cur.queue_free()
		await wait_process_frames(2)


func test_the_row_takes_no_height_when_it_has_nothing_to_show() -> void:
	var t: TitleScreen = _title()
	await wait_process_frames(2)
	var row: Control = t.find_child("ChipRow", true, false) as Control
	assert_eq(row.visible, t.get_unlock_chip().visible, "visible only for the unlock chip while the love button is hidden")
	SettingsStore.love_found = true
	var t2: TitleScreen = _title()
	await wait_process_frames(2)
	assert_true((t2.find_child("ChipRow", true, false) as Control).visible)
