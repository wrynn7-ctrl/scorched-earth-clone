class_name TeamChip
extends Button
## The team chip on a setup row (ARCHITECTURE section 42): "—" (no team), then A, B, C, D, each in its team colour.
## The letter is always drawn, so colour is never the only cue. Pressing is handled by the setup screen, which
## cycles the value; the chip only shows it.

var _team: int = TeamStyle.NONE
var _normal: StyleBoxFlat = StyleBoxFlat.new()
var _pressed: StyleBoxFlat = StyleBoxFlat.new()


func _init() -> void:
	name = "Team"
	focus_mode = Control.FOCUS_NONE
	clip_text = true
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	for sb: StyleBoxFlat in [_normal, _pressed]:
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(8)
		sb.set_content_margin_all(2.0)
	add_theme_stylebox_override("normal", _normal)
	add_theme_stylebox_override("hover", _normal)
	add_theme_stylebox_override("pressed", _pressed)
	add_theme_stylebox_override("focus", _normal)
	add_theme_stylebox_override("disabled", _normal)
	set_team(TeamStyle.NONE)


## `team` is 0..3 or TeamStyle.NONE.
func set_team(team: int) -> void:
	_team = team if TeamStyle.is_team(team) else TeamStyle.NONE
	var c: Color = TeamStyle.color(_team)
	text = TeamStyle.letter(_team)
	if _team == TeamStyle.NONE:
		_normal.bg_color = Color(NeonPalette.PANEL.r, NeonPalette.PANEL.g, NeonPalette.PANEL.b, 0.6)
		_normal.border_color = Color(c, 0.6)
		_pressed.bg_color = Color(c, 0.18)
		_pressed.border_color = c
		for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			add_theme_color_override(k, NeonPalette.TEXT_DIM)
		tooltip_text = tr("TEAM_NONE_TIP")
	else:
		_normal.bg_color = Color(c, 0.9)
		_normal.border_color = Color(TeamStyle.INK, 0.9)
		_pressed.bg_color = c.lightened(0.3)
		_pressed.border_color = Color.WHITE
		for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			add_theme_color_override(k, TeamStyle.INK)
		tooltip_text = TeamStyle.team_name(_team)


func get_team() -> int:
	return _team


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		set_team(_team)
