class_name UiScale
extends RefCounted
## Converts density-independent pixels (dp, 1 dp = 1/160 inch) into canvas units so touch
## targets have the same *physical* size on a 6" phone and a 10" tablet.
##
## The game uses stretch mode canvas_items + aspect expand with a 1600x900 base, so one
## canvas unit = `canvas_scale` physical pixels, where canvas_scale = min(win.x/1600, win.y/900).
## The value is clamped so extreme DPI reports can't make the HUD absurdly big or tiny.

const BASE_W: float = 1600.0
const BASE_H: float = 900.0
const MIN_TOUCH_DP: float = 48.0
const MIN_FACTOR: float = 0.6
const MAX_FACTOR: float = 2.4
const FALLBACK_DPI: float = 320.0

## Test/debug hooks: when > 0 they replace the real DPI / window size.
static var dpi_override: float = 0.0
static var window_px_override: Vector2 = Vector2.ZERO
## User text scale setting (80%..150%), applied by font().
static var text_scale: float = 1.0


static func reset_overrides() -> void:
	dpi_override = 0.0
	window_px_override = Vector2.ZERO
	text_scale = 1.0


static func dpi() -> float:
	if dpi_override > 0.0:
		return dpi_override
	var d: float = float(DisplayServer.screen_get_dpi())
	return d if d >= 72.0 else FALLBACK_DPI


static func window_px() -> Vector2:
	if window_px_override != Vector2.ZERO:
		return window_px_override
	return Vector2(DisplayServer.window_get_size())


## Physical pixels per canvas unit for the given window size (stretch canvas_items, expand).
static func canvas_scale(win: Vector2) -> float:
	return maxf(0.01, minf(win.x / BASE_W, win.y / BASE_H))


## Size of the visible area in canvas units for a window of `win` physical pixels.
static func visible_size(win: Vector2) -> Vector2:
	return win / canvas_scale(win)


## Canvas units per dp, clamped.
static func factor() -> float:
	var win: Vector2 = window_px()
	return clampf(dpi() / 160.0 / canvas_scale(win), MIN_FACTOR, MAX_FACTOR)


## `value_dp` density-independent pixels expressed in canvas units.
static func dp(value_dp: float) -> float:
	return value_dp * factor()


## Minimum comfortable touch target edge (48 dp) in canvas units.
static func touch() -> float:
	return dp(MIN_TOUCH_DP)


## A font size given in dp, with the user's text-scale setting applied.
static func font(size_dp: float) -> int:
	return maxi(8, roundi(dp(size_dp) * text_scale))


## Physical size in dp of a canvas-unit length (for tests/diagnostics).
static func canvas_to_dp(units: float) -> float:
	return units * canvas_scale(window_px()) / (dpi() / 160.0)


## Safe-area insets (notch/cutout) in canvas units: x=left, y=top, z=right, w=bottom.
## Zero except on Android where the display reports a safe area.
static func safe_insets() -> Vector4:
	if not OS.has_feature("android"):
		return Vector4.ZERO
	var win: Vector2 = window_px()
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var cs: float = canvas_scale(win)
	var left: float = maxf(0.0, float(safe.position.x)) / cs
	var top: float = maxf(0.0, float(safe.position.y)) / cs
	var right: float = maxf(0.0, win.x - float(safe.end.x)) / cs
	var bottom: float = maxf(0.0, win.y - float(safe.end.y)) / cs
	return Vector4(left, top, right, bottom)
