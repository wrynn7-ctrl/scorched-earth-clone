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
const MAX_FACTOR: float = 3.4
const FALLBACK_DPI: float = 320.0

## Margin kept between the HUD/screens and the edge of the visible area, in dp (plus the safe-area inset).
const EDGE_MARGIN_DP: float = 12.0
## Largest safe-area inset (dp) we believe per side: a punch-hole or notch is ~45 dp, a gesture bar
## ~24 dp, 3-button navigation 48 dp. A bigger report is bogus (see safe_insets()) and ignored.
const MAX_SIDE_INSET_DP: float = 80.0
const MAX_TOP_INSET_DP: float = 56.0
const MAX_BOTTOM_INSET_DP: float = 56.0

## Test/debug hooks: when > 0 they replace the real DPI / window size.
static var dpi_override: float = 0.0
static var window_px_override: Vector2 = Vector2.ZERO
## Test/debug hook: when x >= 0, replaces the display's safe area with these insets in
## *physical pixels* (x=left, y=top, z=right, w=bottom). Works on every platform.
static var safe_px_override: Vector4 = Vector4(-1.0, -1.0, -1.0, -1.0)
## User text scale setting (80%..150%), applied by font().
static var text_scale: float = 1.0


static func reset_overrides() -> void:
	dpi_override = 0.0
	window_px_override = Vector2.ZERO
	safe_px_override = Vector4(-1.0, -1.0, -1.0, -1.0)
	text_scale = 1.0


static func dpi() -> float:
	if dpi_override > 0.0:
		return dpi_override
	var d: float = float(DisplayServer.screen_get_dpi())
	return d if d >= 72.0 else FALLBACK_DPI


## Physical size of the window in pixels. Prefers the root Window's own size: that is exactly
## what the engine's stretch (and so every Control's anchor rect) is computed from, so the dp
## scale can never disagree with the layout. Falls back to the DisplayServer, then to the base.
static func window_px() -> Vector2:
	if window_px_override != Vector2.ZERO:
		return window_px_override
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null and tree.root.content_scale_size != Vector2i.ZERO:
		var r := Vector2(tree.root.size)
		if r.x > 0.0 and r.y > 0.0:
			return r
	var w := Vector2(DisplayServer.window_get_size())
	return w if w.x > 0.0 and w.y > 0.0 else Vector2(BASE_W, BASE_H)  # headless reports 0


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


## Most the in-battle HUD follows the text-size setting: its controls share a phone-width
## screen, so they grow at most this much (menus and overlays use the full setting).
const HUD_TEXT_CAP: float = 1.1


## Like font(), for dense screens (battle HUD, match setup): text scale capped at HUD_TEXT_CAP.
static func hud_font(size_dp: float) -> int:
	return maxi(8, roundi(dp(size_dp) * minf(text_scale, HUD_TEXT_CAP)))


## Like line_h(), for the HUD.
static func hud_line_h(size_dp: float) -> float:
	return float(hud_font(size_dp)) * 1.4


## Height in canvas units of one line of text of `size_dp` (with the text-scale setting),
## including the font's line spacing. Used to size controls that hold text.
static func line_h(size_dp: float) -> float:
	return float(font(size_dp)) * 1.4


## Pointer to tell tests/tools the text scale changed: re-runs every apply_scale() hooked to
## the root viewport's size_changed. No-op without a tree.
static func notify_changed(tree: SceneTree) -> void:
	if tree != null and tree.root != null:
		tree.root.size_changed.emit()


## Physical size in dp of a canvas-unit length (for tests/diagnostics).
static func canvas_to_dp(units: float) -> float:
	return units * canvas_scale(window_px()) / (dpi() / 160.0)


## Safe-area insets (notch/cutout/gesture bar) in *physical pixels*, relative to the window:
## x=left, y=top, z=right, w=bottom. Unsanitised; see safe_insets().
static func raw_safe_px() -> Vector4:
	if safe_px_override.x >= 0.0:
		return safe_px_override
	if not OS.has_feature("android"):
		return Vector4.ZERO
	var win: Vector2 = window_px()
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	return Vector4(
		maxf(0.0, float(safe.position.x)), maxf(0.0, float(safe.position.y)),
		maxf(0.0, win.x - float(safe.end.x)), maxf(0.0, win.y - float(safe.end.y)))


