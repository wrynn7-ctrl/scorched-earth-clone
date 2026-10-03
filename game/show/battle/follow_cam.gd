class_name FollowCam
extends RefCounted
## The shot-follow camera, as pure math (the battle controller applies the result to its
## Camera2D). The world is always framed to fit the screen width with its bottom edge on the
## bottom of the screen (BattleFraming), so when a shell climbs above the top of the screen
## there is only one way to keep it in view: zoom out (only as far as the whole world width
## still fits, which matters on very wide screens) and pan up.
##
## Smoothness: zoom and pan are critically damped (no overshoot, no jerk). The controller
## feeds the shell heads plus a look-ahead (the highest and lowest points of the next
## fraction of a second, known from the path), so the camera starts to move before the shell
## leaves the picture instead of chasing it. A hard clamp is the safety net: a shell is never
## allowed outside the visible rect (counted in `clamp_hits`, which tests keep at 0).
##
## After the last shell ends the camera waits RETURN_DELAY, then eases back to the normal
## framing. With follow off or reduce motion on, `enabled` is false: the camera never moves
## and the off-screen marker (BattleMarkers) is the only help.

## World units kept between the shell and the top / bottom of the picture.
const PAD_TOP: float = 80.0
const PAD_BOTTOM: float = 40.0
## Smoothing times in seconds (time to cover ~63% of the way, critically damped).
const FOLLOW_TIME: float = 0.14
const RETURN_TIME: float = 0.45
## How long the camera holds after the last shell ended before it returns.
const RETURN_DELAY: float = 0.4
## Seconds of flight the look-ahead covers.
const LOOKAHEAD_SECONDS: float = 0.5
const SNAP_PAN: float = 0.25
const SNAP_ZOOM: float = 0.0002

var enabled: bool = true
## Times the safety clamp had to move the camera (a well-tuned follow never needs it).
var clamp_hits: int = 0

var _view: Vector2 = Vector2(1600.0, 900.0)
var _rest_zoom: float = 1.0
var _rest_center: Vector2 = Vector2(800.0, 450.0)
var _min_zoom: float = 1.0
var _zoom: float = 1.0
var _zoom_v: float = 0.0
## How far the view's bottom edge sits above the world's bottom edge, in world units.
var _pan: float = 0.0
var _pan_v: float = 0.0
var _hold: float = 0.0


func _init(visible_size: Vector2 = Vector2(1600.0, 900.0)) -> void:
	set_view(visible_size)


## The visible rectangle (canvas units) changed: recompute the rest framing and snap to it.
func set_view(visible_size: Vector2) -> void:
	_view = Vector2(maxf(visible_size.x, 1.0), maxf(visible_size.y, 1.0))
	var f: Dictionary = BattleFraming.frame(_view)
	_rest_zoom = f["zoom"] as float
	_rest_center = f["center"] as Vector2
	_min_zoom = BattleFraming.min_zoom(_view)
	reset()


## Snap back to the normal framing at once (new round, cancelled playback, tests).
func reset() -> void:
	_zoom = _rest_zoom
	_zoom_v = 0.0
	_pan = 0.0
	_pan_v = 0.0
	_hold = 0.0


func get_zoom() -> float:
	return _zoom


func get_center() -> Vector2:
	var vis_h: float = _view.y / _zoom
	return Vector2(_rest_center.x, _rest_bottom() - _pan - vis_h * 0.5)


func get_rest_zoom() -> float:
	return _rest_zoom


func get_rest_center() -> Vector2:
	return _rest_center


func get_min_zoom() -> float:
	return _min_zoom


## The world rectangle the camera shows right now.
func get_visible_rect() -> Rect2:
	return BattleFraming.visible_rect(_view, _zoom, get_center())


func is_at_rest() -> bool:
	return absf(_pan) <= SNAP_PAN and absf(_zoom - _rest_zoom) <= SNAP_ZOOM


