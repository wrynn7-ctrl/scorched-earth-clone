class_name AnglePanel
extends PanelContainer
## Angle readout ("47.3°") with ±0.1° fine-tune buttons (long-press repeats).
## `angle_changed` is emitted only for user input on the buttons; set_angle_tenths() is silent.

signal angle_changed(tenths: int)

var _angle: int = 450
var _caption: Label = null
var _readout: Label = null
var _minus: FineButton = null
var _plus: FineButton = null
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
	_readout = Label.new()
	_readout.name = "Readout"
	_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_readout.add_theme_color_override("font_color", NeonPalette.CYAN)
	box.add_child(_readout)
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_row)
	_minus = FineButton.new()
	_minus.name = "Minus"
	_minus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_minus.arrow = FineButton.Arrow.DOWN
	_minus.stepped.connect(_on_step.bind(-1))
	_row.add_child(_minus)
	_plus = FineButton.new()
	_plus.name = "Plus"
	_plus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plus.arrow = FineButton.Arrow.UP
	_plus.stepped.connect(_on_step.bind(1))
	_row.add_child(_plus)


func _ready() -> void:
	apply_scale()
	_refresh()


func apply_scale() -> void:
	_caption.add_theme_font_size_override("font_size", UiScale.font(11.0))
	_readout.add_theme_font_size_override("font_size", UiScale.font(26.0))
	var bs := Vector2(UiScale.dp(64.0), UiScale.touch() * 1.05)
	_minus.custom_minimum_size = bs
	_plus.custom_minimum_size = bs
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
	_caption.text = tr("HUD_ANGLE")
	_readout.text = HudFormat.angle(_angle)
	_minus.tooltip_text = tr("HUD_ANGLE_DOWN")
	_minus.accessibility_name = tr("HUD_ANGLE_DOWN")
	_plus.tooltip_text = tr("HUD_ANGLE_UP")
	_plus.accessibility_name = tr("HUD_ANGLE_UP")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _caption != null:
		_refresh()
