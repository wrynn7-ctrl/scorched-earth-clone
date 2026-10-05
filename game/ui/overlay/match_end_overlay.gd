class_name MatchEndOverlay
extends OverlayPanel
## Final screen: match result and the standings (rank order from Simulation.standings), with
## NEW MATCH / TITLE.

signal new_match_pressed
signal title_pressed

var _title: Label = null
var _sub: Label = null
var _table: StatTable = null


func _init() -> void:
	super._init()
	name = "MatchEndOverlay"
	_title = add_title("")
	_sub = add_label("", 14.0)
	_table = add_stat_table()
	begin_row()
	add_button(tr("OVERLAY_NEW_MATCH"), 150.0).pressed.connect(func() -> void: new_match_pressed.emit())
	add_button(tr("OVERLAY_TITLE"), 110.0).pressed.connect(func() -> void: title_pressed.emit())
	end_container()
	_buttons[0].name = "NewMatch"
	_buttons[1].name = "Title"


## order: tank ids best first (Simulation.standings). rows: [{id, wins, damage, kills}].
## The top player is the winner unless the top two are level on every tie-break
## (wins, damage, kills), which is shown as a draw.
func show_standings(order: Array[int], rows: Array[Dictionary]) -> void:
	var by_id: Dictionary = {}
	for r: Dictionary in rows:
		by_id[r["id"]] = r
	var winner: int = order[0] if not order.is_empty() else -1
	if order.size() >= 2 and _level(by_id[order[0]] as Dictionary, by_id[order[1]] as Dictionary):
		winner = -1
	if winner >= 0:
		_title.text = tr("OVERLAY_MATCH_WINNER") % PlayerNames.label(winner)
		_title.add_theme_color_override("font_color", PlayerLooks.color(winner))
	else:
		_title.text = tr("OVERLAY_DRAW")
		_title.add_theme_color_override("font_color", NeonPalette.TEXT)
	_sub.text = tr("OVERLAY_FINAL_STANDINGS")
	var table_rows: Array[Dictionary] = []
	for rank: int in range(order.size()):
		var id: int = order[rank]
		var r: Dictionary = by_id[id]
		table_rows.append({
			"id": id,
			"label": "%d. %s" % [rank + 1, PlayerNames.label(id)],
			"cells": PackedStringArray([str(r["wins"]), HudFormat.group(r["damage"] as int), str(r["kills"])]),
		})
	_table.set_data(PackedStringArray([tr("SUM_WINS"), tr("SUM_DAMAGE"), tr("SUM_KILLS")]), table_rows, winner)
	open()
	if is_inside_tree():
		apply_scale()
		_refit_next_frame()


## Team games (ARCHITECTURE sections 39 and 42): `team_order` is Simulation.team_standings (team ids, best first),
## `order` the per-tank standings, `teams` the team of every tank. Each team gets a header row with its totals
## (rounds won, damage, kills), its members under it in tank-standings order. Level on every tie-break at the
## top is shown as a draw, as without teams.
func show_team_standings(team_order: Array[int], order: Array[int], rows: Array[Dictionary],
		teams: PackedInt32Array) -> void:
	var by_id: Dictionary = {}
	for r: Dictionary in rows:
		by_id[r["id"]] = r
	var totals: Dictionary = {}
	for team: int in team_order:
		var t: Dictionary = {"wins": 0, "damage": 0, "kills": 0}
		for id: int in order:
			if teams[id] == team:
				var r: Dictionary = by_id[id]
				t["wins"] = maxi(t["wins"] as int, r["wins"] as int)  # teammates share their round wins
				t["damage"] = (t["damage"] as int) + (r["damage"] as int)
				t["kills"] = (t["kills"] as int) + (r["kills"] as int)
		totals[team] = t
	var winner: int = team_order[0] if not team_order.is_empty() else -1
	if team_order.size() >= 2 and _level(totals[team_order[0]] as Dictionary, totals[team_order[1]] as Dictionary):
		winner = -1
	if winner >= 0:
		_title.text = tr("OVERLAY_TEAM_MATCH_WINNER") % TeamStyle.letter(winner)
		_title.add_theme_color_override("font_color", TeamStyle.color(winner))
	else:
		_title.text = tr("OVERLAY_DRAW")
		_title.add_theme_color_override("font_color", NeonPalette.TEXT)
	_sub.text = tr("OVERLAY_FINAL_STANDINGS")
	var table_rows: Array[Dictionary] = []
	for rank: int in range(team_order.size()):
		var team: int = team_order[rank]
		var t: Dictionary = totals[team]
		var lit: bool = team == winner
		table_rows.append({
			"header": true, "team": team, "win": lit,
			"label": "%d. %s" % [rank + 1, TeamStyle.team_name(team)],
			"cells": PackedStringArray([str(t["wins"]), HudFormat.group(t["damage"] as int), str(t["kills"])]),
		})
		for id: int in order:
			if teams[id] != team:
				continue
			var r: Dictionary = by_id[id]
			table_rows.append({
				"id": id, "team": team, "win": lit,
				"label": PlayerNames.label(id),
				"cells": PackedStringArray([str(r["wins"]), HudFormat.group(r["damage"] as int), str(r["kills"])]),
			})
	_table.set_data(PackedStringArray([tr("SUM_WINS"), tr("SUM_DAMAGE"), tr("SUM_KILLS")]), table_rows)
	open()
	if is_inside_tree():
		apply_scale()
		_refit_next_frame()


static func _level(a: Dictionary, b: Dictionary) -> bool:
	return a["wins"] == b["wins"] and a["damage"] == b["damage"] and a["kills"] == b["kills"]


func get_title_text() -> String:
	return _title.text


func get_table() -> StatTable:
	return _table
