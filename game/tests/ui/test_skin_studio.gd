extends GutTest
## The Skin Studio screen: layout on every screen shape and text size, the free/full gate on picture
## import, the crop step, saving, duplicating, deleting, USE FOR... and the title button.

const STUDIO: String = "res://ui/skins/skin_studio.tscn"
const DIR: String = "user://test_skins_ui"
const CACHE: String = "user://test_skins_ui_entitlement.cfg"
const PICTURE: String = "user://test_skin_studio_picture.png"

# [window px, dpi, label]
const CASES: Array = [
	[Vector2(2340, 1080), 500.0, "19.5:9 phone"],
	[Vector2(2340, 1080), 535.0, "narrowest realistic"],
	[Vector2(2560, 1080), 450.0, "21:9 phone"],
	[Vector2(3120, 1440), 560.0, "S26 Ultra"],
	[Vector2(2048, 1536), 264.0, "4:3 tablet"],
	[Vector2(2560, 1600), 280.0, "16:10 tablet"],
	[Vector2(1280, 720), 240.0, "small 16:9"],
]


func before_each() -> void:
	SkinStore.dir = DIR
	_wipe()
	Entitlement.reset_for_tests(true, CACHE)
	SettingsStore.path = "user://test_skin_studio_settings.cfg"
	SettingsStore.delete()
	_make_picture(PICTURE)


func after_each() -> void:
	_wipe()
	SkinStore.dir = SkinStore.DEFAULT_DIR
	Entitlement.forget_for_tests()
	SettingsStore.delete()
	SettingsStore.path = SettingsStore.DEFAULT_PATH
	UiScale.reset_overrides()
	ShowSettings.reset()
	BattleConfig.reset()
	if FileAccess.file_exists(PICTURE):
		DirAccess.remove_absolute(PICTURE)
	if FileAccess.file_exists(CACHE):
		DirAccess.remove_absolute(CACHE)


func _wipe() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for f: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + f)
	DirAccess.remove_absolute(DIR)


func _make_picture(path: String) -> void:
	var img: Image = Image.create(320, 200, false, Image.FORMAT_RGBA8)
	for y: int in range(200):
		for x: int in range(320):
			img.set_pixel(x, y, Color.from_hsv(float(x) / 320.0, 0.7, 0.2 + 0.8 * float(y) / 200.0))
	img.save_png(path)


func _skin(id: String, skin_name: String) -> SkinData:
	var s: SkinData = SkinData.make_default(id, skin_name)
	s.decal = 4
	s.pattern = SkinData.Pattern.STRIPES
	return s


func _studio() -> SkinStudio:
	var s: SkinStudio = (load(STUDIO) as PackedScene).instantiate()
	add_child_autofree(s)
	return s


func _studio_in(win: Vector2, dpi: float) -> Dictionary:
	UiScale.dpi_override = dpi
	UiScale.window_px_override = win
	var vis: Vector2 = UiScale.visible_size(win)
	var vp := SubViewport.new()
	vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child_autofree(vp)
	var s: SkinStudio = (load(STUDIO) as PackedScene).instantiate()
	vp.add_child(s)
	await wait_process_frames(3)
	return {"vp": vp, "studio": s, "vis": vis}


# --- layout -------------------------------------------------------------------------------

## Controls under `root`, not descending into scroll areas (their content is clipped on purpose)
## or windows; `buttons` collects every button including those inside scroll areas.
func _collect(root: Node, out: Array[Control], buttons: Array[BaseButton]) -> void:
	for c: Node in root.get_children():
		if c is Window:
			continue
		if c is BaseButton:
			buttons.append(c as BaseButton)
		if c is Control:
			if not (c as Control).is_visible_in_tree():
				continue
			out.append(c as Control)
			if c is ScrollContainer:
				_collect_buttons_only(c, buttons)
				continue
			if c is TankThumb or c is SkinChoice:
				continue
		_collect(c, out, buttons)


