@warning_ignore_start("integer_division")
class_name StateSerial
extends RefCounted
## Fixed-order binary serialization of a MatchState (docs/ARCHITECTURE.md sections 14, 22,
## 24). It feeds both Simulation.fingerprint and the SaveCodec snapshot, so the two can never
## drift apart. Never hash var_to_bytes or Dictionary iteration order. Any new state field
## must be added to write() AND read() here, and SaveCodec.SAVE_VERSION bumped.

const MAX_TANKS_READ: int = 8
const MAX_WELLS_READ: int = 64
const MAX_INVENTORY_READ: int = 1024

# Sanity ceilings used by validate(); far above anything play can reach.
const MAX_FUEL: int = 100000
const MAX_MONEY: int = 1_000_000_000
const MAX_COUNTER: int = 1_000_000_000  # kills, damage_dealt, turn_number
const WELL_SLACK_Y: int = 64  # wells may sit a little above or below the map (shield bubbles, bedrock)
const M32: int = 0xFFFFFFFF
const INVALID: String = "invalid_state"


static func phase_code(phase: String) -> int:
	if phase == SimConstants.PHASE_AIM:
		return 0
	if phase == SimConstants.PHASE_ROUND_OVER:
		return 1
	if phase == SimConstants.PHASE_MATCH_OVER:
		return 2
	return 3  # shop


static func phase_name(code: int) -> String:
	match code:
		0:
			return SimConstants.PHASE_AIM
		1:
			return SimConstants.PHASE_ROUND_OVER
		2:
			return SimConstants.PHASE_MATCH_OVER
		3:
			return SimConstants.PHASE_SHOP
	return ""


## The state as bytes (terrain last).
static func serialize(state: MatchState) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	write(b, state)
	return b.data_array


