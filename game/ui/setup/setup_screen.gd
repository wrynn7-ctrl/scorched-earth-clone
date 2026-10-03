class_name SetupScreen
extends Control
## Match setup (from the title's START): players 2-8, who controls each slot (Human or a CPU
## from Easy to Expert), rounds, starting money, wind, and each player's colour and emblem.
## START creates the match settings (full game unlocked) and loads the battle, which opens the
## first shop. The last-used setup is remembered (SetupPrefs / SettingsStore).
##
## At least one slot must be human, unless "Watch CPUs play" is ticked.
##
## Layout: options on the left, one scrolling row per player on the right, BACK / START under
## the player list. Everything is containers and dp sizes, so it fits phones and tablets.

const BATTLE_SCENE: String = "res://show/battle/battle_scene.tscn"
const TITLE_SCENE: String = "res://ui/title/title_screen.tscn"
const THEME: Theme = preload("res://ui/theme/neon_theme.tres")

const ROUND_CHOICES: Array[int] = [1, 3, 5, 10, 20]
## Starting money levels: Low / Normal / High.
const MONEY_CHOICES: Array[int] = [5000, 10000, 25000]
const MONEY_KEYS: Array[String] = ["SETUP_LOW", "SETUP_NORMAL", "SETUP_HIGH"]
## Wind levels: Off / Low / Normal / High -> wind_max.
const WIND_CHOICES: Array[int] = [0, 40, 70, 100]
const WIND_KEYS: Array[String] = ["SETUP_OFF", "SETUP_LOW", "SETUP_NORMAL", "SETUP_HIGH"]
const DEFAULT_ROUNDS: int = 3
const DEFAULT_MONEY_LEVEL: int = 1
const DEFAULT_WIND_LEVEL: int = 2

## Chip colour per level (the chip also spells the level out, so colour is never the only cue).
const LEVEL_COLORS: Array[Color] = [Color.WHITE, NeonPalette.GOOD, NeonPalette.CYAN, NeonPalette.WARN, NeonPalette.MAGENTA]

var _players: int = 2
var _rounds: int = DEFAULT_ROUNDS
var _money_level: int = DEFAULT_MONEY_LEVEL
var _wind_level: int = DEFAULT_WIND_LEVEL
var _colors: PackedInt32Array = PackedInt32Array()
var _emblems: PackedInt32Array = PackedInt32Array()
## SimConstants.CTRL_* for every slot (also the hidden ones, so shrinking and growing the
## player count keeps the choices).
var _controllers: PackedInt32Array = PackedInt32Array()
var _watch: bool = false
## False locks CPU Hard and Expert behind the full game (this build: unlocked).
var _full_unlocked: bool = true

var _sky: NeonSky = null
var _margin: MarginContainer = null
var _columns: HBoxContainer = null
var _options_panel: PanelContainer = null
var _options: VBoxContainer = null
var _title: Label = null
var _players_value: Label = null
var _players_minus: Button = null
var _players_plus: Button = null
var _round_buttons: Array[Button] = []
var _money_buttons: Array[Button] = []
var _wind_buttons: Array[Button] = []
var _captions: Array[Label] = []
var _option_rows: Array[HBoxContainer] = []
var _players_panel: PanelContainer = null
var _players_box: VBoxContainer = null
var _players_caption: Label = null
var _scroll: TouchScroll = null
var _rows: VBoxContainer = null
var _player_rows: Array[HBoxContainer] = []
var _player_labels: Array[Label] = []
var _color_buttons: Array[SwatchButton] = []
var _emblem_buttons: Array[SwatchButton] = []
var _kind_buttons: Array[Button] = []
var _chips: Array[PanelContainer] = []
var _chip_labels: Array[Label] = []
var _picker: KindPicker = null
var _header: HBoxContainer = null
var _watch_box: Button = null
var _hint: Label = null
var _bottom: HBoxContainer = null
var _back: Button = null
var _start: Button = null


