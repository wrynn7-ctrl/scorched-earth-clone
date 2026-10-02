class_name BeamFx
extends Node2D
## A laser beam flash (Photon Lance): a wide soft glow, a mid band and a white core along a
## line that thins out and fades in a quarter of a second. Reusable via play().

signal finished

const DURATION: float = 0.35

var _a: Vector2 = Vector2.ZERO
var _b: Vector2 = Vector2.ZERO
var _t: float = -1.0


func _ready() -> void:
	material = FxTextures.additive()
	set_process(false)


func play(from: Vector2, to: Vector2) -> void:
	_a = from
	_b = to
	_t = 0.0
	visible = true
	set_process(true)
	queue_redraw()


func is_active() -> bool:
	return _t >= 0.0


func get_endpoints() -> PackedVector2Array:
	return PackedVector2Array([_a, _b])


func _process(delta: float) -> void:
	_t += delta
	if _t >= DURATION:
		_t = -1.0
		visible = false
		set_process(false)
		finished.emit()
		return
	queue_redraw()


func _draw() -> void:
	if _t < 0.0:
		return
	var k: float = _t / DURATION
	var peak: float = 0.45 if ShowSettings.reduce_flashing else 1.0
	var fade: float = (1.0 - k) * peak
	var w: float = lerpf(22.0, 3.0, k)
	var cyan: Color = NeonPalette.CYAN
	draw_line(_a, _b, Color(cyan, 0.22 * fade), w * 2.4, true)
	draw_line(_a, _b, Color(cyan, 0.55 * fade), w, true)
	draw_line(_a, _b, Color(1, 1, 1, fade), maxf(1.5, w * 0.3), true)
	draw_circle(_a, w * 0.9, Color(cyan, 0.4 * fade))
	draw_circle(_b, w * 1.3, Color(1, 1, 1, 0.6 * fade))
