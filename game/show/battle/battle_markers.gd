class_name BattleMarkers
extends Control
## Overlay drawn above the HUD (its own CanvasLayer between the HUD and the overlays):
##
##  * the "▼ you" marker over the active tank when that tank sits under a HUD panel, so the
##    player can always find their own tank;
##  * a glowing chevron on the top edge for every shell that is flying above the top of the
##    screen, at the shell's x in the shooter's colour, with a faint height readout.
##
## Both are pure presentation: the controller feeds in screen positions. Redraws only when the
## data changes.

const CHEVRON_DP: float = 14.0
const THEME: Theme = preload("res://ui/theme/neon_theme.tres")

var _you_on: bool = false
var _you_pos: Vector2 = Vector2.ZERO
var _you_color: Color = Color.WHITE
var _shells: Array[Dictionary] = []


func _init() -> void:
	name = "Markers"
	theme = THEME  # the HUD font, not the engine default
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## `at` = viewport position of the tip of the arrow (just above the tank's emblem).
func set_you(on: bool, at: Vector2 = Vector2.ZERO, color: Color = Color.WHITE) -> void:
	if on == _you_on and (not on or (at.is_equal_approx(_you_pos) and color == _you_color)):
		return
	_you_on = on
	_you_pos = at
	_you_color = color
	queue_redraw()


func is_you_visible() -> bool:
	return _you_on


func get_you_position() -> Vector2:
	return _you_pos


## Shells above the screen: [{x: float (viewport x), height: int (cells above the top edge),
## color: Color}]. An empty array hides all chevrons.
func set_shells(items: Array[Dictionary]) -> void:
	if items.is_empty() and _shells.is_empty():
		return
	_shells = items
	queue_redraw()


func get_shell_markers() -> Array[Dictionary]:
	return _shells


func shell_count() -> int:
	return _shells.size()


func _draw() -> void:
	if _you_on:
		_draw_you()
	for s: Dictionary in _shells:
		_draw_chevron(s)


func _draw_you() -> void:
	var u: float = UiScale.dp(1.0)
	var font: Font = get_theme_default_font()
	var fs: int = UiScale.hud_font(13.0)
	var outline: Color = Color(NeonPalette.BG_DEEP, 0.95)
	var tri_w: float = 9.0 * u
	var tri_h: float = 9.0 * u
	var tip: Vector2 = _you_pos
	var tri := PackedVector2Array([tip, tip + Vector2(-tri_w, -tri_h), tip + Vector2(tri_w, -tri_h)])
	var fat := PackedVector2Array([tip + Vector2(0, 2.5 * u), tip + Vector2(-tri_w - 3.0 * u, -tri_h - 2.0 * u),
			tip + Vector2(tri_w + 3.0 * u, -tri_h - 2.0 * u)])
	draw_colored_polygon(fat, Color(outline, 0.9))
	draw_colored_polygon(tri, _you_color)
	var label: String = tr("HUD_YOU")
	var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	var base := Vector2(tip.x - w * 0.5, tip.y - tri_h - 5.0 * u)
	draw_string_outline(font, base, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, roundi(5.0 * u), outline)
	draw_string(font, base, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, _you_color)


func _draw_chevron(s: Dictionary) -> void:
	var u: float = UiScale.dp(1.0)
	var col: Color = s["color"]
	var x: float = clampf(s["x"] as float, 14.0 * u, size.x - 14.0 * u)
	var top: float = maxf(UiScale.safe_insets().y, 0.0) + 5.0 * u
	var w: float = CHEVRON_DP * u
	var h: float = CHEVRON_DP * 0.7 * u
	var fs: int = UiScale.hud_font(11.0)
	var font: Font = get_theme_default_font()
	var label: String = tr("HUD_SHELL_UP_FMT") % int(s["height"])
	var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	var half: float = maxf(w, tw * 0.5) + 7.0 * u
	# A dark plate keeps the chevron readable when it passes over the turn banner.
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(NeonPalette.BG_DEEP, 0.92)
	plate.border_color = Color(col, 0.55)
	plate.set_border_width_all(maxi(1, roundi(1.5 * u)))
	plate.set_corner_radius_all(roundi(6.0 * u))
	var plate_rect := Rect2(x - half, top - 4.0 * u, half * 2.0, h * 2.0 + float(fs) + 14.0 * u)
	draw_style_box(plate, plate_rect)
	var pts := PackedVector2Array([Vector2(x - w, top + h), Vector2(x, top), Vector2(x + w, top + h)])
	draw_polyline(pts, Color(col, 0.18), 12.0 * u, true)
	draw_polyline(pts, Color(col, 0.4), 6.0 * u, true)
	draw_polyline(pts, col, 2.5 * u, true)
	var pts2 := PackedVector2Array([Vector2(x - w, top + h * 2.0), Vector2(x, top + h), Vector2(x + w, top + h * 2.0)])
	draw_polyline(pts2, Color(col, 0.45), 2.0 * u, true)
	var pos := Vector2(x - tw * 0.5, top + h * 2.0 + float(fs) + 3.0 * u)
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Color(col.lerp(Color.WHITE, 0.35), 0.8))