func _init() -> void:
	ShotArgs.parse()
	SettingsStore.ensure_loaded()
	theme = THEME
	name = "SetupScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i: int in range(SimConstants.MAX_TANKS):
		_colors.append(i)
		_emblems.append(i)
	_controllers.resize(SimConstants.MAX_TANKS)
	_controllers.fill(SimConstants.CTRL_HUMAN)
	_load_prefs()
	if ShotArgs.players >= SimConstants.MIN_TANKS:
		_players = clampi(ShotArgs.players, SimConstants.MIN_TANKS, SimConstants.MAX_TANKS)
	for i: int in range(mini(ShotArgs.controllers.size(), SimConstants.MAX_TANKS)):
		_controllers[i] = _allowed_level(ShotArgs.controllers[i])
	_build()


func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	apply_scale()
	LayoutWatch.attach(self, apply_scale)
	_refresh()
	ShotHook.attach(self)
	if ShotArgs.setup_picker > 0:
		_open_kind_popup.call_deferred(clampi(ShotArgs.setup_picker - 1, 0, SimConstants.MAX_TANKS - 1))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _picker != null and _picker.visible:
			_picker.close()  # Android back closes the picker first
		else:
			go_back()


## The last-used setup, validated again (SettingsStore clamps it too).
func _load_prefs() -> void:
	if not SetupPrefs.has_saved:
		return
	_players = clampi(SetupPrefs.players, SimConstants.MIN_TANKS, SimConstants.MAX_TANKS)
	_rounds = SetupPrefs.rounds if ROUND_CHOICES.has(SetupPrefs.rounds) else DEFAULT_ROUNDS
	_money_level = clampi(SetupPrefs.money_level, 0, MONEY_CHOICES.size() - 1)
	_wind_level = clampi(SetupPrefs.wind_level, 0, WIND_CHOICES.size() - 1)
	_watch = SetupPrefs.watch
	for i: int in range(SimConstants.MAX_TANKS):
		_controllers[i] = _allowed_level(SetupPrefs.controllers[i] if i < SetupPrefs.controllers.size() else 0)
	_enforce_human_rule()


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
	_columns = HBoxContainer.new()
	_columns.name = "Columns"
	_margin.add_child(_columns)
	_build_options()
	_build_players()
	_picker = KindPicker.new()
	_picker.chosen.connect(_on_kind_chosen)
	add_child(_picker)


func _panel(panel_name: String) -> Array:
	var p := PanelContainer.new()
	p.name = panel_name
	var box := VBoxContainer.new()
	box.name = "Box"
	p.add_child(box)
	return [p, box]


func _build_options() -> void:
	var made: Array = _panel("OptionsPanel")
	_options_panel = made[0]
	_options = made[1]
	_options_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_columns.add_child(_options_panel)
	_title = Label.new()
	_title.name = "Title"
	_title.text = tr("SETUP_TITLE")
	_title.add_theme_color_override("font_color", NeonPalette.CYAN)
	_options.add_child(_title)

	var row: HBoxContainer = _option_row("PlayersRow", tr("SETUP_PLAYERS"))
	_players_minus = _stepper_button("-", func() -> void: set_players(_players - 1))
	_players_minus.name = "PlayersMinus"
	row.add_child(_players_minus)
	_players_value = Label.new()
	_players_value.name = "PlayersValue"
	_players_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_players_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_players_value)
	_players_plus = _stepper_button("+", func() -> void: set_players(_players + 1))
	_players_plus.name = "PlayersPlus"
	row.add_child(_players_plus)

	row = _option_row("RoundsRow", tr("SETUP_ROUNDS"))
	var group := ButtonGroup.new()
	for n: int in ROUND_CHOICES:
		var b: Button = _choice_button(str(n), group)
		b.name = "Rounds%d" % n
		b.pressed.connect(set_rounds.bind(n))
		row.add_child(b)
		_round_buttons.append(b)

	row = _option_row("MoneyRow", tr("SETUP_MONEY"))
	group = ButtonGroup.new()
	for i: int in range(MONEY_CHOICES.size()):
		var b: Button = _choice_button("%s\n%s" % [tr(MONEY_KEYS[i]), HudFormat.group(MONEY_CHOICES[i])], group)
		b.name = "Money%d" % i
		b.pressed.connect(set_money_level.bind(i))
		row.add_child(b)
		_money_buttons.append(b)

	row = _option_row("WindRow", tr("SETUP_WIND"))
	group = ButtonGroup.new()
	for i: int in range(WIND_CHOICES.size()):
		var b: Button = _choice_button(tr(WIND_KEYS[i]), group)
		b.name = "Wind%d" % i
		b.pressed.connect(set_wind_level.bind(i))
		row.add_child(b)
		_wind_buttons.append(b)


func _option_row(row_name: String, caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	_options.add_child(row)
	var l := Label.new()
	l.name = "Caption"
	l.text = caption
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", NeonPalette.TEXT_DIM)
	row.add_child(l)
	_captions.append(l)
	_option_rows.append(row)
	return row


func _stepper_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b


func _choice_button(text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _build_players() -> void:
	var made: Array = _panel("PlayersPanel")
	_players_panel = made[0]
	_players_box = made[1]
	_players_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_players_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_columns.add_child(_players_panel)
	_header = HBoxContainer.new()
	_header.name = "Header"
	_players_box.add_child(_header)
	_players_caption = Label.new()
	_players_caption.name = "PlayersCaption"
	_players_caption.text = tr("SETUP_PLAYER_LIST")
	_players_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Trimmed, not wrapped: a wrapping label whose height changes its parent's width can loop.
	_players_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_players_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_players_caption.add_theme_color_override("font_color", NeonPalette.CYAN)
	_header.add_child(_players_caption)
	# A toggle button (lit when on, and the text says ON/OFF): the default check-box art is
	# invisible on the neon theme.
	_watch_box = Button.new()
	_watch_box.name = "Watch"
	_watch_box.toggle_mode = true
	_watch_box.focus_mode = Control.FOCUS_NONE
	_watch_box.toggled.connect(set_watch)
	_header.add_child(_watch_box)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", NeonPalette.WARN)
	_hint.visible = false
	_players_box.add_child(_hint)
	_scroll = TouchScroll.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_players_box.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rows)
	for i: int in range(SimConstants.MAX_TANKS):
		_build_player_row(i)
	_bottom = HBoxContainer.new()
	_bottom.name = "Bottom"
	_players_box.add_child(_bottom)
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


func _build_player_row(i: int) -> void:
	var row := HBoxContainer.new()
	row.name = "Player%d" % i
	_rows.add_child(row)
	_player_rows.append(row)
	var label := Label.new()
	label.name = "Label"
	label.text = tr("SETUP_PLAYER_SHORT") % (i + 1)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	_player_labels.append(label)
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
	kb.text = tr("SETUP_HUMAN")
	kb.focus_mode = Control.FOCUS_NONE
	kb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kb.clip_text = true
	kb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	kb.pressed.connect(_open_kind_popup.bind(i))
	row.add_child(kb)
	_kind_buttons.append(kb)
	# The level chip sits inside the picker button's right end, so a CPU row needs no extra width.
	var chip := PanelContainer.new()
	chip.name = "Chip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.anchor_left = 1.0
	chip.anchor_right = 1.0
	chip.anchor_top = 0.5
	chip.anchor_bottom = 0.5
	chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	chip.grow_vertical = Control.GROW_DIRECTION_BOTH
	var chip_label := Label.new()
	chip_label.name = "Text"
	chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(chip_label)
	kb.add_child(chip)
	_chips.append(chip)
	_chip_labels.append(chip_label)


func _open_kind_popup(index: int) -> void:
	_picker.open_for(index, _controllers[index], _full_unlocked)


func _on_kind_chosen(level: int) -> void:
	set_controller(_picker.get_player(), level)


# ======================================================================================
# Scale
# ======================================================================================

func apply_scale() -> void:
	UiScale.apply_edge_margins(_margin)
	var pad: float = UiScale.dp(10.0)
	_columns.add_theme_constant_override("separation", roundi(UiScale.dp(10.0)))
	_options.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	_players_box.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	_rows.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	_bottom.add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))
	_title.add_theme_font_size_override("font_size", UiScale.hud_font(22.0))
	_players_caption.add_theme_font_size_override("font_size", UiScale.hud_font(14.0))
	var touch: float = UiScale.touch()
	for row: HBoxContainer in _option_rows:
		row.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	for l: Label in _captions:
		l.custom_minimum_size.x = UiScale.dp(96.0)
		l.add_theme_font_size_override("font_size", UiScale.hud_font(13.0))
	for b: Button in [_players_minus, _players_plus]:
		b.custom_minimum_size = Vector2.ONE * touch
		b.add_theme_font_size_override("font_size", UiScale.hud_font(20.0))
	_players_value.custom_minimum_size = Vector2(UiScale.dp(56.0), touch)
	_players_value.add_theme_font_size_override("font_size", UiScale.hud_font(20.0))
	for b: Button in _round_buttons:
		b.custom_minimum_size = Vector2(UiScale.dp(52.0), touch)
		b.add_theme_font_size_override("font_size", UiScale.hud_font(16.0))
	for b: Button in _money_buttons:
		b.custom_minimum_size = Vector2(UiScale.dp(84.0), touch)
		b.add_theme_font_size_override("font_size", UiScale.hud_font(11.0))
	for b: Button in _wind_buttons:
		b.custom_minimum_size = Vector2(UiScale.dp(66.0), touch)
		b.add_theme_font_size_override("font_size", UiScale.hud_font(12.0))
	for l: Label in _player_labels:
		l.custom_minimum_size.x = UiScale.dp(30.0)
		l.add_theme_font_size_override("font_size", UiScale.hud_font(14.0))
	for b: SwatchButton in _color_buttons:
		b.custom_minimum_size = Vector2.ONE * touch
	for b: SwatchButton in _emblem_buttons:
		b.custom_minimum_size = Vector2.ONE * touch
	for b: Button in _kind_buttons:
		b.custom_minimum_size = Vector2(UiScale.dp(92.0), touch)
		b.add_theme_font_size_override("font_size", UiScale.hud_font(12.0))
	for i: int in range(_chips.size()):
		_chips[i].offset_right = -UiScale.dp(6.0)
		_chips[i].add_theme_stylebox_override("panel", _chip_style(_controllers[i]))
		_chip_labels[i].add_theme_font_size_override("font_size", UiScale.hud_font(10.0))
	_header.add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))
	_watch_box.custom_minimum_size = Vector2(0.0, touch)
	_watch_box.add_theme_font_size_override("font_size", UiScale.hud_font(12.0))
	_hint.add_theme_font_size_override("font_size", UiScale.hud_font(12.0))
	_back.custom_minimum_size = Vector2(UiScale.dp(84.0), UiScale.dp(56.0))
	_back.add_theme_font_size_override("font_size", UiScale.hud_font(15.0))
	_start.custom_minimum_size = Vector2(UiScale.dp(120.0), UiScale.dp(56.0))
	_start.add_theme_font_size_override("font_size", UiScale.hud_font(22.0))


