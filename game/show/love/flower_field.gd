class_name FlowerField
extends Node2D
## The flowers that sprout where hearts land (Love Edition). Purely visual: 3 to 7 small neon
## flowers appear on the terrain surface around each impact, grow with a short bouncy animation and
## then stay for the match. One node draws them all from parallel arrays (no node per flower, no
## per-frame work once they have grown); at most MAX_FLOWERS exist, the oldest is reused first.
## Positions come from the terrain surface and a generator seeded by the impact, so restoring a saved
## match plants the same garden.

const MAX_FLOWERS: int = 48
const MIN_PER_IMPACT: int = 3
const MAX_PER_IMPACT: int = 7
const GROW_SECONDS: float = 0.75
## Tank hull half-width plus a margin: flowers never sprout under a tank.
const TANK_CLEAR: float = 20.0
const PALETTE: Array[Color] = [
	Color(1.0, 0.45, 0.72), Color(1.0, 0.72, 0.52), Color(0.82, 0.58, 1.0),
	Color(1.0, 0.88, 0.94), Color(1.0, 0.42, 0.52),
]
const STEM: Color = Color(0.4, 1.0, 0.7)
const CENTER: Color = Color(1.0, 0.92, 0.5)

var _base: PackedVector2Array = PackedVector2Array()
var _size: PackedFloat32Array = PackedFloat32Array()
var _kind: PackedInt32Array = PackedInt32Array()
var _born: PackedFloat32Array = PackedFloat32Array()
var _lean: PackedFloat32Array = PackedFloat32Array()
var _count: int = 0
var _next: int = 0
var _sprouts: int = 0
var _time: float = 0.0
var _growing: bool = false
var _glow: Node2D = null


func _ready() -> void:
	_glow = Node2D.new()
	_glow.name = "Glow"
	_glow.material = FxTextures.additive()
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	set_process(false)


func _init() -> void:
	_base.resize(MAX_FLOWERS)
	_size.resize(MAX_FLOWERS)
	_kind.resize(MAX_FLOWERS)
	_born.resize(MAX_FLOWERS)
	_lean.resize(MAX_FLOWERS)


func flower_count() -> int:
	return _count


func capacity() -> int:
	return MAX_FLOWERS


func is_growing() -> bool:
	return _growing


## Foot of flower `i` (0 = the oldest still alive).
func get_flower_position(i: int) -> Vector2:
	return _base[_slot(i)]


func clear() -> void:
	_count = 0
	_next = 0
	_sprouts = 0
	_growing = false
	set_process(false)
	_redraw()


## Plants 3 to 7 flowers around the impact (`x`, `y` in cells) on `terrain`'s surface, skipping the
## tank columns in `avoid_xs`. `animate` false shows them fully grown. Returns how many were planted.
func sprout(terrain: Terrain, x: int, y: int, radius: int, avoid_xs: PackedInt32Array, animate: bool = true) -> int:
	_sprouts += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = x * 7919 + y * 104729 + _sprouts * 31
	var n: int = rng.randi_range(MIN_PER_IMPACT, MAX_PER_IMPACT)
	var reach: float = float(radius) + 10.0
	var planted: int = 0
	for i: int in range(n):
		var t: float = (float(i) + 0.5) / float(n)
		var fx: float = float(x) + lerpf(-reach, reach, t) + rng.randf_range(-reach, reach) / float(n)
		fx = _clear_of_tanks(fx, avoid_xs)
		var cx: int = clampi(roundi(fx), 0, terrain.width - 1)
		var sy: int = terrain.surface_y(cx)
		if sy >= terrain.height:
			continue
		_add(Vector2(float(cx), float(sy) + 1.0), rng, animate)
		planted += 1
	_growing = _growing or (animate and not ShowSettings.reduce_motion and planted > 0)
	set_process(_growing)
	_redraw()
	return planted


## Re-plants a saved garden: `impacts` is [[x, y, radius], ...] in the order they happened.
func restore(impacts: Array, terrain: Terrain, avoid_xs: PackedInt32Array) -> void:
	clear()
	for entry: Variant in impacts:
		if typeof(entry) == TYPE_ARRAY and (entry as Array).size() >= 3:
			var a: Array = entry
			sprout(terrain, int(a[0]), int(a[1]), int(a[2]), avoid_xs, false)


