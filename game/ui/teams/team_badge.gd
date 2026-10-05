class_name TeamBadge
extends Control
## A small rounded badge with a team's letter on its colour (ARCHITECTURE section 42). Shape plus letter, so it
## still reads without colour. It never takes input. `team` NONE draws nothing and hides the node.

var _team: int = TeamStyle.NONE
var _px: float = 20.0
var _style: StyleBoxFlat = StyleBoxFlat.new()


func _init() -> void:
	name = "TeamBadge"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style.set_corner_radius_all(4)
	_style.set_border_width_all(1)
	_style.border_color = Color(TeamStyle.INK, 0.9)
	visible = false


## `team` is 0..3, anything else hides the badge.
func set_team(team: int) -> void:
	_team = team if TeamStyle.is_team(team) else TeamStyle.NONE
	visible = _team != TeamStyle.NONE
	tooltip_text = TeamStyle.team_name(_team) if visible else ""
	queue_redraw()


func get_team() -> int:
	return _team


func get_letter() -> String:
	return TeamStyle.letter(_team) if _team != TeamStyle.NONE else ""


## Edge length in canvas units (it is a square).
func set_badge_size(px: float) -> void:
	_px = px
	custom_minimum_size = Vector2(px, px)
	_style.set_corner_radius_all(maxi(2, roundi(px * 0.2)))
	queue_redraw()


func _draw() -> void:
	if _team == TeamStyle.NONE:
		return
	_style.bg_color = TeamStyle.color(_team)
	_style.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
	var font: Font = get_theme_default_font()
	var fs: int = maxi(8, roundi(minf(size.x, size.y) * 0.72))
	var w: float = font.get_string_size(get_letter(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	var asc: float = font.get_ascent(fs)
	var h: float = font.get_height(fs)
	draw_string(font, Vector2((size.x - w) * 0.5, (size.y - h) * 0.5 + asc), get_letter(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, TeamStyle.INK)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _team != TeamStyle.NONE:
		tooltip_text = TeamStyle.team_name(_team)
