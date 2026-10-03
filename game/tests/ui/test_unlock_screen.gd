extends GutTest
## The Unlock screen: content, states (loading / ready / waiting / pending / success / error),
## no dark patterns, the celebration, Settings > Restore purchase, the debug toggle behind the
## diagnostics screen, and the layout on every screen size and text size.

const CACHE: String = "user://test_unlock_entitlement.cfg"

# [window px, dpi, label]
const CASES: Array = [
	[Vector2(2340, 1080), 500.0, "19.5:9 phone"],
	[Vector2(2340, 1080), 535.0, "narrowest realistic"],
	[Vector2(2560, 1080), 450.0, "21:9 phone"],
	[Vector2(3120, 1440), 560.0, "S26 Ultra class"],
	[Vector2(2048, 1536), 264.0, "4:3 tablet"],
	[Vector2(2560, 1600), 280.0, "16:10 tablet"],
	[Vector2(1280, 720), 240.0, "small 16:9"],
]

var _ad: Node = null


func before_each() -> void:
	Entitlement.reset_for_tests(false, CACHE)
	_ad = get_tree().root.get_node("AudioDirector")
	_ad.set("record_log", true)
	(_ad.get("played_log") as Array).clear()


func after_each() -> void:
	_ad.call("reset_for_tests")
	Entitlement.forget_for_tests()
	if FileAccess.file_exists(CACHE):
		DirAccess.remove_absolute(CACHE)
	UiScale.reset_overrides()
	ShowSettings.reset()
	SettingsStore.path = SettingsStore.DEFAULT_PATH


func _viewport(win: Vector2, dpi: float) -> SubViewport:
	UiScale.dpi_override = dpi
	UiScale.window_px_override = win
	var vis: Vector2 = UiScale.visible_size(win)
	var vp := SubViewport.new()
	vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child_autofree(vp)
	return vp


func _screen() -> UnlockScreen:
	var u := UnlockScreen.new()
	add_child_autofree(u)
	return u


func _played(key: String) -> bool:
	return (_ad.get("played_log") as Array).has(key)


# --- content -----------------------------------------------------------------------------------

func test_it_shows_the_title_the_showcase_and_the_three_buttons() -> void:
	Entitlement.debug_build_override = 0  # a store without a price
	var u: UnlockScreen = _screen()
	u.open_for("")
	assert_true(u.visible)
	assert_eq(u.get_title_text(), "UNLOCK THE FULL GAME")
	var features: PackedStringArray = u.get_feature_texts()
	assert_eq(features.size(), 8)
	var all: String = "\n".join(features)
	for needle: String in ["8 tanks", "Hard and Expert", "21 weapons", "Singularity Seed", "Riptide Anchor", "5 terrain themes",
			"images", "10 and 20 rounds", "money and wind", "coming soon"]:
		assert_string_contains(all, needle)
	assert_eq(u.get_buy_button().text, "UNLOCK", "no price known yet")
	assert_eq(u.get_restore_button().text, "RESTORE PURCHASE")
	assert_eq(u.get_close_button().text, "CLOSE")


func test_the_price_shows_on_the_buy_button_once_known() -> void:
	Entitlement.debug_build_override = 1
	var u: UnlockScreen = _screen()
	u.open_for("")  # Entitlement.start() inside asks the fake store for the price
	assert_eq(u.get_buy_button().text, "UNLOCK  $3.99")
	assert_false(u.get_buy_button().disabled)


func test_each_trigger_gives_its_own_one_line_reason() -> void:
	var u: UnlockScreen = _screen()
	for kind: String in UnlockScreen.CONTEXT_KEYS:
		u.open_for(kind)
		assert_ne(u.get_context_text(), "", kind)
		assert_true(u.get_context_text().length() < 90, "one line: " + kind)
		u.close()
	u.open_for("")
	assert_eq(u.get_context_text(), "", "the title chip has no reason line")