static func _clear_of_tanks(fx: float, avoid_xs: PackedInt32Array) -> float:
	for tx: int in avoid_xs:
		if absf(fx - float(tx)) < TANK_CLEAR:
			return float(tx) + (TANK_CLEAR if fx >= float(tx) else -TANK_CLEAR)
	return fx


func _add(foot: Vector2, rng: RandomNumberGenerator, animate: bool) -> void:
	var i: int = _next
	_next = (_next + 1) % MAX_FLOWERS
	_count = mini(_count + 1, MAX_FLOWERS)
	_base[i] = foot
	_size[i] = rng.randf_range(0.85, 1.3)
	_kind[i] = rng.randi_range(0, PALETTE.size() - 1)
	_lean[i] = rng.randf_range(-0.35, 0.35)
	_born[i] = _time + (rng.randf_range(0.0, 0.25) if animate else -GROW_SECONDS)


## Ring-buffer slot of the i-th oldest flower.
func _slot(i: int) -> int:
	return posmod(_next - _count + i, MAX_FLOWERS)


func _process(delta: float) -> void:
	_time += delta
	var still: bool = true
	for i: int in range(_count):
		if _time - _born[_slot(i)] < GROW_SECONDS:
			still = false
			break
	if still:
		_growing = false
		set_process(false)
	_redraw()


func _redraw() -> void:
	queue_redraw()
	if _glow != null:
		_glow.queue_redraw()


## 0 -> 1 with a little overshoot (the bounce of a sprouting flower).
func _grow(i: int) -> float:
	var g: float = clampf((_time - _born[i]) / GROW_SECONDS, 0.0, 1.0)
	if g >= 1.0:
		return 1.0
	var c1: float = 1.70158
	var u: float = g - 1.0
	return maxf(0.0, 1.0 + (c1 + 1.0) * u * u * u + c1 * u * u)


func _head(i: int, g: float) -> Vector2:
	var h: float = _size[i] * 17.0 * g
	return _base[i] + Vector2(_lean[i] * h * 0.5, -h)


func _draw() -> void:
	for n: int in range(_count):
		var i: int = _slot(n)
		var g: float = _grow(i)
		if g <= 0.0:
			continue
		var foot: Vector2 = _base[i]
		var top: Vector2 = _head(i, g)
		var mid: Vector2 = foot.lerp(top, 0.5) + Vector2(_lean[i] * 4.0, 0.0)
		var stem := PackedVector2Array()
		for k: int in range(5):
			var t: float = float(k) / 4.0
			stem.append(foot.lerp(mid, t).lerp(mid.lerp(top, t), t))
		draw_polyline(stem, Color(STEM, 0.9), 1.7, true)
		var leaf: Vector2 = foot.lerp(top, 0.35)
		var lr: float = 3.2 * _size[i] * g
		draw_colored_polygon(PackedVector2Array([leaf, leaf + Vector2(lr * 1.6, -lr * 0.9), leaf + Vector2(lr * 0.4, -lr * 1.5)]), Color(STEM, 0.85))
		var pr: float = 3.0 * _size[i] * g
		var col: Color = PALETTE[_kind[i]]
		for p: int in range(5):
			var a: float = TAU * float(p) / 5.0 - PI / 2.0
			draw_circle(top + Vector2(cos(a), sin(a)) * pr * 1.05, pr * 0.78, col)
		draw_circle(top, pr * 0.62, CENTER)
		draw_circle(top + Vector2(-pr * 0.15, -pr * 0.15), pr * 0.2, Color.WHITE)


func _draw_glow() -> void:
	for n: int in range(_count):
		var i: int = _slot(n)
		var g: float = _grow(i)
		if g <= 0.0:
			continue
		var top: Vector2 = _head(i, g)
		var r: float = 3.0 * _size[i] * g
		var col: Color = PALETTE[_kind[i]]
		_glow.draw_circle(top, r * 3.2, Color(col, 0.13))
		_glow.draw_circle(top, r * 1.9, Color(col, 0.18))
		_glow.draw_circle(top + (_base[i] - top) * 0.0, r * 0.7, Color(1.0, 0.95, 0.8, 0.25))