func _collect_buttons_only(root: Node, buttons: Array[BaseButton]) -> void:
	for c: Node in root.get_children():
		if c is BaseButton and (c as Control).is_visible_in_tree():
			buttons.append(c as BaseButton)
		_collect_buttons_only(c, buttons)


func _check_page(studio: SkinStudio, vis: Vector2, label: String) -> void:
	var rect := Rect2(Vector2.ZERO, vis).grow(1.5)
	var all: Array[Control] = []
	var buttons: Array[BaseButton] = []
	_collect(studio, all, buttons)
	for c: Control in all:
		if c.get_parent() is ScrollContainer or c is CropOverlay.CropCanvas:
			continue
		assert_true(rect.encloses(c.get_global_rect()), "%s: %s %s outside %s" % [label, c.get_path(), c.get_global_rect(), vis])
	for b: BaseButton in buttons:
		if not b.is_visible_in_tree():
			continue
		var dp: float = UiScale.canvas_to_dp(minf(b.size.x, b.size.y))
		assert_gte(dp, 47.5, "%s: button %s only %.1f dp" % [label, b.get_path(), dp])


func test_layout_fits_every_screen_and_text_size() -> void:
	SkinStore.save_skin(_skin("one", "Viper"))
	SkinStore.save_skin(_skin("two", "A Very Long Skin Name!!"))
	SkinStore.assign(0, "one")
	SkinStore.assign(5, "one")
	for size_pct: int in [100, 150]:
		ShowSettings.set_text_size(size_pct)
		for case: Array in CASES:
			var label: String = "%s @%d%%" % [case[2], size_pct]
			var built: Dictionary = await _studio_in(case[0], float(case[1]))
			var studio: SkinStudio = built["studio"]
			var vis: Vector2 = built["vis"]
			# list page
			assert_eq(studio.get_page(), SkinStudio.Page.LIST)
			assert_eq(studio.get_card_count(), 2)
			_check_page(studio, vis, label + " list")
			assert_true(Rect2(Vector2.ZERO, vis).grow(1.5).encloses(studio.get_list_scroll().get_global_rect()), label + ": list scroll on screen")
			assert_true(Rect2(Vector2.ZERO, vis).grow(1.5).encloses(studio.get_list_back_button().get_global_rect()), label + ": BACK on screen")
			# edit page, every tab
			studio.open_skin("one")
			await wait_process_frames(3)
			for tab: int in range(SkinEditor.Tab.IMAGE + 1):
				studio.get_editor().select_tab(tab)
				await wait_process_frames(2)
				var tl: String = "%s tab %d" % [label, tab]
				_check_page(studio, vis, tl)
				var scroll: Rect2 = studio.get_editor().get_scroll().get_global_rect()
				assert_gte(UiScale.canvas_to_dp(scroll.size.y), 60.0, tl + ": the tab content has room (%.0f dp)" % UiScale.canvas_to_dp(scroll.size.y))
				assert_lte(scroll.end.x, vis.x + 1.5)
				# Tiles wrap inside the scroll area: none sticks out sideways.
				for b: BaseButton in studio.get_editor().get_scroll().find_children("*", "BaseButton", true, false):
					if b.is_visible_in_tree():
						assert_lte(b.get_global_rect().end.x, scroll.end.x + 1.5, "%s: %s sticks out" % [tl, b.name])
				var actions: Rect2 = studio.get_actions().get_global_rect()
				var right: Rect2 = studio.get_right_panel().get_global_rect()
				assert_false(actions.intersects(right.grow(-1.0)), tl + ": the actions row and the controls do not overlap")
			# The preview and the strip keep room beside the controls.
			var pv: Rect2 = studio.get_preview().get_global_rect()
			assert_gte(UiScale.canvas_to_dp(pv.size.y), 80.0, label + ": preview tall enough (%.0f dp)" % UiScale.canvas_to_dp(pv.size.y))
			assert_gte(UiScale.canvas_to_dp(pv.size.x), 80.0, label + ": preview wide enough")
			assert_false(pv.intersects(studio.get_right_panel().get_global_rect()), label + ": preview/controls overlap")
			assert_true(studio.get_strip_button(7).get_global_rect().end.x <= studio.get_right_panel().get_global_rect().position.x + 1.5, label + ": strip left of the controls")
			# overlays
			studio.get_use_for_overlay().open_for("one")
			await wait_process_frames(3)
			_check_overlay(studio.get_use_for_overlay(), vis, label + " use-for")
			studio.get_use_for_overlay().close()
			studio.get_crop_overlay().open_with(Image.create(300, 200, false, Image.FORMAT_RGBA8))
			await wait_process_frames(3)
			_check_crop(studio, vis, label + " crop")
			studio.get_crop_overlay().cancel()
			built["vp"].queue_free()
			await wait_process_frames(1)


