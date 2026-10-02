class_name TankView
extends Node2D
## Neon tank: glowing outline hull, rotating turret, player colour + emblem, small health bar.
##
## Local origin = bottom-centre of the tank footprint (24x12 world units, ARCHITECTURE §6),
## so the node's position is the simulation's (x, y) ground point. The whole visual is
## scaled up by VISUAL_SCALE for readability. Angles are tenths of a degree, 0 = right,
## 900 = up. Only redraws when a value changes; no per-frame work.

const TANK_W: float = 24.0
const TANK_H: float = 12.0
const BARREL_LEN: float = 14.0
const VISUAL_SCALE: float = 1.5
const BAR_W: float = 26.0
const BAR_H: float = 3.5

var _angle_tenths: int = 900
var _color_index: int = 0
var _health: int = 100
var _max_health: int = 100
var _dead: bool = false

var _glow: Node2D = null
var _body: Node2D = null
var _turret: Node2D = null
var _turret_glow: Node2D = null


func _ready() -> void:
	scale = Vector2(VISUAL_SCALE, VISUAL_SCALE)
	_glow = _make_layer("Glow", true)
	_body = _make_layer("Body", false)
	_turret = _make_layer("Turret", false)
	_turret.position = Vector2(0, -TANK_H)
	_turret_glow = Node2D.new()
	_turret_glow.name = "TurretGlow"
	_turret_glow.material = FxTextures.additive()
	_turret.add_child(_turret_glow)
	_glow.draw.connect(_draw_glow)
	_body.draw.connect(_draw_body)
	_turret.draw.connect(_draw_turret)
	_turret_glow.draw.connect(_draw_turret_glow)
	_apply_angle()
	_redraw_all()


func set_angle_tenths(a: int) -> void:
	_angle_tenths = a
	_apply_angle()


func get_angle_tenths() -> int:
	return _angle_tenths


func set_color_index(i: int) -> void:
	_color_index = i
	_redraw_all()


func get_color_index() -> int:
	return _color_index


func set_health(h: int, max_h: int) -> void:
	_health = clampi(h, 0, maxi(1, max_h))
	_max_health = maxi(1, max_h)
	if _body != null:
		_body.queue_redraw()


func get_health() -> int:
	return _health


func set_dead(dead: bool) -> void:
	_dead = dead
	if _turret != null:
		_turret.visible = not dead
	_redraw_all()


func is_dead() -> bool:
	return _dead


## Muzzle tip in this node's parent coordinates (for spawning shells/flashes in show code).
func muzzle_position() -> Vector2:
	var a: float = deg_to_rad(float(_angle_tenths) / 10.0)
	return position + (Vector2(0, -TANK_H) + Vector2(cos(a), -sin(a)) * BARREL_LEN) * VISUAL_SCALE


func _make_layer(layer_name: String, additive: bool) -> Node2D:
	var n := Node2D.new()
	n.name = layer_name
	if additive:
		n.material = FxTextures.additive()
	add_child(n)
	return n


func _apply_angle() -> void:
	if _turret != null:
		_turret.rotation = -deg_to_rad(float(_angle_tenths) / 10.0)


func _redraw_all() -> void:
	if _glow == null:
		return
	_glow.queue_redraw()
	_body.queue_redraw()
	_turret.queue_redraw()
	_turret_glow.queue_redraw()


func _col() -> Color:
	var c: Color = NeonPalette.tank_color(_color_index)
	if _dead:
		c = c.darkened(0.65).lerp(Color(0.35, 0.35, 0.4), 0.4)
	return c


static func _hull() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-12, 0), Vector2(12, 0), Vector2(12, -3.5), Vector2(8.5, -8.0),
		Vector2(-8.5, -8.0), Vector2(-12, -3.5), Vector2(-12, 0),
	])


func _draw_glow() -> void:
	var c: Color = _col()
	var h: PackedVector2Array = _hull()
	_glow.draw_polyline(h, Color(c, 0.18), 6.0, true)
	_glow.draw_polyline(h, Color(c, 0.35), 3.2, true)
	if not _dead:
		_glow.draw_circle(Vector2(0, -TANK_H), 5.0, Color(c, 0.22))


func _draw_body() -> void:
	var c: Color = _col()
	var h: PackedVector2Array = _hull()
	_body.draw_colored_polygon(h.slice(0, 6), Color(NeonPalette.BG_DEEP, 0.92).lerp(c, 0.14))
	_body.draw_polyline(h, c, 1.4, true)
	# Tread line + hub.
	_body.draw_line(Vector2(-10, -1.4), Vector2(10, -1.4), Color(c, 0.6), 1.0, true)
	if _dead:
		_body.draw_line(Vector2(-6, -8), Vector2(-2, -4), c, 1.2, true)
		_body.draw_line(Vector2(3, -8), Vector2(7, -3), c, 1.2, true)
		return
	_body.draw_circle(Vector2(0, -TANK_H + 1.0), 3.2, c)
	# Floating marker: emblem (second cue besides colour) above a health bar.
	NeonPalette.draw_emblem(_body, NeonPalette.tank_emblem(_color_index), Vector2(0, -45), 5.5, c)
	var frac: float = float(_health) / float(_max_health)
	var bx: float = -BAR_W * 0.5
	_body.draw_rect(Rect2(bx - 1, -37.5 - 1, BAR_W + 2, BAR_H + 2), Color(NeonPalette.BG_DEEP, 0.85))
	var bc: Color = NeonPalette.GOOD if frac > 0.6 else (NeonPalette.WARN if frac > 0.3 else NeonPalette.BAD)
	if frac > 0.0:
		_body.draw_rect(Rect2(bx, -37.5, BAR_W * frac, BAR_H), bc)


func _draw_turret() -> void:
	var c: Color = _col()
	_turret.draw_rect(Rect2(0, -1.6, BARREL_LEN + 2.0, 3.2), Color(NeonPalette.BG_DEEP, 0.95))
	_turret.draw_rect(Rect2(0, -1.6, BARREL_LEN + 2.0, 3.2), c, false, 1.2)
	_turret.draw_line(Vector2(BARREL_LEN + 2.0, -1.6), Vector2(BARREL_LEN + 2.0, 1.6), NeonPalette.HOT, 1.6)


func _draw_turret_glow() -> void:
	var c: Color = _col()
	_turret_glow.draw_rect(Rect2(-1, -3.2, BARREL_LEN + 4.0, 6.4), Color(c, 0.22))
