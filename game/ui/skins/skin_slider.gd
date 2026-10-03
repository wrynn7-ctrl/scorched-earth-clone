class_name SkinSlider
extends Control
## A big touch slider: a rounded track (optionally a colour gradient, for the hue picker), a round
## knob, and a drag anywhere on the track. At least 48 dp tall. Emits `value_changed` while the
## finger moves. It works on mouse events, which every touch also produces.

signal value_changed(value: float)

var min_value: float = 0.0
var max_value: float = 1.0
var step: float = 0.0
## Optional colours of the track from left to right (the hue rainbow, a brightness ramp).
var track_colors: PackedColorArray = PackedColorArray()

var _value: float = 0.0
var _dragging: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func get_value() -> float:
	return _value


## Sets the value without emitting `value_changed`.
func set_value_no_signal(v: float) -> void:
	_value = _snap(v)
	queue_redraw()


## Sets the value and emits `value_changed` when it changed (what a drag does).
func set_value(v: float) -> void:
	var n: float = _snap(v)
	if is_equal_approx(n, _value):
		return
	_value = n
	queue_redraw()
	value_changed.emit(_value)


func fraction() -> float:
	return clampf((_value - min_value) / maxf(0.00001, max_value - min_value), 0.0, 1.0)


func _snap(v: float) -> float:
	var c: float = clampf(v, min_value, max_value)
	if step > 0.0:
		c = clampf(min_value + roundf((c - min_value) / step) * step, min_value, max_value)
	return c


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
		if _dragging:
			_set_from_x((event as InputEventMouseButton).position.x)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_set_from_x((event as InputEventMouseMotion).position.x)
		accept_event()


func _set_from_x(x: float) -> void:
	var pad: float = _knob_radius()
	var span: float = maxf(1.0, size.x - pad * 2.0)
	set_value(min_value + clampf((x - pad) / span, 0.0, 1.0) * (max_value - min_value))


func _knob_radius() -> float:
	return minf(size.y * 0.42, UiScale.dp(16.0))


func _draw() -> void:
	var pad: float = _knob_radius()
	var track_h: float = maxf(6.0, UiScale.dp(12.0))
	var track := Rect2(pad, (size.y - track_h) * 0.5, maxf(1.0, size.x - pad * 2.0), track_h)
	if track_colors.size() >= 2:
		var n: int = 24
		for i: int in range(n):
			var t: float = float(i) / float(n - 1)
			var seg := Rect2(track.position.x + track.size.x * float(i) / float(n), track.position.y,
					track.size.x / float(n) + 1.0, track.size.y)
			draw_rect(seg, _sample(t))
	else:
		draw_rect(track, Color(NeonPalette.CYAN, 0.18))
		draw_rect(Rect2(track.position, Vector2(track.size.x * fraction(), track.size.y)), Color(NeonPalette.CYAN, 0.7))
	draw_rect(track, Color(NeonPalette.CYAN, 0.6), false, 1.5)
	var kx: float = track.position.x + track.size.x * fraction()
	var kc := Vector2(kx, size.y * 0.5)
	draw_circle(kc, pad * 1.25, Color(NeonPalette.CYAN, 0.25))
	draw_circle(kc, pad, NeonPalette.BG_DEEP)
	draw_arc(kc, pad, 0.0, TAU, 28, NeonPalette.HOT, maxf(2.0, pad * 0.18), true)


func _sample(t: float) -> Color:
	var f: float = clampf(t, 0.0, 1.0) * float(track_colors.size() - 1)
	var i: int = mini(int(f), track_colors.size() - 2)
	return track_colors[i].lerp(track_colors[i + 1], f - float(i))
