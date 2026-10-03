class_name ShopQuantity
extends RefCounted
## The quantity buttons of the shop detail: BUY x1 / x5 / MAX and SELL x1 / ALL. Pure helpers: what each
## button would submit and whether the simulation allows it. The rules stay in the simulation; this only
## asks `Simulation.validate_action` and works out the biggest legal purchase.

const BUY_X5: int = 5


## A buy action for `qty` bundles.
static func buy_action(tank_id: int, item: String, qty: int) -> Dictionary:
	return {"kind": "buy", "tank": tank_id, "item": item, "qty": qty}


static func sell_action(tank_id: int, item: String, qty: int) -> Dictionary:
	return {"kind": "sell", "tank": tank_id, "item": item, "qty": qty}


## The simulation's verdict on buying `qty` bundles ("" = allowed).
static func buy_error(state: MatchState, tank_id: int, item: String, qty: int) -> String:
	return Simulation.validate_action(state, buy_action(tank_id, item, qty))


## How many bundles MAX buys: as many as the money and the inventory cap (99 units) allow, 0 when even one
## bundle is refused (locked, unlimited, wrong phase, too poor, full).
@warning_ignore("integer_division")
static func max_bundles(state: MatchState, tank_id: int, item: String) -> int:
	if buy_error(state, tank_id, item, 1) != "":
		return 0
	var def: Dictionary = Catalog.get_def(item)
	var tank: TankState = state.tanks[tank_id]
	var price: int = def["price"]
	var bundle: int = maxi(1, def["bundle"] as int)
	var by_money: int = tank.money / price if price > 0 else SimConstants.INVENTORY_CAP
	var by_cap: int = (SimConstants.INVENTORY_CAP - tank.stock_of(item)) / bundle
	var n: int = clampi(mini(by_money, by_cap), 0, SimConstants.INVENTORY_CAP)
	# The simulation has the last word (guards against any rule the formula does not know about).
	while n > 1 and buy_error(state, tank_id, item, n) != "":
		n -= 1
	return n


## Units a SELL ALL would sell (everything owned).
static func sell_all_units(state: MatchState, tank_id: int, item: String) -> int:
	return (state.tanks[tank_id] as TankState).stock_of(item)


## Credits SELL ALL would pay.
static func sell_all_refund(state: MatchState, tank_id: int, item: String) -> int:
	var owned: int = sell_all_units(state, tank_id, item)
	return Economy.sell_refund(Catalog.get_def(item), owned, owned)
