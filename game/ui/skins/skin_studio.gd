class_name SkinStudio
extends Control
## The Skin Studio (title -> SKINS): design your own tank look. Everything here is private to
## this device (docs/ARCHITECTURE.md section 35): skins live in user://skins, nothing is uploaded, and
## the player identity (outline, emblem, tag) is drawn on top of any skin by TankView.
##
## Two pages in one screen:
##  - LIST: cards for every saved skin plus NEW SKIN (up to SkinStore.MAX_SKINS), BACK to the title.
##  - EDIT: left a live preview (turret sweeping, glow pulsing, tap to try the next player colour)
##    with the name field and a strip of the skin in all eight player colours; right the tabbed
##    controls (SkinEditor); along the bottom SAVE, USE FOR..., DUPLICATE, DELETE and BACK.
##
## Picture import (IMAGE tab) is the full version's: free players see the tab with a lock and the
## Unlock screen opens. After picking a file the crop step runs, then the neon filter shrinks it to
## 128x64 and it is saved next to the skin file.

const TITLE_SCENE: String = "res://ui/title/title_screen.tscn"
const THEME: Theme = preload("res://ui/theme/neon_theme.tres")
const PREVIEW_PPU: int = 8
const CARD_PPU: int = 3
const STRIP_PPU: int = 2

enum Page { LIST, EDIT }

## Test/debug hook: a Callable returning the picked file path ("" = cancelled) that replaces the
## system file dialog.
var pick_override: Callable = Callable()
## Counts how often the file dialog (or the override) was opened, for tests.
var picker_opens: int = 0

var _page: int = Page.LIST
var _skin: SkinData = null
var _is_new: bool = false
var _saved_sig: String = ""
var _preview_player: int = 0
var _confirm_action: String = ""
var _file_dialog: FileDialog = null

var _sky: NeonSky = null
var _margin: MarginContainer = null
var _stack: Control = null

# list page
var _list_page: VBoxContainer = null
var _list_title: Label = null
var _list_count: Label = null
var _list_note: Label = null
var _list_scroll: TouchScroll = null
var _cards: GridContainer = null
var _new_card: Button = null
var _card_buttons: Array[Button] = []
var _list_back: Button = null

# edit page
var _edit_page: VBoxContainer = null
var _columns: HBoxContainer = null
var _left: HBoxContainer = null
var _left_col: VBoxContainer = null
var _name_field: LineEdit = null
var _preview: TankThumb = null
var _preview_caption: Label = null
var _strip: GridContainer = null
var _strip_buttons: Array[Button] = []
var _strip_thumbs: Array[TankThumb] = []
var _right: PanelContainer = null
var _editor: SkinEditor = null
var _actions: HBoxContainer = null
var _save: Button = null
var _use_for_button: Button = null
var _duplicate: Button = null
var _delete: Button = null
var _back: Button = null

# overlays
var _toast: Toast = null
var _confirm: ConfirmOverlay = null
var _use_for: UseForOverlay = null
var _crop: CropOverlay = null
var _unlock: UnlockScreen = null


func _init() -> void:
	ShotArgs.parse()
	SettingsStore.ensure_loaded()
	_apply_entitlement_args()
	theme = THEME
	name = "SkinStudio"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	apply_scale()
	LayoutWatch.attach(self, apply_scale)
	Entitlement.hub().changed.connect(_on_entitlement_changed)
	_set_preview_player(0)
	refresh_list()
	_show_page(Page.LIST)
	ShotHook.attach(self)
	_run_debug_args.call_deferred()


func _exit_tree() -> void:
	var hub: Entitlement.Hub = Entitlement.hub()
	if hub.changed.is_connected(_on_entitlement_changed):
		hub.changed.disconnect(_on_entitlement_changed)


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if _unlock.visible:
		_unlock.close()
	elif _crop.visible:
		_crop.cancel()
	elif _use_for.visible:
		_use_for.close()
	elif _confirm.visible:
		_confirm.close()
	else:
		go_back()


# ======================================================================================
# Build
# ======================================================================================

