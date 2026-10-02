class_name TankView
extends Node2D
## Neon tank: glowing outline hull, rotating turret, player colour + emblem, small health bar,
## plus the M3 overlays: shield bubble (flickers on hits, breaks), repulsor ring, chute canopy
## and a repair sparkle.
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
## Shield bubble and repulsor field, in this node's local units (world units / VISUAL_SCALE).
const SHIELD_R: float = float(SimConstants.SHIELD_RADIUS) / VISUAL_SCALE
const SHIELD_CY: float = -float(SimConstants.SHIELD_CENTER_DY) / VISUAL_SCALE
const REPULSOR_R: float = float(SimConstants.REPULSOR_RADIUS) / VISUAL_SCALE
const CHUTE_SHOW_SECONDS: float = 1.0
const HIT_FLASH_SECONDS: float = 0.7

var _angle_tenths: int = 900
var _color_index: int = 0
var _health: int = 100
var _max_health: int = 100
var _dead: bool = false
var _emblem_index: int = 0

var _shield_hp: int = 0
var _shield_max: int = 1
var _flicker: float = 0.0
var _break_t: float = -1.0
var _repulsor: bool = false
var _chute_left: float = 0.0
var _anim_t: float = 0.0
var _hit_t: float = 0.0
var _hit_color: Color = Color.WHITE
var _hit_flicker: bool = false
var _aura: Node2D = null
var _sparkle: CPUParticles2D = null

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
	_aura = _make_layer("Aura", true)
	_aura.draw.connect(_draw_aura)
	_build_sparkle()
	set_process(false)
	_glow.draw.connect(_draw_glow)
	_body.draw.connect(_draw_body)
	_turret.draw.connect(_draw_turret)
	_turret_glow.draw.connect(_draw_turret_glow)
	_apply_angle()
	_redraw_all()
	_update_processing()


func set_angle_tenths(a: int) -> void:
	_angle_tenths = a
	_apply_angle()


func get_angle_tenths() -> int:
	return _angle_tenths


## Same colour and emblem index (the palette default).
func set_color_index(i: int) -> void:
	set_look(i, i)


## Colour and emblem picked on the setup screen (PlayerLooks indices).
func set_look(color_index: int, emblem_index: int) -> void:
	_color_index = color_index
	_emblem_index = emblem_index
	_redraw_all()


func get_color_index() -> int:
	return _color_index


func get_emblem_index() -> int:
	return _emblem_index


# --- shield / repulsor / chute / repair ---------------------------------------------------

## Shows (hp > 0) or hides the bubble. `max_hp` scales its brightness and the HP bar.
func set_shield(hp: int, max_hp: int) -> void:
	_shield_hp = maxi(0, hp)
	_shield_max = maxi(1, max_hp)
	_break_t = -1.0
	if _body != null:
		_body.queue_redraw()
	_update_processing()


func get_shield_hp() -> int:
	return _shield_hp


func has_shield_bubble() -> bool:
	return _shield_hp > 0


## A hit on the bubble: it flickers and the HP readout drops.
func shield_hit(hp: int) -> void:
	_shield_hp = maxi(0, hp)
	_flicker = 0.35 if ShowSettings.reduce_flashing else 1.0
	if _body != null:
		_body.queue_redraw()
	_update_processing()


## The bubble pops: an expanding ring and shards that fade out.
func shield_break() -> void:
	_shield_hp = 0
	_break_t = 0.0
	if _body != null:
		_body.queue_redraw()
	_update_processing()


func is_breaking() -> bool:
	return _break_t >= 0.0


func set_repulsor(active: bool) -> void:
	_repulsor = active
	_update_processing()


func is_repulsor_on() -> bool:
	return _repulsor


## Draws the parachute canopy over the tank for `seconds` (while it falls).
func show_chute(seconds: float = CHUTE_SHOW_SECONDS) -> void:
	_chute_left = seconds
	_update_processing()


func is_chute_visible() -> bool:
	return _chute_left > 0.0


## Green sparkles rising from the hull (nanorepair kit).
func repair_burst() -> void:
	if _sparkle != null:
		_sparkle.restart()
		_sparkle.emitting = true


## A short glow over the hull when something other than a blast hurt the tank: a flickering
## orange for burning, a hard cyan-white flash for the Photon Lance. Reduced flashing keeps
## the glow but drops the flicker and the peak.
func hit_flash(color: Color, flicker: bool = false) -> void:
	if _dead:
		return
	_hit_color = color
	_hit_flicker = flicker and not ShowSettings.reduce_flashing
	_hit_t = HIT_FLASH_SECONDS
	_update_processing()


