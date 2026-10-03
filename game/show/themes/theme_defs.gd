class_name ThemeDefs
extends RefCounted
## Terrain themes (ARCHITECTURE section 34): visual only. A theme is a plain Dictionary of colours and
## style switches that NeonSky and TerrainView push into their shaders as uniforms; there is
## no per-theme shader. The theme never touches the simulation, so fingerprints and saves
## stay identical whichever look is chosen. It is stored in the autosave meta, not in core.
##
## Tank identity colours are never part of a theme. To keep every one of the 8 tank colours
## readable, the *body* colours of a theme (sky, ground plane, terrain strata) are dark;
## brightness lives in thin glow accents (rim, horizon band, grid lines, stars). The tests in
## tests/show/test_theme_contrast.gd hold that line (3:1 luminance for the tank outline).
##
## "Random" is not a theme but a choice: resolve() turns it into a concrete theme per round,
## deterministically from the match seed and the round index.

const SUNSET_GRID: String = "sunset_grid"
const ICE_CIRCUIT: String = "ice_circuit"
const MAGMA_CITY: String = "magma_city"
const TOXIC_MARSH: String = "toxic_marsh"
const MIDNIGHT_CHROME: String = "midnight_chrome"
const RANDOM: String = "random"
const DEFAULT_ID: String = SUNSET_GRID

## Display / definition order (setup picker, tests).
const IDS: PackedStringArray = [SUNSET_GRID, ICE_CIRCUIT, MAGMA_CITY, TOXIC_MARSH, MIDNIGHT_CHROME]

const TIER_FREE: String = "free"
const TIER_FULL: String = "full"

## Sun / moon styles (sky.gdshader `sun_style`).
const SUN_SYNTH: int = 0
const SUN_MOON: int = 1
const SUN_CHROME: int = 2

## Ambient particle styles (ThemeAmbient).
const AMBIENT_NONE: String = "none"
const AMBIENT_EMBERS: String = "embers"
const AMBIENT_SPORES: String = "spores"

const STRATA_COUNT: int = 15
## Extra brightness the aurora may add to the sky (also the shader's `aurora_peak`).
const AURORA_PEAK: float = 0.13
## The part of the sky gradient (0 = top, 1 = horizon) behind the tanks that the contrast
## tests cover; above it the horizon glow band is a bright accent, like the terrain rim.
const GLOW_BAND_START: float = 0.72
## terrain.gdshader dims dirt by mix(1.0, 0.42, y / world height). Tanks never stand higher
## than 30% of the world height, so strata are tested at that (brightest) dimming.
const STRATA_DIM_AT_TANK: float = 0.826
## Stream tag for the "Random" pick (show-only, so any value is safe).
const TAG_THEME: int = 7700

## Every key a definition must have (tests/show/test_theme_defs.gd checks it).
const REQUIRED_KEYS: PackedStringArray = [
	"id", "name_key", "tier",
	"sky_top", "sky_mid", "sky_low", "ground_far", "ground_near",
	"sun_style", "sun_a", "sun_b", "sun_pos", "sun_radius", "halo",
	"grid_a", "grid_b", "stars", "star_tint",
	"aurora", "aurora_a", "aurora_b", "city", "city_glow",
	"strata", "edge_a", "edge_b", "glow",
	"tint_core", "tint_ring", "tint_mid", "tint_end",
	"ambient", "ambient_color",
]

## Test hook: -1 = ask Entitlement (when that class exists), 0 = locked, 1 = full.
static var full_override: int = -1

static var _defs: Dictionary = {}
static var _entitlement: Script = null
static var _entitlement_checked: bool = false


static func ids() -> PackedStringArray:
	return IDS


static func has_theme(id: String) -> bool:
	return IDS.has(id)


## `id` normalised: a known theme id or RANDOM, otherwise the default.
static func sanitize(id: Variant) -> String:
	if typeof(id) != TYPE_STRING:
		return DEFAULT_ID
	var s: String = id
	return s if (s == RANDOM or IDS.has(s)) else DEFAULT_ID


static func get_def(id: String) -> Dictionary:
	if _defs.is_empty():
		_build()
	return (_defs[id] if _defs.has(id) else _defs[DEFAULT_ID]) as Dictionary


