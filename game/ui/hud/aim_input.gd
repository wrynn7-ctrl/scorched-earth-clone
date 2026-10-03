class_name AimInput
extends Control
## Full-screen transparent drag surface behind the HUD. Dragging anywhere on the battlefield
## sets the launch angle relative to the active tank's screen position (the pivot).
## Emits `angle_changed(tenths)` (0 = right, 900 = up, 1800 = left) only when the value changes.
##
## Real touch (ScreenTouch/ScreenDrag with a finger index) and the real mouse both work; the control
## tracks only the pointer that started its drag, so another finger can use the power slider meanwhile.
## It receives motion outside its rect while a drag is active.

signal angle_changed(tenths: int)
signal drag_started
signal drag_ended

## Ignore touches closer than this (canvas units) to the pivot: the angle would be noisy.
var min_radius: float = 14.0

var _pivot: Vector2 = Vector2(400, 500)
var _angle: int = 450
var _dragging: bool = false
var _finger: Vector2 = Vector2.ZERO
var _color: Color = NeonPalette.CYAN


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Pivot in this control's coordinates (= viewport canvas coordinates under a CanvasLayer).
func set_pivot(p: Vector2) -> void:
	_pivot = p
	if _dragging:
		queue_redraw()


func get_pivot() -> Vector2:
	return _pivot


func set_angle_tenths(a: int) -> void:
	_angle = clampi(a, 0, HudFormat.ANGLE_MAX)
	if _dragging:
		queue_redraw()


func get_angle_tenths() -> int:
	return _angle


func set_color(c: Color) -> void:
	_color = c


## Ends an in-progress drag (used when input gets locked mid-gesture).
func cancel_drag() -> void:
	if _dragging:
		_dragging = false
		_pointer = NO_POINTER
		drag_ended.emit()
		queue_redraw()


func is_dragging() -> bool:
	return _dragging


## Pure function: angle (tenths) for a finger at `pos` given the tank at `pivot`.
## Below the horizon the angle snaps to the nearest side (0 or 1800). Returns -1 if the
## finger is closer than `min_r` to the pivot.
static func angle_from_drag(pivot: Vector2, pos: Vector2, min_r: float = 0.0) -> int:
	var dx: float = pos.x - pivot.x
	var dy: float = pivot.y - pos.y
	if dx * dx + dy * dy < maxf(min_r * min_r, 0.0001):
		return -1
	if dy < 0.0:
		return 0 if dx >= 0.0 else HudFormat.ANGLE_MAX
	return clampi(roundi(rad_to_deg(atan2(dy, dx)) * 10.0), 0, HudFormat.ANGLE_MAX)


## Pointer id of the mouse (real touch fingers use their index, 0 and up).
const MOUSE_ID: int = -2
const NO_POINTER: int = -1

var _pointer: int = NO_POINTER


## True for events the engine synthesised from the other kind of pointer (emulate_touch_from_mouse and
## emulate_mouse_from_touch both mark them DEVICE_ID_EMULATION). Each control reads the real source only,
## so a finger is never counted twice.
static func is_emulated(event: InputEvent) -> bool:
	return event.device == InputEvent.DEVICE_ID_EMULATION


func _gui_input(event: InputEvent) -> void:
	if is_emulated(event):
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_pointer_event(MOUSE_ID, mb.pressed, mb.position)
			accept_event()
	elif event is InputEventMouseMotion:
		if _pointer == MOUSE_ID and _dragging:
			_pointer_moved((event as InputEventMouseMotion).position)
			accept_event()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		_pointer_event(st.index, st.pressed, st.position)
		accept_event()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _pointer and _dragging:
			_pointer_moved(sd.position)
			accept_event()


## Press/release of pointer `id`. Only the pointer that started the drag can end it, and a second finger
## landing on this control while one is dragging is ignored.
func _pointer_event(id: int, pressed: bool, pos: Vector2) -> void:
	if pressed:
		if _dragging:
			return
		_pointer = id
		_dragging = true
		_finger = pos
		drag_started.emit()
		_update_from(pos)
	else:
		if not _dragging or id != _pointer:
			return
		_pointer = NO_POINTER
		_dragging = false
		drag_ended.emit()
	queue_redraw()


func _pointer_moved(pos: Vector2) -> void:
	_finger = pos
	_update_from(pos)
	queue_redraw()


func _update_from(pos: Vector2) -> void:
	var a: int = angle_from_drag(_pivot, pos, min_radius)
	if a >= 0 and a != _angle:
		_angle = a
		angle_changed.emit(a)


func _draw() -> void:
	if not _dragging:
		return
	var dir: Vector2 = Vector2(cos(deg_to_rad(_angle / 10.0)), -sin(deg_to_rad(_angle / 10.0)))
	var reach: float = clampf(_pivot.distance_to(_finger), 60.0, 520.0)
	draw_dashed_line(_pivot + dir * 30.0, _pivot + dir * reach, Color(_color, 0.55), 3.0, 14.0, true)
	draw_circle(_pivot + dir * reach, 7.0, Color(_color, 0.9))
	draw_arc(_pivot + dir * reach, 14.0, 0.0, TAU, 20, Color(_color, 0.35), 3.0, true)
