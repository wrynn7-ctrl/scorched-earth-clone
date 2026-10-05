extends GutTest
## Player names (ARCHITECTURE section 42): the setup fields, the PLAYER n fallback, remembering the
## names per slot, and long names (12 wide capitals) fitting every screen that shows a label.

const SETUP: String = "res://ui/setup/setup_screen.tscn"
const PREFS_PATH: String = "user://test_names_prefs.cfg"
const W12: String = "WWWWWWWWWWWW"

# [window px, dpi, label]
const CASES: Array = [
	[Vector2(2340, 1080), 500.0, "19.5:9 phone"],
	[Vector2(2340, 1080), 535.0, "narrowest realistic"],
	[Vector2(2560, 1080), 450.0, "21:9 phone"],
	[Vector2(1280, 720), 240.0, "small 16:9"],
	[Vector2(2048, 1536), 264.0, "4:3 tablet"],
	[Vector2(2560, 1600), 280.0, "16:10 tablet"],
]


func before_each() -> void:
	SettingsStore.path = PREFS_PATH
	SettingsStore.delete()
	SetupPrefs.reset()
	PlayerNames.reset()


func after_each() -> void:
	SettingsStore.delete()
	SettingsStore.path = SettingsStore.DEFAULT_PATH
	SetupPrefs.reset()
	UiScale.reset_overrides()
	ShowSettings.reset()
	BattleConfig.reset()
	PlayerLooks.reset()
	PlayerNames.reset()


func _screen() -> SetupScreen:
	var s: SetupScreen = (load(SETUP) as PackedScene).instantiate()
	add_child_autofree(s)
	return s


func _viewport(win: Vector2, dpi: float) -> SubViewport:
	UiScale.dpi_override = dpi
	UiScale.window_px_override = win
	var vis: Vector2 = UiScale.visible_size(win)
	var vp := SubViewport.new()
	vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
	vp.disable_3d = true
	add_child_autofree(vp)
	return vp


# --- PlayerNames ------------------------------------------------------------------------

func test_label_is_the_name_or_player_n() -> void:
	PlayerNames.set_names(PackedStringArray(["anna", "", "  bob   k "]))
	assert_eq(PlayerNames.label(0), "ANNA", "capitals")
	assert_eq(PlayerNames.label(1), "PLAYER 2")
	assert_eq(PlayerNames.label(2), "BOB K", "cleaned")
	assert_eq(PlayerNames.label(5), "PLAYER 6", "a slot without an entry")
	assert_true(PlayerNames.has_custom(0))
	assert_false(PlayerNames.has_custom(1))


func test_blocked_and_empty_names_become_player_n() -> void:
	PlayerNames.set_names(PackedStringArray(["fuck", "   ", "sh1t"]))
	assert_eq(PlayerNames.label(0), "PLAYER 1")
	assert_eq(PlayerNames.label(1), "PLAYER 2")
	assert_eq(PlayerNames.label(2), "PLAYER 3")
	assert_eq(PlayerNames.sanitize("Scunthorpe"), "SCUNTHORPE")
	assert_eq(PlayerNames.sanitize("ABCDEFGHIJKLMNOP"), "ABCDEFGHIJKL")


func test_array_round_trip_and_malformed_input() -> void:
	PlayerNames.set_names(PackedStringArray(["ANNA", "", "BOB"]))
	var saved: Array = PlayerNames.to_array(3)
	assert_eq(saved, ["ANNA", "", "BOB"])
	PlayerNames.reset()
	PlayerNames.from_array(saved)
	assert_eq(PlayerNames.label(2), "BOB")
	for bad: Variant in [null, 5, "ANNA", {"a": 1}, [1, null, 2.5]]:
		PlayerNames.from_array(bad)
		assert_eq(PlayerNames.label(0), "PLAYER 1", "malformed %s means no names" % str(bad))


# --- setup: the name fields -------------------------------------------------------------

func test_every_human_slot_has_a_name_field_and_cpu_slots_do_not() -> void:
	var s: SetupScreen = _screen()
	s.set_players(4)
	await wait_process_frames(2)
	for i: int in range(4):
		assert_true(s.get_name_field(i).visible, "slot %d" % i)
		assert_eq(s.get_name_field(i).placeholder_text, "PLAYER %d" % (i + 1), "the placeholder shows the fallback")
	assert_true(s.set_controller(2, SimConstants.CTRL_HARD))
	assert_false(s.get_name_field(2).visible, "a CPU has no name")
	assert_eq(s.get_kind_button(2).text, "CPU · HARD ▾")
	assert_eq(s.get_kind_button(0).text, "HUMAN ▾")