static func is_free(id: String) -> bool:
	return get_def(id)["tier"] == TIER_FREE


static func name_key(id: String) -> String:
	return "THEME_RANDOM" if id == RANDOM else (get_def(id)["name_key"] as String)


## True when `id` (a theme or RANDOM) can be chosen without the full game.
static func is_locked(id: String, full: bool) -> bool:
	return not full and id != RANDOM and not is_free(id)


## Does this device own the full game? Uses Entitlement.is_full() when that class exists
## (a later task adds it); until then every theme is available.
static func is_full_game() -> bool:
	if full_override >= 0:
		return full_override == 1
	if not _entitlement_checked:
		_entitlement_checked = true
		for entry: Dictionary in ProjectSettings.get_global_class_list():
			if entry.get("class", "") == "Entitlement":
				_entitlement = load(entry["path"] as String) as Script
	if _entitlement != null and _entitlement.has_method("is_full"):
		return _entitlement.call("is_full") as bool
	return true


## The concrete theme for a round. A fixed theme returns itself (falling back to the first
## free theme if it is locked); RANDOM picks from the usable themes by a stream derived only
## from the match seed and the round index, so every round can differ yet a restored match
## shows exactly the same looks.
static func resolve(choice: String, match_seed: int, round_index: int, full: bool = true) -> String:
	var pool: PackedStringArray = usable_ids(full)
	if choice != RANDOM:
		var fixed: String = sanitize(choice)
		return fixed if pool.has(fixed) else DEFAULT_ID
	var rng: Rng = Rng.derive(match_seed, TAG_THEME + maxi(0, round_index))
	return pool[rng.range_int(0, pool.size() - 1)]


## Themes selectable with or without the full game.
static func usable_ids(full: bool) -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in IDS:
		if full or is_free(id):
			out.append(id)
	return out


## Colours the backdrop can show behind or under a tank (everything except thin glow
## accents): sky gradient samples, the ground plane, an aurora-lit sky and every terrain
## stratum at its brightest (as dimmed at a tank's highest standing height). The contrast tests use these.
static func backdrop_samples(def: Dictionary) -> Array[Color]:
	var out: Array[Color] = []
	var top: Color = def["sky_top"]
	var mid: Color = def["sky_mid"]
	var low: Color = def["sky_low"]
	for i: int in range(9):
		var k: float = GLOW_BAND_START * float(i) / 8.0
		out.append(sky_at(top, mid, low, k))
	out.append(def["ground_far"] as Color)
	out.append(def["ground_near"] as Color)
	if (def["aurora"] as float) > 0.0:
		var lit: Color = mid
		var a: Color = def["aurora_a"]
		var b: Color = def["aurora_b"]
		for c: Color in [a, b]:
			out.append(Color(minf(1.0, lit.r + c.r * AURORA_PEAK), minf(1.0, lit.g + c.g * AURORA_PEAK),
					minf(1.0, lit.b + c.b * AURORA_PEAK)))
	for c: Color in (def["strata"] as Array[Color]):
		out.append(Color(c.r * STRATA_DIM_AT_TANK, c.g * STRATA_DIM_AT_TANK, c.b * STRATA_DIM_AT_TANK))
	return out


## The sky gradient exactly as sky.gdshader mixes it (k: 0 top .. 1 horizon).
static func sky_at(top: Color, mid: Color, low: Color, k: float) -> Color:
	var m: float = smoothstep(0.0, 0.75, k)
	var c: Color = top.lerp(mid, m)
	var g: float = smoothstep(0.55, 1.0, k)
	return c.lerp(low, g * g * 0.9)


## WCAG relative luminance (sRGB -> linear).
static func luminance(c: Color) -> float:
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)


## WCAG contrast ratio (1..21) between two colours.
static func contrast(a: Color, b: Color) -> float:
	var la: float = luminance(a)
	var lb: float = luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


# ======================================================================================
# Definitions
# ======================================================================================

static func _build() -> void:
	_defs = {
		SUNSET_GRID: _sunset_grid(),
		ICE_CIRCUIT: _ice_circuit(),
		MAGMA_CITY: _magma_city(),
		TOXIC_MARSH: _toxic_marsh(),
		MIDNIGHT_CHROME: _midnight_chrome(),
	}


