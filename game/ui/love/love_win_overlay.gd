class_name LoveWinOverlay
extends OverlayPanel
## The Love Edition's result: "PLAYER N WINS" between two drawn hearts, REMATCH (a new love match
## with the same players) and TITLE. Unlike the other overlays it does not cover the middle of the
## picture: the winner's smiley and the confetti must stay visible, so the panel sits in the half of
## the screen away from the winning tank and the backdrop is only lightly dimmed.

signal rematch_pressed
signal title_pressed

## Share of the screen width the panel may use (it lives in one half).
const MAX_WIDTH_SHARE: float = 0.46

var _title: Label = null
var _heart_l: HeartIcon = null
var _heart_r: HeartIcon = null
var _winner: int = -1
var _side_right: bool = true


func _init() -> void:
	super._init()
	name = "LoveWinOverlay"
	_dim.color = Color(NeonPalette.BG_DEEP, 0.14)
	var row: HBoxContainer = begin_row()
	row.name = "TitleRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_heart_l = HeartIcon.new()
	_heart_l.name = "HeartLeft"
	row.add_child(_heart_l)
	_title = add_label("", 23.0, NeonPalette.TEXT)
	_title.name = "Title"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_heart_r = HeartIcon.new()
	_heart_r.name = "HeartRight"
	row.add_child(_heart_r)
	end_container()
	begin_row()
	add_button(tr("LOVE_REMATCH"), 130.0).pressed.connect(func() -> void: rematch_pressed.emit())
	add_button(tr("OVERLAY_TITLE"), 100.0).pressed.connect(func() -> void: title_pressed.emit())
	end_container()
	_buttons[0].name = "Rematch"
	_buttons[1].name = "Title"
	_set_side(true)


func apply_scale() -> void:
	super.apply_scale()
	var vw: float = get_viewport_rect().size.x
	_panel.custom_minimum_size.x = minf(_panel.custom_minimum_size.x, vw * MAX_WIDTH_SHARE)
	var h: float = UiScale.dp(26.0)
	_heart_l.set_icon_size(h)
	_heart_r.set_icon_size(h)


## `winner` is the tank id; `winner_x` is where that tank is on screen as a share of the width
## (0 = left edge, 1 = right edge): the panel goes to the other half.
func show_win(winner: int, winner_x: float) -> void:
	_winner = winner
	_title.text = tr("LOVE_WIN_FMT") % (winner + 1)
	_title.add_theme_color_override("font_color", PlayerLooks.color(winner).lightened(0.15))
	_heart_l.color = Color(1.0, 0.4, 0.64)
	_heart_r.color = Color(1.0, 0.4, 0.64)
	_set_side(winner_x < 0.5)
	open()
	if is_inside_tree():
		apply_scale()


## The panel lives in the right half (true) or the left half of the screen.
func _set_side(right: bool) -> void:
	_side_right = right
	_center.anchor_left = 0.5 if right else 0.0
	_center.anchor_right = 1.0 if right else 0.5
	_center.offset_left = 0.0
	_center.offset_right = 0.0


func get_title_text() -> String:
	return _title.text


func get_winner() -> int:
	return _winner


func is_on_right() -> bool:
	return _side_right


func get_panel() -> PanelContainer:
	return _panel


func get_rematch_button() -> Button:
	return _buttons[0]


func get_title_button() -> Button:
	return _buttons[1]
