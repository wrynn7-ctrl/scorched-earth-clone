class_name PowerPanel
extends PanelContainer
## Right-hand power control: caption, numeric readout, +1 / -1 fine buttons (long-press
## repeats) around a large vertical PowerSlider. `power_changed` fires on any user change.

signal power_changed(p: int)

var _caption: Label = null
var _readout: Label = null
var _slider: PowerSlider = null
var _plus: FineButton = null
var _minus: FineButton = null


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
	_readout.add_theme_color_override("font_color", NeonPalette.MAGENTA)
	box.add_child(_readout)
	_plus = FineButton.new()
	_plus.name = "Plus"
	_plus.stepped.connect(_on_step.bind(1))
	box.add_child(_plus)
	_slider = PowerSlider.new()
	_slider.name = "Slider"
	_slider.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_slider.power_changed.connect(_on_slider_changed)
	box.add_child(_slider)
	_minus = FineButton.new()
	_minus.name = "Minus"
	_minus.stepped.connect(_on_step.bind(-1))
	box.add_child(_minus)


func _ready() -> void:
	apply_scale()
	_refresh()


func apply_scale() -> void:
	_caption.add_theme_font_size_override("font_size", UiScale.font(11.0))
	_readout.add_theme_font_size_override("font_size", UiScale.font(22.0))
	_plus.add_theme_font_size_override("font_size", UiScale.font(16.0))
	_minus.add_theme_font_size_override("font_size", UiScale.font(16.0))
	var bs := Vector2(UiScale.dp(64.0), UiScale.touch())
	_plus.custom_minimum_size = bs
	_minus.custom_minimum_size = bs
	_slider.custom_minimum_size = Vector2(UiScale.dp(60.0), UiScale.dp(120.0))


func set_power(p: int) -> void:
	_slider.set_value_silent(p)
	_refresh()


func get_power() -> int:
	return _slider.value


func get_slider() -> PowerSlider:
	return _slider


func _on_step(multiplier: int, direction: int) -> void:
	_slider.nudge(direction * multiplier)


func _on_slider_changed(p: int) -> void:
	_refresh()
	power_changed.emit(p)


func _refresh() -> void:
	_caption.text = tr("HUD_POWER")
	_readout.text = HudFormat.power(_slider.value)
	_plus.text = tr("HUD_POWER_PLUS")
	_minus.text = tr("HUD_POWER_MINUS")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _caption != null:
		_refresh()
