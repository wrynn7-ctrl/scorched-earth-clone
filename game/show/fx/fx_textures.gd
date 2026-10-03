class_name FxTextures
extends RefCounted
## Lazily created, shared procedural textures/materials for glow effects.
## Created once, reused by every trail, explosion and tank (keeps draw calls batched).

static var _glow: ImageTexture = null
static var _ring: ImageTexture = null
static var _additive: CanvasItemMaterial = null
static var _heart: ImageTexture = null
static var _sparkle: ImageTexture = null


## Soft round white glow, 64x64, alpha falls off quadratically.
static func glow() -> Texture2D:
	if _glow == null:
		var n: int = 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y: int in range(n):
			for x: int in range(n):
				var d: float = Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
				var a: float = pow(clampf(1.0 - d, 0.0, 1.0), 2.2)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_glow = ImageTexture.create_from_image(img)
	return _glow


## Thin soft ring, 128x128, peak at 85% of the radius (used for shockwaves).
static func ring() -> Texture2D:
	if _ring == null:
		var n: int = 128
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y: int in range(n):
			for x: int in range(n):
				var d: float = Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
				var a: float = exp(-pow((d - 0.85) / 0.07, 2.0)) * (1.0 if d <= 1.0 else 0.0)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_ring = ImageTexture.create_from_image(img)
	return _ring


## A white heart with a soft halo, 96x96 (tint it with modulate; drawn with the additive material).
static func heart() -> Texture2D:
	if _heart == null:
		var n: int = 96
		var core: PackedFloat32Array = HeartShape.coverage(n, float(n) * 0.3)
		var halo: PackedFloat32Array = HeartShape.blur(core, n, 6, 2)
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y: int in range(n):
			for x: int in range(n):
				var i: int = y * n + x
				img.set_pixel(x, y, Color(1, 1, 1, clampf(maxf(core[i], halo[i] * 1.6), 0.0, 1.0)))
		_heart = ImageTexture.create_from_image(img)
	return _heart


## A four-point twinkle star, 64x64 (sparkles, the secret unlock burst).
static func sparkle() -> Texture2D:
	if _sparkle == null:
		var n: int = 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var half: float = float(n) * 0.5
		for y: int in range(n):
			for x: int in range(n):
				var u := Vector2((float(x) + 0.5 - half) / half, (float(y) + 0.5 - half) / half)
				var ray_h: float = exp(-absf(u.y) * 22.0) * (1.0 - absf(u.x))
				var ray_v: float = exp(-absf(u.x) * 22.0) * (1.0 - absf(u.y))
				var glow: float = exp(-u.length() * 7.0) * 0.8
				var edge: float = 1.0 - smoothstep(0.85, 1.0, u.length())
				img.set_pixel(x, y, Color(1, 1, 1, clampf(maxf(maxf(ray_h, ray_v), glow), 0.0, 1.0) * edge))
		_sparkle = ImageTexture.create_from_image(img)
	return _sparkle


static func additive() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive
