extends GutTest
## Colour-vision-deficiency separation of the 8 tank colours (Vienot 1999 matrices for
## protan/deutan, a Vienot-style projection for tritan, in linear RGB; CIE76 dE in Lab).

const MIN_DE_CVD: float = 20.0
const MIN_DE_NORMAL: float = 35.0
const MIN_L_ON_DARK: float = 55.0

const MATS: Dictionary = {
	"protanopia": [[0.11238, 0.88762, 0.0], [0.11238, 0.88762, 0.0], [0.00401, -0.00401, 1.0]],
	"deuteranopia": [[0.29275, 0.70725, 0.0], [0.29275, 0.70725, 0.0], [-0.02234, 0.02234, 1.0]],
	"tritanopia": [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [-0.395913, 0.801109, 0.0]],
	"normal": [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]],
}


static func _lin(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


static func _simulate(c: Color, mat: Array) -> Vector3:
	var rgb := Vector3(_lin(c.r), _lin(c.g), _lin(c.b))
	var out := Vector3.ZERO
	for i: int in range(3):
		var row: Array = mat[i]
		out[i] = clampf(float(row[0]) * rgb.x + float(row[1]) * rgb.y + float(row[2]) * rgb.z, 0.0, 1.0)
	return out


static func _lab(lin: Vector3) -> Vector3:
	var x: float = (0.4124 * lin.x + 0.3576 * lin.y + 0.1805 * lin.z) / 0.95047
	var y: float = 0.2126 * lin.x + 0.7152 * lin.y + 0.0722 * lin.z
	var z: float = (0.0193 * lin.x + 0.1192 * lin.y + 0.9505 * lin.z) / 1.08883
	var fx: float = _f(x)
	var fy: float = _f(y)
	var fz: float = _f(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


static func _f(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0


## Smallest pairwise dE among the palette under one vision model.
func _min_pair_de(mat: Array) -> Dictionary:
	var best: float = INF
	var pair := Vector2i.ZERO
	var n: int = NeonPalette.TANK_COLORS.size()
	for i: int in range(n):
		for j: int in range(i + 1, n):
			var a: Vector3 = _lab(_simulate(NeonPalette.TANK_COLORS[i], mat))
			var b: Vector3 = _lab(_simulate(NeonPalette.TANK_COLORS[j], mat))
			var d: float = a.distance_to(b)
			if d < best:
				best = d
				pair = Vector2i(i, j)
	return {"de": best, "pair": pair}


func test_there_are_eight_tank_colours() -> void:
	assert_eq(NeonPalette.TANK_COLORS.size(), 8)
	assert_eq(NeonPalette.TANK_COLOR_NAME_KEYS.size(), 8)


func test_pairwise_separation_under_color_vision_deficiency() -> void:
	for model: String in MATS.keys():
		var r: Dictionary = _min_pair_de(MATS[model])
		var need: float = MIN_DE_NORMAL if model == "normal" else MIN_DE_CVD
		gut.p("min pairwise dE76 %-13s = %.1f (pair %s, need >= %.0f)" % [model, float(r["de"]), str(r["pair"]), need])
		assert_gte(float(r["de"]), need, "palette too close for %s" % model)


func test_colours_are_bright_against_dark_background() -> void:
	var bg: Vector3 = _lab(_simulate(NeonPalette.BG_MID, MATS["normal"]))
	for i: int in range(NeonPalette.TANK_COLORS.size()):
		var lab: Vector3 = _lab(_simulate(NeonPalette.TANK_COLORS[i], MATS["normal"]))
		assert_gte(lab.x, MIN_L_ON_DARK, "colour %d lightness" % i)
		assert_gte(lab.distance_to(bg), 45.0, "colour %d vs background" % i)


func test_tank_color_wraps() -> void:
	assert_eq(NeonPalette.tank_color(8), NeonPalette.tank_color(0))
	assert_eq(NeonPalette.tank_emblem(9), 1)


func test_eight_distinct_emblems() -> void:
	var seen: Dictionary = {}
	for i: int in range(NeonPalette.EMBLEM_COUNT):
		var poly: PackedVector2Array = NeonPalette.emblem_polygon(i, 10.0)
		assert_gte(poly.size(), 3, "emblem %d has a polygon" % i)
		for p: Vector2 in poly:
			assert_lte(p.length(), 10.0 * 1.35, "emblem %d fits its radius" % i)
		# Vertex count + area as a cheap shape signature.
		var area: float = 0.0
		for k: int in range(poly.size()):
			var a: Vector2 = poly[k]
			var b: Vector2 = poly[(k + 1) % poly.size()]
			area += a.x * b.y - b.x * a.y
		var sig: String = "%d:%d" % [poly.size(), roundi(absf(area) * 0.5)]
		assert_false(seen.has(sig), "emblem %d duplicates the shape signature %s" % [i, sig])
		seen[sig] = i
	assert_eq(seen.size(), 8)