func test_typing_a_name_keeps_it_clean_and_in_capitals() -> void:
	var s: SetupScreen = _screen()
	await wait_process_frames(1)
	var f: NameField = s.get_name_field(0)
	f.text = "anna  lee x"
	f.text_changed.emit(f.text)
	assert_eq(f.text, "ANNA LEE X")
	f.text = "toolongnameforthis"
	f.text_changed.emit(f.text)
	assert_eq(f.text.length(), NameFilter.MAX_LENGTH)
	f.text = "ab" + String.chr(0x1F600) + "cd"
	f.text_changed.emit(f.text)
	assert_eq(f.text, "ABCD", "emoji never stay in the field")
	f.text = "ANNA "
	f.text_changed.emit(f.text)
	assert_eq(f.text, "ANNA ", "a trailing space survives while typing")


func test_committing_keeps_a_good_name() -> void:
	var s: SetupScreen = _screen()
	assert_eq(s.set_player_name(0, " anna "), "ANNA")
	assert_eq(s.get_name_field(0).text, "ANNA")
	assert_eq(s.get_player_name(0), "ANNA")
	assert_eq(s.get_hint_text(), "")


func test_empty_name_falls_back_to_player_n_without_a_hint() -> void:
	var s: SetupScreen = _screen()
	s.set_player_name(1, "BOB")
	assert_eq(s.set_player_name(1, "   "), "")
	assert_eq(s.get_player_name(1), "PLAYER 2")
	assert_eq(s.get_name_field(1).text, "")
	assert_eq(s.get_hint_text(), "")


func test_blocked_name_falls_back_with_a_hint() -> void:
	var s: SetupScreen = _screen()
	assert_eq(s.set_player_name(1, "sh1thead"), "")
	assert_eq(s.get_player_name(1), "PLAYER 2")
	assert_eq(s.get_name_field(1).text, "", "the field empties so the placeholder shows what is used")
	assert_eq(s.get_hint_text(), "That name isn't allowed. PLAYER 2 is used instead.")
	assert_true(s.get_hint_text() != "")
	# A good name afterwards removes the hint again.
	s.set_player_name(1, "Bob")
	assert_eq(s.get_hint_text(), "")


func test_scunthorpe_style_names_are_accepted() -> void:
	var s: SetupScreen = _screen()
	for n: String in ["Scunthorpe", "Cassie", "Dickens"]:
		assert_eq(s.set_player_name(0, n), n.to_upper(), n)


func test_submit_and_losing_focus_commit() -> void:
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	var f: NameField = s.get_name_field(0)
	f.grab_focus()
	await wait_process_frames(1)
	f.text = "zed"
	f.text_submitted.emit("zed")
	await wait_process_frames(1)
	assert_false(f.has_focus(), "Done on the keyboard ends the edit")
	assert_eq(s.get_player_name(0), "ZED")
	f.grab_focus()
	await wait_process_frames(1)
	f.text = "shit"
	f.release_focus()
	await wait_process_frames(1)
	assert_eq(s.get_player_name(0), "PLAYER 1", "losing focus checks the name too")


func test_a_tap_outside_ends_the_edit() -> void:
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	var f: NameField = s.get_name_field(0)
	f.grab_focus()
	await wait_process_frames(1)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(2.0, 2.0)  # the top-left corner is not the field
	s._input(press)
	assert_false(f.has_focus())


# --- persistence ------------------------------------------------------------------------

func test_names_are_remembered_per_slot_and_restored() -> void:
	var s: SetupScreen = _screen()
	s.set_players(3)
	s.set_player_name(0, "Anna")
	s.set_player_name(2, "Cy")
	s.save_prefs()
	assert_true(FileAccess.file_exists(PREFS_PATH))
	# A fresh process: nothing in memory, only the file.
	SetupPrefs.reset()
	assert_true(SettingsStore.load_into())
	assert_eq(SetupPrefs.names[0], "ANNA")
	assert_eq(SetupPrefs.names[1], "")
	assert_eq(SetupPrefs.names[2], "CY")
	var again: SetupScreen = _screen()
	await wait_process_frames(2)
	assert_eq(again.get_name_field(0).text, "ANNA")
	assert_eq(again.get_name_field(1).text, "")
	assert_eq(again.get_name_field(2).text, "CY")
	assert_eq(again.get_player_name(1), "PLAYER 2")


