class_name SkinEditor
extends VBoxContainer
## The tabbed controls of the Skin Studio (BODY, COLOURS, PATTERN, DECAL, GLOW, IMAGE). It edits
## the SkinData it is bound to in place and says `changed`; the studio owns saving, the preview and
## the picture import. The IMAGE tab is visible for everyone: without the full game it carries a lock
## and the import button reports `locked_tapped` (the studio opens the Unlock screen).

signal changed
signal import_requested
signal remove_image_requested
signal locked_tapped

enum Tab { BODY, COLOURS, PATTERN, DECAL, GLOW, IMAGE }

const TAB_KEYS: Array[String] = [
	"SKIN_TAB_BODY", "SKIN_TAB_COLOURS", "SKIN_TAB_PATTERN", "SKIN_TAB_DECAL", "SKIN_TAB_GLOW", "SKIN_TAB_IMAGE",
]
## Colour slots on the COLOURS tab.
enum Slot { BASE, ACCENT, PATTERN }

var _skin: SkinData = null
var _tab: int = Tab.BODY
var _slot: int = Slot.BASE
var _locked: bool = false

var _tabs: GridContainer = null
var _tab_buttons: Array[Button] = []
var _scroll: TouchScroll = null
var _pages: Array[VBoxContainer] = []
var _choices: Array[SkinChoice] = []
var _hull_tiles: Array[SkinChoice] = []
var _turret_tiles: Array[SkinChoice] = []
var _pattern_tiles: Array[SkinChoice] = []
var _decal_tiles: Array[SkinChoice] = []
var _slot_tiles: Array[SkinChoice] = []
var _picker: SkinColorPicker = null
var _glow_slider: SkinSlider = null
var _glow_value: Label = null
var _labels: Array[Label] = []
var _label_dp: Dictionary = {}
var _flows: Array[HFlowContainer] = []
var _import_button: Button = null
var _remove_button: Button = null
var _image_status: Label = null
var _image_thumb: TextureRect = null
var _note: Label = null
var _buttons: Array[Button] = []


func _init() -> void:
	name = "Editor"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_tabs()
	_scroll = TouchScroll.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var host := VBoxContainer.new()
	host.name = "Pages"
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(host)
	_build_body_page(host)
	_build_colour_page(host)
	_build_pattern_page(host)
	_build_decal_page(host)
	_build_glow_page(host)
	_build_image_page(host)
	select_tab(Tab.BODY)


func _ready() -> void:
	resized.connect(_update_tab_columns)
	refresh_lock()
	apply_scale()


# ======================================================================================
# Public
# ======================================================================================

## Edits `skin` from now on and shows its values (no `changed`).
func bind(skin: SkinData) -> void:
	_skin = skin
	for t: SkinChoice in _hull_tiles:
		t.set_pressed_no_signal(t.index == skin.body_style)
	for t: SkinChoice in _turret_tiles:
		t.set_pressed_no_signal(t.index == skin.turret_style)
	for t: SkinChoice in _pattern_tiles:
		t.set_pressed_no_signal(t.index == skin.pattern)
	for t: SkinChoice in _decal_tiles:
		t.set_pressed_no_signal(t.index == skin.decal)
	_glow_slider.set_value_no_signal(float(skin.glow))
	_glow_value.text = "%d%%" % skin.glow
	_refresh_slots()
	_picker.set_color(_slot_color())
	refresh_image()


func select_tab(t: int) -> void:
	_tab = clampi(t, 0, Tab.IMAGE)
	for i: int in range(_pages.size()):
		_pages[i].visible = i == _tab
		_tab_buttons[i].set_pressed_no_signal(i == _tab)
	_scroll.scroll_vertical = 0
	if _tab == Tab.IMAGE:
		refresh_lock()


func get_tab() -> int:
	return _tab


func get_tab_button(i: int) -> Button:
	return _tab_buttons[i]


func get_tab_count() -> int:
	return _tab_buttons.size()


func get_scroll() -> TouchScroll:
	return _scroll


func get_picker() -> SkinColorPicker:
	return _picker


func get_import_button() -> Button:
	return _import_button


func get_remove_button() -> Button:
	return _remove_button


func get_tile(kind: int, i: int) -> SkinChoice:
	match kind:
		SkinChoice.Kind.HULL:
			return _hull_tiles[i]
		SkinChoice.Kind.TURRET:
			return _turret_tiles[i]
		SkinChoice.Kind.PATTERN:
			return _pattern_tiles[i]
		_:
			return _decal_tiles[i]


