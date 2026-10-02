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
	b.put_64(state.seed)
	b.put_32(state.round_index)
	b.put_32(state.wind)
	for w: int in state.wind_rng_state:
		b.put_64(w)
	b.put_32(state.current_tank)
	b.put_32(state.turn_number)
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
	b.put_32(t.inventory.size())
	for n: int in t.inventory:
		b.put_32(n)


## Parses what write() produced. Returns null if the data is truncated or inconsistent.
static func read(b: StreamPeerBuffer) -> MatchState:
	var s := MatchState.new()
	if b.get_available_bytes() < 8 + 4 * 3 + 8 + 4 + 8 + 4 + 4 + 32 + 12:
		return null
	var st: MatchSettings = s.settings
	st.seed = b.get_64()
	st.num_tanks = b.get_32()
	st.rounds = b.get_32()
	st.wind_max = b.get_32()
	st.start_money = b.get_64()
	st.full_unlocked = b.get_32() != 0
	s.seed = b.get_64()
	s.round_index = b.get_32()
	s.wind = b.get_32()
	var words: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
	for i: int in range(4):
		words[i] = b.get_64()
	s.wind_rng_state = words
	s.current_tank = b.get_32()
	s.turn_number = b.get_32()
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
	if b.get_available_bytes() < 9 * 4 + 8 + 4 + 8 + 6 * 4 + 4:
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
	var n_inv: int = b.get_32()
	if n_inv != Catalog.count() or n_inv > MAX_INVENTORY_READ or b.get_available_bytes() < n_inv * 4:
		return null
	var inv: PackedInt32Array = PackedInt32Array()
	inv.resize(n_inv)
	for i: int in range(n_inv):
		inv[i] = b.get_32()
	t.inventory = inv
	return t
