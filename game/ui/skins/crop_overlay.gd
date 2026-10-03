class_name CropOverlay
extends Control
## The crop step of picture import: the chosen picture with a crop box over it (the shape of the
## hull's skin window). Drag to position the box; pinch, the mouse wheel or the ZOOM slider to zoom
## (a smaller box). USE PICTURE downscales to 128x64 with the neon filter (SkinImage) and reports
## it through `confirmed`; CANCEL (or the Android back button) reports `cancelled`.
## Everything happens on this device; nothing is uploaded.

signal confirmed(image: Image)
signal cancelled

const THEME: Theme = preload("res://ui/theme/neon_theme.tres")

var _src: Image = null
var _tex: ImageTexture = null
var _center: Vector2 = Vector2.ZERO
var _zoom: float = 1.0

var _margin: MarginContainer = null
var _box: VBoxContainer = null
var _title: Label = null
var _hint: Label = null
var _canvas: CropCanvas = null
var _row: HBoxContainer = null
var _zoom_label: Label = null
var _slider: SkinSlider = null
var _cancel: Button = null
var _use: Button = null


func _init() -> void:
	theme = THEME
	name = "CropOverlay"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(NeonPalette.BG_DEEP, 0.94)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	_box = VBoxContainer.new()
	_margin.add_child(_box)
	_title = Label.new()
	_title.text = tr("SKIN_CROP_TITLE")
	_title.add_theme_color_override("font_color", NeonPalette.CYAN)
	_box.add_child(_title)
	_hint = Label.new()
	_hint.text = tr("SKIN_CROP_HINT")
	_hint.add_theme_color_override("font_color", NeonPalette.TEXT_DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = 10.0
	_box.add_child(_hint)
	_canvas = CropCanvas.new()
	_canvas.owner_overlay = self
	_canvas.name = "Canvas"
	_box.add_child(_canvas)
	_row = HBoxContainer.new()
	_row.name = "Row"
	_box.add_child(_row)
	_zoom_label = Label.new()
	_zoom_label.text = tr("SKIN_CROP_ZOOM")
	_zoom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_zoom_label.add_theme_color_override("font_color", NeonPalette.TEXT_DIM)
	_row.add_child(_zoom_label)
	_slider = SkinSlider.new()
	_slider.name = "Zoom"
	_slider.min_value = SkinImage.MIN_ZOOM
	_slider.max_value = SkinImage.MAX_ZOOM
	_slider.step = 0.01
	_slider.set_value_no_signal(1.0)
	_slider.value_changed.connect(set_zoom)
	_row.add_child(_slider)
	_cancel = Button.new()
	_cancel.name = "Cancel"
	_cancel.text = tr("SKIN_CROP_CANCEL")
	_cancel.focus_mode = Control.FOCUS_NONE
	_cancel.pressed.connect(cancel)
	_row.add_child(_cancel)
	_use = Button.new()
	_use.name = "Use"
	_use.text = tr("SKIN_CROP_USE")
	_use.theme_type_variation = &"FireButton"
	_use.focus_mode = Control.FOCUS_NONE
	_use.pressed.connect(confirm)
	_row.add_child(_use)


func _ready() -> void:
	apply_scale()
	LayoutWatch.attach(self, apply_scale, true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		cancel()


# --- public -------------------------------------------------------------------------------

## Shows `picture` with the box centred at zoom 1.
func open_with(picture: Image) -> void:
	_src = picture
	_tex = ImageTexture.create_from_image(picture)
	_zoom = 1.0
	_slider.set_value_no_signal(1.0)
	_center = Vector2(picture.get_size()) * 0.5
	visible = true
	if is_inside_tree():
		Transition.fade_in(self)
		apply_scale()
	_canvas.queue_redraw()


func is_open() -> bool:
	return visible


func get_zoom() -> float:
	return _zoom


func get_center() -> Vector2:
	return _center


func get_crop_canvas() -> Control:
	return _canvas


func get_slider() -> SkinSlider:
	return _slider


func get_use_button() -> Button:
	return _use


func get_cancel_button() -> Button:
	return _cancel


## The crop in source pixels, as it would be applied now.
func get_crop_rect() -> Rect2:
	if _src == null:
		return Rect2()
	return SkinImage.crop_rect(Vector2(_src.get_size()), _center, _zoom)


func set_zoom(z: float) -> void:
	_zoom = clampf(z, SkinImage.MIN_ZOOM, SkinImage.MAX_ZOOM)
	if _src != null:
		_center = SkinImage.clamp_center(_center, Vector2(_src.get_size()), _zoom)
	_slider.set_value_no_signal(_zoom)
	_canvas.queue_redraw()


## Moves the box centre by `delta` source pixels (clamped inside the picture).
func move_by(delta: Vector2) -> void:
	if _src == null:
		return
	_center = SkinImage.clamp_center(_center + delta, Vector2(_src.get_size()), _zoom)
	_canvas.queue_redraw()


## New zoom from a two-finger pinch: the box shrinks as the fingers spread.
static func pinch_zoom(zoom: float, prev_dist: float, new_dist: float) -> float:
	if prev_dist <= 1.0 or new_dist <= 1.0:
		return zoom
	return clampf(zoom * new_dist / prev_dist, SkinImage.MIN_ZOOM, SkinImage.MAX_ZOOM)


func confirm() -> void:
	if _src == null:
		return
	var result: Image = SkinImage.process(_src, get_crop_rect())
	visible = false
	confirmed.emit(result)


func cancel() -> void:
	visible = false
	cancelled.emit()


# --- layout -------------------------------------------------------------------------------

func apply_scale() -> void:
	LayoutGuard.fit(self)
	UiScale.apply_edge_margins(_margin)
	_box.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	_row.add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))
	_title.add_theme_font_size_override("font_size", UiScale.font(18.0))
	_hint.add_theme_font_size_override("font_size", UiScale.font(12.0))
	_zoom_label.add_theme_font_size_override("font_size", UiScale.font(12.0))
	_slider.custom_minimum_size = Vector2(UiScale.dp(90.0), UiScale.touch())
	for b: Button in [_cancel, _use]:
		b.add_theme_font_size_override("font_size", UiScale.font(14.0))
		b.custom_minimum_size = Vector2(UiScale.dp(96.0), UiScale.touch())
	_canvas.custom_minimum_size = Vector2(UiScale.dp(120.0), UiScale.dp(70.0))
	_canvas.queue_redraw()