# ======================================================================================
# State
# ======================================================================================

func set_players(n: int) -> void:
	_players = clampi(n, SimConstants.MIN_TANKS, SimConstants.MAX_TANKS)
	_hint.text = ""
	_enforce_human_rule()
	_refresh()


func set_rounds(n: int) -> void:
	_rounds = n if ROUND_CHOICES.has(n) else DEFAULT_ROUNDS
	_refresh()


func set_money_level(level: int) -> void:
	_money_level = clampi(level, 0, MONEY_CHOICES.size() - 1)
	_refresh()


func set_wind_level(level: int) -> void:
	_wind_level = clampi(level, 0, WIND_CHOICES.size() - 1)
	_refresh()


## Chooses who controls slot `i`: SimConstants.CTRL_HUMAN or a CPU level. Returns false (and
## changes nothing) when the choice is locked (Hard/Expert without the full game) or would
## leave the match without a human while "Watch CPUs play" is off.
func set_controller(i: int, level: int) -> bool:
	if i < 0 or i >= SimConstants.MAX_TANKS or level < SimConstants.CTRL_HUMAN or level > SimConstants.CTRL_MAX:
		return false
	if _allowed_level(level) != level:
		return false
	_hint.text = ""
	if level != SimConstants.CTRL_HUMAN and i < _players and not _watch and _humans_without(i) == 0:
		_hint.text = tr("SETUP_NEED_HUMAN")
		_refresh()
		return false
	_controllers[i] = level
	_refresh()
	return true


