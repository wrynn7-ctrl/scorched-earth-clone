class_name EmberSparks
extends Control
## A few ember sparks drifting up off the title logo. One node, one _draw: each spark is a soft additive dot
## (a faint halo plus a bright core) on a fixed, hand-picked track, so nothing is allocated per frame.
## Reduce motion: the sparks hang still at a pleasant moment. Reduce flashing: no twinkle, only the slow
## fade in and out of a spark's life (no brightness changes faster than that).

const COUNT: int = 14
## Seconds a spark takes to rise its full height at speed 1.
const RISE_SECONDS: float = 5.5
## The frozen moment shown under reduce motion (seconds of the animation clock).
const STILL_TIME: float = 2.7

## Per spark: [x (0..1 across), phase (0..1), speed, size (dp), hue (0 yellow .. 1 red), sway (dp)].
const TRACKS: Array = [
	[0.06, 0.10, 1.00, 2.6, 0.7, 6.0], [0.15, 0.62, 0.80, 2.0, 0.4, 9.0], [0.24, 0.35, 1.15, 3.0, 0.2, 7.0],
	[0.33, 0.88, 0.90, 2.2, 0.8, 5.0], [0.42, 0.20, 0.70, 2.8, 0.5, 8.0], [0.50, 0.55, 1.10, 2.0, 0.1, 6.0],
	[0.58, 0.02, 0.85, 3.2, 0.3, 10.0], [0.66, 0.74, 1.00, 2.2, 0.9, 7.0], [0.74, 0.40, 0.75, 2.6, 0.6, 9.0],
	[0.82, 0.95, 1.20, 2.0, 0.2, 5.0], [0.90, 0.28, 0.95, 2.8, 0.7, 8.0], [0.96, 0.67, 0.80, 2.2, 0.4, 6.0],
	[0.37, 0.48, 0.65, 1.8, 0.5, 4.0], [0.70, 0.15, 0.60, 1.8, 0.8, 4.0],
]
const HOT: Color = Color(1.0, 0.92, 0.45)
const COOL: Color = Color(1.0, 0.28, 0.10)

## Where a spark starts (fraction of this node's height from the top) and how far up it climbs (in heights).
var base_frac: float = 0.6
var rise_heights: float = 1.3
var _clock: float = 0.0
var _unit: float = 1.0


func _init() -> void:
	name = "EmberSparks"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = add


func _ready() -> void:
	refresh()


## Call after the screen scale or the reduce-motion setting changed.
func refresh() -> void:
	_unit = UiScale.dp(1.0)
	var still: bool = ShowSettings.reduce_motion
	_clock = STILL_TIME if still else _clock
	set_process(not still)
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()


func is_still() -> bool:
	return not is_processing()


## The number of sparks that are visible at all right now (the tests use it).
func visible_count() -> int:
	var n: int = 0
	for i: int in range(TRACKS.size()):
		if _life(i)[1] > 0.02:
			n += 1
	return n


## [progress 0..1 along the climb, alpha 0..1] of spark `i` at the current clock.
func _life(i: int) -> Array:
	var trk: Array = TRACKS[i]
	var p: float = fposmod((trk[1] as float) + _clock * (trk[2] as float) / RISE_SECONDS, 1.0)
	# Fade in fast, fade out slowly: p -> 0..1 rise, alpha is a smooth hump.
	var a: float = smoothstep(0.0, 0.12, p) * (1.0 - smoothstep(0.5, 1.0, p))
	if not ShowSettings.reduce_flashing and not ShowSettings.reduce_motion:
		a *= 0.8 + 0.2 * sin(_clock * (5.0 + float(i)) + float(i) * 1.7)
	return [p, a]


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	var base_y: float = h * base_frac
	var climb: float = h * rise_heights
	for i: int in range(TRACKS.size()):
		var trk: Array = TRACKS[i]
		var life: Array = _life(i)
		var p: float = life[0] as float
		var a: float = life[1] as float
		if a <= 0.01:
			continue
		var sway: float = sin(p * TAU * 1.5 + float(i) * 2.1) * (trk[5] as float) * _unit * p
		var pos := Vector2(w * (0.04 + 0.92 * (trk[0] as float)) + sway, base_y - climb * p)
		var col: Color = HOT.lerp(COOL, clampf((trk[4] as float) * 0.6 + p * 0.5, 0.0, 1.0))
		var r: float = (trk[3] as float) * 1.5 * _unit * (1.0 - 0.45 * p)
		draw_circle(pos, r * 2.6, Color(col, 0.22 * a))
		draw_circle(pos, r, Color(col, 0.95 * a))
