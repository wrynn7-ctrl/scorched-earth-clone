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
  - `is_solid(x, y) -> bool`, `surface_y(x) -> int` (first solid y from the top; `height` if the column is empty).
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
action started). Order of events within one impact: `explosion → terrain_carve → damage* → terrain_settle → tank_fall*
→ damage(fall)* → tank_destroyed*`, then `round_end` **or** (`wind`, `turn`).
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
