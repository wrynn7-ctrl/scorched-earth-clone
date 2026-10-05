class_name LoveWinOverlay
extends OverlayPanel
## The Love Edition's result: "PLAYER N WINS" between two drawn hearts, REMATCH (a new love match
## with the same players) and TITLE, all in one slim strip along the bottom edge. Unlike the other
## overlays it leaves the picture alone: both tanks, the winner's smiley and the confetti stay
## visible, and the backdrop is only lightly dimmed.

signal rematch_pressed
signal title_pressed

## The strip's widest size (dp) and the share of the screen width it may use.
const STRIP_DP: float = 600.0
const MAX_WIDTH_SHARE: float = 0.96

var _title: Label = null
var _heart_l: HeartIcon = null
var _heart_r: HeartIcon = null
var _winner: int = -1
var _column: VBoxContainer = null
var _gap: Control = null


func _init() -> void:
	super._init()
	name = "LoveWinOverlay"
	_dim.color = Color(NeonPalette.BG_DEEP, 0.14)
	# Bottom-anchored instead of centred: the base class' centred container stays empty.
	_center.remove_child(_panel)
	_column = VBoxContainer.new()
	_column.name = "Bottom"
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.alignment = BoxContainer.ALIGNMENT_END
	_column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_column)
	move_child(_column, get_child_count() - 2)  # under the input shield
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_column.add_child(_panel)
	_gap = Control.new()
	_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_gap)
	var row: HBoxContainer = begin_row()
	row.name = "Strip"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_heart_l = HeartIcon.new()
	_heart_l.name = "HeartLeft"
	row.add_child(_heart_l)
	_title = add_label("", 19.0, NeonPalette.TEXT)
	_title.name = "Title"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_heart_r = HeartIcon.new()
	_heart_r.name = "HeartRight"
	row.add_child(_heart_r)
	add_button(tr("LOVE_REMATCH"), 120.0).pressed.connect(func() -> void: rematch_pressed.emit())
	add_button(tr("OVERLAY_TITLE"), 90.0).pressed.connect(func() -> void: title_pressed.emit())
	end_container()
	_buttons[0].name = "Rematch"
	_buttons[1].name = "Title"


func apply_scale() -> void:
	super.apply_scale()
	var vw: float = get_viewport_rect().size.x
	_panel.custom_minimum_size.x = minf(UiScale.dp(STRIP_DP), vw * MAX_WIDTH_SHARE)
	_gap.custom_minimum_size.y = UiScale.dp(UiScale.EDGE_MARGIN_DP)
	var h: float = UiScale.dp(22.0)
	_heart_l.set_icon_size(h)
	_heart_r.set_icon_size(h)


## `winner` is the tank id. (`winner_x`, the winner's place on screen as a share of the width, is kept for the
## caller's convenience; the strip does not move.)
func show_win(winner: int, _winner_x: float = 0.5) -> void:
	_winner = winner
	_title.text = tr("LOVE_WIN_FMT") % PlayerNames.label(winner)
	_title.add_theme_color_override("font_color", PlayerLooks.color(winner).lightened(0.15))
	_heart_l.color = Color(1.0, 0.4, 0.64)
	_heart_r.color = Color(1.0, 0.4, 0.64)
	open()
	if is_inside_tree():
		apply_scale()


func get_title_text() -> String:
	return _title.text


func get_winner() -> int:
	return _winner


func get_panel() -> PanelContainer:
	return _panel


func get_rematch_button() -> Button:
	return _buttons[0]


func get_title_button() -> Button:
	return _buttons[1]
