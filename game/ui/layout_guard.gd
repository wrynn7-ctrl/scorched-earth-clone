class_name LayoutGuard
extends RefCounted
## Belt and braces for screens that must cover the whole visible area (the battle HUD and the
## overlays on top of it). Anchors should already do that, but on one real device (a 3120x1440
## phone) the battle HUD ended up ~1586x645 of a 1950x900 canvas while every other screen was
## fine, and the cause was never reproduced. So the screens also *assert* their rectangle: if the
## realised rect differs from the viewport's visible rect by more than TOLERANCE canvas units
## the rect is set explicitly, and the fix is counted so the diagnostics screen can show it.

const TOLERANCE: float = 1.0

## Number of corrections made since start (all guarded screens together), for diagnostics.
static var corrections: int = 0
## What the last correction fixed ("BattleHud: (0,0,1586,645) -> (0,0,1950,900)"), for diagnostics.
static var last_fix: String = ""


static func reset() -> void:
	corrections = 0
	last_fix = ""


## The rect `c` should have in its parent's coordinates: the visible rect under a CanvasLayer (or
## any non-Control parent), the same size at the origin inside a Control parent.
static func wanted_rect(c: Control) -> Rect2:
	var vis: Rect2 = c.get_viewport().get_visible_rect()
	if c.get_parent() is Control:
		return Rect2(Vector2.ZERO, vis.size)
	return vis


static func differs(a: Rect2, b: Rect2) -> bool:
	return absf(a.position.x - b.position.x) > TOLERANCE or absf(a.position.y - b.position.y) > TOLERANCE \
			or absf(a.size.x - b.size.x) > TOLERANCE or absf(a.size.y - b.size.y) > TOLERANCE


## Inside a Control parent the child is expected to use full-rect anchors with zero offsets.
static func _anchors_ok(c: Control) -> bool:
	return c.anchor_left == 0.0 and c.anchor_top == 0.0 and c.anchor_right == 1.0 and c.anchor_bottom == 1.0 \
			and c.offset_left == 0.0 and c.offset_top == 0.0 and c.offset_right == 0.0 and c.offset_bottom == 0.0


## Makes `c` cover the visible rect again if it does not. Returns true when it had to correct
## something. Children of containers are left alone (the container decides their rect).
static func fit(c: Control) -> bool:
	if c == null or not c.is_inside_tree():
		return false
	var parent: Node = c.get_parent()
	if parent is Container:
		return false
	var want: Rect2 = wanted_rect(c)
	if c.get_combined_minimum_size().x > want.size.x + TOLERANCE or c.get_combined_minimum_size().y > want.size.y + TOLERANCE:
		return false  # cannot shrink below its content: nothing to fix, and no point retrying every frame
	var have := Rect2(c.position, c.size)
	var in_control: bool = parent is Control
	var rect_bad: bool = differs(have, want)
	if not rect_bad and not (in_control and not _anchors_ok(c)):
		return false
	corrections += 1
	last_fix = "%s: %s -> %s" % [c.name, _fmt(have), _fmt(want)]
	if in_control:
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if not differs(Rect2(c.position, c.size), want):
			return true
	# Under a CanvasLayer (or when even full-rect anchors do not give the right size, i.e. the
	# parent is wrong): stop depending on anchor resolution and set the rect by hand.
	c.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	c.size = want.size
	c.position = want.position
	return true


static func _fmt(r: Rect2) -> String:
	return "(%d,%d %dx%d)" % [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]
