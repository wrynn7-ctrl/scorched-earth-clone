class_name CpuShop
extends RefCounted
## Computer players shop instantly: their purchases come from AiPlayer.shop_actions and go
## through the same `submit` callable the human shop uses (so they are validated, logged and
## autosaved like any other action), and there is never a hand-over screen for them.

const MAX_FALLBACKS: int = 2


## The controller level (SimConstants.CTRL_*) of tank `id`.
static func level_of(state: MatchState, id: int) -> int:
	var c: PackedInt32Array = state.settings.controllers
	return c[id] if id >= 0 and id < c.size() else SimConstants.CTRL_HUMAN


static func is_cpu(state: MatchState, id: int) -> bool:
	return level_of(state, id) != SimConstants.CTRL_HUMAN


static func human_count(state: MatchState) -> int:
	var n: int = 0
	for t: TankState in state.tanks:
		if not is_cpu(state, t.id):
			n += 1
	return n


## True when the device is passed between people, i.e. at least two humans share it. With one
## human (the rest CPU) or none, hand-over screens would only be noise.
static func needs_handover(state: MatchState) -> bool:
	return human_count(state) >= 2


## Shops for every CPU tank that is not ready yet. `submit` takes an action Dictionary and
## returns "" or an error key. Returns what each of them bought, in tank order:
## [{tank, level, items: [{id, units}]}] (units, not bundles; sells are not listed).
static func run(state: MatchState, submit: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: TankState in state.tanks:
		if not is_cpu(state, t.id) or t.ready:
			continue
		out.append({"tank": t.id, "level": level_of(state, t.id), "items": _shop_one(state, t.id, submit)})
	return out


static func _shop_one(state: MatchState, id: int, submit: Callable) -> Array[Dictionary]:
	var bought: Array[Dictionary] = []
	for a: Dictionary in AiPlayer.shop_actions(state, id):
		var err: String = submit.call(a)
		if err != "":
			push_warning("CpuShop: tank %d action %s rejected: %s" % [id, str(a), err])
			continue
		if a["kind"] == "buy":
			_add(bought, a["item"] as String, (a["qty"] as int) * ((Catalog.get_def(a["item"] as String).get("bundle", 1)) as int))
	# Never leave a CPU unready: that would hold the whole table up.
	if not state.tanks[id].ready:
		var err2: String = submit.call({"kind": "ready", "tank": id})
		if err2 != "":
			push_warning("CpuShop: tank %d could not ready: %s" % [id, err2])
	return bought


static func _add(items: Array[Dictionary], id: String, units: int) -> void:
	for it: Dictionary in items:
		if it["id"] == id:
			it["units"] = (it["units"] as int) + units
			return
	items.append({"id": id, "units": units})


## "Pulse Missile ×5, Glow Shield" (or "nothing").
static func describe(items: Array[Dictionary]) -> String:
	if items.is_empty():
		return TranslationServer.translate("SUM_CPU_NONE")
	var parts: PackedStringArray = PackedStringArray()
	for it: Dictionary in items:
		var name: String = TranslationServer.translate("ITEM_" + (it["id"] as String).to_upper())
		var units: int = it["units"]
		parts.append(TranslationServer.translate("SUM_ITEM_QTY_FMT") % [name, units] if units > 1 else name)
	return ", ".join(parts)
