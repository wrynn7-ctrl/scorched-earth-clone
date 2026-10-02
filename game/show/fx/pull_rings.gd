class_name PullRings
extends Node2D
## Riptide Anchor impact: a few rings that contract from the pull radius onto the impact
## point, so it is clear that every tank in range is about to be dragged toward it. Reusable
## via play(); redraws only while active.

signal finished

const DURATION: float = 0.7
const RINGS: int = 3

var _t: float = -1.0
var _radius: float = 180.0
var _color: Color = NeonPalette.CYAN


func _ready() -> void:
	material = FxTextures.additive()
	set_process(false)


func play(at: Vector2, radius: float, color: Color = NeonPalette.CYAN) -> void:
	position = at
	_radius = radius
	_color = color
	_t = 0.0
	visible = true
	set_process(true)
	queue_redraw()


func is_playing() -> bool:
	return _t >= 0.0


func get_world_rect() -> Rect2:
	if _t < 0.0:
		return Rect2()
	return Rect2(position - Vector2.ONE * _radius, Vector2.ONE * _radius * 2.0)


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
	var peak: float = 0.5 if ShowSettings.reduce_flashing else 1.0
	for i: int in range(RINGS):
		var lag: float = float(i) * 0.18
		var u: float = clampf((k - lag) / (1.0 - lag * RINGS * 0.5), 0.0, 1.0)
		if u <= 0.0 or u >= 1.0:
			continue
		var r: float = _radius * (1.0 - u * u)
		var fade: float = sin(u * PI) * peak
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 72, Color(_color, 0.18 * fade), 10.0, true)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 72, Color(_color.lerp(Color.WHITE, 0.4), 0.9 * fade), 2.5, true)
	draw_circle(Vector2.ZERO, 8.0 + 14.0 * k, Color(_color, 0.5 * (1.0 - k) * peak))
