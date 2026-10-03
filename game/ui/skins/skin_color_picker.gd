class_name SkinColorPicker
extends VBoxContainer
## Colour choice for the studio: a wrapping grid of preset neon swatches plus hue, saturation and
## brightness sliders and the hex code as text. Emits `color_changed` on every edit.

signal color_changed(color: Color)

## Preset swatches: neon brights first, then the dark and neutral tones that work as a hull base.
const PRESETS: Array[Color] = [
	Color8(0x00, 0xED, 0xFF), Color8(0xFF, 0x2E, 0x9E), Color8(0x73, 0x40, 0xFF), Color8(0xFF, 0x73, 0x33),
	Color8(0xFF, 0xE0, 0x33), Color8(0xBC, 0xFE, 0x38), Color8(0x33, 0xFF, 0x8C), Color8(0xFF, 0x40, 0x4D),
	Color8(0x4F, 0xC3, 0xF7), Color8(0xF1, 0xF1, 0xFF), Color8(0x8A, 0x8F, 0xB5), Color8(0x21, 0x14, 0x52),
	Color8(0x0B, 0x1E, 0x3F), Color8(0x1B, 0x1B, 0x26),
]

var _hue: float = 0.0
var _sat: float = 1.0
var _val: float = 1.0
var _color: Color = Color.WHITE

var _swatches: Array[SkinChoice] = []
var _top: BoxContainer = null
var _slot_box: VBoxContainer = null
var _controls: VBoxContainer = null
var _flow: HFlowContainer = null
var _sliders: Array[SkinSlider] = []
var _slider_labels: Array[Label] = []
var _value_labels: Array[Label] = []
var _hex: Label = null
var _group: ButtonGroup = ButtonGroup.new()


func _init() -> void:
	name = "ColorPicker"
	# Top row: the host's colour-slot chips on the left, the three sliders on the right (so the whole picker is
	# short enough to fit a phone's screen); the preset swatches and the hex code wrap underneath. When the two
	# do not fit side by side (big text on a narrow phone) _fit_top() stacks the sliders under the chips.
	_top = BoxContainer.new()
	_top.name = "Top"
	add_child(_top)
	_slot_box = VBoxContainer.new()
	_slot_box.name = "Slots"
	_top.add_child(_slot_box)
	_controls = VBoxContainer.new()
	_controls.name = "Controls"
	_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top.add_child(_controls)
	_flow = HFlowContainer.new()
	_flow.name = "Presets"
	add_child(_flow)
	for c: Color in PRESETS:
		var b := SkinChoice.new(SkinChoice.Kind.COLOR, _swatches.size(), "")
		b.name = "Swatch%d" % _swatches.size()
		b.button_group = _group
		b.tooltip_text = "#" + c.to_html(false).to_upper()
		b.set_color_value(c)
		b.pressed.connect(_on_preset.bind(c))
		_flow.add_child(b)
		_swatches.append(b)
	_hex = Label.new()
	_hex.name = "Hex"
	_hex.add_theme_color_override("font_color", NeonPalette.TEXT_DIM)
	_hex.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_flow.add_child(_hex)  # after the swatches: it fills the gap in the last row
	for key: String in ["SKIN_HUE", "SKIN_SAT", "SKIN_BRIGHT"]:
		_add_slider(key)
	_sliders[0].track_colors = _hue_ramp()
	set_color(Color.WHITE)


## Where the host puts its own controls (the colour slot chips), left of the sliders.
func get_slot_box() -> VBoxContainer:
	return _slot_box


func get_color() -> Color:
	return _color


func get_slider(i: int) -> SkinSlider:
	return _sliders[i]


func get_swatch(i: int) -> SkinChoice:
	return _swatches[i]


func get_hex_text() -> String:
	return _hex.text


## Shows `c` (no signal). The hue is kept when the colour is grey, so the slider does not jump.
func set_color(c: Color) -> void:
	_color = Color(c.r, c.g, c.b, 1.0)
	if _color.s > 0.001 and _color.v > 0.001:
		_hue = _color.h
	_sat = _color.s
	_val = _color.v
	_sync_widgets()