func _check_overlay(o: OverlayPanel, vis: Vector2, label: String) -> void:
	var panel: Control = o.get_node("Center/Panel") as Control
	assert_true(Rect2(Vector2.ZERO, vis).grow(1.5).encloses(panel.get_global_rect()), "%s: panel %s outside %s" % [label, panel.get_global_rect(), vis])
	for b: BaseButton in o.find_children("*", "BaseButton", true, false):
		if b.is_visible_in_tree():
			var dp: float = UiScale.canvas_to_dp(minf(b.size.x, b.size.y))
			assert_gte(dp, 47.5, "%s: %s only %.1f dp" % [label, b.name, dp])


func _check_crop(studio: SkinStudio, vis: Vector2, label: String) -> void:
	var c: CropOverlay = studio.get_crop_overlay()
	var rect := Rect2(Vector2.ZERO, vis).grow(1.5)
	assert_true(rect.encloses(c.get_use_button().get_global_rect()), label + ": USE on screen")
	assert_true(rect.encloses(c.get_cancel_button().get_global_rect()), label + ": CANCEL on screen")
	assert_true(rect.encloses(c.get_slider().get_global_rect()), label + ": slider on screen")
	assert_true(rect.encloses(c.get_crop_canvas().get_global_rect()), label + ": picture area on screen")
	assert_gte(UiScale.canvas_to_dp(c.get_crop_canvas().size.y), 60.0, label + ": the picture has room")
	for b: Button in [c.get_use_button(), c.get_cancel_button()]:
		assert_gte(UiScale.canvas_to_dp(minf(b.size.x, b.size.y)), 47.5, label + ": " + b.name)
	assert_gte(UiScale.canvas_to_dp(c.get_slider().size.y), 47.5, label + ": slider >= 48 dp")


# --- the list and the editor flow ---------------------------------------------------------

func test_the_list_shows_a_card_per_skin_and_a_new_card() -> void:
	SkinStore.save_skin(_skin("s1", "Alpha"))
	SkinStore.save_skin(_skin("s2", "Beta"))
	var s: SkinStudio = _studio()
	await wait_process_frames(2)
	assert_eq(s.get_card_count(), 2)
	assert_false(s.get_new_card().disabled)
	assert_true(s.get_card(0).tooltip_text.contains("Alpha"))
	SkinStore.assign(2, "s2")
	s.refresh_list()
	assert_true(s.get_card(1).tooltip_text.contains("P3"), "the card says which player uses the skin")


