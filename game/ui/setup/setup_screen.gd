class_name SetupScreen
extends Control
## Match setup (from the title's START): players 2-8, who controls each slot (Human or a CPU
## from Easy to Expert), rounds, starting money, wind, and each player's colour and emblem.
## START creates the match settings (with `full_unlocked` = the player's Entitlement) and loads the
## battle, which opens the first shop. The last-used setup is remembered (SetupPrefs / SettingsStore).
##
## Free version (ARCHITECTURE section 32): 4 players, 2 humans, CPU Easy/Normal, rounds 1/3/5,
## Normal money and wind, the two free themes. Locked options stay visible with a padlock; tapping
## one opens the Unlock screen, and a purchase unlocks them live (no restart).
##
## At least one slot must be human, unless "Watch CPUs play" is ticked.
##
## Layout: options on the left, one scrolling row per player on the right, BACK / START under
## the player list. Everything is containers and dp sizes, so it fits phones and tablets.

const BATTLE_SCENE: String = "res://show/battle/battle_scene.tscn"
const TITLE_SCENE: String = "res://ui/title/title_screen.tscn"
const THEME: Theme = preload("res://ui/theme/neon_theme.tres")

## Reported when an option that needs the full game is tapped without it. `kind` is one of
## "players", "human", "rounds", "money", "wind", "theme", "cpu" (UnlockScreen.CONTEXT_KEYS); the
## Unlock screen opens from here.
signal locked_tapped(kind: String, id: String)

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
## Humans sharing one device without the full game.
const FREE_MAX_HUMANS: int = 2
## From this screen width (dp) a human's name field sits in the same line as its colour, emblem and
## picker; below it the field gets a line of its own (a 12-capital name needs about 150 dp).
const NAME_INLINE_MIN_DP: float = 960.0

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
## The name typed for every slot ("" = PLAYER n). Hidden and CPU slots keep theirs.
var _names: PackedStringArray = PackedStringArray()
var _watch: bool = false
## False locks everything section 32 reserves for the full game. Follows Entitlement live.
var _full_unlocked: bool = true
## Terrain theme: a ThemeDefs id or "random" (visual only, applied in the battle).
var _theme: String = ThemeDefs.DEFAULT_ID

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
## One container per slot: the row (label, swatches, picker) and, on narrow screens, the name field below it.
var _slots: Array[VBoxContainer] = []
var _player_rows: Array[HBoxContainer] = []
var _name_fields: Array[NameField] = []
var _player_labels: Array[Label] = []
var _color_buttons: Array[SwatchButton] = []
var _emblem_buttons: Array[SwatchButton] = []
var _kind_buttons: Array[Button] = []
var _picker: KindPicker = null
var _theme_button: Button = null
var _theme_picker: ThemePicker = null
var _unlock: UnlockScreen = null
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
	_names.resize(SimConstants.MAX_TANKS)
	_full_unlocked = ThemeDefs.is_full_game()
	_load_prefs()
	if ShotArgs.players >= SimConstants.MIN_TANKS:
		_players = clampi(ShotArgs.players, SimConstants.MIN_TANKS, SimConstants.MAX_TANKS)
	for i: int in range(mini(ShotArgs.controllers.size(), SimConstants.MAX_TANKS)):
		_controllers[i] = _allowed_level(ShotArgs.controllers[i])
	for i: int in range(mini(ShotArgs.names.size(), SimConstants.MAX_TANKS)):
		_names[i] = PlayerNames.sanitize(ShotArgs.names[i])
	_enforce_free_rules()
	_build()