func is_hit_flashing() -> bool:
	return _hit_t > 0.0


func _update_processing() -> void:
	var run: bool = _shield_hp > 0 or _break_t >= 0.0 or _repulsor or _chute_left > 0.0 or _flicker > 0.0 \
			or _hit_t > 0.0
	set_process(run and is_inside_tree())
	if _aura != null:
		_aura.queue_redraw()


func _process(delta: float) -> void:
	_anim_t += delta
	_flicker = maxf(0.0, _flicker - delta * 3.0)
	if _break_t >= 0.0:
		_break_t += delta / 0.45
		if _break_t >= 1.0:
			_break_t = -1.0
	_chute_left = maxf(0.0, _chute_left - delta)
	_hit_t = maxf(0.0, _hit_t - delta)
	_aura.queue_redraw()
	if not (_shield_hp > 0 or _break_t >= 0.0 or _repulsor or _chute_left > 0.0 or _hit_t > 0.0):
		set_process(false)


func _build_sparkle() -> void:
	_sparkle = CPUParticles2D.new()
	_sparkle.name = "Sparkle"
	_sparkle.amount = 14
	_sparkle.one_shot = true
	_sparkle.explosiveness = 0.7
	_sparkle.emitting = false
	_sparkle.lifetime = 0.9
	_sparkle.position = Vector2(0, -6)
	_sparkle.texture = FxTextures.glow()
	_sparkle.material = FxTextures.additive()
	_sparkle.direction = Vector2(0, -1)
	_sparkle.spread = 35.0
	_sparkle.gravity = Vector2(0, -18)
	_sparkle.initial_velocity_min = 14.0
	_sparkle.initial_velocity_max = 34.0
	_sparkle.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_sparkle.emission_rect_extents = Vector2(10, 3)
	_sparkle.scale_amount_min = 0.05
	_sparkle.scale_amount_max = 0.12
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(NeonPalette.HOT, 0.0), NeonPalette.GOOD, Color(NeonPalette.GOOD, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	_sparkle.color_ramp = ramp
	add_child(_sparkle)


func set_health(h: int, max_h: int) -> void:
	_health = clampi(h, 0, maxi(1, max_h))
	_max_health = maxi(1, max_h)
	if _body != null:
		_body.queue_redraw()


func get_health() -> int:
	return _health


func set_dead(dead: bool) -> void:
	_dead = dead
	if dead:
		_shield_hp = 0
		_repulsor = false
		_chute_left = 0.0
		_break_t = -1.0
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
	NeonPalette.draw_emblem(_body, NeonPalette.tank_emblem(_emblem_index), Vector2(0, -45), 5.5, c)
	var frac: float = float(_health) / float(_max_health)
	var bx: float = -BAR_W * 0.5
	_body.draw_rect(Rect2(bx - 1, -37.5 - 1, BAR_W + 2, BAR_H + 2), Color(NeonPalette.BG_DEEP, 0.85))
	var bc: Color = NeonPalette.GOOD if frac > 0.6 else (NeonPalette.WARN if frac > 0.3 else NeonPalette.BAD)
	if frac > 0.0:
		_body.draw_rect(Rect2(bx, -37.5, BAR_W * frac, BAR_H), bc)
	if _shield_hp > 0:
		_draw_shield_readout(bx)


## Thin cyan bar under the health bar plus the HP number: the shield is never colour-only.
func _draw_shield_readout(bx: float) -> void:
	var f: float = clampf(float(_shield_hp) / float(_shield_max), 0.0, 1.0)
	_body.draw_rect(Rect2(bx - 1, -33.0, BAR_W + 2, 3.5), Color(NeonPalette.BG_DEEP, 0.85))
	_body.draw_rect(Rect2(bx, -32.5, BAR_W * f, 2.5), NeonPalette.CYAN)
	_body.draw_string(ThemeDB.fallback_font, Vector2(bx + BAR_W + 3.0, -29.5), str(_shield_hp),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, NeonPalette.CYAN)


func _draw_turret() -> void:
	var c: Color = _col()
	_turret.draw_rect(Rect2(0, -1.6, BARREL_LEN + 2.0, 3.2), Color(NeonPalette.BG_DEEP, 0.95))
	_turret.draw_rect(Rect2(0, -1.6, BARREL_LEN + 2.0, 3.2), c, false, 1.2)
	_turret.draw_line(Vector2(BARREL_LEN + 2.0, -1.6), Vector2(BARREL_LEN + 2.0, 1.6), NeonPalette.HOT, 1.6)


func _draw_turret_glow() -> void:
	var c: Color = _col()
	_turret_glow.draw_rect(Rect2(-1, -3.2, BARREL_LEN + 4.0, 6.4), Color(c, 0.22))


func _draw_aura() -> void:
	var c: Color = _col()
	if _repulsor:
		_draw_repulsor()
	if _shield_hp > 0:
		var center := Vector2(0, SHIELD_CY)
		var strength: float = 0.45 + 0.55 * clampf(float(_shield_hp) / float(_shield_max), 0.0, 1.0)
		var jitter: float = 0.0
		if _flicker > 0.0:
			jitter = (0.5 + 0.5 * sin(_anim_t * 70.0)) * _flicker
		var a: float = clampf(strength * (0.3 + 0.1 * sin(_anim_t * 3.0)) + jitter * 0.6, 0.0, 1.0)
		_aura.draw_circle(center, SHIELD_R, Color(NeonPalette.CYAN, a * 0.35))
		_aura.draw_arc(center, SHIELD_R, 0.0, TAU, 40, Color(NeonPalette.CYAN, minf(1.0, a + 0.35)), 2.0, true)
		_aura.draw_arc(center, SHIELD_R - 3.0, PI * 1.1, PI * 1.5, 12, Color(NeonPalette.HOT, a + 0.2), 1.6, true)
		if _flicker > 0.0:
			_aura.draw_arc(center, SHIELD_R + 2.0, 0.0, TAU, 40, Color(NeonPalette.HOT, jitter * 0.8), 2.4, true)
	if _break_t >= 0.0:
		_draw_break()
	if _chute_left > 0.0:
		_draw_chute(c)
	if _hit_t > 0.0:
		_draw_hit_flash()


func _draw_hit_flash() -> void:
	var k: float = _hit_t / HIT_FLASH_SECONDS
	var a: float = k * (0.55 if ShowSettings.reduce_flashing else 0.9)
	if _hit_flicker:
		a *= 0.55 + 0.45 * sin(_hit_t * 55.0)
	var hull: PackedVector2Array = _hull().slice(0, 6)
	_aura.draw_colored_polygon(hull, Color(_hit_color, a * 0.7))
	_aura.draw_polyline(_hull(), Color(_hit_color, a), 3.0, true)
	_aura.draw_circle(Vector2(0, -TANK_H * 0.6), 11.0 + 5.0 * (1.0 - k), Color(_hit_color, a * 0.35))


func _draw_break() -> void:
	var center := Vector2(0, SHIELD_CY)
	var k: float = clampf(_break_t, 0.0, 1.0)
	var fade: float = 1.0 - k
	_aura.draw_arc(center, SHIELD_R * (1.0 + 0.5 * k), 0.0, TAU, 40, Color(NeonPalette.CYAN, fade), 2.0, true)
	for i: int in range(8):
		var ang: float = TAU * float(i) / 8.0 + 0.2
		var d := Vector2(cos(ang), sin(ang))
		_aura.draw_line(center + d * SHIELD_R * (0.9 + 0.5 * k), center + d * SHIELD_R * (1.05 + 0.9 * k),
				Color(NeonPalette.HOT, fade), 1.6, true)


func _draw_repulsor() -> void:
	var center := Vector2(0, SHIELD_CY)
	var mint := Color(0.4, 1.0, 0.85)
	_aura.draw_arc(center, REPULSOR_R, 0.0, TAU, 56, Color(mint, 0.18), 1.5, true)
	for i: int in range(2):
		var phase: float = fposmod(_anim_t * 0.9 + float(i) * 0.5, 1.0)
		_aura.draw_arc(center, REPULSOR_R * (0.45 + 0.55 * phase), 0.0, TAU, 48, Color(mint, 0.55 * (1.0 - phase)), 2.0, true)


func _draw_chute(c: Color) -> void:
	var fade: float = clampf(_chute_left / 0.25, 0.0, 1.0)
	var top := Vector2(0, -TANK_H - 22.0)
	var col := Color(NeonPalette.WARN, fade)
	_aura.draw_arc(top, 15.0, PI, TAU, 20, col, 2.0, true)
	_aura.draw_line(top + Vector2(-15, 0), top + Vector2(15, 0), Color(col, 0.6 * fade), 1.0, true)
	for x: float in [-15.0, -5.0, 5.0, 15.0]:
		_aura.draw_line(top + Vector2(x, 0), Vector2(0, -TANK_H - 2.0), Color(c, 0.75 * fade), 1.0, true)
