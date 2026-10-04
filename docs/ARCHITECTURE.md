# Architecture & contracts

This is the binding technical spec. If code and this file disagree, ask the lead; don't silently diverge.

## 1. Layers
```
game/core/   SIMULATION  pure, deterministic rules. RefCounted only. No nodes/scenes/IO/float.
game/ai/     AI          reads MatchState, uses core ballistics to plan, returns Action dictionaries.
game/show/   SHOW        renders state, plays back Timelines (animation, particles, sound, haptics).
game/ui/     UI          menus, HUD, shop, settings. Produces Action dictionaries from input.
game/net/    NET         Firebase sync of action lists (M7).
game/platform/           billing, notifications, save location, haptics bridge.
```
Only `Simulation` mutates `MatchState`. Everything else reads state and submits **actions**.

## 2. Numbers (game/core/fixed_math.gd — `class_name FixedMath`)
- **Fixed point Q16.16** stored in `int` (64-bit). `ONE = 65536`.
- `mul(a, b) = (a * b) >> 16`. Operands must satisfy |a|, |b| < 2^31 (product stays < 2^62).
- `div(a, b) = (a << 16) / b` (GDScript int division truncates toward zero). Callers ensure `b != 0`.
- `to_cell(fp) = fp >> 16` (floor). `from_cell(c) = c << 16`.
- **Angles** are integer **tenths of a degree**. Launch angles are 0..1800 (0 = right, 900 = straight up, 1800 = left).
- `sin10(a)`, `cos10(a)` return Q16.16 for any integer tenth-degree (normalized mod 3600). They use a quarter-wave table
  `game/core/trig_table.gd` (`const SIN_Q: PackedInt32Array`, 901 entries for 0..900) **generated once** by
  `tools/gen_trig_table.py` (round-half-away-from-zero of `sin(deg) * 65536`) and committed. Never generated at runtime.
- `isqrt(n)` floor integer square root for n ≥ 0 (bitwise method, no floats).
- 32-bit helpers for hashing/RNG: `M32 = 0xFFFFFFFF`, `mul32(a, b)` = (a*b) mod 2^32 computed via 16-bit halves so no
  intermediate exceeds 2^62, `rotl32(x, k)`.

## 3. Random numbers (game/core/rng.gd — `class_name Rng`)
- Generator: **xoshiro128\*\*** on four 32-bit words (all ops masked with `M32`, multiplies via `mul32`).
  ```
  result = mul32(rotl32(mul32(s1, 5), 7), 9)
  t  = (s1 << 9) & M32
  s2 ^= s0; s3 ^= s1; s1 ^= s2; s0 ^= s3; s2 ^= t; s3 = rotl32(s3, 11)
  ```
- Seeding: `Rng.new(seed: int)`. Let `x = (seed ^ (seed >> 32)) & M32`. Produce s0..s3 with **SplitMix32**:
  ```
  x = (x + 0x9E3779B9) & M32
  z = x
  z = mul32(z ^ (z >> 16), 0x21F0AAAD)
  z = mul32(z ^ (z >> 15), 0x735A2D97)
  z = z ^ (z >> 15)
  ```
  If all four words are 0, set s0 = 1.
- API: `next_u32() -> int`, `range_int(lo: int, hi: int) -> int` (inclusive, **unbiased** via rejection sampling),
  `chance(num: int, den: int) -> bool`, `fork(tag: int) -> Rng` (= `Rng.new((next_u32() << 32) | mul32(tag, 0x9E3779B9))`).
- `tools/ref/rng_ref.py` is a Python reference implementation. Tests compare the first outputs for several seeds
  against values printed by that script.
- **Streams:** never share one stream between unrelated systems, because adding a draw in one would shift the other.
  `MatchState.seed` is the root. Derive with `Rng.new(seed).fork(tag)`, using tags from `SimConstants`:
  `TAG_TERRAIN + round`, `TAG_WIND + round`, `TAG_PLACEMENT + round`, `TAG_AI + tank_id` (M4).
  The per-turn wind drift uses the round's wind stream, stored in the state so it survives save/load.

## 4. World
- World size **1600 × 900 cells** (`SimConstants.WORLD_W/H`). x → right, y → down. One cell = one world unit.
- y ≥ WORLD_H counts as solid bedrock. y < 0 is open sky (projectiles may go above the screen and come back).
  x < 0 or x ≥ WORLD_W: open walls, so a projectile there is lost (wall modes may come later as a match setting).

## 5. Terrain (game/core/terrain.gd — `class_name Terrain`)
- `cells: PackedByteArray`, **column-major**: `index = x * height + y`. `0` = air, `1..15` = dirt materials (strata
  colour bands), `16..255` reserved.
- Column-major keeps each column contiguous (fast settle/carve). The renderer uploads the bytes unchanged as an R8 texture
  of size (height × width) and the shader swaps coordinates.
- API:
  - `static func generate(w: int, h: int, rng: Rng) -> Terrain`: smooth rolling hills from integer value noise /
    midpoint displacement. Surface y stays within [h*30/100, h*85/100]. Materials are bands by depth below the surface.
  - `get_cell(x, y) -> int` (0 outside the sides/above; `Terrain.BEDROCK` = 16 below the map),
    `is_solid(x, y) -> bool`, `surface_y(x) -> int` (first solid y from the top; `height` if the column is empty).
  - `carve_circle(cx, cy, r) -> Rect2i`: clears cells with dx²+dy² ≤ r², returns the changed bounding box (clipped).
  - `add_circle(cx, cy, r, material) -> Rect2i`: fills air cells only (dirt weapons, M3).
  - `settle(x0, x1) -> Array[Dictionary]`: in each column of [x0, x1], solid cells fall straight down until nothing
    floats. Material order is preserved. Returns fall segments `{x, from_y, to_y, length}` for animation.
  - `flatten(x0, x1, y)`: cells above y become air, cells at/below y become solid (tank pads).
  - `write_bytes(buf: StreamPeerBuffer)` / `static read_bytes(buf) -> Terrain`.

