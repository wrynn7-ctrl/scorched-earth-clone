class_name SetupScreen
extends Control
## Match setup (from the title's START): players 2-8 (every slot human for now), rounds,
## starting money, wind, and each player's colour and emblem. START creates the match settings
## (full game unlocked) and loads the battle, which opens the first shop.
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

var _players: int = 2
var _rounds: int = DEFAULT_ROUNDS
var _money_level: int = DEFAULT_MONEY_LEVEL
var _wind_level: int = DEFAULT_WIND_LEVEL
var _colors: PackedInt32Array = PackedInt32Array()
var _emblems: PackedInt32Array = PackedInt32Array()

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
var _scroll: ScrollContainer = null
var _rows: VBoxContainer = null
var _player_rows: Array[HBoxContainer] = []
var _player_labels: Array[Label] = []
var _color_buttons: Array[SwatchButton] = []
var _emblem_buttons: Array[SwatchButton] = []
var _kind_buttons: Array[Button] = []
var _kind_popup: PopupPanel = null
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
	if ShotArgs.players >= SimConstants.MIN_TANKS:
		_players = clampi(ShotArgs.players, SimConstants.MIN_TANKS, SimConstants.MAX_TANKS)
	_build()


func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	apply_scale()
	LayoutWatch.attach(self, apply_scale)
	_refresh()
	ShotHook.attach(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
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
	_columns = HBoxContainer.new()
	_columns.name = "Columns"
	_margin.add_child(_columns)
	_build_options()
	_build_players()
	_kind_popup = _build_kind_popup()
	add_child(_kind_popup)


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
	_players_caption = Label.new()
	_players_caption.name = "PlayersCaption"
	_players_caption.text = tr("SETUP_PLAYER_LIST")
	_players_caption.add_theme_color_override("font_color", NeonPalette.CYAN)
	_players_box.add_child(_players_caption)
	_scroll = ScrollContainer.new()
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
	kb.pressed.connect(_open_kind_popup.bind(i))
	row.add_child(kb)
	_kind_buttons.append(kb)


## The HUMAN / "AI - COMING SOON" chooser. The AI entry is disabled until M4.
func _build_kind_popup() -> PopupPanel:
	var popup := PopupPanel.new()
	popup.name = "KindPopup"
	var box := VBoxContainer.new()
	box.name = "Box"
	popup.add_child(box)
	var human := Button.new()
	human.name = "Human"
	human.text = tr("SETUP_HUMAN")
	human.focus_mode = Control.FOCUS_NONE
	human.pressed.connect(popup.hide)
	box.add_child(human)
	var ai := Button.new()
	ai.name = "Ai"
	ai.text = tr("SETUP_AI_SOON")
	ai.disabled = true
	ai.focus_mode = Control.FOCUS_NONE
	box.add_child(ai)
	return popup


func _open_kind_popup(index: int) -> void:
	var b: Button = _kind_buttons[index]
	var pos: Vector2 = b.get_screen_position() + Vector2(0.0, b.size.y)
	_kind_popup.popup(Rect2i(Vector2i(pos), Vector2i.ZERO))


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
		l.custom_minimum_size.x = UiScale.dp(34.0)
		l.add_theme_font_size_override("font_size", UiScale.hud_font(14.0))
	for b: SwatchButton in _color_buttons:
		b.custom_minimum_size = Vector2.ONE * touch
	for b: SwatchButton in _emblem_buttons:
		b.custom_minimum_size = Vector2.ONE * touch
	for b: Button in _kind_buttons:
		b.custom_minimum_size = Vector2(UiScale.dp(96.0), touch)
		b.add_theme_font_size_override("font_size", UiScale.hud_font(12.0))
	_back.custom_minimum_size = Vector2(UiScale.dp(84.0), UiScale.dp(56.0))
	_back.add_theme_font_size_override("font_size", UiScale.hud_font(15.0))
	_start.custom_minimum_size = Vector2(UiScale.dp(120.0), UiScale.dp(56.0))
	_start.add_theme_font_size_override("font_size", UiScale.hud_font(22.0))
	for n: Node in _kind_popup.find_children("*", "Button", true, false):
		(n as Button).custom_minimum_size = Vector2(UiScale.dp(220.0), touch)
		(n as Button).add_theme_font_size_override("font_size", UiScale.hud_font(14.0))


# ======================================================================================
# State
# ======================================================================================

func set_players(n: int) -> void:
	_players = clampi(n, SimConstants.MIN_TANKS, SimConstants.MAX_TANKS)
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
	s.full_unlocked = true
	s.seed = ShotArgs.seed_value if ShotArgs.seed_value != 0 else int(randi())
	return s


func start_match() -> void:
	BattleConfig.settings = build_settings()
	BattleConfig.resume = false
	BattleConfig.seed_value = 0
	PlayerLooks.set_looks(_colors.slice(0, _players), _emblems.slice(0, _players))
	# A new match replaces any autosave (the title asked for confirmation already).
	SaveStore.delete(BattleConfig.autosave_path)
	get_tree().change_scene_to_file(BATTLE_SCENE)


func go_back() -> void:
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


func get_kind_popup() -> PopupPanel:
	return _kind_popup


func get_scroll() -> ScrollContainer:
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
