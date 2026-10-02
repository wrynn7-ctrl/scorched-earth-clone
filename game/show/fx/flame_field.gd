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
		var f: float = 1.0 - amp + amp * sin(_t * 17.0 + _phase[i]) * sin(_t * 9.0 + _phase[i] * 1.7)
		var size_px: float = (11.0 + 7.0 * f) * (1.0 - 0.35 * k)
		var lift := Vector2(0.0, -size_px * 0.35)
		draw_texture_rect(glow, Rect2(_pts[i] + lift - Vector2.ONE * size_px, Vector2.ONE * size_px * 2.0),
				false, Color(1.0, 0.38, 0.1, 0.8 * fade * f))
		var core: float = size_px * 0.8
		draw_texture_rect(glow, Rect2(_pts[i] + lift * 1.6 - Vector2.ONE * core * 0.5, Vector2.ONE * core),
				false, Color(1.0, 0.92, 0.6, fade * f))
