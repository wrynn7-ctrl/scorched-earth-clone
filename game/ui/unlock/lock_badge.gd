class_name LockBadge
extends Control
## A small padlock in the top-right corner of a button that needs the full game. The shape is the
## cue (colour is never the only one); the button keeps working so a tap can open the Unlock
## screen. `mark()` adds or removes the badge, dims the label and sets the spoken name.

const SIZE_DP: float = 16.0
const NAME: String = "LockBadge"


func _init() -> void:
	name = NAME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	visible = false


func _draw() -> void:
	ItemIcon.draw_lock(self, size * 0.5, minf(size.x, size.y) * 0.5, NeonPalette.WARN)


## Re-sizes the badge for the current UiScale (call from the screen's apply_scale()).
func apply_scale() -> void:
	var s: float = UiScale.dp(SIZE_DP)
	custom_minimum_size = Vector2.ONE * s
	offset_left = -s - UiScale.dp(4.0)
	offset_right = -UiScale.dp(4.0)
	offset_top = UiScale.dp(4.0)
	offset_bottom = UiScale.dp(4.0) + s
	queue_redraw()


## The badge of `b`, created on first use.
static func of(b: Control) -> LockBadge:
	var existing: Node = b.get_node_or_null(NAME)
	if existing != null:
		return existing as LockBadge
	var badge := LockBadge.new()
	b.add_child(badge)
	badge.apply_scale()
	return badge


## Shows or hides the badge on `b`. A locked button also gets `locked_name` as its tooltip and
## accessibility name (what a screen reader says); an unlocked one gets `open_name`.
static func mark(b: Button, locked: bool, locked_name: String = "", open_name: String = "") -> void:
	var badge: LockBadge = LockBadge.of(b)
	badge.visible = locked
	badge.apply_scale()
	var spoken: String = locked_name if locked else open_name
	if spoken != "":
		b.tooltip_text = spoken
		b.accessibility_name = spoken
