class_name SkinChoice
extends Button
## A toggle tile in the Skin Studio: a drawn picture of a hull, turret, pattern, decal or a colour
## chip, with its name underneath. The chosen tile is lit by the theme *and* carries a check mark,
## so the choice never depends on colour alone. At least 48 dp in both directions.

enum Kind { HULL, TURRET, PATTERN, DECAL, COLOR }

const MIN_DP: float = 48.0
const TILE_DP: float = 76.0

var kind: int = Kind.HULL
var index: int = 0
## The chip colour of a COLOR tile.
var color: Color = Color.WHITE
## A short wide chip (picture left, caption right, one touch row high) instead of the tall picture-over-caption tile.
## The colour slots use it so the COLOURS tab fits on a phone without scrolling.
var compact: bool = false

var _art: Control = null
var _label: Label = null


func _init(tile_kind: int = Kind.HULL, tile_index: int = 0, caption: String = "") -> void:
	kind = tile_kind
	index = tile_index
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	tooltip_text = caption
	_art = Control.new()
	_art.name = "Art"
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.draw.connect(_draw_art)
	add_child(_art)
	_label = Label.new()
	_label.name = "Caption"
	_label.text = caption
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.clip_text = true
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = caption != ""
	add_child(_label)
	toggled.connect(func(_on: bool) -> void: _art.queue_redraw())
	resized.connect(_layout)


func set_color_value(c: Color) -> void:
	color = c
	_art.queue_redraw()


func get_caption() -> String:
	return _label.text


## Sizes the tile from dp and the text size setting. Tiles without a caption (colour swatches)
## are squares of the minimum touch size.
func apply_scale() -> void:
	var font_size: int = UiScale.font(11.0)
	_label.add_theme_font_size_override("font_size", font_size)
	var touch: float = UiScale.dp(MIN_DP)
	if compact and _label.text != "":
		var cfont: Font = _label.get_theme_font("font")
		custom_minimum_size = Vector2(touch + cfont.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x + UiScale.dp(12.0), touch)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	elif _label.text == "":
		custom_minimum_size = Vector2.ONE * touch
	else:
		var font: Font = _label.get_theme_font("font")
		var text_w: float = font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		var line: float = UiScale.line_h(11.0)
		custom_minimum_size = Vector2(
			maxf(UiScale.dp(TILE_DP), text_w + UiScale.dp(12.0)), maxf(UiScale.dp(TILE_DP), UiScale.dp(46.0) + line))
	_layout()


func _layout() -> void:
	if _art == null:
		return
	var pad: float = UiScale.dp(5.0)
	if compact:
		_art.position = Vector2(pad, pad)
		_art.size = Vector2.ONE * maxf(1.0, size.y - pad * 2.0)
		_label.position = Vector2(size.y, 0.0)
		_label.size = Vector2(maxf(1.0, size.x - size.y - pad), size.y)
		_art.queue_redraw()
		return
	var line: float = UiScale.line_h(11.0) if _label.text != "" else 0.0
	_art.position = Vector2(pad, pad)
	_art.size = Vector2(maxf(1.0, size.x - pad * 2.0), maxf(1.0, size.y - pad * 2.0 - line))
	_label.position = Vector2(0.0, size.y - line - pad * 0.5)
	_label.size = Vector2(size.x, line)
	_art.queue_redraw()


func _draw_art() -> void:
	var r := Rect2(Vector2.ZERO, _art.size)
	var ink: Color = NeonPalette.TEXT
	match kind:
		Kind.HULL:
			SkinShapes.draw_hull_icon(_art, index, r, ink)
		Kind.TURRET:
			SkinShapes.draw_turret_icon(_art, index, r, ink)
		Kind.PATTERN:
			SkinShapes.draw_pattern_icon(_art, index, r, ink)
		Kind.DECAL:
			SkinShapes.draw_decal(_art, index, r.get_center(), minf(r.size.x, r.size.y) * 0.42, ink)
		Kind.COLOR:
			var rad: float = minf(r.size.x, r.size.y) * 0.34
			_art.draw_circle(r.get_center(), rad * 1.3, Color(color, 0.28))
			_art.draw_circle(r.get_center(), rad, color)
			_art.draw_arc(r.get_center(), rad, 0.0, TAU, 24, NeonPalette.HOT, maxf(1.0, rad * 0.1), true)
	if button_pressed:
		_draw_check(r)


## A check mark in the top right corner on a dark disc: the chosen tile is marked by shape too.
func _draw_check(r: Rect2) -> void:
	var rad: float = minf(r.size.x, r.size.y) * 0.17
	var c := Vector2(r.end.x - rad, r.position.y + rad)
	_art.draw_circle(c, rad, NeonPalette.BG_DEEP)
	_art.draw_arc(c, rad, 0.0, TAU, 16, NeonPalette.GOOD, maxf(1.0, rad * 0.16), true)
	_art.draw_polyline(PackedVector2Array([c + Vector2(-0.5, 0.05) * rad, c + Vector2(-0.12, 0.45) * rad,
			c + Vector2(0.55, -0.4) * rad]), NeonPalette.GOOD, maxf(1.5, rad * 0.22), true)