func _build() -> void:
	_sky = (load("res://show/sky.tscn") as PackedScene).instantiate()
	add_child(_sky)
	_margin = MarginContainer.new()
	_margin.name = "Margin"
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	_stack = Control.new()
	_stack.name = "Stack"
	_margin.add_child(_stack)
	_build_list_page()
	_build_edit_page()
	_toast = Toast.new()
	_toast.name = "Toast"
	add_child(_toast)
	_confirm = ConfirmOverlay.new()
	_confirm.confirmed.connect(_on_confirmed)
	add_child(_confirm)
	_use_for = UseForOverlay.new()
	_use_for.changed.connect(_on_assignments_changed)
	add_child(_use_for)
	_crop = CropOverlay.new()
	_crop.confirmed.connect(_on_crop_confirmed)
	add_child(_crop)
	_unlock = UnlockScreen.new()
	_unlock.closed.connect(_on_entitlement_changed)
	add_child(_unlock)


func _build_list_page() -> void:
	_list_page = VBoxContainer.new()
	_list_page.name = "ListPage"
	_list_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stack.add_child(_list_page)
	var header := HBoxContainer.new()
	header.name = "Header"
	_list_page.add_child(header)
	_list_title = Label.new()
	_list_title.name = "Title"
	_list_title.text = tr("SKIN_TITLE")
	_list_title.add_theme_color_override("font_color", NeonPalette.CYAN)
	_list_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_list_title)
	_list_count = Label.new()
	_list_count.name = "Count"
	_list_count.add_theme_color_override("font_color", NeonPalette.TEXT_DIM)
	header.add_child(_list_count)
	_list_note = Label.new()
	_list_note.name = "PrivateNote"
	_list_note.text = tr("SKIN_PRIVATE")
	_list_note.add_theme_color_override("font_color", NeonPalette.GOOD)
	_list_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_list_page.add_child(_list_note)
	_list_scroll = TouchScroll.new()
	_list_scroll.name = "Scroll"
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_page.add_child(_list_scroll)
	_cards = GridContainer.new()
	_cards.name = "Cards"
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(_cards)
	_new_card = Button.new()
	_new_card.name = "NewCard"
	_new_card.focus_mode = Control.FOCUS_NONE
	_new_card.pressed.connect(open_new)
	_cards.add_child(_new_card)
	_list_back = Button.new()
	_list_back.name = "Back"
	_list_back.text = tr("SKIN_BACK")
	_list_back.focus_mode = Control.FOCUS_NONE
	_list_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_list_back.pressed.connect(go_back)
	_list_page.add_child(_list_back)
	_list_scroll.resized.connect(_update_card_columns)


