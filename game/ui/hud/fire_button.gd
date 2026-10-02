class_name FireButton
extends Button
## Big glowing FIRE button. Emits `fire_pressed` (on press-release like any Button).
## Glow is the theme StyleBoxFlat shadow; a gentle alpha pulse runs only while enabled
## and when reduce_motion is off (no allocations in _process).

signal fire_pressed

var _t: float = 0.0


func _init() -> void:
	theme_type_variation = &"FireButton"
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	apply_scale()
	_refresh_text()
	pressed.connect(_on_pressed)
	set_process(false)
	_update_pulse_state()


func apply_scale() -> void:
	custom_minimum_size = Vector2(UiScale.dp(120.0), UiScale.dp(68.0))
	add_theme_font_size_override("font_size", UiScale.font(26.0))


func set_enabled(enabled: bool) -> void:
	disabled = not enabled
	_update_pulse_state()


func _on_pressed() -> void:
	if not disabled:
		fire_pressed.emit()


func _update_pulse_state() -> void:
	var run: bool = not disabled and not ShowSettings.reduce_motion and is_inside_tree()
	set_process(run)
	if not run:
		modulate = Color.WHITE


func _process(delta: float) -> void:
	_t += delta
	var k: float = 0.5 + 0.5 * sin(_t * 3.2)
	modulate = Color(1.0, 1.0, 1.0, 1.0).lerp(Color(1.25, 1.1, 1.2, 1.0), k * 0.5)


func _refresh_text() -> void:
	text = tr("HUD_FIRE")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh_text()
	elif what == NOTIFICATION_ENTER_TREE:
		call_deferred("_update_pulse_state")