static func _colors(rows: Array) -> Array[Color]:
	var out: Array[Color] = []
	for r: Variant in rows:
		var v: Array = r
		out.append(Color(v[0] as float, v[1] as float, v[2] as float))
	return out


## The original look (the shaders' old built-in constants).
static func _sunset_grid() -> Dictionary:
	return {
		"id": SUNSET_GRID, "name_key": "THEME_SUNSET_GRID", "tier": TIER_FREE,
		"sky_top": Color(0.027, 0.008, 0.10), "sky_mid": Color(0.18, 0.04, 0.34), "sky_low": Color(1.0, 0.22, 0.52),
		"ground_far": Color(0.035, 0.012, 0.10), "ground_near": Color(0.20, 0.04, 0.30),
		"sun_style": SUN_SYNTH, "sun_a": Color(1.0, 0.92, 0.35), "sun_b": Color(1.0, 0.2, 0.55),
		"sun_pos": Vector2(0.6, 0.40), "sun_radius": 0.14, "halo": Color(1.0, 0.3, 0.6),
		"grid_a": Color(1.0, 0.2, 0.7), "grid_b": Color(0.0, 0.9, 1.0),
		"stars": 0.22, "star_tint": Color(0.8, 0.9, 1.0),
		"aurora": 0.0, "aurora_a": Color(0.2, 1.0, 0.7), "aurora_b": Color(0.5, 0.5, 1.0),
		"city": 0.0, "city_glow": Color(1.0, 0.4, 0.2),
		"strata": _colors([
			[0.30, 0.12, 0.45], [0.24, 0.12, 0.50], [0.18, 0.14, 0.52], [0.13, 0.18, 0.52],
			[0.10, 0.24, 0.50], [0.074, 0.276, 0.442], [0.074, 0.313, 0.405], [0.092, 0.331, 0.35],
			[0.30, 0.16, 0.40], [0.36, 0.12, 0.34], [0.40, 0.10, 0.28], [0.28, 0.10, 0.26],
			[0.20, 0.10, 0.30], [0.14, 0.09, 0.28], [0.10, 0.08, 0.24],
		]),
		"edge_a": Color(0.0, 0.93, 1.0), "edge_b": Color(1.0, 0.18, 0.62), "glow": 1.0,
		"tint_core": Color(1.0, 0.95, 0.75), "tint_ring": Color(0.0, 0.929, 1.0),
		"tint_mid": Color(1.0, 0.45, 0.2), "tint_end": Color(1.0, 0.18, 0.62),
		"ambient": AMBIENT_NONE, "ambient_color": Color(1.0, 1.0, 1.0),
	}


## Cold: icy cyan and white, a pale moon, aurora streaks.
static func _ice_circuit() -> Dictionary:
	return {
		"id": ICE_CIRCUIT, "name_key": "THEME_ICE_CIRCUIT", "tier": TIER_FREE,
		"sky_top": Color(0.008, 0.025, 0.085), "sky_mid": Color(0.03, 0.12, 0.25), "sky_low": Color(0.55, 0.88, 1.0),
		"ground_far": Color(0.01, 0.03, 0.08), "ground_near": Color(0.04, 0.17, 0.26),
		"sun_style": SUN_MOON, "sun_a": Color(0.93, 0.98, 1.0), "sun_b": Color(0.7, 0.88, 1.0),
		"sun_pos": Vector2(0.74, 0.30), "sun_radius": 0.095, "halo": Color(0.45, 0.85, 1.0),
		"grid_a": Color(0.35, 0.9, 1.0), "grid_b": Color(0.92, 1.0, 1.0),
		"stars": 0.3, "star_tint": Color(0.85, 0.95, 1.0),
		"aurora": 1.0, "aurora_a": Color(0.2, 1.0, 0.75), "aurora_b": Color(0.5, 0.45, 1.0),
		"city": 0.0, "city_glow": Color(0.5, 0.9, 1.0),
		"strata": _colors([
			[0.10, 0.30, 0.38], [0.09, 0.27, 0.40], [0.12, 0.30, 0.40], [0.08, 0.24, 0.42],
			[0.11, 0.28, 0.38], [0.07, 0.22, 0.38], [0.10, 0.26, 0.36], [0.06, 0.20, 0.36],
			[0.09, 0.24, 0.34], [0.05, 0.18, 0.32], [0.08, 0.21, 0.32], [0.05, 0.16, 0.28],
			[0.06, 0.17, 0.27], [0.04, 0.13, 0.24], [0.04, 0.11, 0.21],
		]),
		"edge_a": Color(0.55, 1.0, 1.0), "edge_b": Color(0.92, 0.97, 1.0), "glow": 1.0,
		"tint_core": Color(0.95, 1.0, 1.0), "tint_ring": Color(0.55, 0.95, 1.0),
		"tint_mid": Color(0.3, 0.75, 1.0), "tint_end": Color(0.4, 0.4, 1.0),
		"ambient": AMBIENT_NONE, "ambient_color": Color(0.8, 0.95, 1.0),
	}