func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	apply_scale()
	LayoutWatch.attach(self, apply_scale)
	Entitlement.hub().changed.connect(_on_entitlement_changed)
	_refresh()
	ShotHook.attach(self)
	for i: int in range(SimConstants.MAX_TANKS):
		_name_fields[i].set_name_text(_names[i])
	if ShotArgs.focus_name > 0:
		_name_fields[clampi(ShotArgs.focus_name - 1, 0, SimConstants.MAX_TANKS - 1)].grab_focus.call_deferred()
	if ShotArgs.setup_picker > 0:
		_open_kind_popup.call_deferred(clampi(ShotArgs.setup_picker - 1, 0, SimConstants.MAX_TANKS - 1))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _unlock != null and _unlock.is_open():
			_unlock.close()
		elif _theme_picker != null and _theme_picker.is_open():
			_theme_picker.close()
		elif _picker != null and _picker.is_open():
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
	_theme = SetupPrefs.theme if _theme_allowed(SetupPrefs.theme) else ThemeDefs.DEFAULT_ID
	for i: int in range(SimConstants.MAX_TANKS):
		_controllers[i] = _allowed_level(SetupPrefs.controllers[i] if i < SetupPrefs.controllers.size() else 0)
		_names[i] = SetupPrefs.names[i] if i < SetupPrefs.names.size() else ""
	_enforce_free_rules()
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
	_theme_picker = ThemePicker.new()
	_theme_picker.chosen.connect(choose_theme)
	_theme_picker.locked_chosen.connect(_on_theme_locked)
	add_child(_theme_picker)
	_picker.locked_chosen.connect(_on_kind_locked)
	_unlock = UnlockScreen.new()
	add_child(_unlock)
	locked_tapped.connect(_on_locked_tapped)


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

	row = _option_row("ThemeRow", tr("SETUP_THEME"))
	_theme_button = Button.new()
	_theme_button.name = "Theme"
	_theme_button.focus_mode = Control.FOCUS_NONE
	_theme_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_theme_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_theme_button.expand_icon = true
	_theme_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_theme_button.clip_text = true
	_theme_button.pressed.connect(open_theme_picker)
	row.add_child(_theme_button)


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
	var slot := VBoxContainer.new()
	slot.name = "Slot%d" % i
	_rows.add_child(slot)
	_slots.append(slot)
	var row := HBoxContainer.new()
	row.name = "Player%d" % i
	slot.add_child(row)
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
	# Only Human slots have a name. The field starts below the row; _place_name_field moves it
	# into the row on wide screens. (M6-U2: the team chip goes at the end of the row.)
	var nf := NameField.new()
	nf.name = "Name"
	nf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nf.tooltip_text = tr("SETUP_NAME_TIP")
	nf.committed.connect(_on_name_committed.bind(i))
	nf.focus_entered.connect(_on_name_focus.bind(i))
	slot.add_child(nf)
	_name_fields.append(nf)


func _open_kind_popup(index: int) -> void:
	_picker.open_for(index, _controllers[index], _full_unlocked, _human_locked(index))


func _on_kind_locked(level: int) -> void:
	if level == SimConstants.CTRL_HUMAN:
		_lock_tapped("human", "")
	else:
		_lock_tapped("cpu", str(level))


func _on_kind_chosen(level: int) -> void:
	set_controller(_picker.get_player(), level)


# ======================================================================================
# Scale
# ======================================================================================

func apply_scale() -> void:
	UiScale.apply_edge_margins(_margin)
	var pad: float = UiScale.dp(10.0)
	_columns.add_theme_constant_override("separation", roundi(UiScale.dp(10.0)))
	_options.add_theme_constant_override("separation", roundi(UiScale.dp(3.0)))
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
	_theme_button.custom_minimum_size = Vector2(UiScale.dp(200.0), touch)
	_theme_button.add_theme_font_size_override("font_size", UiScale.hud_font(13.0))
	_theme_button.add_theme_constant_override("icon_max_width", roundi(UiScale.dp(44.0)))
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
	var inline_names: bool = names_inline()
	for i: int in range(_name_fields.size()):
		_name_fields[i].apply_scale()
		_place_name_field(i, inline_names)
		_slots[i].add_theme_constant_override("separation", roundi(UiScale.dp(3.0)))
	_header.add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))
	_watch_box.custom_minimum_size = Vector2(0.0, touch)
	_watch_box.add_theme_font_size_override("font_size", UiScale.hud_font(12.0))
	_hint.add_theme_font_size_override("font_size", UiScale.hud_font(12.0))
	_back.custom_minimum_size = Vector2(UiScale.dp(84.0), UiScale.dp(56.0))
	_back.add_theme_font_size_override("font_size", UiScale.hud_font(15.0))
	_start.custom_minimum_size = Vector2(UiScale.dp(120.0), UiScale.dp(56.0))
	_start.add_theme_font_size_override("font_size", UiScale.hud_font(22.0))
	_refresh_locks()


# ======================================================================================
# State
# ======================================================================================

