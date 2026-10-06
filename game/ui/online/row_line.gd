class_name RowLine
extends PanelContainer
## One list row (a match, a friend, a seat): a neon card holding a row of controls. A tap on the card itself (not on
## a button inside it) emits `activated`; a swipe that scrolls the list never counts as a tap, because the press and
## the release must be within TAP_SLOP_DP of each other.

signal activated

const TAP_SLOP_DP: float = 10.0

var content: HBoxContainer = null
var tappable: bool = false
var _press: Vector2 = Vector2.ZERO
var _down: bool = false


func _init(bright: bool = false, can_tap: bool = false) -> void:
	tappable = can_tap
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", OnlineKit.row_style(bright))
	content = HBoxContainer.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(content)


func _gui_input(event: InputEvent) -> void:
	if not tappable or not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_press = mb.global_position
		_down = true
	elif _down:
		_down = false
		if mb.global_position.distance_to(_press) <= UiScale.dp(TAP_SLOP_DP):
			tap()


## What a tap does (tests call it directly).
func tap() -> void:
	if tappable:
		activated.emit()


## Adds a control to the row. `grow` makes it take the free width.
func add_item(c: Control, grow: bool = false) -> Control:
	if grow:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(c)
	return c