## "Watch CPUs play": lets every slot be a CPU. Turning it off while nobody is human makes
## player 1 human again.
func set_watch(on: bool) -> void:
	_hint.text = ""
	_watch = on
	_enforce_human_rule()
	_refresh()


## Humans among the visible slots if slot `skip` were not one of them.
func _humans_without(skip: int) -> int:
	var n: int = 0
	for j: int in range(_players):
		if j != skip and _controllers[j] == SimConstants.CTRL_HUMAN:
			n += 1
	return n


func _enforce_human_rule() -> void:
	if not _watch and _humans_without(-1) == 0:
		_controllers[0] = SimConstants.CTRL_HUMAN


## Hard and Expert fall back to Normal while the full game is locked.
func _allowed_level(level: int) -> int:
	var top: int = SimConstants.CTRL_MAX if _full_unlocked else SimConstants.CTRL_FREE_MAX
	return clampi(level, SimConstants.CTRL_HUMAN, top)


## Test/billing hook: lock or unlock CPU Hard and Expert. Locking also demotes slots that
## already use them.
func set_full_unlocked(unlocked: bool) -> void:
	_full_unlocked = unlocked
	for i: int in range(_controllers.size()):
		_controllers[i] = _allowed_level(_controllers[i])
	_refresh()


## Next colour for player i. If another player has it they swap, so colours stay unique.
func cycle_color(i: int) -> void:
	_cycle(_colors, i, NeonPalette.TANK_COLORS.size())
	_refresh()


func cycle_emblem(i: int) -> void:
	_cycle(_emblems, i, NeonPalette.EMBLEM_COUNT)
	_refresh()


static func _cycle(values: PackedInt32Array, i: int, modulo: int) -> void:
	var cur: int = values[i]
	var next: int = (cur + 1) % modulo
	for j: int in range(values.size()):
		if j != i and values[j] == next:
			values[j] = cur
	values[i] = next


func get_players() -> int:
	return _players


func get_rounds() -> int:
	return _rounds


func get_color_index(i: int) -> int:
	return _colors[i]


func get_emblem_index(i: int) -> int:
	return _emblems[i]


func _refresh() -> void:
	_players_value.text = str(_players)
	_players_minus.disabled = _players <= SimConstants.MIN_TANKS
	_players_plus.disabled = _players >= SimConstants.MAX_TANKS
	for i: int in range(_round_buttons.size()):
		_round_buttons[i].set_pressed_no_signal(ROUND_CHOICES[i] == _rounds)
	for i: int in range(_money_buttons.size()):
		_money_buttons[i].set_pressed_no_signal(i == _money_level)
	for i: int in range(_wind_buttons.size()):
		_wind_buttons[i].set_pressed_no_signal(i == _wind_level)
	for i: int in range(SimConstants.MAX_TANKS):
		_player_rows[i].visible = i < _players
		var col: Color = NeonPalette.tank_color(_colors[i])
		_player_labels[i].add_theme_color_override("font_color", col)
		_color_buttons[i].set_art(col)
		_color_buttons[i].tooltip_text = tr(NeonPalette.TANK_COLOR_NAME_KEYS[_colors[i]])
		_emblem_buttons[i].set_art(col, _emblems[i])
		_emblem_buttons[i].tooltip_text = tr(NeonPalette.EMBLEM_NAME_KEYS[_emblems[i]])
		_refresh_kind(i)
	_watch_box.set_pressed_no_signal(_watch)
	_watch_box.text = "%s: %s" % [tr("SETUP_WATCH"), tr("SET_ON") if _watch else tr("SET_OFF")]
	_hint.visible = _hint.text != ""