## Advances by `delta` real seconds. `heads` are the shells' current world positions and
## `ahead` the extreme points of their next LOOKAHEAD_SECONDS (see lookahead()); both may be
## empty (no shell in the air).
func update(delta: float, heads: PackedVector2Array, ahead: PackedVector2Array = PackedVector2Array()) -> void:
	if not enabled:
		if not is_at_rest():
			reset()
		return
	var dt: float = clampf(delta, 0.0, 0.1)
	if heads.is_empty():
		_return_to_rest(dt)
		return
	_hold = RETURN_DELAY
	var top_head: float = INF
	var bottom_need: float = -INF
	var top_look: float = INF
	for p: Vector2 in heads:
		top_head = minf(top_head, p.y)
		bottom_need = maxf(bottom_need, p.y)
	top_look = top_head
	for p: Vector2 in ahead:
		top_look = minf(top_look, p.y)
		bottom_need = maxf(bottom_need, p.y)
	top_head -= PAD_TOP
	top_look -= PAD_TOP
	bottom_need += PAD_BOTTOM
	var rest_top: float = _rest_bottom() - _view.y / _rest_zoom
	var want_top: float = minf(rest_top, top_look)
	var zoom_t: float = clampf(_view.y / (_rest_bottom() - want_top), _min_zoom, _rest_zoom)
	var h_t: float = _view.y / zoom_t
	# The top edge must clear the shell itself; the look-ahead and the bottom are best effort.
	var pan_min: float = maxf(0.0, _rest_bottom() - h_t - top_head)
	var pan_max: float = maxf(pan_min, _rest_bottom() - bottom_need)
	var pan_t: float = clampf(_rest_bottom() - h_t - want_top, pan_min, pan_max)
	_smooth(zoom_t, pan_t, FOLLOW_TIME, dt)
	_keep_inside(heads)


func _return_to_rest(dt: float) -> void:
	if is_at_rest():
		_hold = 0.0
		return
	if _hold > 0.0:
		_hold -= dt
		return
	_smooth(_rest_zoom, 0.0, RETURN_TIME, dt)
	if absf(_pan) <= SNAP_PAN and absf(_zoom - _rest_zoom) <= SNAP_ZOOM:
		reset()


func _smooth(zoom_t: float, pan_t: float, smooth_time: float, dt: float) -> void:
	var z: Array[float] = _smooth_damp(_zoom, zoom_t, _zoom_v, smooth_time, dt)
	_zoom = clampf(z[0], _min_zoom, _rest_zoom)
	_zoom_v = z[1]
	var p: Array[float] = _smooth_damp(_pan, pan_t, _pan_v, smooth_time, dt)
	_pan = maxf(0.0, p[0])
	_pan_v = p[1]


## Critically damped spring (the usual closed-form approximation). Returns [value, velocity].
static func _smooth_damp(current: float, target: float, velocity: float, smooth_time: float, dt: float) -> Array[float]:
	var omega: float = 2.0 / maxf(smooth_time, 0.0001)
	var x: float = omega * dt
	var e: float = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change: float = current - target
	var temp: float = (velocity + omega * change) * dt
	var vel: float = (velocity - omega * temp) * e
	var out: float = target + (change + temp) * e
	var result: Array[float] = [out, vel]
	return result


## Safety net: a shell head is never left outside the picture.
func _keep_inside(heads: PackedVector2Array) -> void:
	var r: Rect2 = get_visible_rect()
	var top_head: float = INF
	for p: Vector2 in heads:
		top_head = minf(top_head, p.y)
	var deficit: float = (r.position.y + PAD_TOP * 0.4) - top_head
	if deficit > 0.0:
		_pan += deficit
		_pan_v = maxf(_pan_v, 0.0)
		clamp_hits += 1


func _rest_bottom() -> float:
	return _rest_center.y + _view.y / _rest_zoom * 0.5


## World position at fractional index `index` of a per-tick path (clamped to its ends).
static func head_at(path: PackedVector2Array, index: float) -> Vector2:
	if path.is_empty():
		return Vector2.ZERO
	var f: float = clampf(index, 0.0, float(path.size() - 1))
	var i: int = int(f)
	if i >= path.size() - 1:
		return path[path.size() - 1]
	return path[i].lerp(path[i + 1], f - float(i))


## The highest and the lowest point of the path in the `ticks` after `index` (two points).
static func lookahead(path: PackedVector2Array, index: float, ticks: float) -> PackedVector2Array:
	var hi: Vector2 = head_at(path, index)
	var lo: Vector2 = hi
	var first: int = clampi(int(ceil(index)), 0, maxi(path.size() - 1, 0))
	var last: int = clampi(int(floor(index + ticks)), 0, maxi(path.size() - 1, 0))
	for i: int in range(first, last + 1):
		var p: Vector2 = path[i]
		if p.y < hi.y:
			hi = p
		if p.y > lo.y:
			lo = p
	var end: Vector2 = head_at(path, index + ticks)
	if end.y < hi.y:
		hi = end
	if end.y > lo.y:
		lo = end
	return PackedVector2Array([hi, lo])
