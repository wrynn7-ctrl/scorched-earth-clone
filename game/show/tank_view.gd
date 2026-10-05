class_name TankView
extends Node2D
## Neon tank: glowing outline hull, rotating turret, player colour + emblem, small health bar,
## plus the M3 overlays: shield bubble (flickers on hits, breaks), repulsor ring, chute canopy
## and a repair sparkle.
##
## Skins (docs/ARCHITECTURE.md section 35): `set_skin()` swaps the hull and turret shapes and fills the hull with
## a texture baked once (SkinBaker); there is no per-frame work. The player identity is drawn on top
## of any skin from NeonPalette and cannot be changed by one: the outline in the player colour (on a
## dark rim so it reads on any skin), the emblem and the health bar.
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
## Emblem height in preview / thumbnail mode.
const COMPACT_MARKER_Y: float = -33.0
const CHUTE_SHOW_SECONDS: float = 1.0
const HIT_FLASH_SECONDS: float = 0.7
## Love Edition (ARCHITECTURE section 37): the meter replaces the health bar. The heart sits next to the
## emblem, the small bar under them where the health bar was.
const LOVE_PINK: Color = Color(1.0, 0.38, 0.62)
const LOVE_HEART_SIZE: float = 9.0
const LOVE_HEART_POS: Vector2 = Vector2(5.0, -48.0)
const LOVE_EMBLEM_POS: Vector2 = Vector2(-14.0, -48.0)
const LOVE_PULSE_SECONDS: float = 0.8
## The player's typed name floats above the emblem (ARCHITECTURE section 42). Local units.
const TAG_BASELINE_Y: float = -53.0
const TAG_FONT_SIZE: int = 9
const TAG_OUTLINE: int = 3
## The team badge (section 42): a letter on the team colour, left of the name (or alone for a CPU).
const BADGE_SIZE: float = 9.0
const BADGE_GAP: float = 2.5
## Badge and name together stay within this width (local units) so neighbours' tags never meet: a long name
## beside a badge is drawn in a smaller size.
const MAX_TAG_EXTENT: float = 130.0
const MIN_TAG_FONT_SIZE: int = 6
## How fast the displayed fill follows the real value (fraction of the meter per second).
const LOVE_FILL_SPEED: float = 1.1

var _angle_tenths: int = 900
var _color_index: int = 0
var _health: int = 100
var _max_health: int = 100
var _dead: bool = false
var _emblem_index: int = 0
## The name tag text ("" = no tag; only players who typed a name get one).
var _name_tag: String = ""
## The team shown as a badge on the tag (TeamStyle.NONE = no teams in this match).
var _team: int = TeamStyle.NONE
static var _tag_font: Font = null

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

## The skin on this tank (null = the standard look) and its baked hull texture. Local to this
## device: nothing in a match, a save or the network ever refers to it.
var _skin: SkinData = null
var _skin_tex: Texture2D = null
## Studio previews and list thumbnails: the emblem sits close above the hull and the bars are left out.
var _compact: bool = false
## Pixels per hull unit for the baked skin texture (the studio's big preview asks for more).
var skin_ppu: int = SkinBaker.DEFAULT_PPU

var _glow: Node2D = null
var _skin_glow: Node2D = null
var _love_layer: Node2D = null
var _love_glow: Node2D = null
var _love_mode: bool = false
var _love: int = 0
var _love_shown: float = 0.0
var _love_pulse: float = 0.0
var _body: Node2D = null
var _turret: Node2D = null
var _turret_glow: Node2D = null


func _ready() -> void:
	scale = Vector2(VISUAL_SCALE, VISUAL_SCALE)
	_glow = _make_layer("Glow", true)
	_skin_glow = _make_layer("SkinGlow", true)
	_body = _make_layer("Body", false)
	_turret = _make_layer("Turret", false)
	_turret.position = Vector2(0, -TANK_H)
	_turret_glow = Node2D.new()
	_turret_glow.name = "TurretGlow"
	_turret_glow.material = FxTextures.additive()
	_turret.add_child(_turret_glow)
	_aura = _make_layer("Aura", true)
	_aura.draw.connect(_draw_aura)
	_love_layer = _make_layer("Love", false)
	_love_layer.draw.connect(_draw_love)
	_love_glow = _make_layer("LoveGlow", true)
	_love_glow.draw.connect(_draw_love_glow)
	_build_sparkle()
	set_process(false)
	_glow.draw.connect(_draw_glow)
	_skin_glow.draw.connect(_draw_skin_glow)
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


## The name floating above the tank ("" removes it). Long names are squeezed to the tag's width.
func set_name_tag(text: String) -> void:
	if text == _name_tag:
		return
	_name_tag = text
	_redraw_all()