func test_a_cpu_slot_keeps_its_name_for_when_it_is_human_again() -> void:
	var s: SetupScreen = _screen()
	s.set_player_name(1, "Bob")
	s.set_controller(1, SimConstants.CTRL_NORMAL)
	s.save_prefs()
	SetupPrefs.reset()
	SettingsStore.load_into()
	var again: SetupScreen = _screen()
	assert_eq(again.get_controllers()[1], SimConstants.CTRL_NORMAL)
	assert_eq(again.battle_names(), PackedStringArray(["", ""]), "the battle gets no name for a CPU")
	again.set_controller(1, SimConstants.CTRL_HUMAN)
	assert_eq(again.get_name_field(1).text, "BOB", "the name is back")
	assert_eq(again.battle_names(), PackedStringArray(["", "BOB"]))


func test_a_hand_edited_settings_file_cannot_bring_in_bad_names() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("setup", "players", 4)
	cfg.set_value("setup", "names", ["fuck", "OK", 5, "ABCDEFGHIJKLMNOPQRST" + String.chr(0x1F600), "ninth"])
	assert_eq(cfg.save(PREFS_PATH), OK)
	assert_true(SettingsStore.load_into())
	assert_eq(SetupPrefs.names[0], "", "blocked")
	assert_eq(SetupPrefs.names[1], "OK")
	assert_eq(SetupPrefs.names[2], "", "not a string")
	assert_eq(SetupPrefs.names[3], "ABCDEFGHIJKL", "capped")
	assert_eq(SetupPrefs.names.size(), SetupPrefs.SLOTS)
	cfg.set_value("setup", "names", "not an array")
	assert_eq(cfg.save(PREFS_PATH), OK)
	SetupPrefs.reset()
	assert_true(SettingsStore.load_into())
	assert_eq(SetupPrefs.names[1], "")


func test_a_settings_file_without_names_is_fine() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("setup", "players", 3)
	assert_eq(cfg.save(PREFS_PATH), OK)
	assert_true(SettingsStore.load_into())
	var s: SetupScreen = _screen()
	assert_eq(s.get_player_name(0), "PLAYER 1")


func test_the_battle_gets_the_names_of_the_humans() -> void:
	var s: SetupScreen = _screen()
	s.set_players(3)
	s.set_player_name(0, "Anna")
	s.set_player_name(1, "Bob")
	s.set_controller(1, SimConstants.CTRL_EASY)
	PlayerNames.set_names(s.battle_names())  # what start_match does
	assert_eq(PlayerNames.label(0), "ANNA")
	assert_eq(PlayerNames.label(1), "PLAYER 2", "a CPU keeps PLAYER n")
	assert_eq(PlayerNames.label(2), "PLAYER 3")


# --- touch: the name field and the scrolling list ----------------------------------------

func test_a_press_on_a_name_field_is_a_tap_not_a_scroll() -> void:
	var s: SetupScreen = _screen()
	s.set_players(8)
	s.set_watch(true)
	await wait_process_frames(3)
	var scroll: TouchScroll = s.get_scroll()
	var f: NameField = s.get_name_field(0)
	var at: Vector2 = f.get_global_rect().get_center()
	scroll._on_press(at)
	scroll._on_motion(at + Vector2(0.0, UiScale.dp(60.0)))
	assert_false(scroll.is_dragging(), "a finger that starts on the field never scrolls the list")
	scroll._on_release()
	# A drag that starts on the picker button next to it does scroll.
	var other: Vector2 = s.get_color_button(0).get_global_rect().get_center()
	scroll._on_press(other)
	scroll._on_motion(other + Vector2(0.0, -UiScale.dp(60.0)))
	assert_true(scroll.is_dragging())
	scroll._on_release()


func test_focusing_a_field_scrolls_it_into_view() -> void:
	var s: SetupScreen = _screen()
	s.set_players(8)
	await wait_process_frames(3)
	var f: NameField = s.get_name_field(7)
	f.grab_focus()
	await wait_process_frames(3)
	assert_true(s.get_scroll().get_global_rect().grow(1.5).encloses(f.get_global_rect()), "the field is in the visible part of the list")