## 6. Constants (game/core/sim_constants.gd — `class_name SimConstants`)
Starting values, all tunable in this one file:
| Name | Value | Meaning |
|---|---|---|
| `TICKS_PER_SECOND` | 60 | fixed timestep |
| `GRAVITY` | 9830 (≈0.15 cell/tick²) | Q16.16 added to vy each tick |
| `MAX_SPEED` | 17 × ONE | muzzle speed at power 1000; speed = power × MAX_SPEED / 1000 |
| `WIND_MAX` | 100 | wind ∈ [−WIND_MAX, WIND_MAX], + = blows right |
| `WIND_ACCEL_PER_UNIT` | 13 | Q16.16 added to vx per tick per wind unit |
| `WIND_DRIFT` | 6 | per-turn drift ∈ [−WIND_DRIFT, WIND_DRIFT], clamped |
| `MAX_FLIGHT_TICKS` | 1500 | safety cap → projectile ends with reason "timeout" |
| `TANK_W`, `TANK_H` | 24, 12 | hit box; tank occupies x∈[x−12, x+12), y∈[y−12, y) |
| `BARREL_LEN` | 14 | muzzle = tank top-centre (x, y−TANK_H) + barrel vector |
| `MAX_HEALTH` | 100 | |
| `FALL_SAFE` | 12 | fall ≤ this many cells is free |
| `FALL_DMG_DIV` | 2 | damage = (fall − FALL_SAFE) / FALL_DMG_DIV |

## 7. Ballistics (game/core/ballistics.gd — `class_name Ballistics`)
- Launch: `pos = muzzle (Q16.16)`, `vx = mul(cos10(angle), speed)`, `vy = −mul(sin10(angle), speed)`.
- Per tick (semi-implicit Euler): `vx += wind * WIND_ACCEL_PER_UNIT`; `vy += GRAVITY`; then move in
  `n = max(1, ceil(max(|vx|, |vy|) / ONE))` sub-steps. Sub-step i moves by `(v*(i+1))/n − (v*i)/n` per axis, so the parts
  sum exactly to v. After each sub-step, test collision at the cell `(to_cell(x), to_cell(y))`:
  1. Outside the side walls → end "lost".
  2. Inside an alive tank's hit box → end "tank" (the **shooter's own tank is ignored until the shell has left its box once**).
  3. Terrain solid → end "terrain".
- Record the position at the end of every tick. Also expose a **pure** `trace(state, tank_id, angle, power, weapon_id,
  wind_override, max_ticks) -> Dictionary` used by the trajectory preview and the AI (never mutates state).

## 8. Tanks & match state
- `TankState` (`game/core/tank_state.gd`): `id, team, x, y` (cells; y = ground line the tank rests on), `health`,
  `angle` (tenths, default 450 for tanks left of centre, 1350 for the right), `power` (default 500), `alive`, `color_index`.
- Tanks rest on the **highest** surface point under their width: `y = min(surface_y(c) for c in [x−12, x+12))`.
- `MatchSettings` (`game/core/match_settings.gd`): `seed, num_tanks (2..8), rounds, wind_max`, plus later fields.
- `MatchState` (`game/core/match_state.gd`): `settings, seed, round_index, terrain, tanks: Array[TankState], wind,
  wind_rng_state, current_tank, turn_number, phase` (`"aim" | "round_over" | "match_over"`).
- Placement: n equal segments, tank in each at segment centre ± `range_int(−seg/5, seg/5)`; flatten a pad of
  TANK_W+4 at the surface height under the centre column.

## 9. Actions (input to the simulation)
Plain `Dictionary` so it serialises directly to JSON for saves and Firebase:
```
{"kind": "fire", "tank": 0, "angle": 452, "power": 610, "weapon": "pulse_missile"}
```
`Simulation.validate_action(state, action) -> String` returns `""` if legal, or an error key. Illegal actions are
never applied. M2 kinds: `fire`. Later: `move`, `use_item`, `buy`, `sell`, `ready`, `pass`.

## 10. Timeline (output of the simulation)
`Simulation.apply_action(state, action) -> Array[Dictionary]`. Each event has `"type"` and `"tick"` (ticks since the
action started). Order of events within one impact: `explosion → terrain_carve → damage* → terrain_settle →
(tank_fall → damage(fall)?)* → tank_destroyed*`, then `round_end` **or** (`wind`, `turn`). Each falling tank's
`damage(fall)`, if any, comes directly after its own `tank_fall`.
| type | fields |
|---|---|
| `fire` | tank, angle, power, weapon |
| `projectile` | id, weapon, `path: PackedInt32Array` = [x0, y0, x1, y1, …] Q16.16 per tick |
| `projectile_end` | id, reason (`terrain`/`tank`/`lost`/`timeout`), x, y (cells) |
| `explosion` | x, y, radius, weapon |
| `terrain_carve` | x, y, radius |
| `terrain_settle` | x0, x1, falls (from `Terrain.settle`) |
| `damage` | tank, amount, health, cause (`explosion`/`fall`) |
| `tank_fall` | tank, from_y, to_y |
| `tank_destroyed` | tank |
| `wind` | wind |
| `turn` | tank |
| `round_end` | winner (tank id, or −1 for a draw) |
| `round_start` | round (emitted only by `start_round`, followed by `wind` and `turn`) |

The **show** layer keeps its own copy of the terrain and re-applies `terrain_carve`/`terrain_settle` by calling the same
`Terrain` functions, so visuals match exactly. After playback it checks `Simulation.fingerprint` against the authoritative state.

## 11. Damage (game/core/damage.gd)
Explosion at (cx, cy) with radius r and max damage D. For each alive tank, d = `isqrt` of the squared distance from
(cx, cy) to the closest point of the tank's hit box. If d < r: `dmg = D * (r − d) / r` (at least 1). Health is clamped
at 0, and a tank at 0 is destroyed.

## 12. Weapons (game/core/weapons/weapon_defs.gd)
Data table, keyed by id: `{"pulse_missile": {"radius": 28, "damage": 55, "price": 0, "behavior": "explode"}}`.
M2 ships only `pulse_missile`. Behaviours for later weapons are separate scripts in `game/core/weapons/`.