func get_name_tag() -> String:
	return _name_tag


## The team badge beside the name (0..3); anything else removes it. A CPU tank has no name but still gets the badge.
func set_team(team: int) -> void:
	var t: int = team if TeamStyle.is_team(team) else TeamStyle.NONE
	if t == _team:
		return
	_team = t
	_redraw_all()


func get_team() -> int:
	return _team


## Width of the whole tag (badge and name), in local units.
func tag_extent() -> float:
	var w: float = _name_width()
	if _team != TeamStyle.NONE:
		w += BADGE_SIZE + (BADGE_GAP if _name_tag != "" else 0.0)
	return w


## The name's font size: TAG_FONT_SIZE, smaller when a badge leaves too little room for a long name.
func _name_font_size() -> int:
	if _name_tag == "" or _team == TeamStyle.NONE:
		return TAG_FONT_SIZE
	var room: float = MAX_TAG_EXTENT - BADGE_SIZE - BADGE_GAP
	var w: float = tag_width(_name_tag)
	if w <= room:
		return TAG_FONT_SIZE
	return maxi(MIN_TAG_FONT_SIZE, floori(float(TAG_FONT_SIZE) * room / w))


func _name_width() -> float:
	if _name_tag == "":
		return 0.0
	return _get_tag_font().get_string_size(_name_tag, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _name_font_size()).x


## Width the widest possible tag (12 capital letters) takes, in local units: tests keep it clear of the neighbours.
static func tag_width(text: String) -> float:
	return _get_tag_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TAG_FONT_SIZE).x


static func _get_tag_font() -> Font:
	if _tag_font == null:
		_tag_font = load(NameFilter.FONT_PATH) as Font
		if _tag_font == null:
			_tag_font = ThemeDB.fallback_font
	return _tag_font


func _draw_name_tag(c: Color) -> void:
	if _name_tag == "" and _team == TeamStyle.NONE:
		return
	var font: Font = _get_tag_font()
	var total: float = tag_extent()
	var left: float = -total * 0.5
	if _team != TeamStyle.NONE:
		_draw_team_badge(font, left)
		left += BADGE_SIZE + BADGE_GAP
	if _name_tag == "":
		return
	var at := Vector2(left, TAG_BASELINE_Y)
	var fs: int = _name_font_size()
	_body.draw_string_outline(font, at, _name_tag, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, TAG_OUTLINE, Color(NeonPalette.BG_DEEP, 0.9))
	_body.draw_string(font, at, _name_tag, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, c.lightened(0.2))


func _draw_team_badge(font: Font, x: float) -> void:
	var r := Rect2(x, TAG_BASELINE_Y - BADGE_SIZE + 1.5, BADGE_SIZE, BADGE_SIZE)
	var tc: Color = TeamStyle.color(_team)
	if _dead:
		tc = tc.darkened(0.45)
	_body.draw_rect(r.grow(0.8), Color(NeonPalette.BG_DEEP, 0.9))
	_body.draw_rect(r, tc)
	var letter: String = TeamStyle.letter(_team)
	var fs: int = 8
	var lw: float = font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	_body.draw_string(font, Vector2(r.position.x + (BADGE_SIZE - lw) * 0.5, r.end.y - 1.6), letter,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, TeamStyle.INK)


func get_color_index() -> int:
	return _color_index


func get_emblem_index() -> int:
	return _emblem_index


## Puts a skin on this tank (null = the standard look). `baked` lets many views share one texture;
## without it the skin is baked here, once, at `skin_ppu`.
func set_skin(skin: SkinData, baked: Texture2D = null) -> void:
	_skin = skin
	_skin_tex = null
	if skin != null:
		_skin_tex = baked if baked != null else SkinBaker.bake(skin, skin_ppu)
	_redraw_all()


func get_skin() -> SkinData:
	return _skin


func has_skin() -> bool:
	return _skin != null


## The baked hull texture of the current skin (null without one).
func get_skin_texture() -> Texture2D:
	return _skin_tex


## The colour of the identity outline: always the player colour (dimmed when dead), whatever the skin.
func outline_color() -> Color:
	return _col()


## Preview / thumbnail mode (see `_compact`).
func set_compact(on: bool) -> void:
	_compact = on
	_redraw_all()


func is_compact() -> bool:
	return _compact