# --- layout: 12 wide characters everywhere -------------------------------------------------

func _text_width(c: Control, text: String, font_size: int) -> float:
	return c.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x


func test_setup_rows_fit_with_the_widest_names() -> void:
	for size_pct: int in [100, 150]:
		ShowSettings.set_text_size(size_pct)
		for case: Array in CASES:
			var label: String = "%s @%d%%" % [case[2], size_pct]
			var vp: SubViewport = _viewport(case[0] as Vector2, case[1] as float)
			var vis: Vector2 = Vector2(vp.size)
			var s: SetupScreen = (load(SETUP) as PackedScene).instantiate()
			vp.add_child(s)
			s.set_players(4)
			for i: int in range(4):
				s.set_player_name(i, W12)
			await wait_process_frames(3)
			var bounds := Rect2(Vector2.ZERO, vis).grow(1.5)
			for i: int in range(4):
				var f: NameField = s.get_name_field(i)
				assert_eq(f.text, W12, label)
				var r: Rect2 = f.get_global_rect()
				# The list scrolls, so only the first row has to be fully on screen; every row stays inside it sideways.
				assert_true(r.position.x >= -1.5 and r.end.x <= vis.x + 1.5, "%s: field %d %s inside %s sideways" % [label, i, r, vis])
				if i == 0:
					assert_true(bounds.encloses(r), "%s: field %d %s inside %s" % [label, i, r, vis])
				assert_gte(UiScale.canvas_to_dp(r.size.y), 47.5, "%s: field %d is a 48 dp target" % [label, i])
				assert_true(s.get_player_slot(i).get_global_rect().grow(1.5).encloses(r), "%s: field %d inside its slot" % [label, i])
				var inner: float = r.size.x - 20.0
				var w: float = _text_width(f, W12, f.get_theme_font_size("font_size"))
				assert_lte(w, inner + 0.5, "%s: twelve W (%.0f) fit the field (%.0f)" % [label, w, inner])
				assert_gte(f.get_theme_font_size("font_size"), floori(UiScale.dp(NameField.MIN_FONT_DP)), "%s: text stays legible" % label)
				# The row's other controls are still there and big enough.
				for b: Control in [s.get_color_button(i), s.get_emblem_button(i), s.get_kind_button(i)]:
					var br: Rect2 = b.get_global_rect()
					assert_true(br.position.x >= -1.5 and br.end.x <= vis.x + 1.5, "%s: %s inside the screen sideways" % [label, b.name])
					assert_gte(UiScale.canvas_to_dp(minf(b.size.x, b.size.y)), 47.5, "%s: %s >= 48 dp" % [label, b.name])
			assert_true(bounds.encloses(s.get_start_button().get_global_rect()), "%s: START on screen" % label)
			assert_true(bounds.encloses(s.get_scroll().get_global_rect()), "%s: list on screen" % label)
			vp.queue_free()
			await wait_process_frames(1)


func test_names_sit_in_the_row_on_wide_screens_and_below_on_narrow_ones() -> void:
	var narrow: SubViewport = _viewport(Vector2(2340, 1080), 535.0)
	var a: SetupScreen = (load(SETUP) as PackedScene).instantiate()
	narrow.add_child(a)
	await wait_process_frames(2)
	assert_false(a.names_inline())
	assert_eq(a.get_name_field(0).get_parent(), a.get_name_line(0), "narrow: the name shares the second line with the team chip")
	assert_eq(a.get_name_line(0).get_parent(), a.get_player_slot(0))
	assert_gt(a.get_name_field(0).get_global_rect().position.y, a.get_player_row(0).get_global_rect().end.y - 2.0, "below the row")
	var wide: SubViewport = _viewport(Vector2(2048, 1536), 264.0)
	var b: SetupScreen = (load(SETUP) as PackedScene).instantiate()
	wide.add_child(b)
	await wait_process_frames(2)
	assert_true(b.names_inline())
	assert_eq(b.get_name_field(0).get_parent(), b.get_player_row(0))


