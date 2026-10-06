class_name OnlineKit
extends RefCounted
## Small builders for the online screens (ARCHITECTURE section 48). Every control they make carries its size in dp as
## metadata; `apply(root)` turns that into real sizes with UiScale, so a screen calls it from its `apply_scale()` and
## again after it rebuilt a list. That keeps all layout in containers and dp, never in pixels.

const META_FONT: StringName = &"kit_font_dp"
const META_MIN: StringName = &"kit_min_dp"
const META_DENSE: StringName = &"kit_dense"

const ROW_EDGE: Color = Color(0.0, 0.929, 1.0, 0.32)
const ROW_EDGE_TURN: Color = Color(1.0, 0.95, 0.75, 0.95)
const ROW_BG: Color = Color(0.067, 0.031, 0.157, 0.78)


## A label. `dense` caps the text scale like the in-battle HUD does (tabs, chips, small pills).
static func label(text: String, font_dp: float = 14.0, color: Color = NeonPalette.TEXT, wrap: bool = false,
		dense: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.set_meta(META_FONT, font_dp)
	l.set_meta(META_DENSE, dense)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l


## A touch button at least 48 dp tall; `min_w_dp` is its minimum width.
static func button(text: String, min_w_dp: float = 96.0, font_dp: float = 14.0, dense: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.set_meta(META_FONT, font_dp)
	b.set_meta(META_DENSE, dense)
	b.set_meta(META_MIN, Vector2(min_w_dp, UiScale.MIN_TOUCH_DP))
	b.accessibility_name = text
	return b


## Gives a control a minimum size in dp (height never below the 48 dp touch size for buttons).
static func min_size(c: Control, w_dp: float, h_dp: float) -> void:
	c.set_meta(META_MIN, Vector2(w_dp, h_dp))


## A row card: translucent panel with a neon edge. `bright` is for rows that want attention (your turn).
static func row_panel(bright: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", row_style(bright))
	return p


static func row_style(bright: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = ROW_BG
	sb.border_color = ROW_EDGE_TURN if bright else ROW_EDGE
	sb.set_border_width_all(2 if bright else 1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	sb.anti_aliasing = true
	return sb


## A flat translucent plate (status lines, hints) in a given edge colour.
static func plate(edge: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(NeonPalette.BG_DEEP, 0.82)
	sb.border_color = edge
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	sb.anti_aliasing = true
	return sb


## A small outlined badge ("LOVE", "TEAMS") whose text is always there, so colour is never the only cue.
static func badge(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color, 0.16)
	sb.border_color = color
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 6.0
	sb.content_margin_right = 6.0
	sb.content_margin_top = 1.0
	sb.content_margin_bottom = 1.0
	p.add_theme_stylebox_override("panel", sb)
	var l: Label = label(text, 10.0, color, false, true)
	l.name = "Text"
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Lets a line edit look like the NameField (neon outline).
static func style_line_edit(le: LineEdit) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(NeonPalette.BG_DEEP, 0.9)
	normal.border_color = Color(NeonPalette.CYAN, 0.7)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(10)
	normal.content_margin_left = 10.0
	normal.content_margin_right = 10.0
	normal.content_margin_top = 4.0
	normal.content_margin_bottom = 4.0
	le.add_theme_stylebox_override("normal", normal)
	le.add_theme_stylebox_override("read_only", normal)
	var focus: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	focus.border_color = NeonPalette.HOT
	le.add_theme_stylebox_override("focus", focus)
	le.add_theme_color_override("font_color", NeonPalette.TEXT)
	le.add_theme_color_override("font_placeholder_color", NeonPalette.TEXT_DIM)
	le.add_theme_color_override("caret_color", NeonPalette.HOT)
	le.add_theme_color_override("selection_color", Color(NeonPalette.CYAN, 0.35))


## Sets every dp-based size under `root` (and on `root` itself).
static func apply(root: Node) -> void:
	_apply_one(root)
	for n: Node in root.find_children("*", "Control", true, false):
		_apply_one(n)


static func _apply_one(n: Node) -> void:
	var c: Control = n as Control
	if c == null:
		return
	if c.has_meta(META_FONT):
		var dp: float = c.get_meta(META_FONT) as float
		var dense: bool = c.has_meta(META_DENSE) and (c.get_meta(META_DENSE) as bool)
		var px: int = UiScale.hud_font(dp) if dense else UiScale.font(dp)
		c.add_theme_font_size_override("font_size", px)
	if c.has_meta(META_MIN):
		var spec: Vector2 = c.get_meta(META_MIN) as Vector2
		var h: float = UiScale.dp(spec.y)
		if c is BaseButton:
			h = maxf(h, UiScale.touch())
		c.custom_minimum_size = Vector2(UiScale.dp(spec.x), h)


## Frees every child of `box` now (not at the end of the frame, so a rebuild never shows both generations).
static func clear(box: Node) -> void:
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()
