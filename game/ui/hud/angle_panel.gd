class_name AnglePanel
extends PanelContainer
## Angle readout with 0.1° fine-tune buttons (long-press repeats), screen-relative:
## the left button turns the barrel toward the left of the screen, the right button toward the
## right. The readout is the elevation on the side the tank faces ("45.0°") with a small chevron
## showing that side, so facing right the left button raises the number and the right lowers it;
## facing left it is the other way round. The raw core angle (0 right, 900 up, 1800 left) is
## what angle_changed / set_angle_tenths carry. Left = +1 tenth, right = -1 tenth.
## `angle_changed` is emitted only for user input on the buttons; set_angle_tenths() is silent.

signal angle_changed(tenths: int)

## Spoken after the number (accessibility name of the readout), keyed by HudFormat.facing_of().
const FACING_KEYS: Dictionary = {
	HudFormat.FACING_RIGHT: "HUD_FACING_RIGHT",
	HudFormat.FACING_LEFT: "HUD_FACING_LEFT",
	HudFormat.FACING_UP: "HUD_FACING_UP",
}

var _angle: int = 450
var _caption: Label = null
var _readout: Label = null
var _mark_left: FacingMark = null
var _mark_right: FacingMark = null
var _left: FineButton = null
var _right: FineButton = null
var _row: HBoxContainer = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.name = "Box"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_caption = Label.new()
	_caption.name = "Caption"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_color_override("font_color", NeonPalette.TEXT_DIM)
	box.add_child(_caption)
	var read_row := HBoxContainer.new()
	read_row.name = "ReadRow"
	read_row.alignment = BoxContainer.ALIGNMENT_CENTER
	read_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(read_row)
	_mark_left = _make_mark("MarkLeft", HudFormat.FACING_LEFT)
	read_row.add_child(_mark_left)
	_readout = Label.new()
	_readout.name = "Readout"
	_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_readout.add_theme_color_override("font_color", NeonPalette.CYAN)
	read_row.add_child(_readout)
	_mark_right = _make_mark("MarkRight", HudFormat.FACING_RIGHT)
	read_row.add_child(_mark_right)
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_row)
	_left = _make_button("Left", FineButton.Arrow.LEFT, 1)
	_row.add_child(_left)
	_right = _make_button("Right", FineButton.Arrow.RIGHT, -1)
	_row.add_child(_right)


func _make_mark(node_name: String, side: int) -> FacingMark:
	var m := FacingMark.new()
	m.name = node_name
	m.side = side
	return m


## `direction` is the raw change per step: the barrel moves toward the arrow's side of the screen.
func _make_button(node_name: String, arrow: int, direction: int) -> FineButton:
	var b := FineButton.new()
	b.name = node_name
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.arrow = arrow
	b.stepped.connect(_on_step.bind(direction))
	return b


func _ready() -> void:
	apply_scale()
	_refresh()


func apply_scale() -> void:
	_caption.add_theme_font_size_override("font_size", UiScale.hud_font(11.0))
	var font_px: int = UiScale.hud_font(26.0)
	_readout.add_theme_font_size_override("font_size", font_px)
	_mark_left.fit_to_font(font_px)
	_mark_right.fit_to_font(font_px)
	var bs := Vector2(UiScale.dp(64.0), UiScale.touch() * 1.05)
	_left.custom_minimum_size = bs
	_right.custom_minimum_size = bs
	_row.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))


func set_angle_tenths(a: int) -> void:
	_angle = clampi(a, 0, HudFormat.ANGLE_MAX)
	_refresh()


func get_angle_tenths() -> int:
	return _angle


func _on_step(multiplier: int, direction: int) -> void:
	var a: int = clampi(_angle + direction * multiplier, 0, HudFormat.ANGLE_MAX)
	if a != _angle:
		_angle = a
		_refresh()
		angle_changed.emit(a)


func _refresh() -> void:
	var facing: int = HudFormat.facing_of(_angle)
	_caption.text = tr("HUD_ANGLE")
	_readout.text = HudFormat.format_angle(_angle)
	_readout.accessibility_name = "%s %s" % [_readout.text, tr(FACING_KEYS[facing])]
	_mark_left.lit = facing == HudFormat.FACING_LEFT
	_mark_right.lit = facing == HudFormat.FACING_RIGHT
	_left.tooltip_text = tr("HUD_ANGLE_LEFT")
	_left.accessibility_name = tr("HUD_ANGLE_LEFT")
	_right.tooltip_text = tr("HUD_ANGLE_RIGHT")
	_right.accessibility_name = tr("HUD_ANGLE_RIGHT")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _caption != null:
		_refresh()