## The picture area: draws the picture fitted into the control and the crop box over it, and turns
## drags, pinches and the wheel into box moves and zoom.
class CropCanvas extends Control:
	var owner_overlay: CropOverlay = null
	var _dragging: bool = false
	var _touches: Dictionary = {}
	var _pinch_dist: float = 0.0

	func _init() -> void:
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	## Canvas pixels per source pixel and the offset of the picture's top left.
	func fit() -> Dictionary:
		var src: Image = owner_overlay._src
		if src == null:
			return {"k": 1.0, "origin": Vector2.ZERO}
		var k: float = minf(size.x / float(src.get_width()), size.y / float(src.get_height()))
		var shown := Vector2(src.get_size()) * k
		return {"k": k, "origin": (size - shown) * 0.5}

	## The crop box in canvas coordinates.
	func box_rect() -> Rect2:
		var f: Dictionary = fit()
		var r: Rect2 = owner_overlay.get_crop_rect()
		return Rect2((f["origin"] as Vector2) + r.position * (f["k"] as float), r.size * (f["k"] as float))

	func _draw() -> void:
		var src: Image = owner_overlay._src
		if src == null:
			return
		var f: Dictionary = fit()
		var k: float = f["k"]
		var origin: Vector2 = f["origin"]
		var pic := Rect2(origin, Vector2(src.get_size()) * k)
		draw_texture_rect(owner_overlay._tex, pic, false)
		var box: Rect2 = box_rect()
		var shade := Color(NeonPalette.BG_DEEP, 0.7)
		# Dim everything outside the box (four bars around it).
		draw_rect(Rect2(pic.position, Vector2(pic.size.x, maxf(0.0, box.position.y - pic.position.y))), shade)
		draw_rect(Rect2(pic.position.x, box.end.y, pic.size.x, maxf(0.0, pic.end.y - box.end.y)), shade)
		draw_rect(Rect2(pic.position.x, box.position.y, maxf(0.0, box.position.x - pic.position.x), box.size.y), shade)
		draw_rect(Rect2(box.end.x, box.position.y, maxf(0.0, pic.end.x - box.end.x), box.size.y), shade)
		draw_rect(box, Color(NeonPalette.CYAN, 0.9), false, maxf(2.0, UiScale.dp(2.0)))
		var third := Color(NeonPalette.CYAN, 0.3)
		for i: int in range(1, 3):
			draw_line(box.position + Vector2(box.size.x * float(i) / 3.0, 0.0), box.position + Vector2(box.size.x * float(i) / 3.0, box.size.y), third, 1.0)
			draw_line(box.position + Vector2(0.0, box.size.y * float(i) / 3.0), box.position + Vector2(box.size.x, box.size.y * float(i) / 3.0), third, 1.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_dragging = mb.pressed
				accept_event()
			elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				owner_overlay.set_zoom(owner_overlay.get_zoom() * 1.1)
				accept_event()
			elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				owner_overlay.set_zoom(owner_overlay.get_zoom() / 1.1)
				accept_event()
		elif event is InputEventMouseMotion and _dragging and _touches.size() < 2:
			var k: float = fit()["k"]
			owner_overlay.move_by((event as InputEventMouseMotion).relative / maxf(0.0001, k))
			accept_event()
		elif event is InputEventMagnifyGesture:
			owner_overlay.set_zoom(owner_overlay.get_zoom() * (event as InputEventMagnifyGesture).factor)
			accept_event()
		elif event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			if st.pressed:
				_touches[st.index] = st.position
			else:
				_touches.erase(st.index)
			_pinch_dist = _two_finger_distance()
		elif event is InputEventScreenDrag:
			var sd := event as InputEventScreenDrag
			_touches[sd.index] = sd.position
			var d: float = _two_finger_distance()
			if _touches.size() >= 2 and _pinch_dist > 0.0:
				owner_overlay.set_zoom(CropOverlay.pinch_zoom(owner_overlay.get_zoom(), _pinch_dist, d))
			_pinch_dist = d

	func _two_finger_distance() -> float:
		if _touches.size() < 2:
			return 0.0
		var pts: Array = _touches.values()
		return (pts[0] as Vector2).distance_to(pts[1] as Vector2)