func test_new_skin_save_duplicate_delete() -> void:
	var s: SkinStudio = _studio()
	await wait_process_frames(2)
	s.open_new()
	assert_eq(s.get_page(), SkinStudio.Page.EDIT)
	assert_true(s.is_new_skin())
	assert_false(s.is_dirty(), "a fresh skin is not 'edited'")
	assert_true(s.get_delete_button().disabled, "nothing to delete before the first save")
	s.get_editor().get_tile(SkinChoice.Kind.HULL, 2).pressed.emit()
	s.get_editor().get_tile(SkinChoice.Kind.DECAL, 6).pressed.emit()
	assert_true(s.is_dirty())
	assert_true(s.save())
	assert_false(s.is_dirty())
	assert_false(s.is_new_skin())
	assert_eq(SkinStore.count(), 1)
	var id: String = s.get_skin().id
	var back: SkinData = SkinStore.load_skin(id)
	assert_eq(back.body_style, 2)
	assert_eq(back.decal, 6)
	assert_false(back.name.is_empty(), "an unnamed skin gets a default name")
	# duplicate
	assert_true(s.duplicate_current())
	assert_eq(SkinStore.count(), 2)
	assert_ne(s.get_skin().id, id)
	assert_eq(s.get_skin().decal, 6)
	# delete asks first
	s.get_delete_button().pressed.emit()
	assert_true(s.get_confirm_overlay().visible)
	(s.get_confirm_overlay().find_child("Confirm", true, false) as Button).pressed.emit()
	assert_eq(SkinStore.count(), 1)
	assert_eq(s.get_page(), SkinStudio.Page.LIST)
	assert_eq(s.get_card_count(), 1)


func test_name_field_edits_the_skin_and_is_limited() -> void:
	var s: SkinStudio = _studio()
	s.open_new()
	s.get_name_field().text = "x".repeat(60)
	assert_lte(s.get_name_field().text.length(), SkinData.NAME_MAX)
	s.get_name_field().text_changed.emit("Neon Viper")
	assert_eq(s.get_skin().name, "Neon Viper")
	assert_true(s.is_dirty())
	assert_true(s.save())
	assert_eq(SkinStore.load_skin(s.get_skin().id).name, "Neon Viper")


func test_back_asks_before_throwing_away_edits() -> void:
	SkinStore.save_skin(_skin("s1", "Alpha"))
	var s: SkinStudio = _studio()
	await wait_process_frames(2)
	s.open_skin("s1")
	s.get_back_button().pressed.emit()
	assert_eq(s.get_page(), SkinStudio.Page.LIST, "no edits: straight back")
	s.open_skin("s1")
	s.get_editor().get_glow_slider().set_value(10.0)
	assert_true(s.is_dirty())
	s.get_back_button().pressed.emit()
	assert_eq(s.get_page(), SkinStudio.Page.EDIT, "edits: asks first")
	assert_true(s.get_confirm_overlay().visible)
	(s.get_confirm_overlay().find_child("Cancel", true, false) as Button).pressed.emit()
	assert_eq(s.get_page(), SkinStudio.Page.EDIT)
	assert_eq(SkinStore.load_skin("s1").glow, 50, "nothing was saved")
	s.get_back_button().pressed.emit()
	(s.get_confirm_overlay().find_child("Confirm", true, false) as Button).pressed.emit()
	assert_eq(s.get_page(), SkinStudio.Page.LIST)
	assert_eq(SkinStore.load_skin("s1").glow, 50)


func test_edits_in_every_tab_change_the_skin() -> void:
	var s: SkinStudio = _studio()
	s.open_new()
	var e: SkinEditor = s.get_editor()
	e.get_tile(SkinChoice.Kind.HULL, 3).pressed.emit()
	e.get_tile(SkinChoice.Kind.TURRET, 1).pressed.emit()
	e.get_tile(SkinChoice.Kind.PATTERN, 4).pressed.emit()
	e.get_tile(SkinChoice.Kind.DECAL, 9).pressed.emit()
	e.get_glow_slider().set_value(77.0)
	var sk: SkinData = s.get_skin()
	assert_eq([sk.body_style, sk.turret_style, sk.pattern, sk.decal, sk.glow], [3, 1, 4, 9, 77])
	# colours: base, accent and pattern each have their own slot
	e.get_picker().get_swatch(1).pressed.emit()
	assert_eq(sk.base.to_html(false), SkinColorPicker.PRESETS[1].to_html(false))
	e.get_slot_tile(1).pressed.emit()
	e.get_picker().get_swatch(4).pressed.emit()
	assert_eq(sk.accent.to_html(false), SkinColorPicker.PRESETS[4].to_html(false))
	e.get_slot_tile(2).pressed.emit()
	e.get_picker().get_slider(0).set_value(0.5)
	assert_ne(sk.pattern_color.to_html(false), SkinData.DEFAULT_PATTERN_COLOR.to_html(false))
	assert_eq(sk.base.to_html(false), SkinColorPicker.PRESETS[1].to_html(false), "other slots are untouched")
	assert_eq(e.get_picker().get_hex_text(), "#" + sk.pattern_color.to_html(false).to_upper())