## 13. Turns, wind, rounds
- After every resolved action: if ≤ 1 tank is alive, emit `round_end` and set phase `round_over`. Otherwise the next
  alive tank in id order (wrapping) gets the turn, and the wind drifts by the round's wind stream, clamped to ±wind_max.
- New round (`Simulation.start_round(state) -> Array`): new terrain, placement and wind from the round's streams; all
  tanks restored to full health.

## 14. Fingerprint & saves
- `Simulation.fingerprint(state) -> String`: SHA-256 (`HashingContext`, an engine utility, is allowed in core) over a
  hand-built `StreamPeerBuffer` serialization (fixed field order, `put_32`/`put_64`, terrain bytes last). Returns the
  first 16 hex chars. **Never** hash `var_to_bytes` output or Dictionary iteration order.
- Saves (M3) = settings + seed + action list + a snapshot for fast load.

## 15. Rendering notes (show layer)
- Renderer: **Compatibility** (OpenGL ES 3), for the widest Android support. Landscape, stretch mode `canvas_items`,
  aspect `expand`, base viewport 1600×900.
- The terrain shader maps material + depth to neon colours and draws a glowing edge where solid meets air.
- Glow is done with additive sprites and shaders (no full-screen post-processing) to hold 60 fps on mid-range phones.

---

# M3 additions (full single-player loop)

These sections extend the contract above. Where they change an earlier section, the change is called out.

## 16. Phases & match flow (changes §13)
```
new_match ─► "shop" ─(all tanks ready)─► start_round ─► "aim" ─► … ─► round_end ─► "shop" … ─► "match_over"
```
- `new_match` now returns a state in phase **`"shop"`** with `round_index = -1` and no terrain yet (`terrain == null`).
  Tanks exist with starting money and empty inventory (`spark_dart` is unlimited and never stored).
- In `"shop"`, any tank may submit `buy`, `sell` and `ready`, in any order. When every tank is ready, the caller invokes
  `start_round(state)` (valid only in `"shop"` with all tanks ready). It clears the ready flags and starts the round.
- After `round_end`: round economy is paid (§18), then phase becomes `"shop"`, or `"match_over"` after the last round.
- Within a round: `fire` and `use_item(repair)` and `pass` end the turn. `move` and `use_item(shield)` do **not**:
  the same tank keeps the turn and can still fire.
- Round-scoped state is reset by `start_round`: health → 100, shields off, fuel kept, wells cleared, tanks re-placed.
- `PHASE_ROUND_OVER` is no longer used by the core (kept as a constant for compatibility only).

## 17. Catalog: weapons & items (game/core/weapons/weapon_defs.gd, game/core/items/item_defs.gd)
- One ordered catalog `Catalog.IDS: PackedStringArray` (game/core/catalog.gd) lists every weapon then every item, in a
  fixed order. Inventories are `PackedInt32Array` indexed by catalog position, which keeps them deterministic and hashable.
  **Never reorder; only append** (saves and fingerprints depend on indices).
- Each entry: `id, kind ("weapon"|"item"), tier ("free"|"full"), price (credits per bundle), bundle (units per
  purchase), behavior, params…`. Display names come from `tr("ITEM_<ID_UPPER>")`; the core never holds display text.
- `MatchSettings.full_unlocked: bool` (default **true** until billing lands in M5). Buying a `"full"` entry while locked
  → `locked_item`.
- Starting values (tunable; balance later):

| id | tier | price/bundle | behavior | key params |
|---|---|---|---|---|
| spark_dart | free | 0 / ∞ | explode | r 14, dmg 30 |
| pulse_missile | free | 1500 / 5 | explode | r 28, dmg 55 |
| hyperpulse | free | 2500 / 3 | explode | r 44, dmg 70 |
| nova_core | free | 6000 / 1 | explode | r 90, dmg 100 |
| supernova | full | 12000 / 1 | explode | r 160, dmg 100 |
| prism_splitter | free | 4000 / 2 | splitter | 5 children, spread 6 (Q16.16 vx step = 0.6 cell/tick), child r 24 dmg 40 |
| prism_cascade | full | 7000 / 1 | splitter | 9 children, spread 4, child r 18 dmg 30 |
| glide_orb | free | 2000 / 3 | roller | r 30, dmg 55, max roll 400 ticks |
| heavy_orb | full | 3500 / 2 | roller | r 44, dmg 70, faster |
| bore_shell | free | 1800 / 3 | tunneler | length 80, tunnel r 6, end blast r 12 dmg 20 |
| deep_bore | full | 3000 / 2 | tunneler | length 180, tunnel r 7, end blast r 14 dmg 25 |
| mound_mortar | free | 1500 / 3 | dirt | add_circle r 40 |
| landslide | full | 3000 / 2 | dirt | add_circle r 80 |
| sludge_shell | full | 3500 / 2 | sludge | volume 1800 cells, flows downhill |
| ember_rain | free | 3000 / 2 | fire | 60 flame points, 2 dmg/point within 6 cells, cap 40 per tank |
| inferno_gel | full | 5500 / 1 | fire | 110 flame points, 3 dmg/point, cap 70 per tank |
| seeker | free | 4500 / 2 | seeker | homing after apex, max lateral accel 0.05 cell/tick², r 28 dmg 55 |
| photon_lance | full | 4000 / 2 | beam | straight line, len 900, cuts ≤ 120 solid cells (r 3), dmg 35 to first tank |
| static_burst | full | 2500 / 2 | static | r 40, dmg 10, removes shields + repulsors in radius |
| singularity_seed | full | 5000 / 1 | well | well r 300, strength 0.12 cell/tick² at centre, linear falloff, lasts 2 full turn cycles |
| riptide_anchor | full | 4000 / 2 | anchor | pull radius 180, max pull 120 cells toward impact x |
| glow_shield | free | 2000 / 1 | shield | 30 shield HP |
| ion_shield | free | 4000 / 1 | shield | 60 shield HP |
| fortress_field | full | 7000 / 1 | shield | 100 shield HP; halves Riptide pull |
| repulsor_field | full | 6000 / 1 | repulsor | field r 60, charge 100 (−1 per tick a shell is inside), pushes shells away |
| drift_chute | free | 1500 / 2 | chute | passive: auto-used on a fall that would cause damage (≥ 1 HP), negates it |
| fuel_cell | free | 1000 / 1 | fuel | +100 fuel when drawn |
| nanorepair_kit | free | 3000 / 1 | repair | +40 health (max 100); ends turn |