func _build_edit_page() -> void:
	_edit_page = VBoxContainer.new()
	_edit_page.name = "EditPage"
	_edit_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stack.add_child(_edit_page)
	_columns = HBoxContainer.new()
	_columns.name = "Columns"
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_edit_page.add_child(_columns)
	# Left: the name and the big preview, with the eight-colour strip beside it.
	_left = HBoxContainer.new()
	_left.name = "Left"
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left.size_flags_stretch_ratio = 0.38
	_columns.add_child(_left)
	_left_col = VBoxContainer.new()
	_left_col.name = "PreviewColumn"
	_left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left.add_child(_left_col)
	_name_field = LineEdit.new()
	_name_field.name = "NameField"
	_name_field.max_length = SkinData.NAME_MAX
	_name_field.placeholder_text = tr("SKIN_NAME_HINT")
	_name_field.select_all_on_focus = true
	_name_field.text_changed.connect(_on_name_changed)
	_style_line_edit(_name_field)
	_left_col.add_child(_name_field)
	_preview = TankThumb.new()
	_preview.name = "Preview"
	_preview.backdrop = true
	_preview.set_bake_ppu(PREVIEW_PPU)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview.tooltip_text = tr("SKIN_PREVIEW_HINT")
	_preview.gui_input.connect(_on_preview_input)
	_preview.baked.connect(_on_preview_baked)
	_preview.set_animated(true)
	_left_col.add_child(_preview)
	_preview_caption = Label.new()
	_preview_caption.name = "Caption"
	_preview_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_preview_caption.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(NeonPalette.BG_DEEP, 0.75)
	plate.set_corner_radius_all(6)
	plate.content_margin_left = 6.0
	plate.content_margin_right = 6.0
	_preview_caption.add_theme_stylebox_override("normal", plate)
	_preview.add_child(_preview_caption)
	_strip = GridContainer.new()
	_strip.name = "Strip"
	_strip.columns = 2
	_left.add_child(_strip)
	var group := ButtonGroup.new()
	for i: int in range(NeonPalette.TANK_COLORS.size()):
		var b := Button.new()
		b.name = "Strip%d" % i
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = tr(NeonPalette.TANK_COLOR_NAME_KEYS[i])
		b.pressed.connect(_set_preview_player.bind(i))
		var t := TankThumb.new()
		t.name = "Thumb"
		t.set_bake_ppu(STRIP_PPU)
		t.set_player(i, i)
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		t.offset_left = 2.0
		t.offset_right = -2.0
		t.offset_top = 2.0
		t.offset_bottom = -2.0
		b.add_child(t)
		_strip.add_child(b)
		_strip_buttons.append(b)
		_strip_thumbs.append(t)
	# Right: the tabs in a neon panel.
	_right = PanelContainer.new()
	_right.name = "RightPanel"
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.size_flags_stretch_ratio = 0.62
	_columns.add_child(_right)
	_editor = SkinEditor.new()
	_editor.changed.connect(_on_edited)
	_editor.import_requested.connect(request_import)
	_editor.locked_tapped.connect(_open_unlock)
	_editor.remove_image_requested.connect(remove_image)
	_right.add_child(_editor)
	# Bottom: the actions.
	_actions = HBoxContainer.new()
	_actions.name = "Actions"
	_edit_page.add_child(_actions)
	_save = _action("Save", "SKIN_SAVE", save)
	_save.theme_type_variation = &"FireButton"
	_use_for_button = _action("UseFor", "SKIN_USE_FOR", open_use_for)
	_duplicate = _action("Duplicate", "SKIN_DUPLICATE", duplicate_current)
	_delete = _action("Delete", "SKIN_DELETE", ask_delete)
	_back = _action("Back", "SKIN_BACK", go_back)


