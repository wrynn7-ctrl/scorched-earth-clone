class_name HudFade
extends Node
## Fades HUD panels while the action happens behind them (a tank, shell, blast, beam or
## flame under a panel): to FADED_ALPHA over FADE_SECONDS, and back to full when clear.
##
## Faded panels keep receiving touches (modulate never affects hit-testing), and a touch on
## one brings it to full opacity at once and keeps it there for HOLD_SECONDS, so a player
## who is using a control never sees it vanish again under their finger.
##
## Pure presentation: it only reads rectangles. The battle controller feeds it the screen
## rectangles of whatever is going on (set_occluders) and the HUD applies the resulting alpha.

signal alpha_changed(panel: Control)

const FADED_ALPHA: float = 0.3
const FADE_SECONDS: float = 0.15
const HOLD_SECONDS: float = 1.5
## A little slack so a tank that only grazes a panel's edge does not flicker it.
const PAD: float = 4.0

var _panels: Array[Control] = []
var _alpha: Dictionary = {}
var _hold: Dictionary = {}
var _target: Dictionary = {}
var _rects: Array[Rect2] = []
var _segments: PackedVector2Array = PackedVector2Array()
var enabled: bool = true


func add_panel(p: Control) -> void:
	if _panels.has(p):
		return
	_panels.append(p)
	_alpha[p] = 1.0
	_hold[p] = 0.0
	_target[p] = 1.0


func panels() -> Array[Control]:
	return _panels


## The current opacity factor of `p` (1.0 = fully visible).
func get_alpha(p: Control) -> float:
	return _alpha.get(p, 1.0) as float


func get_target(p: Control) -> float:
	return _target.get(p, 1.0) as float


func is_faded(p: Control) -> bool:
	return get_alpha(p) < 0.999


## Screen rectangles (viewport coordinates) of everything happening, plus line segments
## (pairs of points) for beams. Replaces the previous set; call every frame while playing.
func set_occluders(rects: Array[Rect2], segments: PackedVector2Array = PackedVector2Array()) -> void:
	_rects = rects
	_segments = segments
	_retarget()


## True if `r` (viewport coordinates) overlaps any visible tracked panel.
func is_under_panel(r: Rect2) -> bool:
	for p: Control in _panels:
		if p.is_visible_in_tree() and _panel_rect(p).intersects(r):
			return true
	return false


func panel_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for p: Control in _panels:
		if p.is_visible_in_tree():
			out.append(_panel_rect(p))
	return out


## A press at `pos` (viewport coordinates): any panel under it is shown in full at once.
func touch_at(pos: Vector2) -> void:
	for p: Control in _panels:
		if p.is_visible_in_tree() and p.get_global_rect().has_point(pos):
			_hold[p] = HOLD_SECONDS
			_set_alpha(p, 1.0)
			_target[p] = 1.0


func is_held(p: Control) -> bool:
	return (_hold.get(p, 0.0) as float) > 0.0


## Advances the fades by `delta` seconds (called from _process; tests call it directly).
func step(delta: float) -> void:
	var rate: float = (1.0 - FADED_ALPHA) / FADE_SECONDS
	for p: Control in _panels:
		var h: float = _hold[p]
		if h > 0.0:
			_hold[p] = maxf(0.0, h - delta)
			_target[p] = 1.0
		var cur: float = _alpha[p]
		var want: float = _target[p]
		if absf(cur - want) < 0.0005:
			continue
		_set_alpha(p, move_toward(cur, want, rate * delta))


func _process(delta: float) -> void:
	step(delta)


## Forgets everything: all panels back to full at once (new screen, HUD hidden).
func reset() -> void:
	_rects = []
	_segments = PackedVector2Array()
	for p: Control in _panels:
		_hold[p] = 0.0
		_target[p] = 1.0
		_set_alpha(p, 1.0)


func _retarget() -> void:
	for p: Control in _panels:
		var covered: bool = enabled and p.is_visible_in_tree() and _is_covered(_panel_rect(p))
		_target[p] = FADED_ALPHA if (covered and not is_held(p)) else 1.0


func _is_covered(panel: Rect2) -> bool:
	for r: Rect2 in _rects:
		if panel.intersects(r):
			return true
	for i: int in range(0, _segments.size() - 1, 2):
		if _segment_hits(panel, _segments[i], _segments[i + 1]):
			return true
	return false


static func _panel_rect(p: Control) -> Rect2:
	return p.get_global_rect().grow(PAD)


## Segment/rectangle overlap (Liang-Barsky clipping).
static func _segment_hits(r: Rect2, a: Vector2, b: Vector2) -> bool:
	if r.has_point(a) or r.has_point(b):
		return true
	var t0: float = 0.0
	var t1: float = 1.0
	var d: Vector2 = b - a
	var p: Array[float] = [-d.x, d.x, -d.y, d.y]
	var q: Array[float] = [a.x - r.position.x, r.end.x - a.x, a.y - r.position.y, r.end.y - a.y]
	for i: int in range(4):
		if is_zero_approx(p[i]):
			if q[i] < 0.0:
				return false
		else:
			var t: float = q[i] / p[i]
			if p[i] < 0.0:
				t0 = maxf(t0, t)
			else:
				t1 = minf(t1, t)
			if t0 > t1:
				return false
	return true


func _set_alpha(p: Control, a: float) -> void:
	if is_equal_approx(get_alpha(p), a):
		return
	_alpha[p] = a
	alpha_changed.emit(p)
