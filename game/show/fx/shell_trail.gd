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
const SPARKLE_COUNT: int = 8
## Heart head: world-unit size and the spin per path sample (radians).
const HEART_HEAD_SCALE: float = 0.42
const HEART_SPIN: float = 0.03

var samples_per_second: float = 120.0

var _path: PackedVector2Array = PackedVector2Array()
var _pos: float = 0.0
var _playing: bool = false
var _line: Line2D = null
var _wake: Line2D = null
var _wake_grad: Gradient = null
var _head: Sprite2D = null
var _fade: Tween = null
## Love Edition: the shell is a slowly spinning glowing heart with a twinkling sparkle trail.
var _heart_style: bool = false
var _sparkles: Array[Sprite2D] = []


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
	for i: int in range(SPARKLE_COUNT):
		var sp := Sprite2D.new()
		sp.name = "Sparkle%d" % i
		sp.texture = FxTextures.sparkle()
		sp.material = FxTextures.additive()
		sp.visible = false
		add_child(sp)
		_sparkles.append(sp)
	visible = false
	set_process(false)
	if _heart_style:
		set_heart_style(true)  # asked for before the node was in the tree


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


## The Love Edition's look (a heart shell) on or off. Takes effect at once; the trail pool reuses
## nodes, so the controller sets it for every shell it starts.
func set_heart_style(on: bool) -> void:
	_heart_style = on
	if _head == null:
		return
	_head.texture = FxTextures.heart() if on else FxTextures.glow()
	_head.scale = Vector2.ONE * (HEART_HEAD_SCALE if on else 0.5)
	_head.modulate = Color(1.0, 0.62, 0.8) if on else NeonPalette.HOT
	_head.rotation = 0.0
	_line.width = 5.0 if on else 6.0
	var grad: Gradient = _line.gradient
	grad.colors = PackedColorArray([Color(1.0, 0.9, 0.95), Color(1.0, 0.4, 0.7), Color(1.0, 0.6, 0.8, 0.0)]) if on \
			else PackedColorArray([NeonPalette.HOT, NeonPalette.SUNSET, Color(NeonPalette.MAGENTA, 0.0)])
	var wake_c: Color = Color(1.0, 0.55, 0.78) if on else NeonPalette.MAGENTA.lerp(Color.WHITE, 0.3)
	_wake_grad.colors = PackedColorArray([Color(wake_c, 0.0), Color(wake_c, 0.4), Color(wake_c, 0.0), Color(wake_c, 0.0)])
	for sp: Sprite2D in _sparkles:
		sp.visible = on


func is_heart_style() -> bool:
	return _heart_style


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
	for sp: Sprite2D in _sparkles:
		sp.visible = _heart_style
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
	if _heart_style:
		_update_heart()


## Spin and sparkles are functions of the path position, so there is nothing to allocate or store.
func _update_heart() -> void:
	_head.rotation = _pos * HEART_SPIN
	var step: float = TAIL_SPAN / float(SPARKLE_COUNT + 1)
	for i: int in range(SPARKLE_COUNT):
		var k: float = float(i + 1) / float(SPARKLE_COUNT + 1)
		var idx: float = maxf(0.0, _pos - float(i + 1) * step)
		var p: Vector2 = _sample(idx)
		var ahead: Vector2 = _sample(idx + 1.0)
		var dir: Vector2 = (ahead - p).normalized() if ahead != p else Vector2.RIGHT
		var side: Vector2 = Vector2(-dir.y, dir.x)
		var wobble: float = sin(_pos * 0.09 + float(i) * 2.1) * (3.0 + 9.0 * k)
		var tw: float = 0.6 + 0.4 * sin(_pos * 0.35 + float(i) * 1.9)
		var sp: Sprite2D = _sparkles[i]
		sp.position = p + side * wobble
		sp.rotation = float(i) * 0.7 + _pos * 0.02
		sp.scale = Vector2.ONE * (0.4 - 0.22 * k) * tw
		sp.modulate = Color(1.0, 0.82 - 0.2 * k, 0.9, 1.0 - 0.75 * k)


func _sample(idx: float) -> Vector2:
	if _path.is_empty():
		return Vector2.ZERO
	var i0: int = clampi(int(idx), 0, _path.size() - 1)
	var i1: int = mini(i0 + 1, _path.size() - 1)
	return _path[i0].lerp(_path[i1], idx - float(i0))