func test_the_preview_shows_each_player_colour() -> void:
	var s: SkinStudio = _studio()
	s.open_new()
	var view: TankView = s.get_preview().get_view()
	assert_eq(view.get_color_index(), 0)
	s.get_strip_button(5).pressed.emit()
	assert_eq(s.get_preview_player(), 5)
	assert_eq(view.get_color_index(), 5)
	assert_eq(view.get_emblem_index(), 5)
	assert_eq(view.outline_color(), NeonPalette.tank_color(5), "the outline is the player colour")
	assert_true(s.get_preview_caption().text.contains("6"), "the caption names the player: colour is not the only cue")
	for i: int in range(8):
		assert_eq(s.get_strip_thumb(i).get_view().outline_color(), NeonPalette.tank_color(i))
		assert_true(s.get_strip_thumb(i).get_view().has_skin(), "the strip shows the skin in every colour")
	# Tapping the preview cycles to the next colour.
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	s.get_preview().gui_input.emit(ev)
	assert_eq(s.get_preview_player(), 6)


func test_preview_turret_sweeps_and_glow_pulses_unless_reduced() -> void:
	var s: SkinStudio = _studio()
	s.open_new()
	var p: TankThumb = s.get_preview()
	var a0: int = p.get_view().get_angle_tenths()
	p._process(1.0)
	assert_ne(p.get_view().get_angle_tenths(), a0, "the turret sweeps")
	ShowSettings.reduce_motion = true
	p._process(1.0)
	assert_eq(p.get_view().get_angle_tenths(), 1050, "reduced motion: it holds still")
	assert_eq((p.get_view().get_node("SkinGlow") as Node2D).modulate.a, 1.0)


# --- USE FOR ------------------------------------------------------------------------------

func test_use_for_assigns_player_slots_and_persists() -> void:
	var s: SkinStudio = _studio()
	s.open_new()
	s.get_editor().get_tile(SkinChoice.Kind.DECAL, 2).pressed.emit()
	s.get_use_for_button().pressed.emit()
	assert_false(s.is_new_skin(), "USE FOR saves the skin first")
	assert_eq(SkinStore.count(), 1)
	var o: UseForOverlay = s.get_use_for_overlay()
	assert_true(o.visible)
	var id: String = s.get_skin().id
	o.get_tile(0).pressed.emit()
	o.get_tile(2).pressed.emit()
	assert_eq(SkinStore.assigned_id(0), id)
	assert_eq(SkinStore.assigned_id(2), id)
	assert_eq(SkinStore.assigned_id(1), "")
	assert_true(o.get_tile(0).button_pressed)
	assert_true(o.get_tile(0).text.contains(tr("SKIN_USE_THIS")), "the state is spelled out in words")
	assert_true(o.get_tile(1).text.contains(tr("SKIN_USE_DEFAULT")))
	o.get_tile(0).pressed.emit()
	assert_eq(SkinStore.assigned_id(0), "", "pressing again gives the slot back")
	# another skin already on a slot shows as "another skin" and can be taken over
	SkinStore.save_skin(_skin("other", "Other"))
	SkinStore.assign(4, "other")
	o.open_for(id)
	assert_true(o.get_tile(4).text.contains(tr("SKIN_USE_OTHER")))
	o.get_tile(4).pressed.emit()
	assert_eq(SkinStore.assigned_id(4), id)
	o.get_done_button().pressed.emit()
	assert_false(o.visible)


# --- picture import: the free/full gate ---------------------------------------------------