func test_handover_titles_fit_with_the_widest_name() -> void:
	for case: Array in CASES:
		var vp: SubViewport = _viewport(case[0] as Vector2, case[1] as float)
		PlayerNames.set_names(PackedStringArray([W12]))
		var h := HandoverScreen.new()
		vp.add_child(h)
		h.show_player(0)
		await wait_process_frames(3)
		assert_eq(h.get_title_text(), "%s — YOUR SHOP" % W12)
		var title: Label = h.find_child("Title", true, false) as Label
		var vis := Rect2(Vector2.ZERO, Vector2(vp.size)).grow(1.5)
		assert_true(vis.encloses(title.get_global_rect()), "%s: hand-over title %s inside %s" % [case[2], title.get_global_rect(), vis])
		vp.queue_free()
		await wait_process_frames(1)


func test_shop_title_fits_with_the_widest_name() -> void:
	for case: Array in CASES:
		var vp: SubViewport = _viewport(case[0] as Vector2, case[1] as float)
		PlayerNames.set_names(PackedStringArray([W12]))
		var m := MatchSettings.new()
		m.num_tanks = 2
		m.seed = 5
		var st: MatchState = Simulation.new_match(m)
		var f := ShopFlow.new()
		vp.add_child(f)
		f.open(st, func(a: Dictionary) -> String: return Simulation.validate_action(st, Simulation.normalize_action(a)))
		await wait_process_frames(2)
		f.get_handover().get_tap_button().pressed.emit()
		await wait_process_frames(3)
		var screen: ShopScreen = f.get_screen()
		assert_eq(screen.get_title_text(), "%s — SHOP" % W12)
		var title: Label = screen.find_child("Title", true, false) as Label
		var w: float = _text_width(title, title.text, title.get_theme_font_size("font_size"))
		assert_lte(w, title.size.x + 0.5, "%s: the shop title (%.0f) is not cut off (%.0f)" % [case[2], w, title.size.x])
		vp.queue_free()
		await wait_process_frames(1)


func test_summary_and_results_fit_with_the_widest_names() -> void:
	for case: Array in CASES:
		var vp: SubViewport = _viewport(case[0] as Vector2, case[1] as float)
		PlayerNames.set_names(PackedStringArray([W12, W12, "ANNA"]))
		var rnd := RoundEndOverlay.new()
		var fin := MatchEndOverlay.new()
		vp.add_child(rnd)
		vp.add_child(fin)
		var rows: Array[Dictionary] = []
		for i: int in range(3):
			rows.append({"id": i, "earned": 12500, "kills": 1, "wins": 3 - i, "damage": 1200 - i * 100, "money": 20000})
		var cpu: Array[Dictionary] = [{"tank": 2, "level": SimConstants.CTRL_HARD, "items": [{"id": "shield", "units": 1}] as Array[Dictionary]}]
		rnd.show_summary(0, rows, 2, 3, cpu)
		var order: Array[int] = [0, 1, 2]
		fin.show_standings(order, rows)
		await wait_process_frames(3)
		assert_eq(rnd.get_title_text(), "%s WINS THE ROUND" % W12)
		assert_eq(fin.get_title_text(), "%s WINS THE MATCH" % W12)
		assert_string_contains(rnd.get_table().get_text(), W12)
		var vis := Rect2(Vector2.ZERO, Vector2(vp.size)).grow(1.5)
		for o: OverlayPanel in [rnd, fin]:
			var panel: Control = o.get_node("Center/Panel")
			assert_true(vis.encloses(panel.get_global_rect()), "%s: %s panel %s inside %s" % [case[2], o.name, panel.get_global_rect(), vis])
			for l: Node in o.find_children("*", "Label", true, false):
				var lab: Label = l as Label
				if lab.is_visible_in_tree() and lab.get_global_rect().size.x > 0.0:
					assert_true(panel.get_global_rect().grow(1.5).encloses(lab.get_global_rect()), "%s: %s label '%s' %s inside panel %s" % [case[2], o.name, lab.text, lab.get_global_rect(), panel.get_global_rect()])
		vp.queue_free()
		await wait_process_frames(1)


func test_the_widest_tag_is_narrower_than_tanks_two_players_apart() -> void:
	# With 8 tanks on a 1600 wide world a tank has ~200 units; a tag is drawn at 1.5x.
	var w: float = TankView.tag_width(W12) * TankView.VISUAL_SCALE
	assert_lt(w, 200.0, "a 12 capital tag (%.0f units) stays inside one of eight lanes" % w)
	var narrow: float = TankView.tag_width("ANNA") * TankView.VISUAL_SCALE
	assert_lt(narrow, w)
