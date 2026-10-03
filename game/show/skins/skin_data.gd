class_name SkinData
extends RefCounted
## One tank skin (docs/ARCHITECTURE.md section 35). Presentation only and private to this device:
## the simulation never sees it and it is never uploaded or shown to another device.
##
## JSON on disk (`user://skins/<id>.json`):
## {version, name, body_style 0..3, turret_style 0..3, base, accent, pattern 0..5, pattern_color,
##  decal 0..9, glow 0..100, image: "<id>.png" | null}
## Colours are "#rrggbb". `from_dict` clamps or ignores every bad field, so a damaged or
## hand-edited file can never produce an impossible skin.
##
## A skin has no field for the outline, the emblem or the name tag: the player's identity colour is
## drawn on top by TankView from NeonPalette, so no skin can remove or recolour it.

const VERSION: int = 1
const BODY_STYLES: int = 4
const TURRET_STYLES: int = 4
const PATTERNS: int = 6
const DECALS: int = 10
const GLOW_MAX: int = 100
const NAME_MAX: int = 20
const IMAGE_W: int = 128
const IMAGE_H: int = 64

enum Pattern { NONE, STRIPES, CIRCUIT, CAMO, GRID, CHEVRONS }

const DEFAULT_BASE: Color = Color(0.13, 0.08, 0.32)
const DEFAULT_ACCENT: Color = Color(0.0, 0.93, 1.0)
const DEFAULT_PATTERN_COLOR: Color = Color(1.0, 0.18, 0.62)

var id: String = ""
var name: String = ""
var body_style: int = 0
var turret_style: int = 0
var base: Color = DEFAULT_BASE
var accent: Color = DEFAULT_ACCENT
var pattern: int = Pattern.NONE
var pattern_color: Color = DEFAULT_PATTERN_COLOR
var decal: int = 1
var glow: int = 50
## "<id>.png" when the skin has a picture, else "". The pixels live in `image` (128x64 RGBA8).
var image_file: String = ""
var image: Image = null


static func make_default(skin_id: String, skin_name: String = "") -> SkinData:
	var s := SkinData.new()
	s.id = skin_id
	s.name = skin_name
	return s


func has_image() -> bool:
	return image != null


## Copy with a new id. The picture is shared by value (the copy gets its own Image).
func duplicate_skin(new_id: String, new_name: String) -> SkinData:
	var s := SkinData.new()
	s.id = new_id
	s.name = new_name
	s.body_style = body_style
	s.turret_style = turret_style
	s.base = base
	s.accent = accent
	s.pattern = pattern
	s.pattern_color = pattern_color
	s.decal = decal
	s.glow = glow
	if image != null:
		s.image = image.duplicate() as Image
		s.image_file = new_id + ".png"
	return s


func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"name": name,
		"body_style": body_style,
		"turret_style": turret_style,
		"base": base.to_html(false),
		"accent": accent.to_html(false),
		"pattern": pattern,
		"pattern_color": pattern_color.to_html(false),
		"decal": decal,
		"glow": glow,
		"image": (id + ".png") if image != null else null,
	}


## A short text that changes whenever the look changes (the studio compares it for "unsaved").
func signature() -> String:
	var img: String = "-"
	if image != null:
		img = str(hash(image.get_data()))
	return JSON.stringify(to_dict()) + img


## Builds a skin from parsed JSON. Never fails: unknown or invalid fields fall back to defaults.
## `skin_id` comes from the file name; the `image` field only counts when it is "<id>.png".
static func from_dict(d: Dictionary, skin_id: String) -> SkinData:
	var s := SkinData.new()
	s.id = skin_id
	s.name = clean_name(d.get("name", ""))
	s.body_style = _int_in(d.get("body_style", 0), 0, BODY_STYLES - 1, 0)
	s.turret_style = _int_in(d.get("turret_style", 0), 0, TURRET_STYLES - 1, 0)
	s.base = _color(d.get("base", ""), DEFAULT_BASE)
	s.accent = _color(d.get("accent", ""), DEFAULT_ACCENT)
	s.pattern = _int_in(d.get("pattern", 0), 0, PATTERNS - 1, 0)
	s.pattern_color = _color(d.get("pattern_color", ""), DEFAULT_PATTERN_COLOR)
	s.decal = _int_in(d.get("decal", 1), 0, DECALS - 1, 1)
	s.glow = _int_in(d.get("glow", 50), 0, GLOW_MAX, 50)
	var img: Variant = d.get("image", null)
	if typeof(img) == TYPE_STRING and (img as String) == skin_id + ".png":
		s.image_file = img as String
	return s


## Trimmed to NAME_MAX characters, control characters dropped. Non-strings give "".
static func clean_name(v: Variant) -> String:
	if typeof(v) != TYPE_STRING:
		return ""
	var out: String = ""
	for ch: String in (v as String):
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			out += ch
	return out.strip_edges().left(NAME_MAX)


static func _int_in(v: Variant, lo: int, hi: int, fallback: int) -> int:
	if typeof(v) == TYPE_INT:
		return clampi(v as int, lo, hi)
	if typeof(v) == TYPE_FLOAT:
		var f: float = v as float
		if is_nan(f):
			return fallback
		# Clamp as a float first: roundi() of a value beyond int64 overflows to the wrong end (and
		# differently per CPU). +-inf lands on the matching end.
		return roundi(clampf(f, float(lo), float(hi)))
	return fallback


static func _color(v: Variant, fallback: Color) -> Color:
	if typeof(v) == TYPE_STRING and Color.html_is_valid(v as String):
		var c := Color.html(v as String)
		return Color(c.r, c.g, c.b, 1.0)
	return fallback