## Sets the player count. Returns false when 5..8 is asked for without the full game (the Unlock
## screen opens instead). Extra humans beyond FREE_MAX_HUMANS become CPUs in the free version.
func set_players(n: int) -> bool:
	var want: int = clampi(n, SimConstants.MIN_TANKS, SimConstants.MAX_TANKS)
	if players_locked(want):
		_lock_tapped("players", str(want))
		return false
	_players = want
	_hint.text = ""
	_enforce_free_rules()
	_enforce_human_rule()
	_refresh()
	return true


func set_rounds(n: int) -> bool:
	if rounds_locked(n):
		_lock_tapped("rounds", str(n))
		return false
	_rounds = n if ROUND_CHOICES.has(n) else DEFAULT_ROUNDS
	_refresh()
	return true


func set_money_level(level: int) -> bool:
	var want: int = clampi(level, 0, MONEY_CHOICES.size() - 1)
	if money_locked(want):
		_lock_tapped("money", str(want))
		return false
	_money_level = want
	_refresh()
	return true


func set_wind_level(level: int) -> bool:
	var want: int = clampi(level, 0, WIND_CHOICES.size() - 1)
	if wind_locked(want):
		_lock_tapped("wind", str(want))
		return false
	_wind_level = want
	_refresh()
	return true


# --- what the free version may not do (ARCHITECTURE section 32) ---

func players_locked(n: int) -> bool:
	return not _full_unlocked and n > SimConstants.FREE_MAX_TANKS


func rounds_locked(n: int) -> bool:
	return not _full_unlocked and n > SimConstants.FREE_MAX_ROUNDS


func money_locked(level: int) -> bool:
	return not _full_unlocked and level != DEFAULT_MONEY_LEVEL


func wind_locked(level: int) -> bool:
	return not _full_unlocked and level != DEFAULT_WIND_LEVEL


## Choosing Human for slot `i` would exceed FREE_MAX_HUMANS on this device.
func _human_locked(i: int) -> bool:
	return not _full_unlocked and i < _players and _humans_without(i) >= FREE_MAX_HUMANS


## Brings every choice inside the free limits (used when the tier drops, and on load).
func _enforce_free_rules() -> void:
	if _full_unlocked:
		return
	_players = mini(_players, SimConstants.FREE_MAX_TANKS)
	if rounds_locked(_rounds):
		_rounds = DEFAULT_ROUNDS
	_money_level = DEFAULT_MONEY_LEVEL
	_wind_level = DEFAULT_WIND_LEVEL
	var humans: int = 0
	for i: int in range(_controllers.size()):
		_controllers[i] = _allowed_level(_controllers[i])
		if i < _players and _controllers[i] == SimConstants.CTRL_HUMAN:
			humans += 1
			if humans > FREE_MAX_HUMANS:
				_controllers[i] = SimConstants.CTRL_FREE_MAX
	if not _theme_allowed(_theme):
		_theme = ThemeDefs.DEFAULT_ID


## A locked option was tapped: say why and let the host open the Unlock screen.
func _lock_tapped(kind: String, id: String) -> void:
	var key: String = UnlockScreen.CONTEXT_KEYS.get(kind, "UNLOCK_CTX_THEME") as String
	_hint.text = tr(key)
	_refresh()
	locked_tapped.emit(kind, id)


func _on_locked_tapped(kind: String, _id: String) -> void:
	_unlock.open_for(kind)


## The player bought (or lost) the full game while this screen is up.
func _on_entitlement_changed() -> void:
	set_full_unlocked(ThemeDefs.is_full_game())
	_hint.text = ""
	_refresh()


func get_unlock_screen() -> UnlockScreen:
	return _unlock


## Chooses who controls slot `i`: SimConstants.CTRL_HUMAN or a CPU level. Returns false (and
## changes nothing) when the choice is locked (Hard/Expert without the full game) or would
## leave the match without a human while "Watch CPUs play" is off.
func set_controller(i: int, level: int) -> bool:
	if i < 0 or i >= SimConstants.MAX_TANKS or level < SimConstants.CTRL_HUMAN or level > SimConstants.CTRL_MAX:
		return false
	if _allowed_level(level) != level:
		_lock_tapped("cpu", str(level))
		return false
	if level == SimConstants.CTRL_HUMAN and _human_locked(i):
		_lock_tapped("human", "")
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