func test_free_players_see_the_lock_and_cannot_import() -> void:
	Entitlement.reset_for_tests(false, CACHE)
	var s: SkinStudio = _studio()
	s.pick_override = func() -> String: return PICTURE
	s.open_new()
	var e: SkinEditor = s.get_editor()
	assert_true(e.is_import_locked())
	assert_true(e.is_lock_shown(), "the IMAGE tab carries a lock")
	assert_true(LockBadge.of(e.get_import_button()).visible, "so does the import button")
	assert_true(e.get_import_button().text.contains(tr("SKIN_IMAGE_FULL")), "and says FULL GAME in words")
	e.get_tab_button(SkinEditor.Tab.IMAGE).pressed.emit()
	assert_eq(e.get_tab(), SkinEditor.Tab.IMAGE, "the tab can be opened and shows what the full game adds")
	assert_false(s.get_unlock_screen().visible)
	e.get_import_button().pressed.emit()
	assert_true(s.get_unlock_screen().visible, "tapping import opens the Unlock screen")
	assert_eq(s.picker_opens, 0, "the file picker never opened")
	assert_false(s.get_crop_overlay().visible)
	assert_false(s.request_import(), "direct calls are refused too")
	assert_eq(s.picker_opens, 0)
	assert_null(s.get_skin().image)


func test_full_players_can_import_crop_and_save_a_picture() -> void:
	var s: SkinStudio = _studio()
	s.pick_override = func() -> String: return PICTURE
	s.open_new()
	var e: SkinEditor = s.get_editor()
	assert_false(e.is_import_locked())
	assert_false(e.is_lock_shown())
	e.get_tab_button(SkinEditor.Tab.IMAGE).pressed.emit()
	e.get_import_button().pressed.emit()
	assert_eq(s.picker_opens, 1)
	assert_false(s.get_unlock_screen().visible)
	var crop: CropOverlay = s.get_crop_overlay()
	assert_true(crop.visible, "the crop step opens after picking")
	crop.set_zoom(2.0)
	crop.move_by(Vector2(-1000, -1000))
	var r: Rect2 = crop.get_crop_rect()
	assert_eq(r.position, Vector2.ZERO, "dragging to the corner puts the box in the corner")
	assert_true(crop.get_use_button().is_visible_in_tree())
	crop.get_use_button().pressed.emit()
	assert_false(crop.visible)
	var img: Image = s.get_skin().image
	assert_not_null(img)
	assert_eq(img.get_size(), Vector2i(128, 64))
	assert_eq(SkinImage.tone_count(img) <= SkinImage.TONES, true)
	assert_true(s.is_dirty())
	assert_true(e.get_remove_button().visible)
	assert_true(s.save())
	var id: String = s.get_skin().id
	assert_true(FileAccess.file_exists(DIR + "/" + id + ".png"), "the PNG sits next to the skin file")
	assert_eq(SkinStore.load_skin(id).image.get_size(), Vector2i(128, 64))
	# the private note is on the tab
	assert_eq(e.get_note_text(), tr("SKIN_IMAGE_NOTE"))
	assert_eq(e.get_note_text(), "Only you can see your skins.")
	# removing the picture
	e.get_remove_button().pressed.emit()
	assert_null(s.get_skin().image)
	assert_true(s.save())
	assert_false(FileAccess.file_exists(DIR + "/" + id + ".png"))


func test_cancel_in_the_crop_step_and_in_the_file_dialog_change_nothing() -> void:
	var s: SkinStudio = _studio()
	s.open_new()
	s.pick_override = func() -> String: return ""
	assert_true(s.request_import())
	assert_false(s.get_crop_overlay().visible, "a cancelled dialog opens nothing")
	assert_null(s.get_skin().image)
	s.pick_override = func() -> String: return PICTURE
	s.request_import()
	assert_true(s.get_crop_overlay().visible)
	s.get_crop_overlay().get_cancel_button().pressed.emit()
	assert_false(s.get_crop_overlay().visible)
	assert_null(s.get_skin().image)
	assert_false(s.is_dirty())