func test_no_dark_patterns() -> void:
	var u: UnlockScreen = _screen()
	u.open_for("rounds")
	var texts: Array[String] = [u.get_title_text(), u.get_context_text(), u.get_buy_button().text,
			u.get_restore_button().text, u.get_close_button().text]
	texts.append_array(u.get_feature_texts())
	for l: Node in u.find_children("*", "Label", true, false):
		texts.append((l as Label).text.to_lower())
	var joined: String = " ".join(texts).to_lower()
	for word: String in ["limited", "hurry", "only today", "% off", "sale", "countdown", "expires", "last chance", "hours"]:
		assert_false(joined.contains(word), "no '%s'" % word)
	assert_true(u.find_children("*", "Timer", true, false).is_empty(), "no countdown nodes")


# --- states ------------------------------------------------------------------------------------

func test_loading_shows_until_the_price_or_the_timeout() -> void:
	Entitlement.debug_build_override = 0  # a store that never answers with a price
	var u: UnlockScreen = _screen()
	u.open_for("")
	assert_eq(u.get_status_text(), "Contacting the store…")
	u.end_loading()
	assert_eq(u.get_status_text(), "")
	assert_false(u.get_buy_button().disabled, "BUY works while loading: it reports the real reason")
	u.open_for("")
	Entitlement.hub().price_changed.emit("3,99 €")
	assert_eq(u.get_status_text(), "")


func test_waiting_for_the_store_blocks_double_taps() -> void:
	BillingFake.delay_sec = 5.0
	Entitlement.debug_build_override = 1
	var u: UnlockScreen = _screen()
	u.open_for("")
	u.get_buy_button().pressed.emit()
	assert_eq(u.get_status_text(), "Waiting for the store…")
	assert_true(u.get_buy_button().disabled)
	assert_true(u.get_restore_button().disabled)
	assert_false(Entitlement.is_full())


func test_pending_shows_the_message_and_does_not_unlock() -> void:
	Entitlement.debug_build_override = 1
	BillingFake.next_result = "pending"
	var u: UnlockScreen = _screen()
	u.open_for("")
	u.get_buy_button().pressed.emit()
	assert_false(Entitlement.is_full())
	assert_eq(u.get_buy_button().text, "PURCHASE PENDING")
	assert_true(u.get_buy_button().disabled)
	assert_string_contains(u.get_status_text(), "Purchase pending")
	assert_false(u.get_restore_button().disabled, "RESTORE can still look again")
	assert_false(_played("ui_purchase"), "no celebration yet")
	assert_false(u.is_celebrating())


func test_errors_are_shown_in_words_and_BUY_stays_usable() -> void:
	Entitlement.debug_build_override = 0  # release: the fake store is "unavailable"
	var u: UnlockScreen = _screen()
	u.open_for("")
	u.get_buy_button().pressed.emit()
	assert_eq(u.get_status_text(), "Store unavailable")
	assert_false(u.get_buy_button().disabled)
	Entitlement.debug_build_override = 1
	BillingFake.next_result = "network"
	u.get_buy_button().pressed.emit()
	assert_string_contains(u.get_status_text(), "Can't reach the store")
	BillingFake.next_result = "cancel"
	u.get_buy_button().pressed.emit()
	assert_string_contains(u.get_status_text(), "not charged")
	assert_false(Entitlement.is_full())


func test_success_celebrates_with_sound_and_swaps_the_layout() -> void:
	var u: UnlockScreen = _screen()
	watch_signals(u)
	u.open_for("")
	u.get_buy_button().pressed.emit()
	assert_true(Entitlement.is_full())
	assert_eq(u.get_title_text(), "FULL GAME UNLOCKED!")
	assert_eq(u.get_status_text(), "Thank you! Everything is unlocked.")
	assert_false(u.get_buy_button().visible)
	assert_false(u.get_restore_button().visible)
	assert_true(_played("ui_purchase"), "AudioDirector.play_ui(\"purchase\")")
	assert_true(u.is_celebrating(), "a starburst")
	assert_signal_emitted(u, "unlocked")
	u.get_close_button().pressed.emit()
	assert_false(u.visible)
	assert_signal_emitted(u, "closed")


