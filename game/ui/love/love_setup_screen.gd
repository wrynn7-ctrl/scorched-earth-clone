class_name LoveSetupScreen
extends Control
## The Love Edition's setup (ARCHITECTURE section 37), reached from the secret title button: one small
## panel. Player 1 is always human; player 2 is human or a CPU (Easy / Normal, Hard and Expert need
## the full game as usual); each picks a colour and an emblem (pink-ish slots by default).
## START builds MatchSettings with mode = LOVE; the core fixes the rest (2 tanks, 1 round, gentle
## wind, no shop). BACK returns to the title.

const BATTLE_SCENE: String = "res://show/battle/battle_scene.tscn"
const TITLE_SCENE: String = "res://ui/title/title_screen.tscn"
const THEME: Theme = preload("res://ui/theme/neon_theme.tres")
## Orchid and coral: the pinkest of the eight tank colours; star and circle emblems.
const DEFAULT_COLORS: Array[int] = [6, 5]
const DEFAULT_EMBLEMS: Array[int] = [4, 0]
const PINK: Color = Color(1.0, 0.42, 0.68)

## A locked option (Hard / Expert) was tapped; the Unlock screen opens from here.
signal locked_tapped(kind: String, id: String)

var _colors: PackedInt32Array = PackedInt32Array()
var _emblems: PackedInt32Array = PackedInt32Array()
## SimConstants.CTRL_* of player 2.
var _level: int = SimConstants.CTRL_HUMAN
var _full_unlocked: bool = true

var _sky: NeonSky = null
var _margin: MarginContainer = null
var _center: CenterContainer = null
var _panel: PanelContainer = null
var _box: VBoxContainer = null
var _title_row: HBoxContainer = null
var _heart_l: HeartIcon = null
var _heart_r: HeartIcon = null
var _title: Label = null
var _rows: Array[HBoxContainer] = []
var _labels: Array[Label] = []
var _color_buttons: Array[SwatchButton] = []
var _emblem_buttons: Array[SwatchButton] = []
var _kind_buttons: Array[Button] = []
var _hint: Label = null
var _bottom: HBoxContainer = null
var _back: Button = null
var _start: Button = null
var _picker: KindPicker = null
var _unlock: UnlockScreen = null


func _init() -> void:
	ShotArgs.parse()
	SettingsStore.ensure_loaded()
	theme = THEME
	name = "LoveSetupScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i: int in range(2):
		_colors.append(DEFAULT_COLORS[i])
		_emblems.append(DEFAULT_EMBLEMS[i])
	_full_unlocked = ThemeDefs.is_full_game()
	_level = _allowed_level(SetupPrefs.love_cpu)
	_build()


func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	apply_scale()
	LayoutWatch.attach(self, apply_scale)
	Entitlement.hub().changed.connect(_on_entitlement_changed)
	_refresh()
	ShotHook.attach(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _unlock != null and _unlock.is_open():
			_unlock.close()
		elif _picker != null and _picker.is_open():
			_picker.close()
		else:
			go_back()


# ======================================================================================
# Build
# ======================================================================================

func _build() -> void:
	_sky = (load("res://show/sky.tscn") as PackedScene).instantiate()
	add_child(_sky)
	_sky.apply_theme(ThemeDefs.LOVE_THEME)
	_margin = MarginContainer.new()
	_margin.name = "Margin"
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_margin)
	_center = CenterContainer.new()
	_center.name = "Center"
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(_center)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_center.add_child(_panel)
	_box = VBoxContainer.new()
	_box.name = "Box"
	_panel.add_child(_box)

	_title_row = HBoxContainer.new()
	_title_row.name = "TitleRow"
	_title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(_title_row)
	_heart_l = _heart("HeartLeft")
	_title = Label.new()
	_title.name = "Title"
	_title.text = tr("LOVE_BUTTON")
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.92))
	_title_row.add_child(_title)
	_heart_r = _heart("HeartRight")

	for i: int in range(2):
		_build_row(i)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", NeonPalette.WARN)
	_hint.visible = false
	_box.add_child(_hint)

	_bottom = HBoxContainer.new()
	_bottom.name = "Bottom"
	_box.add_child(_bottom)
	_back = Button.new()
	_back.name = "Back"
	_back.text = tr("SETUP_BACK")
	_back.focus_mode = Control.FOCUS_NONE
	_back.pressed.connect(go_back)
	_bottom.add_child(_back)
	_start = Button.new()
	_start.name = "Start"
	_start.text = tr("SETUP_START")
	_start.theme_type_variation = &"FireButton"
	_start.focus_mode = Control.FOCUS_NONE
	_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start.pressed.connect(start_match)
	_bottom.add_child(_start)

	_picker = KindPicker.new()
	_picker.chosen.connect(_on_kind_chosen)
	_picker.locked_chosen.connect(_on_kind_locked)
	add_child(_picker)
	_unlock = UnlockScreen.new()
	add_child(_unlock)
	locked_tapped.connect(func(kind: String, _id: String) -> void: _unlock.open_for(kind))