## One inset (physical px) in canvas units; a report above `max_dp` is treated as a bogus
## value and ignored (a wrong safe area must never shove the HUD away from the screen edge).
static func _sane_inset(px: float, max_dp: float, cs: float) -> float:
	if px <= 0.0:
		return 0.0
	var canvas: float = px / cs
	return canvas if canvas_to_dp(canvas) <= max_dp else 0.0


## Safe-area insets in canvas units: x=left, y=top, z=right, w=bottom. Zero unless the display
## reports one (Android) or a debug override is set. Always converted from physical pixels with
## the live canvas scale, and sanitised.
static func safe_insets() -> Vector4:
	var raw: Vector4 = raw_safe_px()
	if raw == Vector4.ZERO:
		return Vector4.ZERO
	var cs: float = canvas_scale(window_px())
	return Vector4(
		_sane_inset(raw.x, MAX_SIDE_INSET_DP, cs), _sane_inset(raw.y, MAX_TOP_INSET_DP, cs),
		_sane_inset(raw.z, MAX_SIDE_INSET_DP, cs), _sane_inset(raw.w, MAX_BOTTOM_INSET_DP, cs))


## Distance (canvas units) between the screen edge and the HUD's outermost controls:
## EDGE_MARGIN_DP plus the safe-area inset of that side. x=left, y=top, z=right, w=bottom.
static func edge_margins() -> Vector4:
	var pad: float = dp(EDGE_MARGIN_DP)
	var ins: Vector4 = safe_insets()
	return Vector4(pad + ins.x, pad + ins.y, pad + ins.z, pad + ins.w)


## Fills a MarginContainer's four margins from edge_margins().
static func apply_edge_margins(margin: MarginContainer) -> void:
	var m: Vector4 = edge_margins()
	margin.add_theme_constant_override("margin_left", roundi(m.x))
	margin.add_theme_constant_override("margin_top", roundi(m.y))
	margin.add_theme_constant_override("margin_right", roundi(m.z))
	margin.add_theme_constant_override("margin_bottom", roundi(m.w))


## Human-readable dump of every number that decides the layout (hidden diagnostics screen).
static func diagnostics(viewport: Viewport) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var vis: Rect2 = viewport.get_visible_rect() if viewport != null else Rect2()
	var win: Vector2 = window_px()
	var cs: float = canvas_scale(win)
	var root: Window = null
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		root = tree.root
	lines.append("window (UiScale): %d x %d px" % [roundi(win.x), roundi(win.y)])
	lines.append("window (DisplayServer): %s" % str(DisplayServer.window_get_size()))
	if root != null:
		lines.append("root window size: %s  content scale: %s mode %d aspect %d" % [
			str(root.size), str(root.content_scale_size), root.content_scale_mode, root.content_scale_aspect])
	lines.append("visible canvas rect: %s" % str(vis))
	lines.append("expected canvas: %d x %d  (px per unit %.3f)" % [
		roundi(win.x / cs), roundi(win.y / cs), cs])
	lines.append("screen size: %s  usable: %s" % [str(DisplayServer.screen_get_size()), str(DisplayServer.screen_get_usable_rect())])
	lines.append("safe area (raw): %s" % str(DisplayServer.get_display_safe_area()))
	var raw: Vector4 = raw_safe_px()
	lines.append("insets px  L%d T%d R%d B%d%s" % [
		roundi(raw.x), roundi(raw.y), roundi(raw.z), roundi(raw.w),
		"  (override)" if safe_px_override.x >= 0.0 else ""])
	var ins: Vector4 = safe_insets()
	lines.append("insets used (canvas)  L%d T%d R%d B%d" % [roundi(ins.x), roundi(ins.y), roundi(ins.z), roundi(ins.w)])
	lines.append("dpi reported: %d  used: %.0f%s" % [DisplayServer.screen_get_dpi(), dpi(), "  (override)" if dpi_override > 0.0 else ""])
	lines.append("screen scale: %.2f  factor (canvas/dp): %.3f  48 dp = %.1f units" % [DisplayServer.screen_get_scale(), factor(), touch()])
	lines.append("text scale: %.2f  edge margin: %.1f units" % [text_scale, dp(EDGE_MARGIN_DP)])
	lines.append("orientation: %d  platform: %s" % [DisplayServer.screen_get_orientation(), OS.get_name()])
	return "\n".join(lines)