func test_reduced_motion_skips_the_starburst_but_not_the_message() -> void:
	ShowSettings.reduce_motion = true
	var u: UnlockScreen = _screen()
	u.open_for("")
	u.get_buy_button().pressed.emit()
	assert_false(u.is_celebrating())
	assert_eq(u.get_title_text(), "FULL GAME UNLOCKED!")


func test_opening_when_already_owned_shows_thanks_without_a_celebration() -> void:
	Entitlement.reset_for_tests(true, CACHE)
	var u: UnlockScreen = _screen()
	u.open_for("")
	assert_eq(u.get_title_text(), "FULL GAME UNLOCKED!")
	assert_eq(u.get_status_text(), "You own the full game. Thank you!")
	assert_false(u.get_buy_button().visible)
	assert_false(u.is_celebrating())
	assert_false(_played("ui_purchase"))


func test_the_buy_button_has_no_tap_sound_of_its_own() -> void:
	var u: UnlockScreen = _screen()
	assert_eq(u.get_buy_button().get_meta("ui_sound"), "none", "the purchase sound plays on success")


func test_restore_on_the_screen_unlocks_when_the_store_knows_the_purchase() -> void:
	Entitlement.debug_build_override = 1
	var fake := BillingFake.new()
	fake.store_owned = true
	Entitlement.set_backend_for_tests(fake)
	var u: UnlockScreen = _screen()
	u.open_for("")
	u.get_restore_button().pressed.emit()
	assert_true(Entitlement.is_full())
	assert_eq(u.get_title_text(), "FULL GAME UNLOCKED!")


func test_closing_disconnects_from_entitlement() -> void:
	var u: UnlockScreen = _screen()
	u.open_for("")
	u.close()
	Entitlement.purchase_full()  # while closed: nothing may happen to the hidden screen
	assert_false(u.visible)
	assert_false(_played("ui_purchase"))


# --- Settings and diagnostics -------------------------------------------------------------------------

func test_settings_has_restore_purchase_which_opens_the_unlock_screen_and_asks_the_store() -> void:
	SettingsStore.path = "user://test_unlock_settings.cfg"
	Entitlement.debug_build_override = 1
	var fake := BillingFake.new()
	fake.store_owned = false
	Entitlement.set_backend_for_tests(fake)
	var s := SettingsOverlay.new()
	add_child_autofree(s)
	s.open()
	assert_eq(s.get_restore_button().text, "Restore purchase")
	assert_false(s.get_restore_button().disabled)
	s.get_restore_button().pressed.emit()
	var u: UnlockScreen = s.get_unlock_screen()
	assert_true(u.visible)
	assert_eq(u.get_status_text(), "No earlier purchase found for this Google account.")
	u.close()
	fake.store_owned = true
	s.get_restore_button().pressed.emit()
	assert_true(Entitlement.is_full())
	u.close()
	assert_eq(s.get_restore_button().text, "Unlocked")
	assert_true(s.get_restore_button().disabled, "nothing left to restore")
	SettingsStore.delete()


func test_the_debug_toggle_lives_behind_the_diagnostics_screen_in_debug_builds_only() -> void:
	var d := DiagnosticsOverlay.new()
	add_child_autofree(d)
	Entitlement.debug_build_override = 1
	d.open()
	var b: Button = d.get_debug_full_button()
	assert_true(b.visible)
	assert_eq(b.text, "Debug: full version OFF")
	b.button_pressed = true
	assert_true(Entitlement.is_full())
	assert_eq(b.text, "Debug: full version ON")
	b.button_pressed = false
	assert_false(Entitlement.is_full())
	Entitlement.debug_build_override = 0
	d.refresh()
	assert_false(b.visible, "release builds never show it")