func get_slot_tile(i: int) -> SkinChoice:
	return _slot_tiles[i]


func get_glow_slider() -> SkinSlider:
	return _glow_slider


func get_note_text() -> String:
	return _note.text


func is_import_locked() -> bool:
	return _locked


func is_lock_shown() -> bool:
	return LockBadge.of(_tab_buttons[Tab.IMAGE]).visible


func tab_columns() -> int:
	return _tabs.columns


## Re-reads the free/full state (the lock on the IMAGE tab and the import button).
func refresh_lock() -> void:
	_locked = not Entitlement.is_full()
	LockBadge.mark(_tab_buttons[Tab.IMAGE], _locked, tr("SKIN_IMAGE_FULL"), tr("SKIN_TAB_IMAGE"))
	LockBadge.mark(_import_button, _locked, tr("SKIN_IMAGE_FULL"), tr("SKIN_IMAGE_IMPORT"))
	_import_button.text = tr("SKIN_IMAGE_IMPORT") + ("\n" + tr("SKIN_IMAGE_FULL") if _locked else "")
	refresh_image()
	if is_inside_tree():
		apply_scale()


## The IMAGE tab's text and thumbnail follow the bound skin and the lock.
func refresh_image() -> void:
	if _skin == null:
		return
	var has: bool = _skin.has_image()
	if _locked:
		_image_status.text = tr("SKIN_IMAGE_LOCKED_BODY")
	else:
		_image_status.text = tr("SKIN_IMAGE_HAS") if has else tr("SKIN_IMAGE_NONE")
	_image_thumb.visible = has and not _locked
	if has:
		_image_thumb.texture = ImageTexture.create_from_image(_skin.image)
	_remove_button.visible = has and not _locked


# ======================================================================================
# Build
# ======================================================================================

func _build_tabs() -> void:
	_tabs = GridContainer.new()
	_tabs.name = "Tabs"
	_tabs.columns = Tab.IMAGE + 1
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_tabs)
	var group := ButtonGroup.new()
	for i: int in range(TAB_KEYS.size()):
		var b := Button.new()
		b.name = "Tab%d" % i
		b.text = tr(TAB_KEYS[i])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(select_tab.bind(i))
		_tabs.add_child(b)
		_tab_buttons.append(b)


func _page(host: VBoxContainer, page_name: String) -> VBoxContainer:
	var p := VBoxContainer.new()
	p.name = page_name
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.add_child(p)
	_pages.append(p)
	return p


