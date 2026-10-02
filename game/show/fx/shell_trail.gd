class_name ShellTrail
extends Node2D
## Glowing shell trail + head sprite following a polyline path (world coordinates).
##
## Playback is self-driven (samples per second) or externally driven via set_progress().
## Fixed number of tail points; per-frame updates reuse the Line2D points, so no allocations.

signal finished

const TAIL_POINTS: int = 28
## How many path samples the visible tail spans.
const TAIL_SPAN: float = 36.0

var samples_per_second: float = 120.0

var _path: PackedVector2Array = PackedVector2Array()
var _pos: float = 0.0
var _playing: bool = false
var _line: Line2D = null
var _wake: Line2D = null
var _wake_grad: Gradient = null
var _head: Sprite2D = null
var _fade: Tween = null


func _ready() -> void:
	_build_wake()
	_line = Line2D.new()
	_line.name = "Tail"
	_line.width = 6.0
	_line.material = FxTextures.additive()
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	_line.width_curve = curve
	var grad := Gradient.new()
	grad.colors = PackedColorArray([NeonPalette.HOT, NeonPalette.SUNSET, Color(NeonPalette.MAGENTA, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	_line.gradient = grad
	for i: int in range(TAIL_POINTS):
		_line.add_point(Vector2.ZERO)
	add_child(_line)
	_head = Sprite2D.new()
	_head.name = "Head"
	_head.texture = FxTextures.glow()
	_head.material = FxTextures.additive()
	_head.scale = Vector2(0.5, 0.5)
	_head.modulate = NeonPalette.HOT
	add_child(_head)
	visible = false
	set_process(false)


## A faint line along the part of the path already flown, so bent flights (Seeker, wells,
## splitter fans) read as a curve and not just a short tail. The whole path is one Line2D set
## once; a 4-stop gradient reveals it up to the head, so there is no per-frame allocation.
func _build_wake() -> void:
	_wake = Line2D.new()
	_wake.name = "Wake"
	_wake.width = 2.5
	_wake.material = FxTextures.additive()
	_wake.joint_mode = Line2D.LINE_JOINT_ROUND
	_wake_grad = Gradient.new()
	var c := Color(NeonPalette.MAGENTA, 0.0)
	_wake_grad.colors = PackedColorArray([c, Color(NeonPalette.MAGENTA.lerp(Color.WHITE, 0.3), 0.4), c, c])
	_wake_grad.offsets = PackedFloat32Array([0.0, 0.01, 0.02, 1.0])
	_wake.gradient = _wake_grad
	add_child(_wake)


func _update_wake() -> void:
	if _path.size() < 2:
		return
	var p: float = _pos / float(_path.size() - 1)
	var a: float = clampf(p, 0.001, 0.998)
	var b: float = clampf(p + 0.001, 0.002, 0.999)
	# Gradient re-sorts its stops when an offset passes a neighbour: move them in a safe order.
	if a > _wake_grad.get_offset(2):
		_wake_grad.set_offset(2, b)
		_wake_grad.set_offset(1, a)
	else:
		_wake_grad.set_offset(1, a)
		_wake_grad.set_offset(2, b)


## Starts playing `path` (at least 2 points). Re-callable.
func play(path: PackedVector2Array, sps: float = 120.0) -> void:
	if path.size() < 2:
		finished.emit()
		return
	if _fade != null:
		_fade.kill()
	_path = path
	_wake.points = path
	samples_per_second = sps
	_pos = 0.0
	_playing = true
	modulate = Color.WHITE
	visible = true
	_head.visible = true
	_update_visual()
	set_process(true)


func is_playing() -> bool:
	return _playing


## Externally drive the head to a fractional sample index (0 .. path.size()-1).
func set_progress(index: float) -> void:
	if _path.size() < 2:
		return
	_pos = clampf(index, 0.0, float(_path.size() - 1))
	visible = true
	_update_visual()


func head_position() -> Vector2:
	return _sample(_pos)


func clear() -> void:
	_playing = false
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if not _playing:
		return
	_pos += delta * samples_per_second
	var last: float = float(_path.size() - 1)
	if _pos >= last:
		_pos = last
		_playing = false
		_head.visible = false
		_update_visual()
		set_process(false)
		_fade = create_tween()
		_fade.tween_property(self, "modulate:a", 0.0, 0.45)
		_fade.tween_callback(clear)
		finished.emit()
		return
	_update_visual()


func _update_visual() -> void:
	_update_wake()
	var step: float = TAIL_SPAN / float(TAIL_POINTS - 1)
	for i: int in range(TAIL_POINTS):
		_line.set_point_position(i, _sample(maxf(0.0, _pos - float(i) * step)))
	_head.position = _line.get_point_position(0)


func _sample(idx: float) -> Vector2:
	if _path.is_empty():
		return Vector2.ZERO
	var i0: int = clampi(int(idx), 0, _path.size() - 1)
	var i1: int = mini(i0 + 1, _path.size() - 1)
	return _path[i0].lerp(_path[i1], idx - float(i0))