func test_an_unreadable_file_gives_a_message_not_a_crash() -> void:
	var s: SkinStudio = _studio()
	s.open_new()
	var bad: String = "user://test_skin_studio_bad.png"
	var f: FileAccess = FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("definitely not a picture")
	f.close()
	for path: String in [bad, "user://does_not_exist.png", "/nonexistent/dir/x.jpg"]:
		s.pick_override = func() -> String: return path
		assert_true(s.request_import())
		assert_false(s.get_crop_overlay().visible, path)
		assert_eq(s.get_toast().get_text(), tr("SKIN_IMAGE_ERROR"), path)
		assert_null(s.get_skin().image)
	DirAccess.remove_absolute(bad)


func test_buying_the_full_game_unlocks_the_tab_live() -> void:
	Entitlement.reset_for_tests(false, CACHE)
	var s: SkinStudio = _studio()
	s.open_new()
	assert_true(s.get_editor().is_import_locked())
	Entitlement.debug_build_override = 1
	Entitlement.set_debug_full(true)  # the same hub signal a purchase or a restore fires
	assert_false(s.get_editor().is_import_locked())
	assert_false(s.get_editor().is_lock_shown())


func test_the_cap_disables_new_skins() -> void:
	for i: int in range(SkinStore.MAX_SKINS):
		SkinStore.save_skin(_skin("s%03d" % i, "S%d" % i))
	var s: SkinStudio = _studio()
	await wait_process_frames(2)
	assert_eq(s.get_card_count(), 50)
	assert_true(s.get_new_card().disabled)
	s.open_new()
	assert_eq(s.get_page(), SkinStudio.Page.LIST, "no editor for a 51st skin")
	s.open_skin("s000")
	assert_true(s.get_duplicate_button().disabled)


# --- the title button ---------------------------------------------------------------------

