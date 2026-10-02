class_name PlayerLooks
extends RefCounted
## Which colour and emblem each player picked on the setup screen. This is presentation only:
## the simulation never sees it (TankState.color_index stays the player id), so it cannot
## affect fingerprints or saves. It travels in the autosave's `meta` instead.
##
## Defaults are the identity (player i = colour i = emblem i), which is what the palette was
## designed around. Setup keeps both lists free of duplicates, so two tanks never share a
## colour or an emblem.

static var _colors: PackedInt32Array = PackedInt32Array()
static var _emblems: PackedInt32Array = PackedInt32Array()


static func reset() -> void:
	_colors = PackedInt32Array()
	_emblems = PackedInt32Array()


static func set_looks(colors: PackedInt32Array, emblems: PackedInt32Array) -> void:
	_colors = colors.duplicate()
	_emblems = emblems.duplicate()


static func color_index(player: int) -> int:
	if player >= 0 and player < _colors.size():
		return posmod(_colors[player], NeonPalette.TANK_COLORS.size())
	return posmod(player, NeonPalette.TANK_COLORS.size())


static func emblem_index(player: int) -> int:
	if player >= 0 and player < _emblems.size():
		return posmod(_emblems[player], NeonPalette.EMBLEM_COUNT)
	return posmod(player, NeonPalette.EMBLEM_COUNT)


static func color(player: int) -> Color:
	return NeonPalette.tank_color(color_index(player))


static func emblem(player: int) -> int:
	return emblem_index(player)


## For the autosave meta.
static func to_dict(count: int) -> Dictionary:
	var colors: Array = []
	var emblems: Array = []
	for i: int in range(count):
		colors.append(color_index(i))
		emblems.append(emblem_index(i))
	return {"colors": colors, "emblems": emblems}


## Restores from `to_dict` output; anything malformed falls back to the defaults.
static func from_dict(d: Dictionary) -> void:
	reset()
	var colors: PackedInt32Array = PackedInt32Array()
	var emblems: PackedInt32Array = PackedInt32Array()
	var c: Variant = d.get("colors", [])
	var e: Variant = d.get("emblems", [])
	if typeof(c) == TYPE_ARRAY and typeof(e) == TYPE_ARRAY and (c as Array).size() == (e as Array).size():
		for v: Variant in (c as Array):
			colors.append(int(v))
		for v: Variant in (e as Array):
			emblems.append(int(v))
		set_looks(colors, emblems)