## The skin's glow layer breathes between 0 and 1 (the studio preview pulses it).
func set_skin_glow_pulse(k: float) -> void:
	if _skin_glow != null:
		_skin_glow.modulate.a = clampf(k, 0.0, 1.0)


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
			or _hit_t > 0.0 or _love_animating()
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
	if _love_animating():
		_love_pulse = maxf(0.0, _love_pulse - delta / LOVE_PULSE_SECONDS)
		_love_shown = move_toward(_love_shown, _love_target(), LOVE_FILL_SPEED * delta)
		_redraw_love()
	if not (_shield_hp > 0 or _break_t >= 0.0 or _repulsor or _chute_left > 0.0 or _hit_t > 0.0 or _love_animating()):
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


# --- love meter (Love Edition) --------------------------------------------------------------

## Love mode swaps the health bar for the love meter.
func set_love_mode(on: bool) -> void:
	_love_mode = on
	_redraw_all()
	_redraw_love()


func is_love_mode() -> bool:
	return _love_mode


## The real love value 0..100. `animate` lets the heart fill up smoothly (a `love` event); without
## it (a rebuild, reduced motion) the fill snaps.
func set_love(value: int, animate: bool = false) -> void:
	_love = clampi(value, 0, SimConstants.LOVE_MAX)
	if not animate or ShowSettings.reduce_motion:
		_love_shown = _love_target()
	_redraw_love()
	_update_processing()


func get_love() -> int:
	return _love


## The fill the meter currently shows, 0..1 (it follows get_love() / 100 over about half a second).
func get_love_shown() -> float:
	return _love_shown


## A gentle pulse of the heart (a `love` event). Skipped with reduced motion.
func pulse_love() -> void:
	if ShowSettings.reduce_motion:
		return
	_love_pulse = 1.0
	_update_processing()


func is_love_pulsing() -> bool:
	return _love_pulse > 0.0


func _love_target() -> float:
	return float(_love) / float(SimConstants.LOVE_MAX)


func _love_animating() -> bool:
	return _love_mode and (_love_pulse > 0.0 or not is_equal_approx(_love_shown, _love_target()))


func _redraw_love() -> void:
	if _love_layer != null:
		_love_layer.queue_redraw()
		_love_glow.queue_redraw()


func _love_scale() -> float:
	return 1.0 + 0.3 * sin(clampf(_love_pulse, 0.0, 1.0) * PI)


func _draw_love() -> void:
	if not _love_mode or _dead or _compact:
		return
	var k: float = _love_shown
	HeartShape.draw(_love_layer, LOVE_HEART_POS, LOVE_HEART_SIZE * _love_scale(), LOVE_PINK, k, false)
	var bx: float = -BAR_W * 0.5
	_love_layer.draw_rect(Rect2(bx - 1.0, -37.5 - 1.0, BAR_W + 2.0, BAR_H + 2.0), Color(NeonPalette.BG_DEEP, 0.85))
	if k > 0.0:
		_love_layer.draw_rect(Rect2(bx, -37.5, BAR_W * k, BAR_H), LOVE_PINK)
	# Half-way tick: the bar reads without colour.
	_love_layer.draw_line(Vector2(0.0, -37.5), Vector2(0.0, -37.5 + BAR_H), Color(NeonPalette.BG_DEEP, 0.9), 0.8)


func _draw_love_glow() -> void:
	if not _love_mode or _dead or _compact:
		return
	var a: float = 0.16 + 0.12 * _love_shown + 0.3 * sin(clampf(_love_pulse, 0.0, 1.0) * PI) * (0.5 if ShowSettings.reduce_flashing else 1.0)
	var r: float = LOVE_HEART_SIZE * 2.1 * _love_scale()
	_love_glow.draw_texture_rect(FxTextures.heart(), Rect2(LOVE_HEART_POS - Vector2.ONE * r, Vector2.ONE * r * 2.0),
			false, Color(LOVE_PINK, a))


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
	_skin_glow.queue_redraw()
	_body.queue_redraw()
	_turret.queue_redraw()
	_turret_glow.queue_redraw()
	_redraw_love()


func _col() -> Color:
	var c: Color = NeonPalette.tank_color(_color_index)
	if _dead:
		c = c.darkened(0.65).lerp(Color(0.35, 0.35, 0.4), 0.4)
	return c


## The hull outline (open): the standard trapezoid or the skin's body style.
func _hull_open() -> PackedVector2Array:
	return SkinShapes.hull(_skin.body_style if _skin != null else 0)


func _hull() -> PackedVector2Array:
	return SkinShapes.closed(_hull_open())


func _draw_glow() -> void:
	var c: Color = _col()
	var h: PackedVector2Array = _hull()
	_glow.draw_polyline(h, Color(c, 0.18), 6.0, true)
	_glow.draw_polyline(h, Color(c, 0.35), 3.2, true)
	if not _dead:
		_glow.draw_circle(Vector2(0, -TANK_H), 5.0, Color(c, 0.22))


## The skin's own glow: a halo in its accent colour, scaled by the glow setting. It sits under the
## player-colour halo and the outline, so it can never hide them.
func _draw_skin_glow() -> void:
	if _skin == null or _dead or _skin.glow <= 0:
		return
	var g: float = float(_skin.glow) / float(SkinData.GLOW_MAX)
	var h: PackedVector2Array = _hull()
	_skin_glow.draw_polyline(h, Color(_skin.accent, 0.16 * g), 10.0, true)
	_skin_glow.draw_polyline(h, Color(_skin.accent, 0.34 * g), 5.0, true)
	_skin_glow.draw_colored_polygon(_hull_open(), Color(_skin.accent, 0.12 * g))
	var tb: Rect2 = SkinShapes.turret_bounds(_skin.turret_style)
	_skin_glow.draw_circle(Vector2(0, -TANK_H) + Vector2(tb.get_center().x * 0.5, 0.0), 6.5 * (0.5 + 0.5 * g), Color(_skin.accent, 0.2 * g))


func _draw_body() -> void:
	var c: Color = _col()
	var h: PackedVector2Array = _hull()
	var open: PackedVector2Array = _hull_open()
	if _skin_tex != null:
		var tint: Color = Color(0.4, 0.4, 0.45) if _dead else Color.WHITE
		_body.draw_colored_polygon(open, tint, SkinShapes.hull_uvs(open), _skin_tex)
		# A dark rim under the identity outline keeps it readable on any skin colour.
		_body.draw_polyline(h, Color(NeonPalette.BG_DEEP, 0.9), 3.6, true)
	else:
		_body.draw_colored_polygon(open, Color(NeonPalette.BG_DEEP, 0.92).lerp(c, 0.14))
	_body.draw_polyline(h, c, 1.4, true)
	# Tread line + hub.
	_body.draw_line(Vector2(-10, -1.4), Vector2(10, -1.4), Color(c, 0.6), 1.0, true)
	if _dead:
		_body.draw_line(Vector2(-6, -8), Vector2(-2, -4), c, 1.2, true)
		_body.draw_line(Vector2(3, -8), Vector2(7, -3), c, 1.2, true)
		return
	_body.draw_circle(Vector2(0, -TANK_H + 1.0), 3.2, c)
	# Floating marker: emblem (second cue besides colour) above a health bar.
	if _compact:
		NeonPalette.draw_emblem(_body, NeonPalette.tank_emblem(_emblem_index), Vector2(0, COMPACT_MARKER_Y), 5.5, c)
		return
	_draw_name_tag(c)
	if _love_mode:
		NeonPalette.draw_emblem(_body, NeonPalette.tank_emblem(_emblem_index), LOVE_EMBLEM_POS, 5.0, c)
		return  # the love meter (Love layer) takes the health bar's place
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
	if _skin != null:
		_draw_skin_turret(c)
		return
	_turret.draw_rect(Rect2(0, -1.6, BARREL_LEN + 2.0, 3.2), Color(NeonPalette.BG_DEEP, 0.95))
	_turret.draw_rect(Rect2(0, -1.6, BARREL_LEN + 2.0, 3.2), c, false, 1.2)
	_turret.draw_line(Vector2(BARREL_LEN + 2.0, -1.6), Vector2(BARREL_LEN + 2.0, 1.6), NeonPalette.HOT, 1.6)


func _draw_skin_turret(c: Color) -> void:
	var fill: Color = Color(_skin.base.lerp(NeonPalette.BG_DEEP, 0.35), 0.96)
	for poly: PackedVector2Array in SkinShapes.turret_polys(_skin.turret_style):
		_turret.draw_colored_polygon(poly, fill)
		_turret.draw_polyline(SkinShapes.closed(poly), c, 1.2, true)
	_turret.draw_line(Vector2(3.0, 0.0), Vector2(BARREL_LEN - 1.0, 0.0), Color(_skin.accent, 0.85), 0.8, true)
	var half: float = SkinShapes.turret_tip_half(_skin.turret_style)
	_turret.draw_line(Vector2(SkinShapes.BARREL_TIP, -half), Vector2(SkinShapes.BARREL_TIP, half), NeonPalette.HOT, 1.6)


func _draw_turret_glow() -> void:
	var c: Color = _col()
	if _skin != null:
		_turret_glow.draw_rect(SkinShapes.turret_bounds(_skin.turret_style).grow(1.6), Color(c, 0.22))
		return
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
	var hull: PackedVector2Array = _hull_open()
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