## Billing / test hook: switch the whole tier. Locking also pulls every choice back inside the
## free limits (players, humans, CPU levels, rounds, money, wind, theme).
func set_full_unlocked(unlocked: bool) -> void:
	_full_unlocked = unlocked
	_enforce_free_rules()
	_refresh()


func get_theme_choice() -> String:
	return _theme


## Chooses the terrain theme (a ThemeDefs id or "random"). A theme that needs the full game is
## refused (returns false, shows the lock hint and emits locked_tapped).
func choose_theme(id: String) -> bool:
	var clean: String = ThemeDefs.sanitize(id)
	if clean != id:
		return false
	if not _theme_allowed(clean):
		_on_theme_locked(clean)
		return false
	_hint.text = ""
	_theme = clean
	_refresh()
	return true


func _theme_allowed(id: String) -> bool:
	return ThemeDefs.sanitize(id) == id and not ThemeDefs.is_locked(id, _full_unlocked)


func _on_theme_locked(id: String) -> void:
	_hint.text = tr("SETUP_THEME_LOCKED")
	_refresh()
	locked_tapped.emit("theme", id)


func open_theme_picker() -> void:
	_theme_picker.open_for(_theme, _full_unlocked)


func get_theme_button() -> Button:
	return _theme_button


func get_theme_picker() -> ThemePicker:
	return _theme_picker


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
		_slots[i].visible = i < _players
		var col: Color = NeonPalette.tank_color(_colors[i])
		_player_labels[i].add_theme_color_override("font_color", col)
		_color_buttons[i].set_art(col)
		_color_buttons[i].tooltip_text = tr(NeonPalette.TANK_COLOR_NAME_KEYS[_colors[i]])
		_emblem_buttons[i].set_art(col, _emblems[i])
		_emblem_buttons[i].tooltip_text = tr(NeonPalette.EMBLEM_NAME_KEYS[_emblems[i]])
		_refresh_kind(i)
	_theme_button.text = "%s ▾" % tr(ThemeDefs.name_key(_theme))
	_theme_button.icon = ThemeSwatch.texture(_theme)
	_theme_button.tooltip_text = tr(ThemeDefs.name_key(_theme))
	_sky.apply_theme(ThemeDefs.DEFAULT_ID if _theme == ThemeDefs.RANDOM else _theme)  # live preview
	_watch_box.set_pressed_no_signal(_watch)
	_watch_box.text = "%s: %s" % [tr("SETUP_WATCH"), tr("SET_ON") if _watch else tr("SET_OFF")]
	_hint.visible = _hint.text != ""
	_refresh_locks()


## Padlocks on every option the free version cannot use. They stay visible and tappable.
func _refresh_locks() -> void:
	if _players_plus == null:
		return
	LockBadge.mark(_players_plus, players_locked(_players + 1) and _players < SimConstants.MAX_TANKS,
			tr("LOCK_FULL_FMT") % tr("SETUP_PLAYERS"), tr("SETUP_PLAYERS"))
	for i: int in range(_round_buttons.size()):
		var n: int = ROUND_CHOICES[i]
		LockBadge.mark(_round_buttons[i], rounds_locked(n), tr("LOCK_FULL_FMT") % str(n), str(n))
	for i: int in range(_money_buttons.size()):
		var label: String = tr(MONEY_KEYS[i])
		LockBadge.mark(_money_buttons[i], money_locked(i), tr("LOCK_FULL_FMT") % label, label)
	for i: int in range(_wind_buttons.size()):
		var label: String = tr(WIND_KEYS[i])
		LockBadge.mark(_wind_buttons[i], wind_locked(i), tr("LOCK_FULL_FMT") % label, label)


## Slot i's picker button (HUMAN, or CPU with its level spelled out) and name field.
func _refresh_kind(i: int) -> void:
	var level: int = _controllers[i]
	var cpu: bool = level != SimConstants.CTRL_HUMAN
	var kb: Button = _kind_buttons[i]
	kb.text = tr("SETUP_KIND_CPU_FMT") % CpuNames.level_word(level) if cpu else tr("SETUP_HUMAN")
	kb.tooltip_text = CpuNames.full_name(level)
	# Level colour on the text (the words are the cue, the colour only helps).
	kb.add_theme_color_override("font_color", LEVEL_COLORS[clampi(level, 0, LEVEL_COLORS.size() - 1)] if cpu else NeonPalette.TEXT)
	_name_fields[i].visible = not cpu
	_name_fields[i].placeholder_text = tr("HUD_PLAYER_N") % (i + 1)
	# Inline, the name takes the free width and the picker keeps its own; otherwise the picker fills the row.
	kb.size_flags_horizontal = Control.SIZE_SHRINK_END if (names_inline() and not cpu) else Control.SIZE_EXPAND_FILL


# --- names ---

## True when the name fields sit inside the player rows (wide screens).
func names_inline() -> bool:
	return UiScale.canvas_to_dp(get_viewport_rect().size.x) >= NAME_INLINE_MIN_DP


## Puts slot i's name field into its row (before the picker) or below it.
func _place_name_field(i: int, inline: bool) -> void:
	var nf: NameField = _name_fields[i]
	var target: Node = _player_rows[i] if inline else _slots[i]
	if nf.get_parent() != target:
		nf.get_parent().remove_child(nf)
		target.add_child(nf)
	if inline:
		target.move_child(nf, _kind_buttons[i].get_index())
	_refresh_kind(i)


func _on_name_committed(player_name: String, blocked: bool, i: int) -> void:
	_names[i] = player_name
	if blocked:
		_hint.text = tr("SETUP_NAME_BLOCKED") % (tr("HUD_PLAYER_N") % (i + 1))
	elif _hint.text == tr("SETUP_NAME_BLOCKED") % (tr("HUD_PLAYER_N") % (i + 1)):
		_hint.text = ""
	_hint.visible = _hint.text != ""
	_keyboard_shift(0.0)


func _on_name_focus(i: int) -> void:
	_scroll.ensure_control_visible(_name_fields[i])


## Types `raw` into slot i's field and finishes the edit, as the keyboard's Done key would.
## Returns the name that was kept ("" for an empty or blocked name).
func set_player_name(i: int, raw: String) -> String:
	_name_fields[i].text = raw
	_name_fields[i].commit()
	return _names[i]


## What slot i will be called: its name, or PLAYER n.
func get_player_name(i: int) -> String:
	return _names[i] if _names[i] != "" else tr("HUD_PLAYER_N") % (i + 1)


func get_name_field(i: int) -> NameField:
	return _name_fields[i]


## Names for the battle: a Human's typed name, "" for a CPU slot.
func battle_names() -> PackedStringArray:
	var out := PackedStringArray()
	for i: int in range(_players):
		out.append(_names[i] if _controllers[i] == SimConstants.CTRL_HUMAN else "")
	return out


## A tap anywhere else ends the edit (the keyboard goes away); Godot would keep the field focused.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused is NameField and not focused.get_global_rect().has_point((event as InputEventMouseButton).position):
		focused.release_focus()


func _process(_delta: float) -> void:
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused is NameField and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		var kb: float = float(DisplayServer.virtual_keyboard_get_height())
		if kb > 0.0:
			var room: float = get_viewport_rect().size.y - kb
			# The field's rect already includes the shift applied so far.
			_keyboard_shift(maxf(0.0, focused.get_global_rect().end.y + UiScale.dp(8.0) - room - _margin.offset_top))
			return
	if _margin.offset_top != 0.0:
		_keyboard_shift(0.0)


## Slides the whole layout up by `amount` canvas units so the focused field clears the on-screen keyboard.
func _keyboard_shift(amount: float) -> void:
	_margin.offset_top = -amount
	_margin.offset_bottom = -amount


# ======================================================================================
# Start / back
# ======================================================================================

## The settings START would use. `full_unlocked` follows the player's entitlement; the free caps
## are applied here too (the core clamps them again).
func build_settings() -> MatchSettings:
	_enforce_free_rules()
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
	SetupPrefs.remember(_players, _rounds, _money_level, _wind_level, _controllers, _watch, _theme, _names)
	SettingsStore.save()


func start_match() -> void:
	save_prefs()
	BattleConfig.settings = build_settings()
	BattleConfig.resume = false
	BattleConfig.seed_value = 0
	BattleConfig.theme = _theme
	PlayerLooks.set_looks(_colors.slice(0, _players), _emblems.slice(0, _players))
	PlayerNames.set_names(battle_names())
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


## The row of slot i (label, swatches, picker); the slot itself also holds a narrow screen's name field.
func get_player_row(i: int) -> HBoxContainer:
	return _player_rows[i]


func get_player_slot(i: int) -> VBoxContainer:
	return _slots[i]


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