func _action(node_name: String, key: String, handler: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = tr(key)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(handler)
	_actions.add_child(b)
	return b


func _style_line_edit(le: LineEdit) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(NeonPalette.BG_DEEP, 0.9)
	normal.border_color = Color(NeonPalette.CYAN, 0.7)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(10)
	normal.content_margin_left = 10.0
	normal.content_margin_right = 10.0
	normal.content_margin_top = 4.0
	normal.content_margin_bottom = 4.0
	le.add_theme_stylebox_override("normal", normal)
	var focus: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	focus.border_color = NeonPalette.HOT
	le.add_theme_stylebox_override("focus", focus)
	le.add_theme_color_override("font_color", NeonPalette.TEXT)
	le.add_theme_color_override("font_placeholder_color", NeonPalette.TEXT_DIM)
	le.add_theme_color_override("caret_color", NeonPalette.HOT)
	le.add_theme_color_override("selection_color", Color(NeonPalette.CYAN, 0.35))


# ======================================================================================
# Scale
# ======================================================================================

func apply_scale() -> void:
	UiScale.apply_edge_margins(_margin)
	var touch: float = UiScale.touch()
	var gap: int = roundi(UiScale.dp(8.0))
	# list page
	_list_page.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	_list_title.add_theme_font_size_override("font_size", UiScale.font(22.0))
	_list_count.add_theme_font_size_override("font_size", UiScale.font(14.0))
	_list_note.add_theme_font_size_override("font_size", UiScale.font(13.0))
	_cards.add_theme_constant_override("h_separation", gap)
	_cards.add_theme_constant_override("v_separation", gap)
	_list_back.custom_minimum_size = Vector2(UiScale.dp(120.0), touch)
	_list_back.add_theme_font_size_override("font_size", UiScale.font(14.0))
	_update_card_sizes()
	_update_card_columns()
	# edit page
	_edit_page.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	_columns.add_theme_constant_override("separation", gap)
	_left.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	_left_col.add_theme_constant_override("separation", roundi(UiScale.dp(4.0)))
	_strip.add_theme_constant_override("h_separation", roundi(UiScale.dp(4.0)))
	_strip.add_theme_constant_override("v_separation", roundi(UiScale.dp(4.0)))
	_actions.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	_name_field.custom_minimum_size = Vector2(UiScale.dp(80.0), touch)
	_name_field.add_theme_font_size_override("font_size", UiScale.font(14.0))
	_preview.custom_minimum_size = Vector2(UiScale.dp(100.0), UiScale.dp(70.0))
	_preview_caption.add_theme_font_size_override("font_size", UiScale.font(10.0))
	_preview_caption.offset_left = UiScale.dp(4.0)
	_preview_caption.offset_bottom = -UiScale.dp(4.0)
	for b: Button in _strip_buttons:
		b.custom_minimum_size = Vector2.ONE * touch
	for b: Button in [_save, _use_for_button, _duplicate, _delete, _back]:
		b.custom_minimum_size = Vector2(UiScale.dp(52.0), touch)
		b.add_theme_font_size_override("font_size", UiScale.font(12.0))
	_save.add_theme_font_size_override("font_size", UiScale.font(14.0))
	_editor.apply_scale()


func _update_card_sizes() -> void:
	for b: Button in _card_buttons:
		b.custom_minimum_size = Vector2(UiScale.dp(132.0), UiScale.dp(76.0) + UiScale.line_h(12.0) * 2.0)
		for l: Label in b.find_children("*", "Label", true, false):
			l.add_theme_font_size_override("font_size", UiScale.font(12.0))
	_new_card.custom_minimum_size = _card_size()
	_new_card.add_theme_font_size_override("font_size", UiScale.font(14.0))


func _card_size() -> Vector2:
	return Vector2(UiScale.dp(132.0), UiScale.dp(76.0) + UiScale.line_h(12.0) * 2.0)


func _update_card_columns() -> void:
	if _cards == null or _list_scroll == null:
		return
	var cell: float = UiScale.dp(132.0) + UiScale.dp(8.0)
	_cards.columns = maxi(1, int((_list_scroll.size.x - UiScale.dp(30.0)) / cell))


# ======================================================================================
# Pages
# ======================================================================================

func get_page() -> int:
	return _page


func _show_page(p: int) -> void:
	_page = p
	_list_page.visible = p == Page.LIST
	_edit_page.visible = p == Page.EDIT
	Transition.fade_in(_stack)
	if p == Page.EDIT:
		_preview.flush()


## Rebuilds the cards from what is on disk.
func refresh_list() -> void:
	for b: Button in _card_buttons:
		_cards.remove_child(b)
		b.queue_free()
	_card_buttons.clear()
	var skins: Array[SkinData] = SkinStore.list_skins(true)
	var at_limit: bool = skins.size() >= SkinStore.MAX_SKINS
	_new_card.text = ("+  " + tr("SKIN_NEW")) if not at_limit else tr("SKIN_LIMIT")
	_new_card.disabled = at_limit
	for s: SkinData in skins:
		_add_card(s)
	_list_count.text = tr("SKIN_COUNT") % [skins.size(), SkinStore.MAX_SKINS]
	if is_inside_tree():
		_update_card_sizes()
		_update_card_columns()


func _add_card(s: SkinData) -> void:
	var b := Button.new()
	b.name = "Card_" + s.id
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(open_skin.bind(s.id))
	var shown: String = s.name if s.name != "" else tr("SKIN_UNNAMED")
	var slots: Array[int] = SkinStore.slots_using(s.id)
	var used: String = ""
	if not slots.is_empty():
		var names: PackedStringArray = PackedStringArray()
		for slot: int in slots:
			names.append("P%d" % (slot + 1))
		used = tr("SKIN_USED_BY") % ", ".join(names)
	b.tooltip_text = shown + ("\n" + used if used != "" else "")
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 6.0
	col.offset_right = -6.0
	col.offset_top = 6.0
	col.offset_bottom = -4.0
	col.add_theme_constant_override("separation", 0)
	b.add_child(col)
	var thumb := TankThumb.new()
	thumb.name = "Thumb"
	thumb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	thumb.set_bake_ppu(CARD_PPU)
	thumb.set_player(0, 0)
	thumb.set_skin(s)
	col.add_child(thumb)
	for text: String in [shown, used]:
		var l := Label.new()
		l.text = text
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_color_override("font_color", NeonPalette.TEXT if text == shown else NeonPalette.CYAN)
		col.add_child(l)
	_cards.add_child(b)
	_card_buttons.append(b)


## NEW SKIN: a fresh default skin in the editor (it is saved by SAVE).
func open_new() -> void:
	if SkinStore.is_full():
		_toast.show_message(tr("SKIN_AT_LIMIT") % SkinStore.MAX_SKINS)
		return
	var s: SkinData = SkinData.make_default(SkinStore.new_id(), tr("SKIN_DEFAULT_NAME") % (SkinStore.count() + 1))
	_edit(s, true)


func open_skin(skin_id: String) -> void:
	var s: SkinData = SkinStore.load_skin(skin_id)
	if s == null:
		refresh_list()
		return
	_edit(s, false)


func _edit(s: SkinData, is_new: bool) -> void:
	_skin = s
	_is_new = is_new
	_saved_sig = s.signature()
	_name_field.text = s.name
	_editor.bind(s)
	_editor.select_tab(SkinEditor.Tab.BODY)
	_preview.request_skin(s)
	_show_page(Page.EDIT)
	_preview.flush()
	_refresh_buttons()


func _refresh_buttons() -> void:
	_delete.disabled = _skin == null or _is_new
	_duplicate.disabled = _skin == null or SkinStore.is_full()


## BACK (or the Android back key): the list from the editor, the title from the list.
func go_back() -> void:
	if _page == Page.EDIT:
		if is_dirty():
			_confirm_action = "discard"
			_confirm.ask(tr("SKIN_DISCARD_CONFIRM"))
		else:
			_leave_editor()
	else:
		Transition.go(get_tree(), TITLE_SCENE)


func _leave_editor() -> void:
	_skin = null
	refresh_list()
	_show_page(Page.LIST)


# ======================================================================================
# Editing
# ======================================================================================

func is_dirty() -> bool:
	return _skin != null and _skin.signature() != _saved_sig


func is_new_skin() -> bool:
	return _is_new


func get_skin() -> SkinData:
	return _skin


func _on_edited() -> void:
	_preview.request_skin(_skin)
	_refresh_buttons()


func _on_name_changed(text: String) -> void:
	if _skin != null:
		_skin.name = SkinData.clean_name(text)


func _on_preview_baked(_tex: Texture2D) -> void:
	if _skin == null:
		return
	var small: Texture2D = SkinBaker.bake(_skin, STRIP_PPU)
	for t: TankThumb in _strip_thumbs:
		t.set_skin(_skin, small)


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_set_preview_player((_preview_player + 1) % NeonPalette.TANK_COLORS.size())


## Shows the skin in player colour `i` (its emblem too) in the big preview.
func _set_preview_player(i: int) -> void:
	_preview_player = posmod(i, NeonPalette.TANK_COLORS.size())
	if _preview != null:
		_preview.set_player(_preview_player, _preview_player)
	for k: int in range(_strip_buttons.size()):
		_strip_buttons[k].set_pressed_no_signal(k == _preview_player)
	_preview_caption.text = tr("SKIN_PLAYER_PREVIEW") % [
		_preview_player + 1, tr(NeonPalette.TANK_COLOR_NAME_KEYS[_preview_player])]


func get_preview_player() -> int:
	return _preview_player


## SAVE: writes the skin (and its picture) to user://skins. Returns false and says why on failure.
func save() -> bool:
	if _skin == null:
		return false
	if _is_new and SkinStore.is_full():
		_toast.show_message(tr("SKIN_AT_LIMIT") % SkinStore.MAX_SKINS)
		return false
	if _skin.name == "":
		_skin.name = tr("SKIN_DEFAULT_NAME") % (SkinStore.count() + (1 if _is_new else 0))
		_name_field.text = _skin.name
	if not SkinStore.save_skin(_skin):
		_toast.show_message(tr("SKIN_SAVE_FAILED"))
		return false
	_is_new = false
	_saved_sig = _skin.signature()
	_toast.show_message(tr("SKIN_SAVED"))
	_refresh_buttons()
	return true


## DUPLICATE: saves a copy of what is on screen under a new id and opens it.
func duplicate_current() -> bool:
	if _skin == null:
		return false
	if SkinStore.is_full():
		_toast.show_message(tr("SKIN_AT_LIMIT") % SkinStore.MAX_SKINS)
		return false
	var base_name: String = _skin.name if _skin.name != "" else tr("SKIN_UNNAMED")
	var copy: SkinData = _skin.duplicate_skin(SkinStore.new_id(), (base_name + " 2").left(SkinData.NAME_MAX))
	if not SkinStore.save_skin(copy):
		_toast.show_message(tr("SKIN_SAVE_FAILED"))
		return false
	_edit(copy, false)
	_toast.show_message(tr("SKIN_COPIED"))
	return true


func ask_delete() -> void:
	if _skin == null or _is_new:
		return
	_confirm_action = "delete"
	_confirm.ask(tr("SKIN_DELETE_CONFIRM"))


func _on_confirmed() -> void:
	match _confirm_action:
		"delete":
			if _skin != null:
				SkinStore.delete_skin(_skin.id)
				_toast.show_message(tr("SKIN_DELETED"))
				_leave_editor()
		"discard":
			_leave_editor()
	_confirm_action = ""


## USE FOR...: saves first (a slot can only point at a saved skin), then asks which players.
func open_use_for() -> void:
	if _skin == null:
		return
	if (_is_new or is_dirty()) and not save():
		return
	_use_for.open_for(_skin.id)


func _on_assignments_changed() -> void:
	pass


# ======================================================================================
# Picture import (full version)
# ======================================================================================

## IMAGE tab "Import picture...". Free players get the Unlock screen and nothing else; with the
## full game the system file picker opens. Returns true when a picker was opened.
func request_import() -> bool:
	if not Entitlement.is_full():
		_open_unlock()
		return false
	if _skin == null:
		return false
	picker_opens += 1
	if pick_override.is_valid():
		_on_picked(str(pick_override.call()))
		return true
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var filters: PackedStringArray = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; " + tr("SKIN_IMAGE_FILTER")])
		var err: int = DisplayServer.file_dialog_show(tr("SKIN_IMAGE_PICK_TITLE"), "", "", false,
				DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters, _on_native_file)
		if err == OK:
			return true
	_open_builtin_dialog()
	return true


func _on_native_file(status: bool, paths: PackedStringArray, _filter: int) -> void:
	# Cancel arrives as status false or an empty list; both mean "do nothing".
	if status and not paths.is_empty():
		_on_picked.call_deferred(paths[0])


func _open_builtin_dialog() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.name = "FileDialog"
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.use_native_dialog = false
		_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; " + tr("SKIN_IMAGE_FILTER")])
		_file_dialog.title = tr("SKIN_IMAGE_PICK_TITLE")
		_file_dialog.file_selected.connect(_on_picked)
		add_child(_file_dialog)
	_file_dialog.popup_centered_ratio(0.8)


## A file was chosen ("" = cancelled): read it and open the crop step, or say it could not be read.
func _on_picked(path: String) -> void:
	if path == "" or _skin == null:
		return
	var img: Image = SkinImage.load_file(path)
	if img == null:
		_toast.show_message(tr("SKIN_IMAGE_ERROR"))
		return
	_crop.open_with(img)


func _on_crop_confirmed(result: Image) -> void:
	if _skin == null:
		return
	_skin.image = result
	_skin.image_file = _skin.id + ".png"
	_editor.refresh_image()
	_on_edited()
	_toast.show_message(tr("SKIN_IMAGE_ADDED"))


func remove_image() -> void:
	if _skin == null:
		return
	_skin.image = null
	_skin.image_file = ""
	_editor.refresh_image()
	_on_edited()


func _open_unlock() -> void:
	_unlock.open_for("skin")


func _on_entitlement_changed() -> void:
	_editor.refresh_lock()


# ======================================================================================
# Accessors (tests)
# ======================================================================================

func get_editor() -> SkinEditor:
	return _editor


func get_preview() -> TankThumb:
	return _preview


func get_strip_thumb(i: int) -> TankThumb:
	return _strip_thumbs[i]


func get_strip_button(i: int) -> Button:
	return _strip_buttons[i]


func get_card_count() -> int:
	return _card_buttons.size()


func get_card(i: int) -> Button:
	return _card_buttons[i]


func get_new_card() -> Button:
	return _new_card


func get_name_field() -> LineEdit:
	return _name_field


func get_save_button() -> Button:
	return _save


func get_use_for_button() -> Button:
	return _use_for_button


func get_duplicate_button() -> Button:
	return _duplicate


func get_delete_button() -> Button:
	return _delete


func get_back_button() -> Button:
	return _back


func get_list_back_button() -> Button:
	return _list_back


func get_use_for_overlay() -> UseForOverlay:
	return _use_for


func get_crop_overlay() -> CropOverlay:
	return _crop


func get_confirm_overlay() -> ConfirmOverlay:
	return _confirm


func get_unlock_screen() -> UnlockScreen:
	return _unlock


func get_toast() -> Toast:
	return _toast


func get_list_scroll() -> TouchScroll:
	return _list_scroll


func get_preview_caption() -> Label:
	return _preview_caption


func get_right_panel() -> PanelContainer:
	return _right


func get_actions() -> HBoxContainer:
	return _actions


# ======================================================================================
# Screenshot / debug arguments
# ======================================================================================

## --skin-full / --skin-free before anything asks Entitlement: a scratch cache, so a screenshot run
## never touches the real one.
func _apply_entitlement_args() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a == "--skin-full" or a == "--skin-free":
			Entitlement.cache_path = "user://skin_shot_entitlement.cfg"
			Entitlement.set_debug_full(a == "--skin-full")


## Command-line helpers for screenshots (after `--`):
##   --skin-full / --skin-free   pretend the full game is (not) owned (a scratch entitlement cache)
##   --skin-edit[=<id>]          open the first (or that) saved skin in the editor
##   --skin-demo                 open an in-memory demo skin (nothing is saved)
##   --skin-tab=<0..5>           select a tab        --skin-player=<1..8>  preview colour
##   --skin-import=<png>         run the import on that file (crop centred) and attach the result
##   --skin-crop=<png>           open the crop step with that file
##   --skin-use-for              open USE FOR...
func _run_debug_args() -> void:
	var edit_id: String = ""
	var want_edit: bool = false
	var demo: bool = false
	var tab: int = -1
	var import_path: String = ""
	var crop_path: String = ""
	var use_for: bool = false
	for a: String in OS.get_cmdline_user_args():
		if a == "--skin-edit" or a.begins_with("--skin-edit="):
			want_edit = true
			edit_id = a.substr(12)
		elif a == "--skin-demo":
			demo = true
		elif a.begins_with("--skin-tab="):
			tab = a.substr(11).to_int()
		elif a.begins_with("--skin-player="):
			_set_preview_player(a.substr(14).to_int() - 1)
		elif a.begins_with("--skin-import="):
			import_path = a.substr(14)
		elif a.begins_with("--skin-crop="):
			crop_path = a.substr(12)
		elif a == "--skin-use-for":
			use_for = true
	if demo:
		var d: SkinData = SkinData.make_default("demo", "Neon Viper")
		d.body_style = 1
		d.turret_style = 2
		d.base = Color8(0x1B, 0x10, 0x4A)
		d.accent = Color8(0xFF, 0x73, 0x33)
		d.pattern = SkinData.Pattern.CHEVRONS
		d.pattern_color = Color8(0x73, 0x40, 0xFF)
		d.decal = 4
		d.glow = 80
		_edit(d, true)
	elif want_edit:
		var ids: PackedStringArray = SkinStore.list_ids()
		var pick: String = edit_id if edit_id != "" else (ids[0] if not ids.is_empty() else "")
		if pick != "":
			open_skin(pick)
	if _skin != null and import_path != "":
		var src: Image = SkinImage.load_file(import_path)
		if src != null:
			_skin.image = SkinImage.process(src, SkinImage.crop_rect(Vector2(src.get_size()), Vector2(src.get_size()) * 0.5, 1.0))
			_skin.image_file = _skin.id + ".png"
			_editor.refresh_image()
			_on_edited()
	if _skin != null and crop_path != "":
		var src2: Image = SkinImage.load_file(crop_path)
		if src2 != null:
			_crop.open_with(src2)
	if _skin != null and tab >= 0:
		_editor.select_tab(tab)
	if _skin != null and use_for:
		open_use_for()
