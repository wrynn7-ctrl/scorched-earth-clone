class_name OnlineOverlay
extends Control
## What an online match adds on top of the battle HUD (ARCHITECTURE section 48), all in one full-screen layer that never
## takes input except for the message popup:
##  * a connection pill (Live / Waiting for NAME / Reconnecting... / Offline, actions queued) with a shape for every
##    state, so colour is never the only cue;
##  * the live turn timer ring;
##  * "Waiting for NAME" in the middle of the screen while the controls are off because it is someone else's turn;
##  * quick-message bubbles over the senders' tanks, and the message popup.
## The battle controller feeds it; it knows nothing about the match.

signal message_chosen(msg: int)

const THEME: Theme = preload("res://ui/theme/neon_theme.tres")
const BUBBLE_LIFT_WORLD: float = 124.0
const MAX_BUBBLES: int = 8

enum Conn { LIVE, WAITING, RECONNECTING, OFFLINE, CLOSED }

## Callable(seat: int) -> Vector2: where a tank's head is on screen (canvas units), or Vector2(-1, -1) when unknown.
var tank_pos: Callable = Callable()
## Callable(seat: int) -> Color: the seat's tank colour.
var seat_color: Callable = Callable()
## Extra distance from the top for the strip (the sudden-death tag sits right under the top row).
var strip_extra: float = 0.0

var _top: VBoxContainer = null
var _strip: HBoxContainer = null
var _pill: PanelContainer = null
var _glyph: StatusGlyph = null
var _pill_text: Label = null
var _ring: TurnRing = null
var _wait: PanelContainer = null
var _wait_title: Label = null
var _wait_sub: Label = null
var _bubble_layer: Control = null
var _bubbles: Array[MessageBubble] = []
var _picker: MessagePicker = null
var _conn: int = Conn.LIVE
var _pill_style: StyleBoxFlat = StyleBoxFlat.new()


func _init() -> void:
	theme = THEME
	name = "OnlineOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_top = VBoxContainer.new()
	_top.name = "Top"
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.anchor_left = 0.5
	_top.anchor_right = 0.5
	_top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_top)
	_strip = HBoxContainer.new()
	_strip.name = "Strip"
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	_top.add_child(_strip)
	_pill = PanelContainer.new()
	_pill.name = "Pill"
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pill_style.bg_color = Color(NeonPalette.BG_DEEP, 0.82)
	_pill_style.set_border_width_all(2)
	_pill_style.set_corner_radius_all(14)
	_pill_style.content_margin_left = 10.0
	_pill_style.content_margin_right = 12.0
	_pill_style.content_margin_top = 3.0
	_pill_style.content_margin_bottom = 3.0
	_pill_style.anti_aliasing = true
	_pill.add_theme_stylebox_override("panel", _pill_style)
	_strip.add_child(_pill)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.add_child(row)
	_glyph = StatusGlyph.new(StatusGlyph.Kind.DOT, NeonPalette.GOOD)
	_glyph.name = "Glyph"
	row.add_child(_glyph)
	_pill_text = Label.new()
	_pill_text.name = "Text"
	_pill_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pill_text.add_theme_color_override("font_color", NeonPalette.TEXT)
	row.add_child(_pill_text)
	_ring = TurnRing.new()
	_strip.add_child(_ring)
	_wait = PanelContainer.new()
	_wait.name = "Waiting"
	_wait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wait.visible = false
	_wait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(NeonPalette.BG_DEEP, 0.7)
	plate.border_color = Color(NeonPalette.CYAN, 0.5)
	plate.set_border_width_all(1)
	plate.set_corner_radius_all(12)
	plate.content_margin_left = 16.0
	plate.content_margin_right = 16.0
	plate.content_margin_top = 6.0
	plate.content_margin_bottom = 6.0
	plate.anti_aliasing = true
	_wait.add_theme_stylebox_override("panel", plate)
	_top.add_child(_wait)
	var wbox := VBoxContainer.new()
	wbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wait.add_child(wbox)
	_wait_title = Label.new()
	_wait_title.name = "Title"
	_wait_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wait_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wait_title.add_theme_color_override("font_color", NeonPalette.TEXT)
	wbox.add_child(_wait_title)
	_wait_sub = Label.new()
	_wait_sub.name = "Sub"
	_wait_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wait_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wait_sub.add_theme_color_override("font_color", NeonPalette.TEXT_DIM)
	wbox.add_child(_wait_sub)
	_bubble_layer = Control.new()
	_bubble_layer.name = "Bubbles"
	_bubble_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bubble_layer)
	_picker = MessagePicker.new()
	_picker.chosen.connect(func(msg: int) -> void: message_chosen.emit(msg))
	add_child(_picker)
	set_connection(Conn.LIVE, "")


func _ready() -> void:
	apply_scale()
	LayoutWatch.attach(self, apply_scale, true)