## Hot: deep red and orange strata, a glowing city silhouette on the horizon, rising embers.
static func _magma_city() -> Dictionary:
	return {
		"id": MAGMA_CITY, "name_key": "THEME_MAGMA_CITY", "tier": TIER_FULL,
		"sky_top": Color(0.045, 0.0, 0.02), "sky_mid": Color(0.22, 0.02, 0.04), "sky_low": Color(1.0, 0.38, 0.06),
		"ground_far": Color(0.06, 0.0, 0.01), "ground_near": Color(0.26, 0.035, 0.02),
		"sun_style": SUN_SYNTH, "sun_a": Color(1.0, 0.85, 0.3), "sun_b": Color(1.0, 0.12, 0.08),
		"sun_pos": Vector2(0.38, 0.42), "sun_radius": 0.16, "halo": Color(1.0, 0.4, 0.1),
		"grid_a": Color(1.0, 0.32, 0.0), "grid_b": Color(1.0, 0.8, 0.15),
		"stars": 0.1, "star_tint": Color(1.0, 0.8, 0.6),
		"aurora": 0.0, "aurora_a": Color(1.0, 0.5, 0.1), "aurora_b": Color(1.0, 0.2, 0.1),
		"city": 1.0, "city_glow": Color(1.0, 0.45, 0.1),
		"strata": _colors([
			[0.50, 0.15, 0.03], [0.46, 0.12, 0.03], [0.42, 0.10, 0.04], [0.38, 0.08, 0.04],
			[0.48, 0.14, 0.02], [0.44, 0.09, 0.03], [0.36, 0.07, 0.04], [0.32, 0.06, 0.04],
			[0.40, 0.11, 0.02], [0.34, 0.07, 0.03], [0.30, 0.05, 0.04], [0.26, 0.05, 0.04],
			[0.22, 0.04, 0.04], [0.18, 0.04, 0.04], [0.14, 0.03, 0.04],
		]),
		"edge_a": Color(1.0, 0.55, 0.1), "edge_b": Color(1.0, 0.2, 0.12), "glow": 1.1,
		"tint_core": Color(1.0, 0.95, 0.65), "tint_ring": Color(1.0, 0.55, 0.15),
		"tint_mid": Color(1.0, 0.32, 0.05), "tint_end": Color(0.85, 0.05, 0.0),
		"ambient": AMBIENT_EMBERS, "ambient_color": Color(1.0, 0.55, 0.15),
	}