- Inventory cap: 99 units per entry.

## 18. Economy (game/core/economy.gd — `class_name Economy`)
`TankState` gains: `money, kills, damage_dealt, round_wins, ready, fuel, shield_type (catalog index or −1), shield_hp,
repulsor_charge, inventory: PackedInt32Array`.
| Event | Credits |
|---|---|
| Damage to an enemy | +15 per HP **actually removed** (health before − health after; never the nominal amount) |
| Kill an enemy (it dies from your shot, including fall damage your shot caused) | +1500, `kills += 1` |
| Damage to yourself | −15 per HP actually removed (money never below 0) |
| Survive a round | +1000 |
| Win a round (last tank standing) | +2500 more, `round_wins += 1` |
- Credit attribution: every damage in a fire timeline is attributed to the firing tank, including falls, burns and drags
  caused by that shot.
- `MatchSettings.start_money` (default 10000, clamped 0..1,000,000).
- Selling refunds `price * qty_units / bundle / 2` (integer division), at most what's owned.
- Match winner: most `round_wins`; ties broken by `damage_dealt`, then `kills`, then lower id. Exposed as
  `Simulation.standings(state) -> Array[int]` (tank ids, best first).
- New timeline event: `money` `{tank, delta, money, reason}` with reason ∈ `damage, kill, self_damage, survive, win,
  buy, sell`. It is emitted right after the damage/kill it pays for. Round pay is emitted after `round_end`.

