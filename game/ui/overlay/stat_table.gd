class_name StatTable
extends VBoxContainer
## A small table for overlays: a header row, then one row per player (emblem, name, values).
## Used by the round summary and the final standings. It lives inside a ScrollContainer, so
## eight players still fit a phone in landscape.

const VALUE_MIN_DP: float = 84.0

var _grid: GridContainer = null
var _headers: PackedStringArray = PackedStringArray()
var _rows: Array[Dictionary] = []
var _head_labels: Array[Label] = []
var _name_labels: Array[Label] = []
var _value_labels: Array[Label] = []
var _icons: Array[EmblemIcon] = []
## Team badges: [{badge: TeamBadge, dp: float}] (group headers and the member rows of a team match).
var _badges: Array[Dictionary] = []
var _highlight: int = -1


func _init() -> void:
	name = "StatTable"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid = GridContainer.new()
	_grid.name = "Grid"
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_grid)


## headers: names of the value columns (already translated).
## rows: [{id: player index, label: String, cells: PackedStringArray}] in display order. Optional keys (team games,
## ARCHITECTURE section 42): "team" (0..3) adds a letter badge next to the emblem; "header": true makes the row a team
## header (badge instead of an emblem, in the team colour; "id" is not used); "win": bool says which rows are lit
## (default: the row whose id is `highlight`).
func set_data(headers: PackedStringArray, rows: Array[Dictionary], highlight: int = -1) -> void:
	_headers = headers
	_rows = rows
	_highlight = highlight
	for c: Node in _grid.get_children():
		_grid.remove_child(c)
		c.free()
	_head_labels.clear()
	_name_labels.clear()
	_value_labels.clear()
	_icons.clear()
	_badges.clear()
	_grid.columns = 2 + headers.size()
	_head_labels.append(_add_label("", NeonPalette.TEXT_DIM, false))  # emblem column
	_head_labels.append(_add_label("", NeonPalette.TEXT_DIM, false))  # name column
	for h: String in headers:
		_head_labels.append(_add_label(h, NeonPalette.TEXT_DIM, true))
	var lit_by_flag: bool = false
	for row: Dictionary in rows:
		lit_by_flag = lit_by_flag or row.has("win")
	for row: Dictionary in rows:
		var team: int = row.get("team", TeamStyle.NONE)
		var is_header: bool = row.get("header", false)
		var id: int = row.get("id", -1)
		var lit: bool = (row["win"] as bool) if lit_by_flag else (highlight == id)
		var dim: bool = (lit_by_flag or highlight >= 0) and not lit
		var col: Color
		if is_header:
			_grid.add_child(_make_badge(team, 24.0))
			col = TeamStyle.color(team)
		else:
			_add_emblem_cell(id, team)
			col = PlayerLooks.color(id)
		if dim:
			col = col.darkened(0.3)
		var name_l: Label = _add_label(row["label"] as String, col, false)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_name_labels.append(name_l)
		var cells: PackedStringArray = row["cells"]
		for c: String in cells:
			_value_labels.append(_add_label(c, NeonPalette.HOT if lit else NeonPalette.TEXT, true))
	apply_scale()


func _make_badge(team: int, dp: float) -> TeamBadge:
	var b := TeamBadge.new()
	b.set_team(team)
	_badges.append({"badge": b, "dp": dp})
	return b


## The first cell of a player row: the emblem, plus a small team badge beside it in a team game.
func _add_emblem_cell(id: int, team: int) -> void:
	var icon := EmblemIcon.new()
	icon.set_index(id)
	_icons.append(icon)
	if not TeamStyle.is_team(team):
		_grid.add_child(icon)
		return
	var box := HBoxContainer.new()
	box.name = "EmblemCell"
	box.add_theme_constant_override("separation", 3)
	box.add_child(icon)
	box.add_child(_make_badge(team, 16.0))
	_grid.add_child(box)


func _add_label(text: String, color: Color, right: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	_grid.add_child(l)
	return l


func apply_scale() -> void:
	_grid.add_theme_constant_override("h_separation", roundi(UiScale.dp(12.0)))
	_grid.add_theme_constant_override("v_separation", roundi(UiScale.dp(4.0)))
	for l: Label in _head_labels:
		l.add_theme_font_size_override("font_size", UiScale.font(12.0))
	for i: int in range(2, _head_labels.size()):
		_head_labels[i].custom_minimum_size.x = UiScale.dp(VALUE_MIN_DP)
	for l: Label in _name_labels:
		l.add_theme_font_size_override("font_size", UiScale.font(15.0))
	for l: Label in _value_labels:
		l.add_theme_font_size_override("font_size", UiScale.font(15.0))
		l.custom_minimum_size.x = UiScale.dp(VALUE_MIN_DP)
	for icon: EmblemIcon in _icons:
		icon.custom_minimum_size = Vector2.ONE * UiScale.dp(24.0)
	for entry: Dictionary in _badges:
		(entry["badge"] as TeamBadge).set_badge_size(UiScale.dp(entry["dp"] as float))


## Rows as text, for tests: "PLAYER 1 +$3,500 2 1; PLAYER 2 ...".
func get_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for row: Dictionary in _rows:
		var cells: PackedStringArray = row["cells"]
		parts.append("%s %s" % [row["label"], " ".join(cells)])
	return "; ".join(parts)


## Number of team badges in the table (0 without teams).
func badge_count() -> int:
	return _badges.size()


func get_badge_teams() -> PackedInt32Array:
	var out := PackedInt32Array()
	for entry: Dictionary in _badges:
		out.append((entry["badge"] as TeamBadge).get_team())
	return out


func row_count() -> int:
	return _rows.size()


func get_row_cells(index: int) -> PackedStringArray:
	return _rows[index]["cells"] as PackedStringArray


## Height the table wants (used to size the scroll area).
func content_height() -> float:
	return _grid.get_combined_minimum_size().y