func test_the_diagnostics_screen_is_the_five_taps_on_the_version_number() -> void:
	SettingsStore.path = "user://test_unlock_settings.cfg"
	Entitlement.debug_build_override = 1
	var s := SettingsOverlay.new()
	add_child_autofree(s)
	s.open()
	for i: int in range(SettingsOverlay.DIAG_TAPS):
		s.tap_version()
	assert_true(s.get_diagnostics().visible)
	assert_true(s.get_diagnostics().get_debug_full_button().visible)
	assert_string_contains(s.get_diagnostics().get_text(), "full game: false")
	SettingsStore.delete()


# --- layout ------------------------------------------------------------------------------------------------

func _buttons(root: Node, out: Array[BaseButton]) -> void:
	for c: Node in root.get_children():
		if c is BaseButton and (c as Control).is_visible_in_tree():
			out.append(c as BaseButton)
		_buttons(c, out)


func _check(u: UnlockScreen, vp: SubViewport, label: String) -> void:
	var vis := Rect2(Vector2.ZERO, Vector2(vp.size))
	var r: Rect2 = u.get_panel().get_global_rect()
	assert_true(vis.encloses(r), "%s: panel %s outside %s" % [label, r, vis])
	assert_true(vis.encloses(u.get_scroll().get_global_rect()), "%s: showcase off screen" % label)
	var btns: Array[BaseButton] = []
	_buttons(u, btns)
	assert_gte(btns.size(), 1)
	for b: BaseButton in btns:
		if u.get_scroll().is_ancestor_of(b):
			continue
		var dp: float = UiScale.canvas_to_dp(minf(b.size.y, b.size.x))
		assert_gte(dp, 47.5, "%s: %s is %.1f dp" % [label, b.name, dp])
		assert_true(vis.encloses(b.get_global_rect()), "%s: button %s off screen %s" % [label, b.name, b.get_global_rect()])
	# Nothing overlaps: BUY above the RESTORE | CLOSE row, the status line above BUY.
	if u.get_buy_button().visible:
		assert_lte(u.get_buy_button().get_global_rect().end.y, u.get_restore_button().get_global_rect().position.y + 1.0, label + ": BUY above RESTORE")
		assert_lte(u.get_restore_button().get_global_rect().end.x, u.get_close_button().get_global_rect().position.x + 1.0, label + ": RESTORE left of CLOSE")


func test_the_screen_fits_every_resolution_text_size_and_state() -> void:
	SettingsStore.path = "user://test_unlock_settings.cfg"
	for size_pct: int in [80, 100, 150]:
		ShowSettings.set_text_size(size_pct)
		for case: Array in CASES:
			var vp: SubViewport = _viewport(case[0], float(case[1]))
			var u := UnlockScreen.new()
			vp.add_child(u)
			for state: String in ["ready", "error", "pending", "owned"]:
				Entitlement.reset_for_tests(state == "owned", CACHE)
				Entitlement.debug_build_override = 1
				match state:
					"error":
						BillingFake.next_result = "network"
					"pending":
						BillingFake.next_result = "pending"
				u.open_for("players")
				if state == "error" or state == "pending":
					u.get_buy_button().pressed.emit()
				await wait_process_frames(8)
				_check(u, vp, "%s @%d%% [%s]" % [case[2], size_pct, state])
				u.close()
			vp.queue_free()
			await wait_process_frames(1)
	SettingsStore.delete()


func test_the_showcase_scrolls_when_the_screen_is_short() -> void:
	ShowSettings.set_text_size(150)
	var vp: SubViewport = _viewport(Vector2(1280, 720), 240.0)
	var u := UnlockScreen.new()
	vp.add_child(u)
	u.open_for("")
	await wait_process_frames(3)
	var content: float = u.get_scroll().get_child(0).get_combined_minimum_size().y
	assert_lt(u.get_scroll().size.y, content, "the list is longer than its window...")
	assert_true(Rect2(Vector2.ZERO, Vector2(vp.size)).encloses(u.get_close_button().get_global_rect()), "...so CLOSE stays on screen")