func _heart(node_name: String) -> HeartIcon:
	var h := HeartIcon.new()
	h.name = node_name
	h.color = PINK
	_title_row.add_child(h)
	return h


func _build_row(i: int) -> void:
	var row := HBoxContainer.new()
	row.name = "Player%d" % i
	_box.add_child(row)
	_rows.append(row)
	var label := Label.new()
	label.name = "Label"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	_labels.append(label)
	var cb := SwatchButton.new()
	cb.name = "Color"
	cb.pressed.connect(cycle_color.bind(i))
	row.add_child(cb)
	_color_buttons.append(cb)
	var eb := SwatchButton.new()
	eb.name = "Emblem"
	eb.pressed.connect(cycle_emblem.bind(i))
	row.add_child(eb)
	_emblem_buttons.append(eb)
	var kb := Button.new()
	kb.name = "Kind"
	kb.focus_mode = Control.FOCUS_NONE
	kb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kb.clip_text = true
	kb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if i == 0:
		kb.disabled = true  # player 1 is always human
		kb.set_meta(AudioDirector.UI_SOUND_META, "none")
	else:
		kb.pressed.connect(open_kind_picker)
	row.add_child(kb)
	_kind_buttons.append(kb)


func apply_scale() -> void:
	UiScale.apply_edge_margins(_margin)
	var touch: float = UiScale.touch()
	var pad: int = roundi(UiScale.dp(16.0))
	var frame := _panel.get_theme_stylebox("panel")
	if frame is StyleBoxFlat:
		var sb: StyleBoxFlat = (frame as StyleBoxFlat).duplicate()
		sb.border_color = PINK
		sb.set_content_margin_all(float(pad))
		_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size.x = minf(UiScale.dp(400.0 * maxf(1.0, UiScale.text_scale * 0.85)), get_viewport_rect().size.x * 0.92)
	_box.add_theme_constant_override("separation", roundi(UiScale.dp(10.0)))
	_title_row.add_theme_constant_override("separation", roundi(UiScale.dp(10.0)))
	_bottom.add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))
	_title.add_theme_font_size_override("font_size", UiScale.hud_font(24.0))
	_heart_l.set_icon_size(UiScale.dp(30.0))
	_heart_r.set_icon_size(UiScale.dp(30.0))
	for row: HBoxContainer in _rows:
		row.add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))
	for l: Label in _labels:
		l.custom_minimum_size.x = UiScale.dp(84.0)
		l.add_theme_font_size_override("font_size", UiScale.hud_font(14.0))
	for b: SwatchButton in _color_buttons:
		b.custom_minimum_size = Vector2.ONE * touch
	for b: SwatchButton in _emblem_buttons:
		b.custom_minimum_size = Vector2.ONE * touch
	for b: Button in _kind_buttons:
		b.custom_minimum_size = Vector2(UiScale.dp(120.0), touch)
		b.add_theme_font_size_override("font_size", UiScale.hud_font(13.0))
	_hint.add_theme_font_size_override("font_size", UiScale.hud_font(12.0))
	_back.custom_minimum_size = Vector2(UiScale.dp(96.0), UiScale.dp(56.0))
	_back.add_theme_font_size_override("font_size", UiScale.hud_font(15.0))
	_start.custom_minimum_size = Vector2(UiScale.dp(140.0), UiScale.dp(56.0))
	_start.add_theme_font_size_override("font_size", UiScale.hud_font(22.0))


# ======================================================================================
# State
# ======================================================================================

## Player 2's controller: SimConstants.CTRL_HUMAN, or a CPU level the entitlement allows. Hard and
## Expert without the full game are refused (false) and open the Unlock screen.
func set_player2(level: int) -> bool:
	if level < SimConstants.CTRL_HUMAN or level > SimConstants.CTRL_MAX:
		return false
	if _allowed_level(level) != level:
		_hint.text = tr(UnlockScreen.CONTEXT_KEYS["cpu"] as String)
		_refresh()
		locked_tapped.emit("cpu", str(level))
		return false
	_hint.text = ""
	_level = level
	_refresh()
	return true


