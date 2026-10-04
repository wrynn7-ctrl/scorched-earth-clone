class_name DiagnosticsOverlay
extends OverlayPanel
## Hidden on-device diagnostics (settings screen: tap the version number 5 times). Shows every
## number that decides the layout and draws frames so a screenshot is enough to debug an
## edge/inset problem: yellow = the rect this screen was given, magenta = the viewport's
## visible rect, cyan = the safe-area insets that are actually applied.
## Also openable in a battle (hold the pause button for 1.5 s, or pause > settings > tap the version
## 5 times). Then it lists the battle HUD's rectangles in a second column and outlines them:
## yellow = HUD root, cyan = the content rect inside the Safe margins, green = the three columns.

signal closed

const REFRESH_SECONDS: float = 0.5
const FONT_DP: float = 9.0

var _text: Label = null
var _text_hud: Label = null
var _frames: Control = null
var _debug_full: Button = null
var _since: float = 0.0


func _init() -> void:
	super._init()
	name = "DiagnosticsOverlay"
	add_title(tr("DIAG_TITLE"), NeonPalette.CYAN, 20.0)
	# Two columns at a small font: the battle adds ~20 lines and a phone canvas is only 900 units high.
	begin_row()
	_text = _text_label("Text")
	_text_hud = _text_label("TextHud")
	end_container()
	# Debug builds only: pretend the full game is owned (or not) to test both modes before the Play
	# listing exists. Release builds never show it, and Entitlement ignores the call there anyway.
	_debug_full = add_button("", 260.0)
	_debug_full.name = "DebugFull"
	_debug_full.toggle_mode = true
	_debug_full.toggled.connect(func(on: bool) -> void:
		Entitlement.set_debug_full(on)
		_sync_debug_full())
	add_button(tr("DIAG_CLOSE"), 160.0).pressed.connect(close)
	_buttons[_buttons.size() - 1].name = "Close"
	_frames = Control.new()
	_frames.name = "Frames"
	_frames.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frames.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frames.draw.connect(_draw_frames)
	add_child(_frames)


func _text_label(node_name: String) -> Label:
	var l: Label = add_label("", FONT_DP, NeonPalette.TEXT)
	l.name = node_name
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_constant_override("line_spacing", 0)
	return l


func open() -> void:
	refresh()
	super.open()


func close() -> void:
	if is_open():
		super.close()
		closed.emit()


func apply_scale() -> void:
	super.apply_scale()
	# Wide enough for the longest line; the text itself never wraps.
	var wide: float = get_viewport_rect().size.x * 0.96 if _find_hud() != null else UiScale.dp(520.0)
	_panel.custom_minimum_size.x = minf(maxf(UiScale.dp(520.0), wide), get_viewport_rect().size.x * 0.96)
	if _frames != null:
		_frames.queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_since += delta
	if _since >= REFRESH_SECONDS:
		_since = 0.0
		refresh()


func _sync_debug_full() -> void:
	_debug_full.visible = Entitlement.is_debug_build()
	_debug_full.set_pressed_no_signal(Entitlement.is_debug_full())
	_debug_full.text = tr("DIAG_DEBUG_FULL_FMT") % (tr("SET_ON") if Entitlement.is_debug_full() else tr("SET_OFF"))


func get_debug_full_button() -> Button:
	return _debug_full


func refresh() -> void:
	_sync_debug_full()
	var extra: String = "this screen: %s\nversion: %s\nfull game: %s (store: %s, debug override: %s)\n%s" % [
			str(get_global_rect()), BuildInfo.VERSION, str(Entitlement.is_full()), Entitlement.backend_name(),
			str(Entitlement.is_debug_full()), audio_line()]
	_text.text = UiScale.diagnostics(get_viewport()) + "\n" + extra
	var hud: BattleHud = _find_hud()
	_text_hud.visible = hud != null
	_text_hud.text = "\n".join(hud.diagnostics_lines()) if hud != null else ""
	apply_scale()  # the panel width depends on whether the HUD column exists
	_frames.queue_redraw()


## The engine's own audio delay (Bluetooth adds more on top, which the engine can't see).
static func audio_line() -> String:
	return "audio: mix %d Hz, output latency %d ms" % [
			roundi(AudioServer.get_mix_rate()), roundi(AudioServer.get_output_latency() * 1000.0)]


## All the text on the screen (both columns).
func get_text() -> String:
	return _text.text if _text_hud.text == "" else _text.text + "\n" + _text_hud.text


func get_hud_text() -> String:
	return _text_hud.text


## The live battle HUD, if a battle is running.
func _find_hud() -> BattleHud:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(BattleHud.GROUP) as BattleHud


func _draw_frames() -> void:
	var hud: BattleHud = _find_hud()
	var own := Rect2(Vector2.ZERO, _frames.size)
	_frames.draw_rect(own.grow(-1.0), Color(1.0, 0.9, 0.2) if hud == null else Color(1, 1, 1, 0.5), false, 2.0)
	var vis: Rect2 = get_viewport().get_visible_rect()
	_frames.draw_rect(Rect2(vis.position + Vector2(4, 4), vis.size - Vector2(8, 8)), NeonPalette.MAGENTA, false, 2.0)
	if hud != null:
		_draw_hud_frames(hud)
		return
	var ins: Vector4 = UiScale.safe_insets()
	var safe := Rect2(vis.position + Vector2(ins.x, ins.y), vis.size - Vector2(ins.x + ins.z, ins.y + ins.w))
	_frames.draw_rect(safe.grow(-8.0), NeonPalette.CYAN, false, 2.0)


## Outlines of the HUD's own rectangles, converted from viewport to this control's coordinates.
func _draw_hud_frames(hud: BattleHud) -> void:
	var rects: Dictionary = hud.get_outline_rects()
	var origin: Vector2 = _frames.get_global_rect().position
	var yellow := Color(1.0, 0.9, 0.2)
	var green := Color(0.2, 1.0, 0.3)
	for col: Variant in rects["columns"] as Array:
		_frames.draw_rect(Rect2((col as Rect2).position - origin, (col as Rect2).size), green, false, 2.0)
	var content: Rect2 = rects["content"]
	_frames.draw_rect(Rect2(content.position - origin, content.size), NeonPalette.CYAN, false, 3.0)
	var root: Rect2 = rects["root"]
	_frames.draw_rect(Rect2(root.position - origin, root.size).grow(-2.0), yellow, false, 3.0)