## 19. Actions (extends §9)
All numeric fields are ints. `Simulation.normalize_action(a: Dictionary) -> Dictionary` converts whole-number floats
from JSON (e.g. `452.0`) to ints and leaves anything else untouched; callers run it before `validate_action`.
| kind | fields | phase | ends turn | errors (in addition to §9's) |
|---|---|---|---|---|
| `fire` | tank, angle, power, weapon | aim | yes | `out_of_stock` |
| `move` | tank, dx (−200..200, ≠ 0) | aim | no | `no_fuel`, `bad_field` |
| `use_item` | tank, item (shield/repulsor/repair) | aim | repair: yes; others: no | `out_of_stock`, `not_usable` |
| `pass` | tank | aim | yes | |
| `buy` | tank, item, qty (bundles ≥ 1) | shop | — | `locked_item`, `no_money`, `inventory_full`, `not_buyable` (spark_dart) |
| `sell` | tank, item, qty (units ≥ 1) | shop | — | `out_of_stock` |
| `ready` | tank | shop | — | `already_ready` |
In `"shop"`, `not_your_turn` does not apply. Dead tanks (from the previous round) can still shop.

## 20. Movement & items
- **Move:** the tank walks |dx| cells one at a time toward the target. Each step costs 1 fuel; when `fuel` hits 0 a
  `fuel_cell` is auto-drawn from inventory (+100). It stops early when out of fuel, when the next step would climb
  more than 3 cells (`MAX_CLIMB`), at the map edge (tank fully on map), or when it would overlap another alive tank.
  Each step sets y = `rest_y`. Drops accumulate as a fall (see the chute rule); a drop ≤ 3 per step is "walking".
  Events: `tank_move {tank, from_x, to_x, fuel}`, then any `tank_fall`/`damage(fall)` as usual.
- **Shield:** `use_item` with a shield sets `shield_type`/`shield_hp` (it replaces any current shield). Event
  `shield_on {tank, item, hp}`.
  - Projectiles collide with the shield **bubble** (radius 24 around (x, y−6)) → end reason `"shield"`; the blast
    happens there.
  - Explosion/burn damage is taken from `shield_hp` first; the remainder goes to health. Fall damage ignores shields.
  - Event `shield_hit {tank, absorbed, hp}`, and `shield_down {tank}` at 0.
- **Repulsor:** `use_item` sets `repulsor_charge = 100` (independent of shields). During flight, a shell within 60 cells
  of the tank centre gets an accel away from it of `0.10 × (60 − d) / 60` cell/tick², and charge −1 per tick while
  inside. At 0 → event `repulsor_down`.
- **Chute:** when a tank falls more than `FALL_SAFE` and owns a `drift_chute`, one is consumed and no fall damage is
  taken. A chute is only consumed when the fall would actually cause damage (computed fall damage >= 1); a fall of 13 cells
  costs 0 HP and keeps the chute. Event `chute {tank}` is emitted between `tank_fall` and where the damage would have been.
- **Repair:** +40 health (cap 100), then the turn ends. Event `repair {tank, amount, health}`.

## 21. Weapon behaviours (game/core/weapons/*.gd)
`Simulation._apply_fire` delegates to `WeaponResolver.resolve(state, tank_id, action, events)`, which dispatches on
`behavior`. Every behaviour reuses one damage pipeline: `Simulation.apply_damage(state, attacker, target, amount,
cause, tick, events)`, which handles shields, money, kills and death. It also uses the shared settle/fall/chute helper.
Flight paths are produced by `Ballistics` (the same code as `trace`), so the preview and the AI match reality.
- **explode:** §7 + §11 as in M2.
- **splitter:** fly as normal. On the first tick where vy ≥ 0 (apex), spawn N children at the shell's position with
  `vx_i = vx + (i − (N−1)/2) × spread`, same vy. Each child flies and explodes independently. Children resolve in index
  order; each child gets its own `projectile` id (1..N) and its own impact events.
- **roller:** on a terrain impact the shell becomes a roller at the surface above the impact column. Each tick it moves 1
  cell toward the lower neighbouring column (2 cells/tick for heavy). It stops when both neighbours are higher or equal,
  at a wall, or after max roll. It explodes on contact with a tank box, when it stops, or at max roll. It ends
  immediately if the impact was on a tank or shield. Path ticks continue in the same `projectile` event (rolling
  positions appended).
- **tunneler:** on terrain impact, continue in the flight direction (unit vector from the last velocity, via
  `isqrt`), carving `r` every cell for `length` cells (stop early at a tank or the map edge). Then fire the end blast.
  Events: `tunnel {x0, y0, x1, y1, radius}` (show re-applies it by calling the same terrain function), then `explosion`
  etc.
- **dirt:** at impact, `add_circle(cx, cy, r, material)`. Cells inside alive tank boxes are skipped. Then settle.
  Event `terrain_add {x, y, radius, material}`.
- **sludge:** pour `volume` cells one at a time. Each cell starts at the impact column and walks downhill while a
  neighbour column's surface is lower (prefer left on ties, then alternate), up to 300 steps. It is placed on top of
  that column. Event `terrain_pour {x, cells: PackedInt32Array of columns in placement order, material}`.
- **fire:** like sludge, but each of the N flame points walks downhill (≤ 200 steps), producing points
  `PackedInt32Array [x, y, …]`. Each point damages every alive tank whose box is within 6 cells: per-point damage,
  capped per tank. Damage is applied once, at the impact tick. Event `flames {points}`, then damage.
- **seeker:** after apex, each tick add a lateral accel toward the nearest alive enemy's centre:
  `ax = clamp((tx − x) × K, −A, A)`, where A = 0.05 cell/tick² and K is chosen so it saturates beyond 200 cells.
- **beam:** step 1 cell at a time along the aim direction (Q16.16, no gravity/wind) from the muzzle. Carve r 3 while in
  solid (≤ 120 solid cells, then stop). Stop at the first tank or shield (apply damage) or at the map edge.
  Event `beam {x0, y0, x1, y1}`, then `terrain_carve`-like `tunnel` event and damage.
- **static:** explode (small) + strip shields/repulsors of tanks whose centre is within r. Events `shield_down`/
  `repulsor_down`.
- **well:** on impact (terrain/tank/shield) create a well `{owner, x, y, expires_turn}` with
  `expires_turn = turn_number + 2 × alive_tank_count`. A new well by the same owner replaces the old one.
  - Ballistics: for each active well with d = `isqrt` of the squared distance, if 4 < d < 300:
    `a = STRENGTH × (300 − d) / 300`, then `ax += a × dx / d`, `ay += a × dy / d`.
  - Wells expire when `turn_number ≥ expires_turn` (checked at turn change), and are cleared at round start.
  - Events `well_on {owner, x, y, expires_turn}` and `well_off {owner}`.
  - `MatchState.wells: Array[Dictionary]` is kept in owner order and included in the fingerprint.
- **anchor:** on terrain impact, every alive tank whose centre is within 180 cells (the shooter included) is dragged
  toward the impact x by up to 120 cells (60 with `fortress_field` active), but not past it. Drag is step by step like
  move (fuel-free, climbing allowed up to 6 cells/step, otherwise it stops). Drops accumulate into a fall.
  Events `tank_drag {tank, from_x, to_x}`, then fall/chute/damage.

## 22. Saves (game/core/save_codec.gd — `class_name SaveCodec`, pure; IO lives in game/platform/)
- `SaveCodec.encode(state: MatchState, actions: Array[Dictionary]) -> PackedByteArray`:
  - magic `"CRTL"`, `SAVE_VERSION`, the full binary state snapshot (same field order as the fingerprint plus anything
    the fingerprint omits);
  - the action log as JSON (for replays/online);
  - `fingerprint(state)` as a check.
- `SaveCodec.decode(bytes) -> Dictionary` returns `{ok, error, state, actions}`. It verifies magic, version and the
  fingerprint.
- `game/platform/save_store.gd` writes `user://autosave.crtl` atomically (write `.tmp`, then rename). It autosaves after
  every resolved action and on `NOTIFICATION_APPLICATION_PAUSED` / `WM_CLOSE_REQUEST`. The title screen offers
  CONTINUE when a valid autosave exists.

## 23. Settings validation
`new_match` clamps a copy of the settings before use (num_tanks 2..8, rounds 1..20, wind_max 0..100, start_money
0..1,000,000). In the free version (`full_unlocked == false`), num_tanks is capped at 4 and rounds at 5
(`SimConstants.FREE_MAX_TANKS/FREE_MAX_ROUNDS`, M5). The **clamped** values are what's stored and fingerprinted.

## 24. Fingerprint additions
All new `TankState` fields, `MatchState.wells` and anything else added to state **must** be included in
`fingerprint()` in a fixed order. Golden fixtures in `game/tests/qa/fixtures/` will be regenerated deliberately for M3.

## 25. M3-C1 resolutions (binding)
- Extra events: `ready {tank}`, `repulsor_on {tank, charge}`. `tank_move` carries `fuel`. `repulsor_down` follows
  `projectile` with the tick the charge ran out.
- Extra error key `unknown_item` (an id not in the catalog). Buy checks run in this order: `bad_field, unknown_item,
  not_buyable, locked_item, inventory_full, no_money`. A buy that would exceed 99 is rejected whole. Selling more than
  you own sells what you own.
- Weapon param keys: `r`, `dmg` for blasts. Q16.16 params are stored raw; splitter `spread` is in tenths of a cell/tick.
  See the header of `weapon_defs.gd`.
- `START_FUEL = 0`: moving needs a Fuel Cell.
- `damage.amount` is the nominal amount after shield absorption. Event order per hit: `shield_hit → [shield_down] → damage → money`.
- Walking falls have no attacker (no money effect). Team damage counts as self-damage.
- The repulsor never pushes its owner's shell, and resets at `start_round`.
- Save format: magic, version, snapshot from `StateSerial` (shared with the fingerprint), action JSON, fingerprint,
  SHA-256 trailer. Decode errors: `too_short, bad_magic, bad_version, corrupt, fingerprint, invalid_state` (the last when `StateSerial.validate` rejects out-of-range values); plus `no_file` from SaveStore.

## 26. M3-C2 resolutions (binding; supersede §17/§20/§21 where they differ)
- **Tuned constants:** `REPULSOR_PUSH` = 2.00 cell/tick² (131072). Seeker accel = 0.10 cell/tick² (6554). Well strength
  = 0.15 cell/tick² (9830).
- **Seeker:** after the apex, it steers on the *predicted landing x* at the target's centre height, not the current gap.
  The gain saturates at 25 cells of predicted miss. The target is the nearest alive enemy, locked at the apex.
- **Shared flow rule** (sludge, roller, fire), in `weapons/surface_cache.gd`:
  - Move toward the strictly lower neighbour; keep direction over level ground; stop when the next column ahead is
    higher.
  - Ties alternate by column parity (left on even columns).
  - A resting roller or flame only starts moving if its level run ends in a drop within 8 columns.
- **Splitter:** the main shell ends at the apex with `projectile_end.reason = "split"`. Children resolve sequentially,
  in index order, against the world left by earlier children. Hitting something before the apex explodes with the
  child r/dmg.
- **Path/tick convention:** `projectile.path[i]` is the position at tick `event.tick + i + 1`, and
  `projectile_end.tick = event.tick + path.size()/2`. Ticks are not monotone across splitter children.
- **New damage causes:** `burn` (fire) and `beam` (photon lance).
- **Terrain functions used by the show:**
  - `carve_tunnel(x0, y0, x1, y1, r)` (union of discs along the segment);
  - `pour(columns, material)`;
  - `add_circle_skipping(cx, cy, r, material, skip)`. `skip` = half-open tank boxes [x0, y0, x1, y1, …].
- **Behaviour details:**
  - Dirt uses the impact column's surface material, and tanks can be buried.
  - A tunnel and its crater share one settle.
  - The beam has no projectile/explosion, and a shield absorbs its damage.
  - Static strips shields before damage.
  - A same-owner well emits `well_off` then `well_on`, and the pull affects everyone's shells, the owner's included.
  - The anchor triggers on any impact; `tank_drag` only for tanks that moved.
  - Fire start columns use a fixed ±10 pattern (no RNG). One damage event per tank per shot.

---

# M4 additions (computer opponents)

## 27. Controllers & AI-visible state (core changes)
- `MatchSettings.controllers: PackedInt32Array`, with one entry per tank: `0` human, `1` easy, `2` normal,
  `3` hard, `4` expert (`SimConstants.CTRL_*`). Default: all human. `new_match` clamps it: size = num_tanks, values
  0..4. It is fingerprinted, saved and validated. If `full_unlocked` is false, values 3–4 are clamped to 2 (Hard/Expert
  are full-version).
- `TankState.last_fire_*` (all ints): `last_fire_angle, last_fire_power, last_fire_weapon` (catalog index, −1 = none),
  `last_fire_x, last_fire_y` (impact cell; −1 if lost/timeout), `last_fire_wind`, `last_fire_turn` (turn_number when
  fired).
  - Written by the simulation on every `fire`, for any controller.
  - Reset to −1/0 at `start_round`.
  - Fingerprinted, saved and validated.
  - It is the AI's only "memory", so AI decisions are a pure function of the state, and save/load/online stay
    deterministic.
- No AI code lives in core. Core only stores these fields.

## 28. AI interface (game/ai/ — `class_name AiPlayer`, pure, deterministic, integer math)
```
AiPlayer.next_action(state: MatchState, tank_id: int) -> Dictionary   # phase "aim": one action
AiPlayer.shop_actions(state: MatchState, tank_id: int) -> Array[Dictionary]  # phase "shop": buys/sells then ready
```
- Difficulty comes from `state.settings.controllers[tank_id]`.
- Randomness: `Rng.derive(state.seed, SimConstants.TAG_AI).fork(round_index * 100000 + turn_number * 16 + tank_id)`,
  or the equivalent derived purely from the state. Never the global RNG; never Time.
- `next_action` may return a non-turn-ending action (`use_item` shield/repulsor, or `move`). The caller applies it
  and calls `next_action` again. The AI must guarantee a turn-ending action (`fire`/`pass`/`use_item` repair) within
  **3 calls**, so it never loops. Every returned action must pass `Simulation.validate_action`. If something
  unexpected happens, return a legal `fire` with `spark_dart`.
- Any device computes the same AI action from the same state. That's how online matches will run AI turns (M7).
- Budget: < 50 ms per call on a mid-range phone (assume about 3× slower than this container), so ≲ 15 ms here.
  `Ballistics.trace` calls must be bounded (≤ 48 per decision).

## 29. Behaviour by difficulty (starting values, all in `game/ai/ai_profile.gd`)
| | Easy | Normal | Hard | Expert |
|---|---|---|---|---|
| Wind used in aiming (per-mille of actual) | 0 | 500 | 900 | 1000 |
| Consistent power bias per round (‰ of power, sign seeded) | ±80–150 | ±40–80 | ±15–30 | 0 |
| Shot-to-shot noise (‰ of power, σ-ish) | 40 | 25 | 10 | 4 |
| Correction from last miss on same target (‰) | 250 | 500 | 800 | 1000 |
| Weapon choice | basic missiles, random | sensible by range/terrain | right tool (tunnel/dirt/roller/Seeker) | best value incl. originals, counters shields (Static Burst) |
| Shields / repulsor / repair | never | uses a shield if owned and health < 50 | uses shields proactively | shields + repulsor timing, repair when worth it |
| Moves | never | never | rarely (out of a pit) | when it improves the line of fire |
| Shop | random cheap mix | balanced, simple | plan: shield + strong weapons + chutes | saves money, counters opponents' stock |
| Target | nearest | nearest, or whoever last hit it | weakest (kill-securing) | best expected value (kill chance × reward, threat) |

- **Human-like misses:** the first shot at a new target uses the AI's noisy estimate. Each later shot at the same
  target corrects by `correction ‰` of the observed miss (`last_fire_x` vs the target). The bias stays consistent for
  the round, so Easy is "always a bit short", not random.
- **Aim search:** pick a launch angle (prefer 30–70° toward the target, steeper over hills), then binary-search power
  with `Ballistics.trace` (using the believed wind) until the predicted landing is within a tolerance. Then apply
  bias/noise.

## 30. AI acceptance tests (game/tests/ai/)
Measured over ≥ 200 seeded scenarios each, with rates reported:
- Expert hits a stationary target (≤ damage-radius miss) with its first shot in 60–75% (human-like, not perfect),
  within 2 shots in ≥ 90%, within 3 in ≥ 97%.
- Hard's first shot hits in 35–55%, within 3 shots in ≥ 80%, and stays clearly below Expert.
- Normal's first shot hits in 10–40%, and it improves within 5 shots.
- Easy's first shot misses in ≥ 85%, with a "believable" median miss of 40–250 cells. With strong wind Easy misses
  more than with no wind; with no wind Easy still misses because of bias.
- Determinism: the same state gives the same action, including after a save/load round trip.
- Every action is valid. A turn ends within 3 calls.
- Budget: p95 decision time ≤ 15 ms × `PERF_BUDGET_SCALE`.
- A 4-AI match (one per difficulty) runs to match_over with no errors. Over many matches Expert wins the most rounds
  (roughly 55–75%, not near-total), and Hard ends clearly ahead of Normal on kills.

## 31. M4-A resolutions (binding)
- AI aim searches run on `game/ai/ai_flight.gd` (`AiFlight`), an integer copy of the shell physics, including wells and
  repulsors, because one `Ballistics.trace` costs about 2.5 ms. A regression test keeps AiFlight within 2 cells of
  `Ballistics.trace`. **Any change to `Ballistics` flight physics must update AiFlight too.**
- AI streams: `Rng.derive(seed, TAG_AI + tank_id).fork(round_index*100000 + turn_number*16 + tank_id)`. The round bias
  uses the fork `round_index*100000 + 99999`; shop streams use a large constant offset.
- The AI doesn't use or buy fire/sludge weapons (weakest heuristics; may come later).

---

# M5 additions (polish, sound, themes, skins, full unlock)

## 32. Entitlement (free vs full) — game/platform/entitlement.gd (`class_name Entitlement`, autoload-style static)
- `Entitlement.is_full() -> bool` is the single source of truth for the UI. It is true if the Play purchase
  `full_unlock` is owned (non-consumable), OR the device has a Play Pass entitlement (Play Billing reports it as an
  owned purchase), OR the debug override is on.
- The state is cached in `user://entitlement.cfg`, so it works offline. It's refreshed from Billing at startup and on
  resume. A `changed` signal fires when it changes.
- Backends:
  - `BillingAndroid`: the GodotGooglePlayBilling plugin, only when the plugin singleton exists.
  - `BillingFake`: desktop/tests and when the plugin is missing. Its purchase succeeds instantly, but only in debug
    builds.
- API: `purchase_full()`, `restore()`, `price_text() -> String` ("" until known, then the store's localized price),
  and `set_debug_full(bool)` (debug builds only).
- Every match is created with `MatchSettings.full_unlocked = Entitlement.is_full()`. The core enforces item tiers,
  controller clamps and (new) `num_tanks ≤ 4` when not full.

| Feature | Free | Full |
|---|---|---|
| Tanks per match | 2–4 | 2–8 |
| Humans per device (pass-and-play) | ≤ 2 | ≤ 8 |
| CPU levels | Easy, Normal | + Hard, Expert |
| Weapons/items | `tier == "free"` | all |
| Rounds | 1, 3, 5 | + 10, 20 |
| Start money / wind presets | Normal only | all |
| Terrain themes | 2 (Sunset Grid, Ice Circuit) | all |
| Skin Studio | editor | + image import |
Locked options stay **visible** with a small "FULL GAME" lock. Tapping one opens the Unlock screen; nothing is
hidden.

## 33. Audio — game/show/audio/ (`AudioDirector`, an autoload)
- Buses: Master → SFX, UI, Music. Volumes (0–100) and on/off are stored in SettingsStore.
- Sound effects are generated offline by `tools/sfx/gen_sfx.py`, a deterministic sfxr-style synthesizer with
  parameters checked into `tools/sfx/presets.json`. The output WAVs are committed in `game/assets/sfx/`, all original.
- Event → sound map:
  - fire, by weapon class
  - explosion (small/medium/large/nuke)
  - terrain crumble, dirt thud, sludge pour, fire crackle, beam zap, well hum (looping while a well exists), anchor
    clank
  - shield up/hit/break, repulsor
  - chute pop, repair chime, money gain/loss, tank destroyed, round win, match win
  - UI tap/back/purchase/locked, CPU "thinking" tick (subtle)
- Voices are pooled; at most 12 concurrent SFX, with priority by loudness. Pitch is jittered ±4% (floats are fine here).
- Music: a `Music` bus and player with no track. Dropping an OGG into `game/assets/music/` plus one line in
  `audio_director.gd` enables it. The Settings "Music" volume exists already.

## 33a. Sound redesign (owner feedback 2026-10-04, binding; supersedes the "sfxr-style" sound character of §33)
- **Style:** heavy sci-fi. Big, bassy shots and explosions with a slight futuristic edge, not retro/arcade. Every
  sound is redone, UI included, so the set matches.
- **Bass that survives a phone speaker:** each impact has a sub layer (40–80 Hz) *and* strong upper-bass harmonics
  (100–300 Hz) so the weight is heard on a phone speaker, not only on headphones. The transient comes first (a sharp
  click or crack), then the body, then a rumble or reverb tail. Size scales small → medium → large → nuke in
  length, low end and loudness.
- **Loudness:** peaks ≤ −1 dBFS. Battle sounds sit clearly above UI sounds. No sound clips after the director's
  mix (voice cap 12 still holds).
- **Love Edition:** soothing and romantic. Soft chimes, harp-like plucks and warm pads for heart shots, bursts and
  flowers; no booms or harsh noise. The win gets a sweeter, longer melody (about 3–5 s). No Love music loop for now.
- **Haptics (vibration):** uses the existing Settings "Haptics" toggle (on by default). A short light pulse on
  firing; a pulse on impact that scales with explosion size; a heavy rumble on a nuke-class blast and on a tank
  destroyed. Love Edition: no rumble on hearts, only a gentle double "heartbeat" pulse on the win. Haptics are
  independent of reduce-motion and never fire while the app is in the background.
- Generation stays offline and deterministic (`tools/sfx/gen_sfx.py` + `presets.json`, standard library only);
  the generator may gain new layer types (for example FM bells, plucked strings, reverb, compressor/limiter).

## 34. Terrain themes — visual only (game/show/themes/)
- `ThemeDefs`: id, name key, sky gradient, sun/moon, grid colour, terrain strata palette, edge glow colour, particle
  tint, tier.
- Ids: `sunset_grid` (free), `ice_circuit` (free), `magma_city`, `toxic_marsh`, `midnight_chrome`.
- The theme is chosen in setup (or "Random"). It is per match and stored in autosave meta, not in core state, so
  determinism and fingerprints are unaffected.

## 35. Skins — local only (game/show/skins/, game/ui/skins/)
- Skin JSON at `user://skins/<id>.json`:
  `{version, name, body_style 0..3, turret_style 0..3, base, accent, pattern 0..5, pattern_color, decal 0..9, glow 0..100, image: "<id>.png"|null}`.
  An imported image (full only) is stored as a 128×64 PNG next to it after a neon posterize filter.
- Assignment: `user://skins/assign.cfg` maps a player slot to a skin id. It is used when that slot is Human on this
  device.
- Never uploaded. Never shown to other devices.
- The player identity colour (outline, name tag, emblem) is always drawn on top, from NeonPalette.

## 36. Easy AI retune (owner feedback, binding; supersedes the Easy column of §29/§30)
- Profile: noise 55‰, per-round bias ±120–190‰, nominal correction 115‰.
- Correction "dice" per shot:
  - ~60% correct 80–150‰ of the miss;
  - ~25% over-correct (1700–2300‰), landing past the target;
  - ~15% barely correct (0–30‰).
- After a lost shell (off the map), the next shot cuts power by 150–400‰. It's a crude reaction, not exact bracketing.
- Veteran phase: after about 8 own turns in a round (estimated as turn_number / tank_count), correction becomes
  250–450‰ and noise drops to 35‰, so all-Easy rounds still end. Set `veteran_shots = 0` to disable it.
- Bands (200 seeded scenarios): first shot 1–8%, within 3 shots 5–20%, within 6 shots 20–40%. Median miss on shots
  2–4 is 60–300 cells. Normal stays at least 20 points better within 3 shots.

---

# Secret: Love Edition (owner request)

## 37. Love mode (binding)
- **How it's unlocked:** tap the title logo 7 times within ~3 s. A heart sparkle plays, and a hidden "LOVE EDITION"
  button appears on the title. The discovery is stored in SettingsStore (`love_found=true`), so the button stays from
  then on. It's available in free and full; CPU Hard/Expert follow the normal §32 gating.
- **Core:** `MatchSettings.mode: int` (`SimConstants.MODE_STANDARD = 0`, `MODE_LOVE = 1`). It is fingerprinted,
  saved, validated and clamped. Love mode forces num_tanks = 2, rounds = 1, wind_max ≤ 30 and start_money = 0.
  - `new_match` in love mode skips the shop and starts round 0 directly (phase "aim").
  - `TankState.love: int` (0..100, starts at 0). It is fingerprinted, saved and validated; always 0 in standard mode.
  - The weapon id `heart` lives in `WeaponDefs` but is **not** in the shop Catalog (inventories and old saves are
    unchanged). Behaviour `love`: r 30, amount 34 (so about 3 good hits fill a meter).
    - It is valid only in love mode, where it's unlimited and the only legal weapon.
    - `last_fire_weapon` records `Catalog.HEART_INDEX = -2`.
  - Love resolution: the flight is normal (gravity, wind; tanks block). On impact there's **no terrain change and no
    damage**. Every alive tank *other than the shooter* within r gains love with the same falloff as §11 damage
    (amount × (r − d) / r, minimum 1), capped at 100. A hit on yourself does nothing.
  - Events:
    - `heart_burst {x, y, radius}`
    - `love {tank, amount, love, from}`
    - when a meter reaches 100: `round_end {winner = the shooter}` and phase "match_over"
  - In love mode, `move`, `use_item`, `buy`, `sell` and `ready` are invalid (`bad_mode`); `fire` (heart only) and
    `pass` are allowed.
- **AI:** in love mode, AiPlayer always fires `heart` at the opponent using the usual aim/error model for its level.
  There's no shop, items or move, and no self-damage guard (a self-hit is just wasted).
- **Show/UI:**
  - a rose/pink love theme
  - love meters (pink hearts) instead of health bars
  - heart projectiles with a sparkle trail
  - sparkle burst plus persistent glowing flowers sprouting on the terrain surface at the impact (visual only, kept for
    the match)
  - a win overlay with a smiling face floating up over the winning tank, heart confetti, and REMATCH / TITLE
  - the HUD hides money, items and move
  - new sfx: heart fire (soft chime), heart burst (sparkle), love win jingle

## 38. Out-of-reach rule (M5-AI, binding; amends §29 "Moves")
- **When it applies:** a target counts as hopeless when the best plan falls short at max power with no workable
  weapon, or when the last shot at it was at ≥ 985 power and landed ≥ 150 cells short. If every target is hopeless,
  **all levels**, Easy included, fall back to this rule.
- **What the AI does:**
  - with fuel (≤ 200 units in hand), walk up to 200 cells toward the nearest enemy (gaining at least 20), then fire;
  - otherwise, fire the closest-landing max-power Spark Dart.
- **Shop:** after a long round spent out of range (≥ 10 turns per tank, last shot lost or > 300 cells from every
  enemy), buy 1 Fuel Cell (2 after ≥ 25 turns per tank). The AI never holds more than 200 fuel units.