func get_player2() -> int:
	return _level


func _allowed_level(level: int) -> int:
	var top: int = SimConstants.CTRL_MAX if _full_unlocked else SimConstants.CTRL_FREE_MAX
	return clampi(level, SimConstants.CTRL_HUMAN, top)


## Billing / test hook: the whole tier.
func set_full_unlocked(unlocked: bool) -> void:
	_full_unlocked = unlocked
	_level = _allowed_level(_level)
	_refresh()


func _on_entitlement_changed() -> void:
	set_full_unlocked(ThemeDefs.is_full_game())
	_hint.text = ""
	_refresh()


func open_kind_picker() -> void:
	_picker.open_for(1, _level, _full_unlocked, false)


func _on_kind_chosen(level: int) -> void:
	set_player2(level)


func _on_kind_locked(level: int) -> void:
	set_player2(level)


## Next colour for player i; if the other player has it they swap, so the two never match.
func cycle_color(i: int) -> void:
	SetupScreen._cycle(_colors, i, NeonPalette.TANK_COLORS.size())
	_refresh()


func cycle_emblem(i: int) -> void:
	SetupScreen._cycle(_emblems, i, NeonPalette.EMBLEM_COUNT)
	_refresh()


func get_color_index(i: int) -> int:
	return _colors[i]


func get_emblem_index(i: int) -> int:
	return _emblems[i]


func _refresh() -> void:
	for i: int in range(2):
		var col: Color = NeonPalette.tank_color(_colors[i])
		_labels[i].text = tr("LOVE_SETUP_PLAYER") % (i + 1)
		_labels[i].add_theme_color_override("font_color", col)
		_color_buttons[i].set_art(col)
		_color_buttons[i].tooltip_text = tr(NeonPalette.TANK_COLOR_NAME_KEYS[_colors[i]])
		_emblem_buttons[i].set_art(col, _emblems[i])
		_emblem_buttons[i].tooltip_text = tr(NeonPalette.EMBLEM_NAME_KEYS[_emblems[i]])
	_kind_buttons[0].text = tr("LOVE_SETUP_FIXED")
	_kind_buttons[1].text = "%s ▾" % CpuNames.full_name(_level)
	_hint.visible = _hint.text != ""


# ======================================================================================
# Start / back
# ======================================================================================

## What START uses: a love match (the core clamps everything else to its fixed duel).
func build_settings() -> MatchSettings:
	var s := MatchSettings.new()
	s.mode = SimConstants.MODE_LOVE
	s.num_tanks = 2
	s.rounds = 1
	s.wind_max = SimConstants.LOVE_WIND_MAX
	s.start_money = 0
	s.full_unlocked = _full_unlocked
	s.controllers = PackedInt32Array([SimConstants.CTRL_HUMAN, _allowed_level(_level)])
	s.seed = ShotArgs.seed_value if ShotArgs.seed_value != 0 else int(randi())
	return s


func save_prefs() -> void:
	SetupPrefs.love_cpu = _level
	SettingsStore.save()


func start_match() -> void:
	save_prefs()
	BattleConfig.settings = build_settings()
	BattleConfig.resume = false
	BattleConfig.seed_value = 0
	BattleConfig.theme = ThemeDefs.DEFAULT_ID
	PlayerLooks.set_looks(_colors.duplicate(), _emblems.duplicate())
	PlayerNames.reset()  # the Love Edition has no name fields: PLAYER 1 and PLAYER 2
	# A new match replaces any autosave (the title asked for confirmation already).
	SaveStore.delete(BattleConfig.autosave_path)
	Transition.go(get_tree(), BATTLE_SCENE)


func go_back() -> void:
	save_prefs()
	Transition.go(get_tree(), TITLE_SCENE)


# --- accessors (tests, tools) ---

func get_start_button() -> Button:
	return _start


func get_back_button() -> Button:
	return _back


func get_kind_button(i: int) -> Button:
	return _kind_buttons[i]


func get_kind_popup() -> KindPicker:
	return _picker


func get_color_button(i: int) -> SwatchButton:
	return _color_buttons[i]


func get_emblem_button(i: int) -> SwatchButton:
	return _emblem_buttons[i]


func get_hint_text() -> String:
	return _hint.text


func get_unlock_screen() -> UnlockScreen:
	return _unlock


func get_panel() -> PanelContainer:
	return _panel