## First 16 hex chars of SHA-256 over `bytes`.
static func hash_hex(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode().substr(0, 16)


static func write(b: StreamPeerBuffer, state: MatchState) -> void:
	var st: MatchSettings = state.settings
	b.put_64(st.seed)
	b.put_32(st.num_tanks)
	b.put_32(st.rounds)
	b.put_32(st.wind_max)
	b.put_64(st.start_money)
	b.put_32(1 if st.full_unlocked else 0)
	b.put_32(st.controllers.size())
	for c: int in st.controllers:
		b.put_32(c)
	b.put_32(st.mode)
	b.put_32(st.teams.size())
	for tm: int in st.teams:
		b.put_32(tm)
	b.put_32(1 if st.friendly_fire else 0)
	b.put_64(state.seed)
	b.put_32(state.round_index)
	b.put_32(state.wind)
	for w: int in state.wind_rng_state:
		b.put_64(w)
	b.put_32(state.current_tank)
	b.put_32(state.turn_number)
	b.put_32(state.sudden_death_cycles)
	b.put_32(phase_code(state.phase))
	b.put_32(state.tanks.size())
	for t: TankState in state.tanks:
		_write_tank(b, t)
	b.put_32(state.wells.size())
	for wl: Dictionary in state.wells:
		b.put_32(wl["owner"])
		b.put_32(wl["x"])
		b.put_32(wl["y"])
		b.put_32(wl["expires_turn"])
	if state.terrain == null:
		b.put_32(0)
		b.put_32(0)
	else:
		b.put_32(state.terrain.width)
		b.put_32(state.terrain.height)
		b.put_data(state.terrain.cells)


static func _write_tank(b: StreamPeerBuffer, t: TankState) -> void:
	b.put_32(t.id)
	b.put_32(t.team)
	b.put_32(t.x)
	b.put_32(t.y)
	b.put_32(t.health)
	b.put_32(t.angle)
	b.put_32(t.power)
	b.put_32(1 if t.alive else 0)
	b.put_32(t.color_index)
	b.put_64(t.money)
	b.put_32(t.kills)
	b.put_64(t.damage_dealt)
	b.put_32(t.round_wins)
	b.put_32(1 if t.ready else 0)
	b.put_32(t.fuel)
	b.put_32(t.shield_type)
	b.put_32(t.shield_hp)
	b.put_32(t.repulsor_charge)
	b.put_32(t.last_fire_angle)
	b.put_32(t.last_fire_power)
	b.put_32(t.last_fire_weapon)
	b.put_32(t.last_fire_x)
	b.put_32(t.last_fire_y)
	b.put_32(t.last_fire_wind)
	b.put_32(t.last_fire_turn)
	b.put_32(t.love)
	b.put_32(t.inventory.size())
	for n: int in t.inventory:
		b.put_32(n)


## Parses what write() produced. Returns null if the data is truncated or inconsistent.
static func read(b: StreamPeerBuffer) -> MatchState:
	var s := MatchState.new()
	if b.get_available_bytes() < 8 + 4 * 3 + 8 + 4 + 8 + 4 + 4 + 4 + 4 + 4 + 32 + 12:
		return null
	var st: MatchSettings = s.settings
	st.seed = b.get_64()
	st.num_tanks = b.get_32()
	st.rounds = b.get_32()
	st.wind_max = b.get_32()
	st.start_money = b.get_64()
	st.full_unlocked = b.get_32() != 0
	var n_ctrl: int = b.get_32()
	if n_ctrl < 0 or n_ctrl > MAX_TANKS_READ or b.get_available_bytes() < n_ctrl * 4 + 4 + 8 + 4 * 3 + 4 + 32 + 12:
		return null
	var ctrl := PackedInt32Array()
	ctrl.resize(n_ctrl)
	for i: int in range(n_ctrl):
		ctrl[i] = b.get_32()
	st.controllers = ctrl
	st.mode = b.get_32()
	var n_teams: int = b.get_32()
	if n_teams < 0 or n_teams > MAX_TANKS_READ or b.get_available_bytes() < n_teams * 4 + 4 + 8 + 4 * 3 + 4 + 32 + 12:
		return null
	var teams := PackedInt32Array()
	teams.resize(n_teams)
	for i: int in range(n_teams):
		teams[i] = b.get_32()
	st.teams = teams
	st.friendly_fire = b.get_32() != 0
	s.seed = b.get_64()
	s.round_index = b.get_32()
	s.wind = b.get_32()
	var words: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
	for i: int in range(4):
		words[i] = b.get_64()
	s.wind_rng_state = words
	s.current_tank = b.get_32()
	s.turn_number = b.get_32()
	s.sudden_death_cycles = b.get_32()
	var phase: String = phase_name(b.get_32())
	if phase == "":
		return null
	s.phase = phase
	var n_tanks: int = b.get_32()
	if n_tanks < 0 or n_tanks > MAX_TANKS_READ:
		return null
	for i: int in range(n_tanks):
		var t: TankState = _read_tank(b)
		if t == null:
			return null
		s.tanks.append(t)
	if b.get_available_bytes() < 4:
		return null
	var n_wells: int = b.get_32()
	if n_wells < 0 or n_wells > MAX_WELLS_READ or b.get_available_bytes() < n_wells * 16 + 8:
		return null
	for i: int in range(n_wells):
		var owner: int = b.get_32()
		var wx: int = b.get_32()
		var wy: int = b.get_32()
		var ex: int = b.get_32()
		s.wells.append({"owner": owner, "x": wx, "y": wy, "expires_turn": ex})
	var w: int = b.get_32()
	var h: int = b.get_32()
	if w < 0 or h < 0 or w > 65536 or h > 65536 or w * h > b.get_available_bytes():
		return null
	if w > 0:
		var res: Array = b.get_data(w * h)
		if res[0] != OK:
			return null
		var terrain := Terrain.new(0, h)
		terrain.width = w
		terrain.cells = res[1]
		s.terrain = terrain
	return s


static func _read_tank(b: StreamPeerBuffer) -> TankState:
	if b.get_available_bytes() < 9 * 4 + 8 + 4 + 8 + 6 * 4 + 7 * 4 + 4 + 4:
		return null
	var t := TankState.new()
	t.id = b.get_32()
	t.team = b.get_32()
	t.x = b.get_32()
	t.y = b.get_32()
	t.health = b.get_32()
	t.angle = b.get_32()
	t.power = b.get_32()
	t.alive = b.get_32() != 0
	t.color_index = b.get_32()
	t.money = b.get_64()
	t.kills = b.get_32()
	t.damage_dealt = b.get_64()
	t.round_wins = b.get_32()
	t.ready = b.get_32() != 0
	t.fuel = b.get_32()
	t.shield_type = b.get_32()
	t.shield_hp = b.get_32()
	t.repulsor_charge = b.get_32()
	t.last_fire_angle = b.get_32()
	t.last_fire_power = b.get_32()
	t.last_fire_weapon = b.get_32()
	t.last_fire_x = b.get_32()
	t.last_fire_y = b.get_32()
	t.last_fire_wind = b.get_32()
	t.last_fire_turn = b.get_32()
	t.love = b.get_32()
	var n_inv: int = b.get_32()
	if n_inv != Catalog.count() or n_inv > MAX_INVENTORY_READ or b.get_available_bytes() < n_inv * 4:
		return null
	var inv: PackedInt32Array = PackedInt32Array()
	inv.resize(n_inv)
	for i: int in range(n_inv):
		inv[i] = b.get_32()
	t.inventory = inv
	return t


# --- range validation -----------------------------------------------------------------------

## Returns "" if `state` is something the simulation can produce, otherwise a short reason.
## Used by SaveCodec.decode (which reports every reason as "invalid_state"): a save is only
## protected by a checksum, so anyone can re-seal a tampered state, and a state like
## current_tank 99 would soft-lock the match. Cost is O(tanks x catalog), never per cell.
static func validate(state: MatchState) -> String:
	var err: String = _validate_header(state)
	if err != "":
		return err
	var n: int = state.tanks.size()
	for t: TankState in state.tanks:
		err = _validate_tank(state, t, n)
		if err != "":
			return "tank %d: %s" % [t.id, err]
	err = _validate_flow(state)
	if err != "":
		return err
	return _validate_wells(state, n)


static func _validate_header(state: MatchState) -> String:
	var st: MatchSettings = state.settings
	if st.num_tanks < SimConstants.MIN_TANKS or st.num_tanks > SimConstants.MAX_TANKS:
		return "settings.num_tanks %d" % st.num_tanks
	if st.rounds < SimConstants.MIN_ROUNDS or st.rounds > SimConstants.MAX_ROUNDS:
		return "settings.rounds %d" % st.rounds
	if not st.full_unlocked:
		if st.num_tanks > SimConstants.FREE_MAX_TANKS:
			return "settings.num_tanks %d in the free version" % st.num_tanks
		if st.rounds > SimConstants.FREE_MAX_ROUNDS:
			return "settings.rounds %d in the free version" % st.rounds
	if st.wind_max < 0 or st.wind_max > SimConstants.WIND_MAX:
		return "settings.wind_max %d" % st.wind_max
	if st.start_money < 0 or st.start_money > SimConstants.MAX_START_MONEY:
		return "settings.start_money %d" % st.start_money
	if st.mode < SimConstants.MODE_STANDARD or st.mode > SimConstants.MODE_MAX:
		return "settings.mode %d" % st.mode
	if st.mode == SimConstants.MODE_LOVE:
		if st.num_tanks != 2 or st.rounds != 1 or st.wind_max > SimConstants.LOVE_WIND_MAX or st.start_money != 0:
			return "love mode settings (tanks %d, rounds %d, wind_max %d, money %d)" % [st.num_tanks,
					st.rounds, st.wind_max, st.start_money]
	if st.mode == SimConstants.MODE_LOVE and not st.teams.is_empty():
		return "settings.teams in love mode"
	if st.validate() != "":
		return "settings.teams %s with %d tanks" % [str(st.teams), st.num_tanks]
	if st.controllers.size() != st.num_tanks:
		return "settings.controllers size %d != num_tanks %d" % [st.controllers.size(), st.num_tanks]
	var top: int = SimConstants.CTRL_MAX if st.full_unlocked else SimConstants.CTRL_FREE_MAX
	for c: int in st.controllers:
		if c < SimConstants.CTRL_HUMAN or c > top:
			return "settings.controllers value %d" % c
	if state.tanks.size() != st.num_tanks:
		return "tank count %d != settings.num_tanks %d" % [state.tanks.size(), st.num_tanks]
	if state.phase != SimConstants.PHASE_AIM and state.phase != SimConstants.PHASE_SHOP \
			and state.phase != SimConstants.PHASE_MATCH_OVER:
		return "phase '%s'" % state.phase
	if state.round_index < -1 or state.round_index >= st.rounds:
		return "round_index %d" % state.round_index
	if state.wind < -st.wind_max or state.wind > st.wind_max:
		return "wind %d beyond +-%d" % [state.wind, st.wind_max]
	if state.turn_number < 0 or state.turn_number > MAX_COUNTER:
		return "turn_number %d" % state.turn_number
	var err: String = _validate_sudden_death(state)
	if err != "":
		return err
	if state.current_tank < 0 or state.current_tank >= state.tanks.size():
		return "current_tank %d" % state.current_tank
	if state.wind_rng_state.size() != 4:
		return "wind_rng_state size"
	var any_set: bool = false
	for w: int in state.wind_rng_state:
		if w < 0 or w > M32:
			return "wind_rng_state word %d" % w
		any_set = any_set or w != 0
	# Only a match that has not started yet has an unseeded wind stream (all zero words).
	if not any_set and state.round_index >= 0:
		return "wind_rng_state is all zero"
	return ""


## sudden_death_cycles (section 40): none before the sudden-death turn, never in love mode, and at most
## one cycle per turn played since the threshold (the wrap that reaches it counts).
static func _validate_sudden_death(state: MatchState) -> String:
	var cycles: int = state.sudden_death_cycles
	if cycles < 0:
		return "sudden_death_cycles %d" % cycles
	if cycles == 0:
		return ""
	if state.settings.mode == SimConstants.MODE_LOVE or state.round_index < 0:
		return "sudden_death_cycles %d outside a standard round" % cycles
	var threshold: int = Simulation.sudden_death_turn(state.settings)
	if state.turn_number < threshold or cycles > state.turn_number - threshold + 1:
		return "sudden_death_cycles %d at turn %d (threshold %d)" % [cycles, state.turn_number, threshold]
	return ""


## Phase, round, terrain and who-may-act consistency.
static func _validate_flow(state: MatchState) -> String:
	var rounds: int = state.settings.rounds
	var before_start: bool = state.round_index == -1
	if before_start and state.phase != SimConstants.PHASE_SHOP:
		return "round_index -1 outside the shop"
	if state.phase == SimConstants.PHASE_MATCH_OVER and state.round_index != rounds - 1:
		return "match_over before the last round"
	if state.phase == SimConstants.PHASE_SHOP and state.round_index == rounds - 1:
		return "shop after the last round"
	var terrain: Terrain = state.terrain
	if terrain == null:
		if not before_start:
			return "terrain missing"
	else:
		if before_start:
			return "terrain before the first round"
		if terrain.width != SimConstants.WORLD_W or terrain.height != SimConstants.WORLD_H:
			return "terrain size %dx%d" % [terrain.width, terrain.height]
		if terrain.cells.size() != terrain.width * terrain.height:
			return "terrain cell count"
	if state.settings.mode == SimConstants.MODE_LOVE:
		var err: String = _validate_love_flow(state)
		if err != "":
			return err
	return _validate_round_flow(state)


## Who may be alive in each phase. A round is over exactly when the living tanks form at most one
## team (section 39), so "aim" needs two teams alive and a finished round (shop / match_over after
## a round) at most one. Love mode ends by a full meter instead and is exempt from the second rule.
static func _validate_round_flow(state: MatchState) -> String:
	var teams_alive: int = 0
	var alive: int = 0
	var seen: int = 0
	for t: TankState in state.tanks:
		if t.alive:
			alive += 1
			if (seen & (1 << t.team)) == 0:
				seen |= 1 << t.team
				teams_alive += 1
	if state.phase == SimConstants.PHASE_AIM:
		if teams_alive < 2:
			return "aim phase with %d tank(s) alive on %d team(s)" % [alive, teams_alive]
		if not state.tanks[state.current_tank].alive:
			return "current_tank %d is dead" % state.current_tank
	elif state.round_index >= 0 and state.settings.mode != SimConstants.MODE_LOVE and teams_alive > 1:
		return "round over with %d teams alive" % teams_alive
	return ""


## Love mode (section 37) has no shop; a meter is full exactly when the match is over.
static func _validate_love_flow(state: MatchState) -> String:
	if state.phase == SimConstants.PHASE_SHOP:
		return "shop in love mode"
	var most: int = 0
	for t: TankState in state.tanks:
		most = maxi(most, t.love)
	if state.phase == SimConstants.PHASE_AIM and most >= SimConstants.LOVE_MAX:
		return "full love meter during aim"
	if state.phase != SimConstants.PHASE_MATCH_OVER:
		return ""
	# A finished match: the shooter who filled the other tank's meter holds the one round win
	# (love.gd). Exactly one meter is full and its owner is never the winner.
	var full: int = 0
	for t: TankState in state.tanks:
		if t.love >= SimConstants.LOVE_MAX:
			full += 1
	if full != 1:
		return "love match over with %d full meters" % full
	for t: TankState in state.tanks:
		var expected: int = 0 if t.love >= SimConstants.LOVE_MAX else 1
		if t.round_wins != expected:
			return "love match over: tank %d round_wins %d (expected %d)" % [t.id, t.round_wins, expected]
	return ""


static func _validate_tank(state: MatchState, t: TankState, n: int) -> String:
	var st: MatchSettings = state.settings
	if t.id != state.tanks.find(t):
		return "id does not match its position"
	if t.team != st.team_of(t.id):
		return "team %d does not match the settings" % t.team
	if t.team < 0 or t.team >= SimConstants.MAX_TANKS or t.color_index < 0 or t.color_index >= SimConstants.MAX_TANKS:
		return "team/color"
	if t.health < 0 or t.health > SimConstants.MAX_HEALTH:
		return "health %d" % t.health
	if t.alive != (t.health > 0):
		return "alive=%s with health %d" % [str(t.alive), t.health]
	if t.angle < 0 or t.angle > SimConstants.MAX_ANGLE:
		return "angle %d" % t.angle
	if t.power < SimConstants.MIN_POWER or t.power > SimConstants.MAX_POWER:
		return "power %d" % t.power
	if t.money < 0 or t.money > MAX_MONEY:
		return "money %d" % t.money
	if t.kills < 0 or t.kills > MAX_COUNTER or t.damage_dealt < 0 or t.damage_dealt > MAX_COUNTER:
		return "kills/damage_dealt"
	if t.round_wins < 0 or t.round_wins > st.rounds:
		return "round_wins %d" % t.round_wins
	if t.ready and state.phase != SimConstants.PHASE_SHOP:
		return "ready outside the shop"
	if t.fuel < 0 or t.fuel > MAX_FUEL:
		return "fuel %d" % t.fuel
	if t.repulsor_charge < 0 or t.repulsor_charge > SimConstants.REPULSOR_CHARGE:
		return "repulsor_charge %d" % t.repulsor_charge
	if t.love < 0 or t.love > SimConstants.LOVE_MAX:
		return "love %d" % t.love
	if t.love != 0 and st.mode != SimConstants.MODE_LOVE:
		return "love %d outside love mode" % t.love
	var err: String = _validate_last_fire(state, t)
	if err != "":
		return err
	err = _validate_shield(t, st.full_unlocked)
	if err != "":
		return err
	err = _validate_inventory(t, st.full_unlocked)
	if err != "":
		return err
	if state.terrain != null:
		var half: int = SimConstants.TANK_W / 2
		if t.x - half < 0 or t.x + half > SimConstants.WORLD_W:
			return "box off the map (x %d)" % t.x
		if t.y < 0 or t.y > SimConstants.WORLD_H:
			return "y %d" % t.y
	return ""


## last_fire_* (section 27): either the reset record, or a plausible shot with a real weapon.
## x/y may lie one cell outside the map (a beam that left it); -1 doubles as "none".
static func _validate_last_fire(state: MatchState, t: TankState) -> String:
	if t.last_fire_weapon == -1:
		if t.last_fire_angle != 0 or t.last_fire_power != 0 or t.last_fire_x != -1 or t.last_fire_y != -1 \
				or t.last_fire_wind != 0 or t.last_fire_turn != -1:
			return "last_fire fields set without a weapon"
		return ""
	var is_heart: bool = t.last_fire_weapon == Catalog.HEART_INDEX
	if is_heart:
		if state.settings.mode != SimConstants.MODE_LOVE:
			return "heart fired outside love mode"
	elif t.last_fire_weapon < 0 or t.last_fire_weapon >= Catalog.count() \
			or not Catalog.is_weapon(Catalog.id_at(t.last_fire_weapon)):
		return "last_fire_weapon %d" % t.last_fire_weapon
	elif state.settings.mode == SimConstants.MODE_LOVE:
		return "catalog weapon fired in love mode"
	elif not state.settings.full_unlocked and Catalog.get_def(Catalog.id_at(t.last_fire_weapon))["tier"] == "full":
		return "last_fire_weapon %d is a full-version weapon in a free match" % t.last_fire_weapon
	if t.last_fire_angle < 0 or t.last_fire_angle > SimConstants.MAX_ANGLE:
		return "last_fire_angle %d" % t.last_fire_angle
	if t.last_fire_power < SimConstants.MIN_POWER or t.last_fire_power > SimConstants.MAX_POWER:
		return "last_fire_power %d" % t.last_fire_power
	if t.last_fire_x < -1 or t.last_fire_x > SimConstants.WORLD_W \
			or t.last_fire_y < -1 or t.last_fire_y > SimConstants.WORLD_H:
		return "last_fire impact (%d, %d)" % [t.last_fire_x, t.last_fire_y]
	if absi(t.last_fire_wind) > state.settings.wind_max:
		return "last_fire_wind %d" % t.last_fire_wind
	if t.last_fire_turn < 0 or t.last_fire_turn > state.turn_number:
		return "last_fire_turn %d" % t.last_fire_turn
	return ""


static func _validate_shield(t: TankState, full_unlocked: bool) -> String:
	if t.shield_type == -1:
		return "" if t.shield_hp == 0 else "shield_hp %d without a shield" % t.shield_hp
	var id: String = Catalog.id_at(t.shield_type)
	if id == "" or not ItemDefs.has(id) or ItemDefs.get_def(id)["behavior"] != "shield":
		return "shield_type %d" % t.shield_type
	if not full_unlocked and Catalog.get_def(id)["tier"] == "full":
		return "shield_type %d is a full-version item" % t.shield_type
	var max_hp: int = ItemDefs.get_def(id)["hp"]
	if t.shield_hp < 1 or t.shield_hp > max_hp:
		return "shield_hp %d (max %d)" % [t.shield_hp, max_hp]
	return ""


## A free-version match can never hold a full-tier item (buy refuses it, the starting stock has
## none), so a non-zero count there means a tampered save (section 32).
static func _validate_inventory(t: TankState, full_unlocked: bool) -> String:
	if t.inventory.size() != Catalog.count():
		return "inventory size"
	for i: int in range(t.inventory.size()):
		var units: int = t.inventory[i]
		if units < 0 or units > SimConstants.INVENTORY_CAP:
			return "inventory[%d] = %d" % [i, units]
		if units != 0 and not full_unlocked and Catalog.get_def(Catalog.id_at(i))["tier"] == "full":
			return "inventory[%d] is a full-version item in a free match" % i
	if t.inventory[Catalog.index_of(Catalog.SPARK_DART)] != 0:
		return "spark_dart stored"
	return ""


## Wells: one per owner at most, in ascending owner order, owner a real tank, coordinates near the map.
static func _validate_wells(state: MatchState, n: int) -> String:
	var last_owner: int = -1
	for w: Dictionary in state.wells:
		var owner: int = w["owner"]
		if owner < 0 or owner >= n:
			return "well owner %d" % owner
		if owner <= last_owner:
			return "wells not in strict owner order"
		last_owner = owner
		var wx: int = w["x"]
		var wy: int = w["y"]
		if wx < 0 or wx >= SimConstants.WORLD_W or wy < -WELL_SLACK_Y or wy > SimConstants.WORLD_H + WELL_SLACK_Y:
			return "well at (%d, %d)" % [wx, wy]
		var ex: int = w["expires_turn"]
		if ex < 0 or ex > state.turn_number + 2 * SimConstants.MAX_TANKS:
			return "well expires_turn %d" % ex
	return ""
