class_name DiagnosticsOverlay
extends OverlayPanel
## Hidden on-device diagnostics (settings screen: tap the version number 5 times). Shows every
## number that decides the layout and draws frames so a screenshot is enough to debug an
## edge/inset problem: yellow = the rect this screen was given, magenta = the viewport's
## visible rect, cyan = the safe-area insets that are actually applied.

signal closed

const REFRESH_SECONDS: float = 0.5

var _text: Label = null
var _frames: Control = null
var _since: float = 0.0


func _init() -> void:
	super._init()
	name = "DiagnosticsOverlay"
	add_title(tr("DIAG_TITLE"), NeonPalette.CYAN, 20.0)
	_text = add_label("", 11.0, NeonPalette.TEXT)
	_text.name = "Text"
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_button(tr("DIAG_CLOSE"), 160.0).pressed.connect(close)
	_buttons[_buttons.size() - 1].name = "Close"
	_frames = Control.new()
	_frames.name = "Frames"
	_frames.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frames.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frames.draw.connect(_draw_frames)
	add_child(_frames)


func open() -> void:
	refresh()
	super.open()


func close() -> void:
	if visible:
		super.close()
		closed.emit()


func apply_scale() -> void:
	super.apply_scale()
	# Wide enough for the longest line; the text itself never wraps.
	_panel.custom_minimum_size.x = minf(UiScale.dp(520.0), get_viewport_rect().size.x * 0.96)
	if _frames != null:
		_frames.queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_since += delta
	if _since >= REFRESH_SECONDS:
		_since = 0.0
		refresh()


func refresh() -> void:
	var extra: String = "this screen: %s\nversion: %s" % [str(get_global_rect()), BuildInfo.VERSION]
	_text.text = UiScale.diagnostics(get_viewport()) + "\n" + extra
	_frames.queue_redraw()


func get_text() -> String:
	return _text.text


func _draw_frames() -> void:
	var own := Rect2(Vector2.ZERO, _frames.size)
	_frames.draw_rect(own.grow(-1.0), Color(1.0, 0.9, 0.2), false, 2.0)
	var vis: Rect2 = get_viewport().get_visible_rect()
	_frames.draw_rect(Rect2(vis.position + Vector2(4, 4), vis.size - Vector2(8, 8)), NeonPalette.MAGENTA, false, 2.0)
	var ins: Vector4 = UiScale.safe_insets()
	var safe := Rect2(vis.position + Vector2(ins.x, ins.y), vis.size - Vector2(ins.x + ins.z, ins.y + ins.w))
	_frames.draw_rect(safe.grow(-8.0), NeonPalette.CYAN, false, 2.0)
