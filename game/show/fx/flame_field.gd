class_name FlameField
extends Node2D
## Flickering fire at a set of points (Ember Rain / Inferno Gel): additive glow sprites that
## flicker and fade over ~1.5 s. One node is reusable: call play() again to re-trigger.
## Redraws only while burning.

signal finished

const DURATION: float = 1.5

var _pts: PackedVector2Array = PackedVector2Array()
var _phase: PackedFloat32Array = PackedFloat32Array()
var _t: float = -1.0


func _ready() -> void:
	material = FxTextures.additive()
	set_process(false)


## `points` is the event's PackedInt32Array [x, y, x, y, ...] in cells.
func play(points: PackedInt32Array) -> void:
	_pts.resize(points.size() / 2)
	_phase.resize(_pts.size())
	for i: int in range(_pts.size()):
		_pts[i] = Vector2(float(points[i * 2]), float(points[i * 2 + 1]))
		_phase[i] = fposmod(float(i) * 2.399, TAU)  # golden-angle spread: no two points flicker together
	_t = 0.0
	visible = true
	set_process(true)
	queue_redraw()


func is_burning() -> bool:
	return _t >= 0.0


func point_count() -> int:
	return _pts.size()


## Bounding box of the burning points (empty when out); parent coordinates.
func get_world_rect() -> Rect2:
	if _t < 0.0 or _pts.is_empty():
		return Rect2()
	var r := Rect2(_pts[0], Vector2.ZERO)
	for p: Vector2 in _pts:
		r = r.expand(p)
	return r.grow(20.0)


func stop() -> void:
	_t = -1.0
	visible = false
	set_process(false)
	finished.emit()


func _process(delta: float) -> void:
	_t += delta
	if _t >= DURATION:
		stop()
		return
	queue_redraw()


func _draw() -> void:
	if _t < 0.0:
		return
	var k: float = _t / DURATION
	var fade: float = 1.0 - smoothstep(0.45, 1.0, k)
	var amp: float = 0.25 if ShowSettings.reduce_flashing else 0.5
	var glow: Texture2D = FxTextures.glow()
	for i: int in range(_pts.size()):
		var ph: float = _phase[i]
		var f: float = 1.0 - amp + amp * sin(_t * 17.0 + ph) * sin(_t * 9.0 + ph * 1.7)
		# Points that rest in the same column are spread a little so the patch reads as a fire,
		# not one dot; each tongue licks upwards with its own flicker.
		var base: Vector2 = _pts[i] + Vector2(sin(ph * 5.0) * 15.0, cos(ph * 3.0) * 4.0)
		var size_px: float = (13.0 + 8.0 * f) * (1.0 - 0.35 * k)
		var tongue: float = size_px * (0.5 + 0.5 * f)
		draw_texture_rect(glow, Rect2(base + Vector2(0.0, -size_px * 0.35) - Vector2.ONE * size_px, Vector2.ONE * size_px * 2.0),
				false, Color(1.0, 0.3, 0.08, 0.3 * fade * f))
		var mid: float = size_px * 1.0
		draw_texture_rect(glow, Rect2(base + Vector2(0.0, -tongue * 0.9) - Vector2.ONE * mid * 0.5, Vector2.ONE * mid),
				false, Color(1.0, 0.55, 0.12, 0.34 * fade * f))
		var tip: float = size_px * 0.6
		draw_texture_rect(glow, Rect2(base + Vector2(sin(_t * 11.0 + ph) * 3.0, -tongue * 1.8) - Vector2.ONE * tip * 0.5, Vector2.ONE * tip),
				false, Color(1.0, 0.85, 0.45, 0.4 * fade * f))
