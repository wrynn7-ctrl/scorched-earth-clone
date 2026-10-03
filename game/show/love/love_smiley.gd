class_name LoveSmiley
extends Node2D
## The winner's reward (Love Edition): a big neon smiley that floats up over the winning tank, bobs
## gently, and has a ring of little hearts orbiting it. Drawn from arcs and circles (no assets).
## With reduced motion it simply appears in place, with the hearts still. Visual only.

const RADIUS: float = 34.0
## Where it settles above the tank's ground point (world units).
const HOVER: float = 150.0
const RISE_SECONDS: float = 1.2
const ORBIT_HEARTS: int = 6
const FACE: Color = Color(1.0, 0.86, 0.5)
const CHEEK: Color = Color(1.0, 0.4, 0.6)

var _glow: Sprite2D = null
var _hearts: Array[Sprite2D] = []
var _anim_t: float = 0.0
var _tween: Tween = null
var _rest: Vector2 = Vector2.ZERO
var _showing: bool = false


func _ready() -> void:
	_glow = Sprite2D.new()
	_glow.name = "Halo"
	_glow.texture = FxTextures.glow()
	_glow.material = FxTextures.additive()
	_glow.modulate = Color(1.0, 0.6, 0.7, 0.55)
	_glow.scale = Vector2.ONE * (RADIUS * 4.2 / float(FxTextures.glow().get_width()))
	add_child(_glow)
	for i: int in range(ORBIT_HEARTS):
		var h := Sprite2D.new()
		h.name = "Orbit%d" % i
		h.texture = FxTextures.heart()
		h.material = FxTextures.additive()
		h.scale = Vector2.ONE * 0.2
		h.modulate = Color(1.0, 0.5 + 0.07 * float(i % 3), 0.7 + 0.06 * float(i % 2))
		add_child(h)
		_hearts.append(h)
	visible = false
	set_process(false)


## Floats up from the tank at `tank_ground` (the tank's ground point in world coordinates).
func show_over(tank_ground: Vector2, animate: bool = true) -> void:
	_rest = tank_ground + Vector2(0.0, -HOVER)
	_rest.y = maxf(_rest.y, RADIUS * 1.9)  # a tank high on a hill must not push the face off the top
	_showing = true
	visible = true
	_anim_t = 0.0
	if _tween != null:
		_tween.kill()
	if animate and not ShowSettings.reduce_motion:
		position = tank_ground + Vector2(0.0, -40.0)
		scale = Vector2.ONE * 0.3
		modulate.a = 0.0
		_tween = create_tween().set_parallel(true)
		_tween.tween_property(self, "position", _rest, RISE_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "scale", Vector2.ONE, RISE_SECONDS * 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "modulate:a", 1.0, 0.4)
	else:
		position = _rest
		scale = Vector2.ONE
		modulate.a = 1.0
	_place_hearts()
	set_process(not ShowSettings.reduce_motion)
	queue_redraw()


func hide_smiley() -> void:
	_showing = false
	visible = false
	set_process(false)
	if _tween != null:
		_tween.kill()


func is_showing() -> bool:
	return _showing


## Where the face rests (world coordinates), without the bob.
func get_rest_position() -> Vector2:
	return _rest


func orbit_heart_count() -> int:
	return _hearts.size()


func _process(delta: float) -> void:
	_anim_t += delta
	# The bob is a small offset of the children's drawing, so it never fights the rise tween.
	_place_hearts()
	queue_redraw()


func _bob() -> float:
	return 0.0 if ShowSettings.reduce_motion else sin(_anim_t * 2.3) * 4.5


## The hearts circle the face on a tilted ellipse, bigger when "in front".
func _place_hearts() -> void:
	var spin: float = 0.0 if ShowSettings.reduce_motion else _anim_t * 0.9
	for i: int in range(_hearts.size()):
		var a: float = spin + TAU * float(i) / float(_hearts.size())
		var depth: float = 0.5 + 0.5 * sin(a)
		var p := Vector2(cos(a) * RADIUS * 1.75, sin(a) * RADIUS * 0.55 - RADIUS * 0.2 + _bob())
		_hearts[i].position = p
		_hearts[i].scale = Vector2.ONE * (0.15 + 0.09 * depth)
		_hearts[i].rotation = cos(a) * 0.35
		_hearts[i].z_index = 1 if depth > 0.5 else -1
	_glow.position = Vector2(0.0, _bob())


func _draw() -> void:
	var c := Vector2(0.0, _bob())
	var r: float = RADIUS
	draw_circle(c, r, Color(FACE, 0.2))
	draw_arc(c, r, 0.0, TAU, 56, Color(FACE, 0.28), 11.0, true)
	draw_arc(c, r, 0.0, TAU, 56, FACE, 4.2, true)
	# Happy closed eyes (arcs) read as a smile even at a glance.
	for sx: float in [-1.0, 1.0]:
		var e: Vector2 = c + Vector2(sx * r * 0.36, -r * 0.16)
		draw_arc(e, r * 0.17, PI, TAU, 14, Color(FACE, 0.3), 8.0, true)
		draw_arc(e, r * 0.17, PI, TAU, 14, FACE, 3.6, true)
	draw_arc(c + Vector2(0.0, r * 0.02), r * 0.6, PI * 0.14, PI * 0.86, 24, Color(FACE, 0.3), 9.0, true)
	draw_arc(c + Vector2(0.0, r * 0.02), r * 0.6, PI * 0.14, PI * 0.86, 24, FACE, 4.0, true)
	for sx: float in [-1.0, 1.0]:
		var ch: Vector2 = c + Vector2(sx * r * 0.62, r * 0.2)
		draw_circle(ch, r * 0.2, Color(CHEEK, 0.22))
		draw_circle(ch, r * 0.12, Color(CHEEK, 0.5))