func _label(parent: Control, text: String, dp: float, color: Color = NeonPalette.TEXT_DIM, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = 10.0  # lets the label shrink and wrap inside the scroll area
	parent.add_child(l)
	_labels.append(l)
	_label_dp[l] = dp
	return l


func _flow(parent: Control) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(f)
	_flows.append(f)
	return f


func _tile(flow: Container, group: ButtonGroup, kind: int, i: int, key: String) -> SkinChoice:
	var t := SkinChoice.new(kind, i, tr(key))
	t.button_group = group
	flow.add_child(t)
	_choices.append(t)
	return t


func _build_body_page(host: VBoxContainer) -> void:
	var p: VBoxContainer = _page(host, "Body")
	_label(p, tr("SKIN_HULL"), 12.0)
	var flow: HFlowContainer = _flow(p)
	var group := ButtonGroup.new()
	for i: int in range(SkinData.BODY_STYLES):
		var t: SkinChoice = _tile(flow, group, SkinChoice.Kind.HULL, i, SkinShapes.BODY_NAME_KEYS[i])
		t.name = "Hull%d" % i
		t.pressed.connect(_on_body.bind(i))
		_hull_tiles.append(t)
	_label(p, tr("SKIN_TURRET"), 12.0)
	flow = _flow(p)
	group = ButtonGroup.new()
	for i: int in range(SkinData.TURRET_STYLES):
		var t: SkinChoice = _tile(flow, group, SkinChoice.Kind.TURRET, i, SkinShapes.TURRET_NAME_KEYS[i])
		t.name = "Turret%d" % i
		t.pressed.connect(_on_turret.bind(i))
		_turret_tiles.append(t)
	_label(p, tr("SKIN_IDENTITY_NOTE"), 12.0, NeonPalette.TEXT_DIM, true)


func _build_colour_page(host: VBoxContainer) -> void:
	var p: VBoxContainer = _page(host, "Colours")
	_picker = SkinColorPicker.new()
	_picker.color_changed.connect(_on_color)
	p.add_child(_picker)
	# The three colour slots are compact chips stacked beside the sliders.
	var group := ButtonGroup.new()
	for i: int in range(3):
		var key: String = ["SKIN_COLOR_BASE", "SKIN_COLOR_ACCENT", "SKIN_COLOR_PATTERN"][i]
		var t: SkinChoice = _tile(_picker.get_slot_box(), group, SkinChoice.Kind.COLOR, i, key)
		t.compact = true
		t.name = "Slot%d" % i
		t.pressed.connect(_on_slot.bind(i))
		_slot_tiles.append(t)


func _build_pattern_page(host: VBoxContainer) -> void:
	var p: VBoxContainer = _page(host, "Pattern")
	var flow: HFlowContainer = _flow(p)
	var group := ButtonGroup.new()
	for i: int in range(SkinData.PATTERNS):
		var t: SkinChoice = _tile(flow, group, SkinChoice.Kind.PATTERN, i, SkinShapes.PATTERN_NAME_KEYS[i])
		t.name = "Pattern%d" % i
		t.pressed.connect(_on_pattern.bind(i))
		_pattern_tiles.append(t)
	_label(p, tr("SKIN_PATTERN_HINT"), 12.0, NeonPalette.TEXT_DIM, true)


func _build_decal_page(host: VBoxContainer) -> void:
	var p: VBoxContainer = _page(host, "Decal")
	var flow: HFlowContainer = _flow(p)
	var group := ButtonGroup.new()
	for i: int in range(SkinData.DECALS):
		var t: SkinChoice = _tile(flow, group, SkinChoice.Kind.DECAL, i, SkinShapes.DECAL_NAME_KEYS[i])
		t.name = "Decal%d" % i
		t.pressed.connect(_on_decal.bind(i))
		_decal_tiles.append(t)


func _build_glow_page(host: VBoxContainer) -> void:
	var p: VBoxContainer = _page(host, "Glow")
	var row := HBoxContainer.new()
	p.add_child(row)
	_label(row, tr("SKIN_GLOW_LABEL"), 12.0)
	_glow_slider = SkinSlider.new()
	_glow_slider.min_value = 0.0
	_glow_slider.max_value = float(SkinData.GLOW_MAX)
	_glow_slider.step = 1.0
	_glow_slider.track_colors = PackedColorArray([Color(NeonPalette.CYAN, 0.12), NeonPalette.CYAN])
	_glow_slider.value_changed.connect(_on_glow)
	row.add_child(_glow_slider)
	_glow_value = _label(row, "0%", 12.0, NeonPalette.TEXT)
	_glow_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_glow_value.custom_minimum_size.x = 56.0
	_label(p, tr("SKIN_GLOW_HINT"), 12.0, NeonPalette.TEXT_DIM, true)


func _build_image_page(host: VBoxContainer) -> void:
	var p: VBoxContainer = _page(host, "Image")
	_image_status = _label(p, "", 13.0, NeonPalette.TEXT, true)
	_image_thumb = TextureRect.new()
	_image_thumb.name = "Thumb"
	_image_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image_thumb.stretch_mode = TextureRect.STRETCH_SCALE
	_image_thumb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_image_thumb.visible = false
	p.add_child(_image_thumb)
	_import_button = Button.new()
	_import_button.name = "Import"
	_import_button.focus_mode = Control.FOCUS_NONE
	_import_button.pressed.connect(_on_import)
	p.add_child(_import_button)
	_remove_button = Button.new()
	_remove_button.name = "Remove"
	_remove_button.text = tr("SKIN_IMAGE_REMOVE")
	_remove_button.focus_mode = Control.FOCUS_NONE
	_remove_button.pressed.connect(func() -> void: remove_image_requested.emit())
	p.add_child(_remove_button)
	_buttons.append(_import_button)
	_buttons.append(_remove_button)
	_note = _label(p, tr("SKIN_IMAGE_NOTE"), 12.0, NeonPalette.GOOD, true)
	_note.name = "PrivateNote"


# ======================================================================================
# Scale
# ======================================================================================

func apply_scale() -> void:
	add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	_tabs.add_theme_constant_override("h_separation", roundi(UiScale.dp(4.0)))
	_tabs.add_theme_constant_override("v_separation", roundi(UiScale.dp(4.0)))
	for p: VBoxContainer in _pages:
		p.add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))
	for f: HFlowContainer in _flows:
		f.add_theme_constant_override("h_separation", roundi(UiScale.dp(6.0)))
		f.add_theme_constant_override("v_separation", roundi(UiScale.dp(6.0)))
	for l: Label in _labels:
		l.add_theme_font_size_override("font_size", UiScale.font(float(_label_dp[l])))
	for t: SkinChoice in _choices:
		t.apply_scale()
	_picker.apply_scale()
	_glow_slider.custom_minimum_size = Vector2(UiScale.dp(120.0), UiScale.touch())
	_glow_value.custom_minimum_size.x = UiScale.dp(52.0) * maxf(1.0, UiScale.text_scale * 0.8)
	for b: Button in _buttons:
		b.add_theme_font_size_override("font_size", UiScale.font(14.0))
		b.custom_minimum_size = Vector2(UiScale.dp(200.0), UiScale.touch())
	_image_thumb.custom_minimum_size = Vector2(UiScale.dp(168.0), UiScale.dp(63.0))
	for i: int in range(_tab_buttons.size()):
		_tab_buttons[i].add_theme_font_size_override("font_size", UiScale.font(12.0))
		_tab_buttons[i].custom_minimum_size = Vector2(0.0, UiScale.touch())
	LockBadge.of(_tab_buttons[Tab.IMAGE]).apply_scale()
	LockBadge.of(_import_button).apply_scale()
	_update_tab_columns()


