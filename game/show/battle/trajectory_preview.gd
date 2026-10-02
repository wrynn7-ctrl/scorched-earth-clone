class_name TrajectoryPreview
extends Node2D
## "Short" trajectory preview (PLAN 3.5): a dotted glowing arc over the first quarter of the
## flight, computed with the pure Ballistics.trace and NO wind (wind_override = 0), so wind is
## still something the player has to judge. Recomputed only when the aim changes, and at most
## once per frame (request() just marks it dirty).

const FRACTION: float = 0.25
const DOT_SPACING: float = 15.0
const MIN_TICKS: int = 4

var _dirty: bool = false
var _state: MatchState = null
var _tank_id: int = 0
var _angle: int = 0
var _power: int = 0
var _dots: PackedVector2Array = PackedVector2Array()
var _color: Color = NeonPalette.CYAN
var _recomputes: int = 0


func _ready() -> void:
	material = FxTextures.additive()
	set_process(false)


## Marks the preview stale for this aim; the arc is rebuilt on the next frame.
func request(state: MatchState, tank_id: int, angle: int, power: int) -> void:
	_state = state
	_tank_id = tank_id
	_angle = angle
	_power = power
	_color = NeonPalette.tank_color(state.tanks[tank_id].color_index)
	_dirty = true
	visible = true
	set_process(true)


func hide_preview() -> void:
	_dirty = false
	visible = false
	set_process(false)


## Number of times the arc was rebuilt (tests: at most once per frame).
func get_recompute_count() -> int:
	return _recomputes


func get_dot_count() -> int:
	return _dots.size()


func _process(_delta: float) -> void:
	if not _dirty:
		return
	_dirty = false
	rebuild_now()
	set_process(false)


func rebuild_now() -> void:
	_recomputes += 1
	_dots.clear()
	if _state == null or _power < SimConstants.MIN_POWER:
		queue_redraw()
		return
	var tr: Dictionary = Ballistics.trace(_state, _tank_id, _angle, _power, "pulse_missile",
			0, SimConstants.MAX_FLIGHT_TICKS)
	var path: PackedInt32Array = tr["path"]
	var ticks: int = tr["ticks"]
	var keep: int = clampi(int(float(ticks) * FRACTION), mini(MIN_TICKS, ticks), ticks)
	var inv: float = 1.0 / float(FixedMath.ONE)
	var last: Vector2 = Vector2(float(path[0]) * inv, float(path[1]) * inv)
	_dots.append(last)
	var acc: float = 0.0
	for i: int in range(1, keep):
		var p := Vector2(float(path[i * 2]) * inv, float(path[i * 2 + 1]) * inv)
		acc += p.distance_to(last)
		last = p
		if acc >= DOT_SPACING:
			acc = 0.0
			_dots.append(p)
	queue_redraw()


func _draw() -> void:
	var n: int = _dots.size()
	if n == 0:
		return
	var glow: Texture2D = FxTextures.glow()
	for i: int in range(n):
		var fade: float = 1.0 - 0.65 * float(i) / float(maxi(1, n - 1))
		var p: Vector2 = _dots[i]
		draw_texture_rect(glow, Rect2(p - Vector2(13, 13), Vector2(26, 26)), false, Color(_color, 0.55 * fade))
		draw_circle(p, 2.6, Color(NeonPalette.HOT, 0.95 * fade))
