extends GutTest
func test_dbg() -> void:
	UiScale.dpi_override = 535.0
	UiScale.window_px_override = Vector2(2340, 1080)
	var vis: Vector2 = UiScale.visible_size(Vector2(2340, 1080))
	var vp := SubViewport.new()
	vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
	add_child_autofree(vp)
	var studio: SkinStudio = (load("res://ui/skins/skin_studio.tscn") as PackedScene).instantiate()
	vp.add_child(studio)
	studio.open_new()
	studio.get_editor().select_tab(SkinEditor.Tab.COLOURS)
	await wait_process_frames(4)
	var pk: SkinColorPicker = studio.get_editor().get_picker()
	var sc: TouchScroll = studio.get_editor().get_scroll()
	print("DBG vis ", vis, " dp=", UiScale.dp(1.0), " scroll ", sc.size, " picker ", pk.size, " avail ", pk._available_width())
	print("DBG slots ", pk._slot_box.get_combined_minimum_size(), " rows ", pk._controls.get_child(0).get_combined_minimum_size(), " vertical ", pk._top.vertical)