## One row of tabs when their captions fit, otherwise two rows of three (large text on a phone).
func _update_tab_columns() -> void:
	if _tabs == null or _tab_buttons.is_empty():
		return
	var need: float = 0.0
	var gap: float = UiScale.dp(4.0)
	var fs: int = UiScale.font(12.0)
	for i: int in range(_tab_buttons.size()):
		var font: Font = _tab_buttons[i].get_theme_font("font")
		var w: float = font.get_string_size(_tab_buttons[i].text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x + UiScale.dp(22.0)
		if i == Tab.IMAGE and _locked:
			w += UiScale.dp(22.0)
		need += w + gap
	var cols: int = _tab_buttons.size() if need <= size.x else 3
	if _tabs.columns != cols:
		_tabs.columns = cols
	for b: Button in _tab_buttons:
		b.custom_minimum_size.x = 0.0


# ======================================================================================
# Edits
# ======================================================================================

func _on_body(i: int) -> void:
	_skin.body_style = i
	changed.emit()


func _on_turret(i: int) -> void:
	_skin.turret_style = i
	changed.emit()


func _on_pattern(i: int) -> void:
	_skin.pattern = i
	changed.emit()


func _on_decal(i: int) -> void:
	_skin.decal = i
	changed.emit()


func _on_glow(v: float) -> void:
	_skin.glow = roundi(v)
	_glow_value.text = "%d%%" % _skin.glow
	changed.emit()


func _on_slot(i: int) -> void:
	_slot = i
	_picker.set_color(_slot_color())


func _slot_color() -> Color:
	match _slot:
		Slot.ACCENT:
			return _skin.accent
		Slot.PATTERN:
			return _skin.pattern_color
		_:
			return _skin.base


func _on_color(c: Color) -> void:
	match _slot:
		Slot.ACCENT:
			_skin.accent = c
		Slot.PATTERN:
			_skin.pattern_color = c
		_:
			_skin.base = c
	_refresh_slots()
	changed.emit()


func _refresh_slots() -> void:
	_slot_tiles[Slot.BASE].set_color_value(_skin.base)
	_slot_tiles[Slot.ACCENT].set_color_value(_skin.accent)
	_slot_tiles[Slot.PATTERN].set_color_value(_skin.pattern_color)
	for i: int in range(_slot_tiles.size()):
		_slot_tiles[i].set_pressed_no_signal(i == _slot)


func _on_import() -> void:
	if _locked:
		locked_tapped.emit()
	else:
		import_requested.emit()


## Test hook: edit as if the player pressed a colour slot tile.
func select_slot(i: int) -> void:
	_on_slot(clampi(i, 0, 2))
	_refresh_slots()