func test_the_title_has_a_skins_button_that_opens_the_studio() -> void:
	var t: TitleScreen = (load("res://ui/title/title_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(t)
	await wait_process_frames(2)
	var b: Button = t.get_skins_button()
	assert_not_null(b)
	assert_true(b.visible)
	assert_eq(b.text, tr("TITLE_SKINS"))
	b.pressed.emit()
	await wait_process_frames(3)
	var cur: Node = get_tree().current_scene
	assert_true(cur is SkinStudio, "SKINS opens the studio")
	if cur != null:
		cur.queue_free()
		await wait_process_frames(2)


# --- preview framing ----------------------------------------------------------------------

## The geometry TankThumb.BOX has to cover, in tank units: every hull and turret style (the turret turned through
## 0..180 degrees round its pivot), the glow beyond the outline and the emblem marker.
func test_preview_box_covers_every_hull_turret_and_the_emblem() -> void:
	var box: Rect2 = TankThumb.BOX
	for style: int in range(SkinData.BODY_STYLES):
		for p: Vector2 in SkinShapes.hull(style):
			assert_true(box.grow(-5.0).has_point(p), "hull %d point %s keeps room for the glow" % [style, p])
	var pivot := Vector2(0.0, -TankView.TANK_H)
	for style: int in range(SkinData.TURRET_STYLES):
		for poly: PackedVector2Array in SkinShapes.turret_polys(style):
			for p: Vector2 in poly:
				for deg: int in range(0, 181, 5):
					var q: Vector2 = pivot + Vector2(p.x, -p.y).rotated(-deg_to_rad(float(deg)))
					assert_true(box.has_point(q), "turret %d point %s at %d deg" % [style, p, deg])
	assert_true(box.has_point(Vector2(0.0, TankView.COMPACT_MARKER_Y - 5.5)), "emblem marker")


func test_preview_fits_whole_tank_with_a_margin_at_every_resolution() -> void:
	for case: Array in [[Vector2(3120, 1440), 560.0], [Vector2(2340, 1080), 535.0], [Vector2(2560, 1080), 450.0],
			[Vector2(1280, 720), 240.0], [Vector2(2048, 1536), 264.0], [Vector2(2560, 1600), 280.0]]:
		UiScale.dpi_override = case[1]
		UiScale.window_px_override = case[0]
		var vis: Vector2 = UiScale.visible_size(case[0])
		var vp := SubViewport.new()
		vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
		vp.disable_3d = true
		add_child_autofree(vp)
		var studio: SkinStudio = (load("res://ui/skins/skin_studio.tscn") as PackedScene).instantiate()
		vp.add_child(studio)
		studio.open_new()
		await wait_process_frames(3)
		var preview: TankThumb = studio.get_preview()
		var r := Rect2(Vector2.ZERO, preview.size)
		var box: Rect2 = preview.tank_box()
		var label: String = "%s dpi %d" % [str(case[0]), int(case[1])]
		assert_true(r.encloses(box), "%s: tank box %s inside the preview %s" % [label, box, r])
		var mx: float = minf(box.position.x, r.size.x - box.end.x) / r.size.x
		var my: float = minf(box.position.y, r.size.y - box.end.y) / r.size.y
		assert_gte(maxf(mx, my), 0.045, "%s: a margin on the limiting side (~10%% total)" % label)
		assert_almost_eq(box.get_center().x, r.get_center().x, 1.0, "%s: centred across" % label)
		assert_almost_eq(box.get_center().y, r.get_center().y, 1.0, "%s: centred up/down" % label)
		vp.queue_free()
		await wait_process_frames(1)
		UiScale.reset_overrides()


# --- the COLOURS tab on phones ------------------------------------------------------------

## [window px, dpi, label, must fit without scrolling]
const COLOUR_TAB_CASES: Array = [
	[Vector2(3120, 1440), 560.0, "19.5:9 (S26 Ultra)", true],
	[Vector2(3360, 1440), 450.0, "21:9", true],
	[Vector2(1600, 900), 320.0, "16:9 800 dp", true],
	[Vector2(2048, 1536), 264.0, "4:3 tablet", true],
	[Vector2(2560, 1600), 280.0, "16:10 tablet", true],
	[Vector2(2340, 1080), 535.0, "narrowest phone (~700 dp): may scroll", false],
]


func test_colour_tab_fits_without_scrolling_where_there_is_room() -> void:
	for case: Array in COLOUR_TAB_CASES:
		UiScale.dpi_override = case[1]
		UiScale.window_px_override = case[0]
		var vis: Vector2 = UiScale.visible_size(case[0])
		var vp := SubViewport.new()
		vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
		vp.disable_3d = true
		add_child_autofree(vp)
		var studio: SkinStudio = (load("res://ui/skins/skin_studio.tscn") as PackedScene).instantiate()
		vp.add_child(studio)
		studio.open_new()
		var editor: SkinEditor = studio.get_editor()
		editor.select_tab(SkinEditor.Tab.COLOURS)
		await wait_process_frames(4)
		var scroll: TouchScroll = editor.get_scroll()
		var content: float = editor.get_picker().get_combined_minimum_size().y
		var label: String = str(case[2])
		if case[3]:
			assert_lte(content, scroll.size.y + 1.0, "%s: the colour tab needs %.0f of %.0f px" % [label, content, scroll.size.y])
		# Always: nothing sticks out sideways and every control is a real touch target.
		var picker: SkinColorPicker = editor.get_picker()
		for i: int in range(3):
			var sl: Rect2 = picker.get_slider(i).get_global_rect()
			assert_gte(UiScale.canvas_to_dp(sl.size.y), 47.5, "%s: slider %d >= 48 dp" % [label, i])
			assert_lte(sl.end.x, editor.get_global_rect().end.x + 1.0, "%s: slider %d inside the panel" % [label, i])
		for i: int in range(3):
			assert_gte(UiScale.canvas_to_dp(editor.get_slot_tile(i).size.y), 47.5, "%s: slot chip %d >= 48 dp" % [label, i])
		assert_almost_eq(picker.get_slider(0).get_global_rect().position.x, picker.get_slider(1).get_global_rect().position.x, 1.5,
				"%s: the three sliders line up" % label)
		vp.queue_free()
		await wait_process_frames(1)
		UiScale.reset_overrides()