func apply_scale() -> void:
	LayoutGuard.fit(self)
	_ring.apply_scale()
	_glyph.apply_scale()
	_pill_text.add_theme_font_size_override("font_size", UiScale.hud_font(13.0))
	_wait_title.add_theme_font_size_override("font_size", UiScale.hud_font(14.0))
	_wait_sub.add_theme_font_size_override("font_size", UiScale.hud_font(12.0))
	_strip.add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))
	_place_strip()
	for b: MessageBubble in _bubbles:
		b.apply_scale()


func _place_strip() -> void:
	var top: float = UiScale.edge_margins().y + UiScale.touch() + UiScale.dp(6.0) + strip_extra
	_top.offset_top = top
	_top.offset_bottom = top + _top.get_combined_minimum_size().y
	_top.add_theme_constant_override("separation", roundi(UiScale.dp(4.0)))


# --- connection pill ----------------------------------------------------------------------------------------------

## What the pill says. `waiting_name` is the player the match waits for (CONN.WAITING).
func set_connection(conn: int, waiting_name: String) -> void:
	_conn = conn
	var color: Color = NeonPalette.GOOD
	var kind: int = StatusGlyph.Kind.DOT
	var text: String = tr("NET_CONN_LIVE")
	match conn:
		Conn.WAITING:
			kind = StatusGlyph.Kind.RING
			color = NeonPalette.CYAN
			text = tr("NET_CONN_WAITING") % waiting_name
		Conn.RECONNECTING:
			kind = StatusGlyph.Kind.BROKEN
			color = NeonPalette.WARN
			text = tr("NET_CONN_RECONNECTING")
		Conn.OFFLINE:
			kind = StatusGlyph.Kind.CROSS
			color = NeonPalette.BAD
			text = tr("NET_CONN_OFFLINE")
		Conn.CLOSED:
			kind = StatusGlyph.Kind.CROSS
			color = NeonPalette.TEXT_DIM
			text = tr("NET_CONN_CLOSED")
	_glyph.set_glyph(kind, color)
	_pill_text.text = text
	_pill_text.accessibility_name = text
	_pill_style.border_color = Color(color, 0.9)
	_place_strip()


func connection() -> int:
	return _conn


func connection_text() -> String:
	return _pill_text.text


func get_glyph_kind() -> int:
	return _glyph.kind


# --- timer ring ---------------------------------------------------------------------------------------------------

func set_timer(left: float, total: float) -> void:
	_ring.set_time(left, total)


func get_ring() -> TurnRing:
	return _ring


# --- "Waiting for NAME" -------------------------------------------------------------------------------------------

## Shows (or hides, with an empty title) the waiting text under the indicator.
func set_waiting(title: String, sub: String = "") -> void:
	_wait.visible = title != ""
	_wait_title.text = title
	_wait_sub.text = sub
	_wait_sub.visible = sub != ""
	_place_strip()


func waiting_text() -> String:
	return _wait_title.text if _wait.visible else ""


func waiting_sub_text() -> String:
	return _wait_sub.text if _wait.visible and _wait_sub.visible else ""


# --- bubbles ------------------------------------------------------------------------------------------------------

## A bubble for `seat` (replaces that seat's current one). `color` frames it.
func show_bubble(seat: int, msg: int, color: Color) -> MessageBubble:
	var bubble: MessageBubble = null
	for b: MessageBubble in _bubbles:
		if b.seat == seat:
			bubble = b
	if bubble == null:
		if _bubbles.size() >= MAX_BUBBLES:
			_remove_bubble(_bubbles[0])
		bubble = MessageBubble.new()
		_bubble_layer.add_child(bubble)
		_bubbles.append(bubble)
	bubble.show_message(seat, msg, color)
	_place_bubble(bubble)
	return bubble


func bubble_count() -> int:
	return _bubbles.size()


func bubble_for(seat: int) -> MessageBubble:
	for b: MessageBubble in _bubbles:
		if b.seat == seat:
			return b
	return null


func _remove_bubble(b: MessageBubble) -> void:
	_bubbles.erase(b)
	if b.get_parent() != null:
		b.get_parent().remove_child(b)
	b.queue_free()


func _process(delta: float) -> void:
	for b: MessageBubble in _bubbles.duplicate():
		if not b.tick(delta):
			_remove_bubble(b)
		else:
			_place_bubble(b)


func _place_bubble(b: MessageBubble) -> void:
	if not tank_pos.is_valid():
		return
	var p: Vector2 = tank_pos.call(b.seat) as Vector2
	if p.x < 0.0:
		b.visible = false
		return
	b.visible = true
	var s: Vector2 = b.get_combined_minimum_size()
	var vis: Rect2 = get_viewport_rect()
	var x: float = clampf(p.x - s.x * 0.5, vis.position.x + 4.0, vis.end.x - s.x - 4.0)
	b.position = Vector2(x, maxf(p.y - s.y, vis.position.y + 4.0))


# --- picker -------------------------------------------------------------------------------------------------------

func get_picker() -> MessagePicker:
	return _picker


func open_picker() -> void:
	_picker.open()


func get_strip() -> Control:
	return _strip


func get_pill() -> Control:
	return _pill
