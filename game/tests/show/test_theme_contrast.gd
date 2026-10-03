extends GutTest
## Every theme keeps all 8 tank colours readable. Luminance contrast (WCAG ratio):
##  A. the tank OUTLINE (its identity colour) against every body colour of the backdrop: sky
##     gradient (above the horizon glow band), ground plane, aurora-lit sky and each terrain
##     stratum at surface brightness. Must be >= 3:1.
##  B. the tank's dark HULL FILL against the bright glow accents it stands on (rim colours and
##     the horizon band), so the silhouette reads where outline-vs-glow cannot: >= 3:1.
## Thin accents (stars, windows, grid lines) are excluded. Numbers are printed per theme.

const MIN_RATIO: float = 3.0


## The hull fill TankView paints for a tank colour (see tank_view.gd _draw_body).
static func _hull_fill(c: Color) -> Color:
	return Color(NeonPalette.BG_DEEP, 1.0).lerp(c, 0.14)


func _worst_outline(def: Dictionary) -> Dictionary:
	var worst: float = INF
	var who: int = -1
	for i: int in range(NeonPalette.TANK_COLORS.size()):
		for bg: Color in ThemeDefs.backdrop_samples(def):
			var r: float = ThemeDefs.contrast(NeonPalette.TANK_COLORS[i], bg)
			if r < worst:
				worst = r
				who = i
	return {"ratio": worst, "tank": who}


func _worst_hull(def: Dictionary) -> Dictionary:
	var glows: Array[Color] = [def["edge_a"] as Color, def["edge_b"] as Color, def["sky_low"] as Color]
	var worst: float = INF
	var who: int = -1
	for i: int in range(NeonPalette.TANK_COLORS.size()):
		var fill: Color = _hull_fill(NeonPalette.TANK_COLORS[i])
		for g: Color in glows:
			var r: float = ThemeDefs.contrast(fill, g)
			if r < worst:
				worst = r
				who = i
	return {"ratio": worst, "tank": who}


func test_outline_contrast_per_theme() -> void:
	for id: String in ThemeDefs.ids():
		var res: Dictionary = _worst_outline(ThemeDefs.get_def(id))
		print("contrast A (outline vs backdrop) %-16s min %.2f:1 (tank %d)" % [id, res["ratio"], res["tank"]])
		assert_gte(res["ratio"] as float, MIN_RATIO, "%s: tank %d outline vs backdrop" % [id, res["tank"]])


func test_hull_fill_contrast_against_glow_per_theme() -> void:
	for id: String in ThemeDefs.ids():
		var res: Dictionary = _worst_hull(ThemeDefs.get_def(id))
		print("contrast B (hull fill vs glow)    %-16s min %.2f:1 (tank %d)" % [id, res["ratio"], res["tank"]])
		assert_gte(res["ratio"] as float, MIN_RATIO, "%s: tank %d hull vs glow" % [id, res["tank"]])


func test_contrast_math_is_wcag() -> void:
	assert_almost_eq(ThemeDefs.contrast(Color.WHITE, Color.BLACK), 21.0, 0.001)
	assert_almost_eq(ThemeDefs.contrast(Color.BLACK, Color.BLACK), 1.0, 0.001)
	assert_almost_eq(ThemeDefs.luminance(Color.WHITE), 1.0, 0.001)


func test_themes_never_change_tank_colours() -> void:
	# Identity colours come from NeonPalette only: a theme definition has no tank colour key.
	for id: String in ThemeDefs.ids():
		for key: String in ThemeDefs.get_def(id).keys():
			assert_false(key.contains("tank"), "%s defines %s" % [id, key])
