class_name NameField
extends LineEdit
## A one-line player name editor in the neon style (setup screen; M7 can reuse it). Tap it and the
## Android keyboard appears. While typing, the text is kept clean (NameFilter.clean, in capitals,
## at most NameFilter.MAX_LENGTH characters); when the player finishes (Done on the keyboard, or
## the field loses focus) the name is checked once and `committed` fires.
##
## An empty or blocked name is emptied again, so the placeholder ("PLAYER 2") shows what will be
## used. `committed(name, blocked)`: `name` is "" in both cases, `blocked` tells them apart.

signal committed(player_name: String, blocked: bool)

## Widest realistic name, used to size the text so a full 12 capitals always fit.
const WIDEST: String = "WWWWWWWWWWWW"
const BASE_FONT_DP: float = 13.0
const MIN_FONT_DP: float = 8.0

var _fitting: bool = false


func _init() -> void:
	name = "NameField"
	max_length = NameFilter.MAX_LENGTH
	select_all_on_focus = false
	context_menu_enabled = false
	# Android (and iOS) raise their keyboard; a desktop or headless display server has none (and complains).
	virtual_keyboard_enabled = DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD)
	virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	caret_blink = true
	focus_mode = Control.FOCUS_CLICK
	text_changed.connect(_on_text_changed)
	text_submitted.connect(_on_text_submitted)
	focus_exited.connect(commit)
	resized.connect(fit_font)
	_apply_style()


func _apply_style() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(NeonPalette.BG_DEEP, 0.9)
	normal.border_color = Color(NeonPalette.CYAN, 0.7)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(10)
	normal.content_margin_left = 10.0
	normal.content_margin_right = 10.0
	normal.content_margin_top = 4.0
	normal.content_margin_bottom = 4.0
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("read_only", normal)
	var focus: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	focus.border_color = NeonPalette.HOT
	add_theme_stylebox_override("focus", focus)
	add_theme_color_override("font_color", NeonPalette.TEXT)
	add_theme_color_override("font_placeholder_color", NeonPalette.TEXT_DIM)
	add_theme_color_override("caret_color", NeonPalette.HOT)
	add_theme_color_override("selection_color", Color(NeonPalette.CYAN, 0.35))


## Tap-target height and text size for the current screen. Call again when the scale changes.
func apply_scale() -> void:
	custom_minimum_size.y = UiScale.touch()
	fit_font()


## Largest font size (up to BASE_FONT_DP) at which twelve capital W still fit between the margins.
func fit_font() -> void:
	if _fitting:
		return
	_fitting = true
	var base: int = UiScale.hud_font(BASE_FONT_DP)
	var chosen: int = base
	var font: Font = get_theme_font("font")
	var room: float = size.x - 20.0
	if font != null and room > 0.0:
		var w: float = font.get_string_size(WIDEST, HORIZONTAL_ALIGNMENT_LEFT, -1.0, base).x
		if w > room:
			chosen = maxi(roundi(UiScale.dp(MIN_FONT_DP)), floori(float(base) * room / w))
	add_theme_font_size_override("font_size", chosen)
	_fitting = false


## Sets the shown text without firing anything (cleaned, in capitals).
func set_name_text(value: String) -> void:
	text = NameFilter.clean(value).to_upper()


func _on_text_changed(new_text: String) -> void:
	var cleaned: String = NameFilter.clean(new_text, false).to_upper().substr(0, NameFilter.MAX_LENGTH)
	if cleaned != new_text:
		var caret: int = caret_column
		text = cleaned
		caret_column = mini(caret, cleaned.length())


func _on_text_submitted(_value: String) -> void:
	if has_focus():
		release_focus()  # focus_exited commits
	else:
		commit()


## Checks the name now: keeps it, or empties the field when it is empty or blocked.
func commit() -> void:
	var raw: String = NameFilter.clean(text)
	var kept: String = PlayerNames.sanitize(raw)
	var blocked: bool = raw != "" and kept == ""
	if text != kept:
		text = kept
	committed.emit(kept, blocked)