## Slot i's picker button, level chip and tooltip.
func _refresh_kind(i: int) -> void:
	var level: int = _controllers[i]
	var cpu: bool = level != SimConstants.CTRL_HUMAN
	_kind_buttons[i].text = tr("SETUP_KIND_CPU") if cpu else tr("SETUP_HUMAN")
	_kind_buttons[i].tooltip_text = CpuNames.full_name(level)
	_chips[i].visible = cpu
	if cpu:
		_chip_labels[i].text = CpuNames.level_word(level)
		_chip_labels[i].add_theme_color_override("font_color", LEVEL_COLORS[level])
		_chips[i].add_theme_stylebox_override("panel", _chip_style(level))


## A small outlined badge in the level's colour.
func _chip_style(level: int) -> StyleBoxFlat:
	var col: Color = LEVEL_COLORS[clampi(level, 0, LEVEL_COLORS.size() - 1)]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col, 0.16)
	sb.border_color = col
	sb.set_border_width_all(maxi(1, roundi(UiScale.dp(1.5))))
	sb.set_corner_radius_all(roundi(UiScale.dp(8.0)))
	sb.set_content_margin_all(UiScale.dp(4.0))
	return sb


# ======================================================================================
# Start / back
# ======================================================================================

## The settings START would use (full game unlocked until billing exists).
func build_settings() -> MatchSettings:
	var s := MatchSettings.new()
	s.num_tanks = _players
	s.rounds = _rounds
	s.start_money = MONEY_CHOICES[_money_level]
	s.wind_max = WIND_CHOICES[_wind_level]
	s.full_unlocked = _full_unlocked
	var c := PackedInt32Array()
	for i: int in range(_players):
		c.append(_allowed_level(_controllers[i]))
	s.controllers = c
	s.seed = ShotArgs.seed_value if ShotArgs.seed_value != 0 else int(randi())
	return s


## Remembers the current choices in SetupPrefs and writes settings.cfg.
func save_prefs() -> void:
	SetupPrefs.remember(_players, _rounds, _money_level, _wind_level, _controllers, _watch)
	SettingsStore.save()


func start_match() -> void:
	save_prefs()
	BattleConfig.settings = build_settings()
	BattleConfig.resume = false
	BattleConfig.seed_value = 0
	PlayerLooks.set_looks(_colors.slice(0, _players), _emblems.slice(0, _players))
	# A new match replaces any autosave (the title asked for confirmation already).
	SaveStore.delete(BattleConfig.autosave_path)
	get_tree().change_scene_to_file(BATTLE_SCENE)


func go_back() -> void:
	save_prefs()
	get_tree().change_scene_to_file(TITLE_SCENE)


# --- accessors (tests, tools) ---

func get_start_button() -> Button:
	return _start


func get_back_button() -> Button:
	return _back


func get_player_row(i: int) -> HBoxContainer:
	return _player_rows[i]


func get_color_button(i: int) -> SwatchButton:
	return _color_buttons[i]


func get_emblem_button(i: int) -> SwatchButton:
	return _emblem_buttons[i]


func get_kind_button(i: int) -> Button:
	return _kind_buttons[i]


func get_kind_popup() -> KindPicker:
	return _picker


func get_controllers() -> PackedInt32Array:
	return _controllers.slice(0, _players)


func get_chip(i: int) -> PanelContainer:
	return _chips[i]


func get_chip_text(i: int) -> String:
	return _chip_labels[i].text


func get_watch_box() -> Button:
	return _watch_box


func is_watch() -> bool:
	return _watch


func get_hint_text() -> String:
	return _hint.text


func get_money_level() -> int:
	return _money_level


func get_wind_level() -> int:
	return _wind_level


func get_scroll() -> TouchScroll:
	return _scroll


func get_players_value_text() -> String:
	return _players_value.text


func get_round_button(n: int) -> Button:
	return _round_buttons[ROUND_CHOICES.find(n)]


func get_money_button(level: int) -> Button:
	return _money_buttons[level]


func get_wind_button(level: int) -> Button:
	return _wind_buttons[level]


func get_players_minus() -> Button:
	return _players_minus


func get_players_plus() -> Button:
	return _players_plus
