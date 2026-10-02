class_name MoveControls
extends HBoxContainer
## Left / right drive buttons with a fuel readout. Each press emits `move_pressed(dir)` with
## dir -1 or +1 (the controller turns it into a `move` action of dx = dir * 10); holding a
## button repeats every 150 ms. Hidden when the player has no fuel and no fuel cells.

signal move_pressed(dir: int)

const REPEAT_SECONDS: float = 0.15

var _left: Button = null
var _right: Button = null
var _fuel: Label = null
var _timer: Timer = null
var _held_dir: int = 0
var _fuel_total: int = 0


func _init() -> void:
	name = "MoveControls"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	_left = _make_button("Left", "HUD_MOVE_LEFT_ICON", -1)
	add_child(_left)
	_fuel = Label.new()
	_fuel.name = "Fuel"
	_fuel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fuel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fuel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fuel.add_theme_color_override("font_color", NeonPalette.SUNSET)
	add_child(_fuel)
	_right = _make_button("Right", "HUD_MOVE_RIGHT_ICON", 1)
	add_child(_right)
	_timer = Timer.new()
	_timer.name = "Repeat"
	_timer.wait_time = REPEAT_SECONDS
	_timer.one_shot = false
	_timer.timeout.connect(_on_repeat)
	add_child(_timer)


func _make_button(node_name: String, text_key: String, dir: int) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = tr(text_key)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tr("HUD_MOVE_LEFT") if dir < 0 else tr("HUD_MOVE_RIGHT")
	b.button_down.connect(_on_down.bind(dir))
	b.button_up.connect(_on_up)
	return b


func _ready() -> void:
	apply_scale()


func apply_scale() -> void:
	add_theme_constant_override("separation", roundi(UiScale.dp(4.0)))
	for b: Button in [_left, _right]:
		b.custom_minimum_size = Vector2.ONE * UiScale.touch()
		b.add_theme_font_size_override("font_size", UiScale.hud_font(18.0))
	_fuel.custom_minimum_size = Vector2(UiScale.dp(44.0), UiScale.touch())
	_fuel.add_theme_font_size_override("font_size", UiScale.hud_font(11.0))


## fuel_total: fuel in the tank plus what the owned fuel cells would add. Hidden at 0.
func set_fuel(fuel_total: int) -> void:
	_fuel_total = fuel_total
	_fuel.text = tr("HUD_FUEL") + "\n" + str(fuel_total)
	visible = fuel_total > 0
	if fuel_total <= 0:
		_stop()


func get_fuel_total() -> int:
	return _fuel_total


func get_left_button() -> Button:
	return _left


func get_right_button() -> Button:
	return _right


func get_fuel_text() -> String:
	return _fuel.text


## Same as pressing and releasing the button once (tests and key bindings).
func press(dir: int) -> void:
	move_pressed.emit(dir)


func _on_down(dir: int) -> void:
	_held_dir = dir
	move_pressed.emit(dir)
	_timer.start()


func _on_up() -> void:
	_stop()


func _on_repeat() -> void:
	if _held_dir != 0:
		move_pressed.emit(_held_dir)


func _stop() -> void:
	_held_dir = 0
	if _timer != null:
		_timer.stop()


func is_repeating() -> bool:
	return _held_dir != 0 and not _timer.is_stopped()