## Acid green over purple, with slow drifting spores.
static func _toxic_marsh() -> Dictionary:
	return {
		"id": TOXIC_MARSH, "name_key": "THEME_TOXIC_MARSH", "tier": TIER_FULL,
		"sky_top": Color(0.04, 0.0, 0.09), "sky_mid": Color(0.13, 0.04, 0.20), "sky_low": Color(0.55, 1.0, 0.12),
		"ground_far": Color(0.02, 0.03, 0.03), "ground_near": Color(0.07, 0.19, 0.06),
		"sun_style": SUN_SYNTH, "sun_a": Color(0.85, 1.0, 0.3), "sun_b": Color(0.6, 0.2, 0.9),
		"sun_pos": Vector2(0.32, 0.44), "sun_radius": 0.13, "halo": Color(0.5, 1.0, 0.2),
		"grid_a": Color(0.55, 1.0, 0.1), "grid_b": Color(0.72, 0.3, 1.0),
		"stars": 0.16, "star_tint": Color(0.8, 1.0, 0.7),
		"aurora": 0.0, "aurora_a": Color(0.5, 1.0, 0.2), "aurora_b": Color(0.7, 0.3, 1.0),
		"city": 0.0, "city_glow": Color(0.5, 1.0, 0.2),
		"strata": _colors([
			[0.16, 0.30, 0.10], [0.30, 0.11, 0.40], [0.14, 0.28, 0.12], [0.26, 0.10, 0.36],
			[0.12, 0.26, 0.12], [0.22, 0.10, 0.32], [0.14, 0.24, 0.10], [0.20, 0.09, 0.30],
			[0.10, 0.22, 0.10], [0.18, 0.08, 0.26], [0.10, 0.18, 0.09], [0.15, 0.07, 0.22],
			[0.08, 0.15, 0.08], [0.12, 0.06, 0.18], [0.07, 0.11, 0.07],
		]),
		"edge_a": Color(0.6, 1.0, 0.1), "edge_b": Color(0.82, 0.32, 1.0), "glow": 1.0,
		"tint_core": Color(0.92, 1.0, 0.6), "tint_ring": Color(0.6, 1.0, 0.2),
		"tint_mid": Color(0.45, 0.9, 0.1), "tint_end": Color(0.55, 0.12, 0.85),
		"ambient": AMBIENT_SPORES, "ambient_color": Color(0.7, 1.0, 0.4),
	}


## Black, silver and magenta: a chrome sun over a dense starfield.
static func _midnight_chrome() -> Dictionary:
	return {
		"id": MIDNIGHT_CHROME, "name_key": "THEME_MIDNIGHT_CHROME", "tier": TIER_FULL,
		"sky_top": Color(0.0, 0.0, 0.012), "sky_mid": Color(0.03, 0.03, 0.075), "sky_low": Color(0.65, 0.4, 0.78),
		"ground_far": Color(0.0, 0.0, 0.015), "ground_near": Color(0.08, 0.04, 0.13),
		"sun_style": SUN_CHROME, "sun_a": Color(0.95, 0.95, 1.0), "sun_b": Color(1.0, 0.2, 0.8),
		"sun_pos": Vector2(0.5, 0.36), "sun_radius": 0.15, "halo": Color(0.75, 0.5, 1.0),
		"grid_a": Color(0.78, 0.78, 0.9), "grid_b": Color(1.0, 0.2, 0.75),
		"stars": 0.62, "star_tint": Color(0.95, 0.95, 1.0),
		"aurora": 0.0, "aurora_a": Color(0.8, 0.8, 1.0), "aurora_b": Color(1.0, 0.3, 0.8),
		"city": 0.0, "city_glow": Color(0.8, 0.5, 1.0),
		"strata": _colors([
			[0.20, 0.20, 0.25], [0.30, 0.10, 0.27], [0.17, 0.17, 0.22], [0.26, 0.09, 0.24],
			[0.15, 0.15, 0.20], [0.23, 0.08, 0.22], [0.13, 0.13, 0.18], [0.20, 0.07, 0.19],
			[0.12, 0.12, 0.16], [0.17, 0.06, 0.17], [0.10, 0.10, 0.14], [0.14, 0.05, 0.14],
			[0.08, 0.08, 0.12], [0.10, 0.04, 0.11], [0.06, 0.06, 0.09],
		]),
		"edge_a": Color(0.92, 0.94, 1.0), "edge_b": Color(1.0, 0.22, 0.78), "glow": 1.0,
		"tint_core": Color(1.0, 1.0, 1.0), "tint_ring": Color(0.88, 0.88, 1.0),
		"tint_mid": Color(0.88, 0.3, 0.85), "tint_end": Color(0.45, 0.0, 0.45),
		"ambient": AMBIENT_NONE, "ambient_color": Color(1.0, 1.0, 1.0),
	}
