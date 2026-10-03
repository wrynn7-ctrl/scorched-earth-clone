class_name ThemeSwatch
extends RefCounted
## Tiny preview pictures of the terrain themes for the setup screen: sky gradient, sun or
## moon, a hill with its glowing rim. Drawn once per theme into an Image (a few thousand
## pixels) and cached; Buttons show them as their icon. "Random" is five slanted stripes,
## one per theme. The theme's name next to it is always the primary cue.

const W: int = 72
const H: int = 44

static var _cache: Dictionary = {}


static func texture(id: String) -> Texture2D:
	if not _cache.has(id):
		_cache[id] = ImageTexture.create_from_image(image(id))
	return _cache[id] as Texture2D


static func image(id: String) -> Image:
	var img: Image = Image.create(W, H, false, Image.FORMAT_RGBA8)
	if id == ThemeDefs.RANDOM:
		_paint_random(img)
	else:
		_paint_theme(img, ThemeDefs.get_def(id))
	_frame(img)
	return img


static func _paint_theme(img: Image, def: Dictionary) -> void:
	var horizon: float = float(H) * 0.58
	var top: Color = def["sky_top"]
	var mid: Color = def["sky_mid"]
	var low: Color = def["sky_low"]
	var strata: Array[Color] = def["strata"]
	var sun_a: Color = def["sun_a"]
	var sun_b: Color = def["sun_b"]
	var sun_c := Vector2(float(W) * 0.68, float(H) * 0.34)
	var sun_r: float = float(H) * 0.19
	var edge: Color = def["edge_a"]
	for x: int in range(W):
		var fx: float = float(x)
		var surface: float = float(H) * (0.62 + 0.09 * sin(fx * 0.16 + 1.0) + 0.045 * sin(fx * 0.41))
		for y: int in range(H):
			var fy: float = float(y)
			var c: Color
			if fy < horizon:
				c = ThemeDefs.sky_at(top, mid, low, fy / horizon)
			else:
				c = (def["ground_far"] as Color).lerp(def["ground_near"] as Color, (fy - horizon) / (float(H) - horizon))
			var d: float = Vector2(fx + 0.5, fy + 0.5).distance_to(sun_c)
			if d < sun_r:
				c = sun_a.lerp(sun_b, clampf((fy - (sun_c.y - sun_r)) / (sun_r * 2.0), 0.0, 1.0))
			if fy >= surface:
				var band: int = clampi(int((fy - surface) / 4.0), 0, strata.size() - 1)
				c = strata[band].lightened(0.25)
			var rim: float = 1.0 - clampf(absf(fy - surface) / 1.6, 0.0, 1.0)
			if rim > 0.0:
				c = c.lerp(edge, rim)
			img.set_pixel(x, y, c)


static func _paint_random(img: Image) -> void:
	var ids: PackedStringArray = ThemeDefs.ids()
	for x: int in range(W):
		for y: int in range(H):
			var k: float = (float(x) + float(y) * 0.5) / float(W + H / 2)
			var def: Dictionary = ThemeDefs.get_def(ids[mini(ids.size() - 1, int(k * float(ids.size())))])
			var t: float = float(y) / float(H)
			var c: Color = (def["sky_top"] as Color).lerp(def["sky_low"] as Color, t * t) if t < 0.75 else (def["edge_a"] as Color)
			img.set_pixel(x, y, c)


## A 1 px lighter border so the swatch reads on any button colour.
static func _frame(img: Image) -> void:
	var line: Color = Color(NeonPalette.TEXT_DIM, 1.0)
	for x: int in range(W):
		img.set_pixel(x, 0, line)
		img.set_pixel(x, H - 1, line)
	for y: int in range(H):
		img.set_pixel(0, y, line)
		img.set_pixel(W - 1, y, line)