func apply_scale() -> void:
	add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	_top.add_theme_constant_override("separation", roundi(UiScale.dp(10.0)))
	_slot_box.add_theme_constant_override("separation", roundi(UiScale.dp(2.0)))
	_controls.add_theme_constant_override("separation", 0)
	_flow.add_theme_constant_override("h_separation", roundi(UiScale.dp(4.0)))
	_flow.add_theme_constant_override("v_separation", roundi(UiScale.dp(4.0)))
	for b: SkinChoice in _swatches:
		b.apply_scale()
	_hex.add_theme_font_size_override("font_size", UiScale.font(13.0))
	_hex.custom_minimum_size = Vector2(UiScale.dp(86.0), UiScale.touch())
	for i: int in range(_sliders.size()):
		_sliders[i].custom_minimum_size = Vector2(UiScale.dp(92.0), UiScale.touch())
		_slider_labels[i].custom_minimum_size.x = _label_width()
		_slider_labels[i].add_theme_font_size_override("font_size", UiScale.font(12.0))
		_value_labels[i].custom_minimum_size.x = UiScale.dp(36.0) * maxf(1.0, UiScale.text_scale * 0.8)
		_value_labels[i].add_theme_font_size_override("font_size", UiScale.font(12.0))
		_slider_labels[i].get_parent().add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	_fit_top()


## The chips and the sliders share the top row when they fit side by side, else the sliders go under the chips.
## "Fits" is measured against the scroll area that holds the picker, not the picker itself (a container is never
## narrower than its own minimum, which would hide the problem).
func _fit_top() -> void:
	if _top == null:
		return
	var avail: float = _available_width()
	var slots_w: float = _slot_box.get_combined_minimum_size().x
	var gap: float = float(_top.get_theme_constant("separation"))
	var need: float = 0.0
	for row: Node in _controls.get_children():
		need = maxf(need, (row as Control).get_combined_minimum_size().x)
	var stacked: bool = slots_w + gap + need > avail
	if _top.vertical != stacked:
		_top.vertical = stacked


func _available_width() -> float:
	var n: Node = get_parent()
	while n != null and not (n is ScrollContainer):
		n = n.get_parent()
	if n == null:
		return size.x
	return (n as ScrollContainer).size.x - TouchScroll.bar_thickness()


func _enter_tree() -> void:
	var n: Node = get_parent()
	while n != null and not (n is ScrollContainer):
		n = n.get_parent()
	if n != null and not (n as ScrollContainer).resized.is_connected(_fit_top):
		(n as ScrollContainer).resized.connect(_fit_top)


## One width for every caption (the widest), so the three sliders line up.
func _label_width() -> float:
	var widest: float = 0.0
	for l: Label in _slider_labels:
		var font: Font = l.get_theme_font("font")
		widest = maxf(widest, font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiScale.font(12.0)).x)
	return widest + UiScale.dp(4.0)


func _add_slider(key: String) -> void:
	var row := HBoxContainer.new()
	row.name = "Row%d" % _sliders.size()
	_controls.add_child(row)
	var l := Label.new()
	l.text = tr(key)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", NeonPalette.TEXT_DIM)
	row.add_child(l)
	var s := SkinSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.value_changed.connect(_on_slider)
	row.add_child(s)
	var v := Label.new()
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(v)
	_slider_labels.append(l)
	_sliders.append(s)
	_value_labels.append(v)


func _hue_ramp() -> PackedColorArray:
	var ramp := PackedColorArray()
	for i: int in range(7):
		ramp.append(Color.from_hsv(float(i) / 6.0, 1.0, 1.0))
	return ramp


func _on_preset(c: Color) -> void:
	set_color(c)
	color_changed.emit(_color)


func _on_slider(_v: float) -> void:
	_hue = _sliders[0].get_value()
	_sat = _sliders[1].get_value()
	_val = _sliders[2].get_value()
	_color = Color.from_hsv(_hue, _sat, _val, 1.0)
	_update_labels()
	_mark_preset()
	color_changed.emit(_color)


func _sync_widgets() -> void:
	_sliders[0].set_value_no_signal(_hue)
	_sliders[1].set_value_no_signal(_sat)
	_sliders[2].set_value_no_signal(_val)
	_sliders[1].track_colors = PackedColorArray([Color.from_hsv(_hue, 0.0, maxf(_val, 0.35)), Color.from_hsv(_hue, 1.0, maxf(_val, 0.35))])
	_sliders[2].track_colors = PackedColorArray([Color.BLACK, Color.from_hsv(_hue, _sat, 1.0)])
	_sliders[1].queue_redraw()
	_sliders[2].queue_redraw()
	_update_labels()
	_mark_preset()


func _update_labels() -> void:
	_value_labels[0].text = "%d" % roundi(_hue * 360.0)
	_value_labels[1].text = "%d%%" % roundi(_sat * 100.0)
	_value_labels[2].text = "%d%%" % roundi(_val * 100.0)
	_hex.text = "#" + _color.to_html(false).to_upper()


## Lights the preset that equals the current colour (none when it was mixed by hand).
func _mark_preset() -> void:
	for i: int in range(_swatches.size()):
		_swatches[i].set_pressed_no_signal(PRESETS[i].to_html(false) == _color.to_html(false))
