class_name NeonSky
extends CanvasLayer
## Background: gradient sky, synthwave sun or moon, perspective grid horizon, parallax stars.
## A single ColorRect + cheap shader on a CanvasLayer behind the world (not affected by the camera).
## apply_theme() restyles it from a ThemeDefs definition (colours become shader uniforms).

const SHADER: Shader = preload("res://show/sky.gdshader")

const EMBER_SUN_TOP: Color = Color(1.0, 0.86, 0.30)
const EMBER_SUN_BASE: Color = Color(1.0, 0.16, 0.12)
const EMBER_HALO: Color = Color(1.0, 0.34, 0.10)
const EMBER_HORIZON: Color = Color(1.0, 0.24, 0.20)

@export var moon: bool = false:
	set(v):
		moon = v
		_apply_moon()

var _rect: ColorRect = null
var _material: ShaderMaterial = null
var _ambient: ThemeAmbient = null
var _theme_id: String = ""
var _pending_theme: String = ""


func _ready() -> void:
	layer = -10
	_rect = ColorRect.new()
	_rect.name = "SkyRect"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect.material = _material
	add_child(_rect)
	_ambient = ThemeAmbient.new()
	_ambient.name = "Ambient"
	add_child(_ambient)
	_rect.resized.connect(_on_resized)
	_on_resized()
	_apply_moon()
	if _pending_theme != "":
		apply_theme(_pending_theme)


## Camera position (world units); stars/grid shift slightly for depth.
func set_parallax(cam_pos: Vector2) -> void:
	if _material != null:
		_material.set_shader_parameter("parallax", cam_pos * 0.01)


## Restyles the sky for ThemeDefs theme `id` (an unknown id means the default look).
func apply_theme(id: String) -> void:
	if _material == null:
		_pending_theme = id  # applied in _ready
		return
	var def: Dictionary = ThemeDefs.get_def(id)
	if def["id"] == _theme_id:
		return
	_theme_id = def["id"] as String
	var m: ShaderMaterial = _material
	for pair: Array in [
			["sky_top", "sky_top"], ["sky_mid", "sky_mid"], ["sky_low", "sky_low"],
			["ground_near", "ground_near"], ["ground_far", "ground_far"],
			["grid_col", "grid_a"], ["grid_col2", "grid_b"],
			["sun_col_a", "sun_a"], ["sun_col_b", "sun_b"], ["halo_col", "halo"],
			["star_tint", "star_tint"], ["aurora_a", "aurora_a"], ["aurora_b", "aurora_b"],
			["city_glow", "city_glow"]]:
		m.set_shader_parameter(pair[0] as String, def[pair[1] as String] as Color)
	m.set_shader_parameter("sun_style", def["sun_style"] as int)
	m.set_shader_parameter("sun_pos", def["sun_pos"] as Vector2)
	m.set_shader_parameter("sun_radius", def["sun_radius"] as float)
	# Star density: the cell threshold drops as the theme's `stars` rises (0.22 = the old 0.78).
	m.set_shader_parameter("star_thresh", 1.0 - (def["stars"] as float))
	m.set_shader_parameter("aurora_mix", def["aurora"] as float)
	m.set_shader_parameter("aurora_peak", ThemeDefs.AURORA_PEAK)
	m.set_shader_parameter("city_mix", def["city"] as float)
	_ambient.set_style(def["ambient"] as String, def["ambient_color"] as Color)


## How fast the horizon grid scrolls toward the viewer (rows per second; 0 stops it).
func set_scroll_speed(speed: float) -> void:
	if _material != null:
		_material.set_shader_parameter("scroll_speed", speed)


## Warms the default sky toward embers (hot yellow sun, red-orange sun base, orange halo, a hotter horizon glow).
## `amount` 0 = the normal look. The title uses it; call it after the sky is in the tree and not after apply_theme.
func set_ember_tint(amount: float) -> void:
	if _material == null:
		return
	var k: float = clampf(amount, 0.0, 1.0)
	_material.set_shader_parameter("sun_col_a", EMBER_SUN_TOP.lerp(Color(1.0, 0.92, 0.35), 1.0 - k))
	_material.set_shader_parameter("sun_col_b", EMBER_SUN_BASE.lerp(Color(1.0, 0.2, 0.55), 1.0 - k))
	_material.set_shader_parameter("halo_col", EMBER_HALO.lerp(Color(1.0, 0.3, 0.6), 1.0 - k))
	_material.set_shader_parameter("sky_low", EMBER_HORIZON.lerp(Color(1.0, 0.22, 0.52), 1.0 - k))


func get_theme_id() -> String:
	return _theme_id if _theme_id != "" else _pending_theme


func get_ambient() -> ThemeAmbient:
	return _ambient


func get_sky_material() -> ShaderMaterial:
	return _material


func _on_resized() -> void:
	if _rect.size.y > 0.0:
		_material.set_shader_parameter("aspect", _rect.size.x / _rect.size.y)
		if _ambient != null:
			_ambient.set_area(_rect.size)


func _apply_moon() -> void:
	if _material != null:
		_material.set_shader_parameter("moon_mix", 1.0 if moon else 0.0)
