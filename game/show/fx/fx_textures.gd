class_name FxTextures
extends RefCounted
## Lazily created, shared procedural textures/materials for glow effects.
## Created once, reused by every trail, explosion and tank (keeps draw calls batched).

static var _glow: ImageTexture = null
static var _ring: ImageTexture = null
static var _additive: CanvasItemMaterial = null


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


static func additive() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive
