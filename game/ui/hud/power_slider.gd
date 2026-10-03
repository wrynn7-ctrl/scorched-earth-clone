class_name PowerSlider
extends Control
## Large vertical neon slider, value 0..1000. Drag anywhere on it (absolute position). Mouse or touch; it
## follows only the finger that started on it.
## Emits `power_changed(p)` whenever the value actually changes.

signal power_changed(p: int)

const MIN_VALUE: int = 0
const MAX_VALUE: int = HudFormat.POWER_MAX

var _value: int = 500
var _dragging: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(UiScale.dp(60.0), UiScale.dp(140.0))


var value: int:
	get:
		return _value
	set(v):
		set_value(v)


## Clamps to 0..1000 and emits power_changed if the value changed.
func set_value(v: int) -> void:
	var c: int = clampi(v, MIN_VALUE, MAX_VALUE)
	if c == _value:
		return
	_value = c
	queue_redraw()
	power_changed.emit(_value)


## Same as set_value but never emits (use when the model drives the UI).
func set_value_silent(v: int) -> void:
	_value = clampi(v, MIN_VALUE, MAX_VALUE)
	queue_redraw()


func nudge(delta_value: int) -> void:
	set_value(_value + delta_value)


## Track geometry: the usable travel is inset by half a handle so the handle stays inside.
func _track_rect() -> Rect2:
	var pad: float = _handle_h() * 0.5
	var w: float = clampf(size.x * 0.34, 10.0, 40.0)
	return Rect2((size.x - w) * 0.5, pad, w, maxf(1.0, size.y - pad * 2.0))


func _handle_h() -> float:
	return maxf(UiScale.touch() * 0.8, 36.0)


## Pure mapping from a y coordinate to a power value for a given track.
static func value_for_y(y: float, top: float, bottom: float) -> int:
	if bottom <= top:
		return MIN_VALUE
	var t: float = clampf((bottom - y) / (bottom - top), 0.0, 1.0)
	return roundi(t * float(MAX_VALUE))


## Pointer ids: the mouse, or a touch finger's index (see AimInput; each control tracks only its own finger).
const MOUSE_ID: int = -2
const NO_POINTER: int = -1

var _pointer: int = NO_POINTER


func _gui_input(event: InputEvent) -> void:
	if AimInput.is_emulated(event):
		return  # the engine's copy of a real touch/mouse event: the real one is handled
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_pointer_event(MOUSE_ID, mb.pressed, mb.position.y)
			accept_event()
	elif event is InputEventMouseMotion:
		if _pointer == MOUSE_ID and _dragging:
			_set_from_y((event as InputEventMouseMotion).position.y)
			accept_event()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		_pointer_event(st.index, st.pressed, st.position.y)
		accept_event()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _pointer and _dragging:
			_set_from_y(sd.position.y)
			accept_event()


func is_dragging() -> bool:
	return _dragging


func _pointer_event(id: int, pressed: bool, y: float) -> void:
	if pressed:
		if _dragging:
			return
		_pointer = id
		_dragging = true
		_set_from_y(y)
	elif _dragging and id == _pointer:
		_pointer = NO_POINTER
		_dragging = false


func _set_from_y(y: float) -> void:
	var tr_rect: Rect2 = _track_rect()
	set_value(value_for_y(y, tr_rect.position.y, tr_rect.end.y))


func _draw() -> void:
	var tr_rect: Rect2 = _track_rect()
	var frac: float = float(_value) / float(MAX_VALUE)
	var hot: Color = NeonPalette.CYAN.lerp(NeonPalette.MAGENTA, frac)
	# Track + glow, filled part from the bottom.
	draw_rect(tr_rect.grow(3.0), Color(hot, 0.14))
	draw_rect(tr_rect, Color(NeonPalette.BG_DEEP, 0.95))
	var fill_h: float = tr_rect.size.y * frac
	draw_rect(Rect2(tr_rect.position.x, tr_rect.end.y - fill_h, tr_rect.size.x, fill_h), Color(hot, 0.85))
	draw_rect(tr_rect, Color(NeonPalette.CYAN, 0.8), false, 2.0)
	# Tick marks every 100, longer every 500.
	for i: int in range(0, 11):
		var ty: float = tr_rect.end.y - tr_rect.size.y * float(i) / 10.0
		var tick_len: float = 14.0 if i % 5 == 0 else 8.0
		draw_line(Vector2(tr_rect.position.x - tick_len, ty), Vector2(tr_rect.position.x - 3.0, ty), Color(NeonPalette.TEXT_DIM, 0.8), 2.0)
	# Handle.
	var hh: float = _handle_h()
	var hy: float = tr_rect.end.y - fill_h
	var hr := Rect2(2.0, hy - hh * 0.5, size.x - 4.0, hh)
	draw_rect(hr.grow(4.0), Color(hot, 0.22))
	draw_rect(hr, Color(NeonPalette.BG_MID, 0.96))
	draw_rect(hr, hot, false, 3.0)
	draw_line(Vector2(hr.position.x + 8.0, hy), Vector2(hr.end.x - 8.0, hy), NeonPalette.HOT, 2.0)
