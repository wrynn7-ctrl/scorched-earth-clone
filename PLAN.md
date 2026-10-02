# PLAN — Neon Artillery Game for Android

Status: **APPROVED (2026-10-02).** Working title "Craterline"; free/full split and $3.99 as in §4. Image import ships in M5. Reports: private review list + auto-hide a name after 3 reports from different players.

---

## 1. Decisions so far (from your answers)

| Topic | Decision |
|---|---|
| Engine | **Godot 4** (latest stable 4.x, exact version pinned in the project). Language: **GDScript** with strict typing (see §6.1). |
| Online play | **Live and asynchronous** in one system. **Friends-only** at launch (invite code/link); matchmaking later. |
| Backend | **Firebase**: sign-in, Realtime Database, Cloud Functions, push notifications. |
| Art style | **Neon / synthwave**: dark skies, glowing outlines, bloom, bright trails. |
| Audio | Sound effects from a sound generator (fully owned by you). Music is **optional**: a music volume control is built in from day one and a track can be added later. |
| Business model | **Free to try, one purchase unlocks the full game.** No ads, no other paid add-ons. Built to meet **Google Play Pass** rules. |
| Android | **Minimum Android 8.0 (API 26)**. Target the API level Google requires at release (currently Android 16 / API 36). **Phones and tablets** both get a proper layout. |
| Test builds | **GitHub Actions** builds an installable APK on every update; you download it on your phone. |
| Test phone | Samsung Galaxy S26 Ultra (see the performance note in §9). |
| Language | English at launch. All text goes through a translation table so other languages can be added later. |

**Why Android 8.0:** it reaches about 95%+ of active devices, and its graphics drivers handle our glow effects reliably. Supporting older versions would add testing work for very few players.

---

## 2. Title options (all original)

1. **Craterline** — short and memorable; it's what the game does (craters, lines of fire). ⭐ *My pick*
2. **Neon Barrage** — says the art style and the genre at a glance.
3. **Voltfall** — punchy, has a synthwave feel, and looks good as a logo.
4. **Afterglow Artillery** — evocative, and matches the glowing trails.
5. **Gridfire** — retro-future grid look combined with artillery fire.

Before you commit to one, search the Play Store for it and check the free trademark search at tmsearch.uspto.gov (or your country's equivalent). I can't do a legal clearance check. This plan uses "Craterline" as a working title, and renaming later is cheap.

---

## 3. The game

### 3.1 Core rules
- **2–8 tanks** on randomly generated, **fully destructible** 2D terrain (hills, valleys, cliffs, overhangs).
- On your turn: set **angle** and **power**, pick a weapon, and **fire**. You can also **move** your tank (uses fuel) or **use an item**.
- **Gravity** is constant. **Wind** changes every round and drifts slightly every turn. It's shown as an arrow plus a number.
- **Terrain collapses** when you dig under it: unsupported dirt falls.
- **Fall damage**: tanks fall when the ground under them disappears. Long falls hurt, and parachutes prevent the damage.
- **Rounds**: a match has 1–20 rounds (default 5). A round ends when one tank (or team) is left standing.
- **Money**: earned for damage dealt, kills, surviving, and winning the round. You lose money for hurting yourself or teammates. You spend it in the **shop between rounds**, and can sell items back for 50%.
- **Match winner**: the most points (kills + damage + round wins). The exact formula will be tuned during playtesting.

### 3.2 Arsenal (original names)

| # | Name | Archetype | What it does |
|---|---|---|---|
| 1 | **Spark Dart** | Small missile | Cheap, small blast. Unlimited supply. |
| 2 | **Pulse Missile** | Missile | Standard all-rounder. |
| 3 | **Hyperpulse** | Large missile | Bigger blast, pricier. |
| 4 | **Nova Core** | Large nuke | Very large blast. |
| 5 | **Supernova** | Nuke-scale | Huge blast, screen-filling flash, very expensive. |
| 6 | **Prism Splitter** | Splitting (MIRV-style) | At the top of its arc it splits into 5 warheads that fan out. |
| 7 | **Prism Cascade** | Heavy splitter | Splits into 9 smaller warheads. |
| 8 | **Glide Orb** | Rolling bomb | Lands, rolls downhill and explodes when it stops or hits a tank. |
| 9 | **Heavy Orb** | Heavy roller | Bigger, faster roller with a larger blast. |
| 10 | **Bore Shell** | Tunneler | Drills a tunnel along its path into the ground, then pops. |
| 11 | **Deep Bore** | Heavy tunneler | Longer tunnel. Great for undermining tanks so they fall. |
| 12 | **Mound Mortar** | Adds dirt | Drops a ball of dirt. Buries tanks or builds a wall. |
| 13 | **Landslide** | Big dirt | Large dirt pile. Can trap a tank in a pit. |
| 14 | **Sludge Shell** | Flowing dirt | Liquid dirt that flows downhill and fills valleys. |
| 15 | **Ember Rain** | Fire | Burning gel that spreads and flows downhill, damaging over time. |
| 16 | **Inferno Gel** | Heavy fire | Bigger, hotter spread. |
| 17 | **Seeker** | Guided | After the top of its arc, it steers gently toward the nearest enemy (limited turning). |
| 18 | **Photon Lance** | Laser | Fires a straight beam that ignores wind and gravity. Cuts through some terrain. Low damage, perfect accuracy. |
| 19 | **Static Burst** | Shield breaker | Small blast that strips shields from tanks it touches. |
| 20 | **Singularity Seed** ✨ | *Original* | See §3.4. |
| 21 | **Riptide Anchor** ✨ | *Original* | See §3.4. |

### 3.3 Defensive and utility items

| Name | What it does |
|---|---|
| **Glow Shield** | Light shield that absorbs a little damage, then breaks. |
| **Ion Shield** | Medium shield. |
| **Fortress Field** | Heavy shield. |
| **Repulsor Field** | Bends incoming projectiles away. Weakens with each deflection. |
| **Drift Chute** | Automatically opens during a fall and prevents fall damage. One use. |
| **Fuel Cell** | Fuel for driving your tank left and right. |
| **Nanorepair Kit** | Restores some health. Using it takes your turn. |

### 3.4 Two original weapons (the game's identity)

#### ✨ Singularity Seed — "bend the battlefield"
- **What it does:** a small shell that, on impact, plants a **glowing gravity well** where it lands. For the next **2 full turn cycles**, every projectile flying near it gets pulled toward it, like a planet bending a spaceship's path. It does **no damage** itself.
- **How it plays:**
  - *Defense:* plant it between you and an enemy who keeps hitting you, and their shots curve away.
  - *Offense:* use it to curve your own shots around a mountain you couldn't otherwise hit over.
  - *Mind games:* everyone sees the well's pull radius, so players adapt and look for trick shots.
- **Why it's balanced:** no damage; limited lifetime; **one active per player**; expensive; it affects *everyone's* shots, including yours. The AI handles it naturally because it plans shots using the same physics.

#### ✨ Riptide Anchor — "the ground is the weapon"
- **What it does:** a harpoon that sticks into the ground on impact and **yanks every tank within range toward that point**, dragging them along the terrain surface. It does **no direct damage**. The damage comes from what happens next: getting pulled off a cliff, into a pit, or into burning Ember Rain.
- **How it plays:**
  - Pull an enemy off a ledge so they take **fall damage**.
  - Drag enemies into a crater, then follow up with a Landslide to bury them.
  - **Self-rescue:** fire it at the ground next to *yourself* to relocate when you're stuck in a hole.
- **Why it's balanced:** zero direct damage; pull distance is capped; **Drift Chutes fully counter** the fall damage; heavy shields reduce the pull. It rewards reading the terrain, which is the heart of the genre, instead of raw damage.

### 3.5 Trajectory preview
The classic genre has no aiming guide; part of the skill is guessing. Our default is a **short dotted arc** showing the first ~25% of the flight, **without wind**, so it helps with aiming but doesn't solve the shot. Match settings: **Off / Short (default) / Full**. "Full" is meant for the practice range.

---

## 4. Free vs. full version (proposal — tell me what to change)

| | Free | Full (one purchase, suggested $3.99) |
|---|---|---|
| Single-player vs AI | ✅ up to 4 tanks | ✅ up to 8 tanks |
| AI difficulties | Easy, Normal | + Hard, Expert |
| Weapons & items | 10 core weapons + all basic items | All 21 weapons including the two originals |
| Pass-and-play | ✅ 2 players | ✅ up to 8 players |
| Online | Can **join** a friend's match (and use the full arsenal inside it) | Can **host** matches |
| Terrain themes | 2 | All |
| Custom match rules | — | ✅ (gravity, wind strength, starting money, rounds…) |
| Skin Studio (tank editor) | ✅ shapes, colors, patterns, decals, glow | ✅ + **import your own images** |

**Why "free players can join online games":** a friend can try the full game with you at no cost. That's the best advertising a no-ads game can get.

**Google Play Pass:** Play Pass is **by Google's selection**: you apply in the Play Console and Google decides. Its rules (no ads, everything unlocked for subscribers) already fit our design: Play Pass subscribers simply get the full unlock automatically. Being accepted is not guaranteed.

### 4.1 Skin Studio (player-made tank skins)
- An **in-game editor** for designing your own tank look: pick a body and turret style, colors, patterns (stripes, circuits, camo, grid), decals, and glow color and intensity. Save as many skins as you like.
- **Full version only:** import a picture from your phone (photo picker), then crop it and place it on the tank. The game shrinks it and gives it a neon-style filter so it fits the art.
- **Only you ever see your skins.** They're stored on your device and never uploaded. In online matches your opponents see your tank in its standard style. In pass-and-play everyone shares one screen, so they'll see it there.
- **Colorblind-safe identity:** your *player color* (glow outline, name tag, emblem) always stays from the colorblind-friendly palette, so a custom skin can't make tanks hard to tell apart.
- Because skins are never shared, Google's moderation rules for user-made content don't apply to them. That keeps the feature simple and cheap.

**How the unlock works:** one Google Play in-app product ("full_unlock") that is bought once and kept forever. Purchases restore automatically on a new phone, and the unlock keeps working offline once verified.

---

## 5. Computer opponents (AI)

The AI aims with the **same physics** the game uses, then adds human-like mistakes. "Human-like" here means missing the way a person does: consistently a bit short, forgetting the wind, then correcting on the next shot ("bracketing"), rather than firing randomly.

| | Easy | Normal | Hard | Expert |
|---|---|---|---|---|
| **Aiming error** | Large, but consistent (tends to overshoot or undershoot) | Medium | Small | Tiny |
| **Wind** | Ignores it | Accounts for about half | Accounts for nearly all | Fully |
| **Learning from misses** | Barely corrects | Corrects about halfway each shot | Corrects quickly | Usually hits by the 2nd shot |
| **Weapon choice** | Mostly basic missiles | Sensible | Picks the right tool (tunnel under tanks on cliffs, etc.) | Best value; uses originals, shields and parachutes cleverly |
| **Shop strategy** | Buys randomly, mostly cheap | Balanced but simple | Plans: shields + strong weapons | Saves money, counters what opponents buy |
| **Target choice** | Nearest tank | Nearest, or whoever just hit it (revenge) | Weakest tank (to finish kills) | Best overall payoff: kill chance, threat, money |

- **Thinking time:** the AI pauses briefly and visibly swings its turret before firing, so it feels like a player.
- **Mixed matches:** every tank has its own setting (Human / Easy / Normal / Hard / Expert), so "you vs. Easy + Expert" works, and teams are possible.
- **Same results every time:** the AI uses the match's seeded random numbers, so a replayed match behaves identically. This is needed for online play and for tests.

---

## 6. How it's built (architecture)

### 6.1 Why GDScript (and not C#)
GDScript is Godot's own language. It reads a lot like Python, has the best documentation, and works on Android with no extra setup. Godot's C# support on Android still has rough edges. We'll use **typed GDScript** (every variable has a declared type), which catches many mistakes before the game runs. If profiling ever shows a slow spot, that one piece can be moved to C++ without rewriting the rest.

### 6.2 The key idea: "simulation" vs. "show"
The game is split into two layers:

1. **Simulation (the rules):** pure logic with no graphics. Given the current state and one player action (e.g. "fire, angle 47.3°, power 612, Pulse Missile"), it calculates *everything* that happens: the flight path, explosions, terrain changes, damage, falls and money. It returns that as a **timeline of events**.
2. **Show (the presentation):** takes that timeline and plays it back beautifully with glow trails, particles, screen shake, sound and haptics.

**Why this matters:**
- **Online play:** devices only send each other *actions*, never results. Every phone runs the same simulation and gets identical results, so a cheater can't send "I hit you for 100 damage."
- **Reconnecting:** a match is just "starting seed + list of actions." A reconnecting phone replays the list instantly and is caught up.
- **Auto-save:** the save file is tiny, and a closed app resumes exactly where it was.
- **Testing:** the rules can be tested thousands of times per second without opening a screen.
- **AI:** the AI "imagines" shots by running the simulation's flight math.

### 6.3 Determinism (identical results on every phone)
Computers can round decimal numbers slightly differently on different chips, and over a long flight those tiny differences grow into a hit on one phone and a miss on another. To prevent that:
- The simulation uses **only whole-number math** (fixed-point: positions are stored as whole numbers of 1/65536ths of a pixel). It uses no decimal numbers and no built-in sine/cosine; we use our own lookup tables.
- **Fixed timestep:** physics always advances in exact 1/60-second steps (with sub-steps for fast shells), no matter how fast the phone renders.
- **Seeded random numbers:** our own generator (PCG32), seeded per match. Terrain, wind and AI "personality" all come from it.
- **State fingerprint:** after every turn, a hash (fingerprint) of the whole game state is computed. Online, every phone compares fingerprints, and a mismatch reveals a bug or a tampered app. Automated tests also lock in known fingerprints, so any change that breaks determinism fails the build.

### 6.4 Project folders
```
game/                     Godot project
  core/                   SIMULATION — pure rules, no graphics
    fixed_math.gd         whole-number math, trig tables
    rng.gd                seeded random numbers (PCG32)
    terrain.gd            terrain grid: generate, carve, add dirt, collapse
    ballistics.gd         projectile flight: gravity, wind, wells, collisions
    weapons/              weapon & item definitions (data) + behaviours
    tank_state.gd, damage.gd, economy.gd, shop.gd
    match_state.gd        rounds, turns, scores
    simulation.gd         apply_action(state, action) -> event timeline
    save_codec.gd         save/load, state fingerprint
  ai/                     computer opponents
  show/                   battlefield rendering, effects, camera, haptics, audio
  ui/                     menus, HUD, shop screen, settings, accessibility
  net/                    Firebase client, match sync, reconnection
  platform/               billing (unlock), notifications, save location
  assets/                 shaders, generated sounds, fonts (open-licensed)
  locale/                 translation table (English first)
  tests/                  automated tests (GUT test framework)
firebase/                 backend: database rules, Cloud Functions (TypeScript), rule tests
.github/workflows/        automatic test runs + APK/AAB builds
store/                    store listing text, privacy policy, Data Safety answers, screenshots
.claude/agents/           AI helper definitions (see §8)
```

### 6.5 Core interface (contract between helpers)
```gdscript
# Simulation — the only way game state changes.
Simulation.new_match(settings: MatchSettings, seed: int) -> MatchState
Simulation.apply_action(state: MatchState, action: Action) -> Timeline   # changes state
Simulation.fingerprint(state: MatchState) -> int
# Action = { player, kind: FIRE|MOVE|USE_ITEM|BUY|SELL|END_SHOP|PASS, angle_tenths, power, item_id, ... }
# Timeline = ordered events: ProjectileStep, Explosion, TerrainChanged, Damage, TankFell,
#            TankDestroyed, MoneyChanged, RoundEnded ...
```
The **show** layer and **AI** only *read* state and *submit* actions. Only the simulation changes state.

### 6.6 Terrain
- A grid of cells (about 1600 × 900; the exact size will be tuned for speed) marks each cell as dirt or air, with a dirt type for color.
- Explosions carve circles; dirt weapons add shapes; tunnels carve paths. Afterwards a "settle" step drops unsupported dirt column by column.
- Rendering: the grid is turned into a texture, and a shader adds the glowing neon edge along every surface.
- Generation: seeded layered noise produces hills, valleys and plateaus. **Themes** change colors and shapes (e.g. "Sunset Grid," "Ice Circuit," "Magma City").

### 6.7 Screens and controls
- **Landscape only.** The battlefield always fits the screen width. Taller screens (tablets) show more sky, and wider phones (21:9) get slimmer side panels. Interface size is set from the screen's *physical* size, so buttons are big enough on phones and not oversized on tablets.
- **Aiming:** drag from your tank to aim the angle. **Power:** a large slider on the side, or drag distance. **Fine-tune buttons** (±0.1°, ±1 power) for precision. A **big Fire button**. Pinch to zoom, drag to pan, and the camera follows the shell.
- **Tablets:** two-column shop, larger HUD, and room to see the whole battlefield at once.
- **Haptics:** a light tick when adjusting aim, a thump when firing, and a rumble scaled to explosion size.
- **Auto-save** after every turn and whenever the app goes to the background.

### 6.8 Neon look
- Dark gradient skies with a distant grid horizon and a sunset or moon glow.
- Glow is done with cheap **additive-blended glow sprites and edge shaders** rather than expensive full-screen effects. That's how we hit 60 fps on mid-range phones.
- Particle explosions, shockwave rings, glowing smoke trails, subtle screen shake, and a brief flash for nukes.
- Fonts: open-licensed (SIL OFL) futuristic fonts such as *Orbitron* / *Exo 2*, which are free for commercial use.

### 6.9 Accessibility
- **Colorblind-friendly tank colors** (a palette tested for the common color-vision types), *plus* each tank has a **distinct shape/emblem**, so color is never the only cue.
- **Text size** 80–150%.
- Separate toggles/volumes for **sound effects, music and haptics**. Toggles for **screen shake** and **reduced flashing**; the reduced-flashing toggle matters for a neon game with bright explosions, for players sensitive to flashes.
- Optional left-handed layout (Fire button on the left).

### 6.10 Sound
- Effects come from a retro-synth sound generator ("sfxr"-style). We store the generator settings in the project, so every sound can be regenerated or tweaked, and **you own all of it**.
- Separate **Music** and **Effects** audio channels from day one, so a music track can be dropped in later without code changes.

---

## 7. Online multiplayer (Firebase)

### 7.1 How a match works
1. A host creates a match and gets a **6-character invite code** plus a share link (WhatsApp, SMS, etc.).
2. Friends join with the code or link. The host can also add AI tanks.
3. The match lives in Firebase as **settings + seed + an ordered list of actions**.
4. **Live mode:** everyone is connected, and each new action appears on all phones within about a second.
5. **Async mode:** take your turn whenever you like, and a **push notification** tells you when it's your turn again.
6. The same match can switch freely between the two: if everyone is online it feels live, and if someone leaves it becomes async.

### 7.2 Disconnects and resuming
- A dropped connection shows "Reconnecting…" and catches up automatically by replaying missed actions.
- Interrupted matches appear in a **"Your matches"** list and resume from the latest state.
- **Turn timers** (set by the host): live mode, e.g. 60 seconds, then your turn is skipped; async mode, e.g. 72 hours, then an AI takes over your tank for that turn, or the match ends, depending on the host's setting.
- **AI tanks in online matches:** because the AI is deterministic, *any* player's phone can compute the AI's turn. Every phone computes the same move, so AI turns never wait on the host.

### 7.3 Cheat protection (appropriate for a friends-only game)
- **Actions only:** phones send "angle, power, weapon," never results, so results can't be faked.
- **Database rules** (enforced by Firebase's servers): only the player whose turn it is can add an action; actions must be in valid ranges; nobody can edit past actions.
- **Fingerprint cross-check:** every phone reports its state fingerprint after each turn, and mismatches are flagged.
- **Purchases:** a Cloud Function verifies the full-unlock purchase with Google before allowing match hosting.
- *Future option if ever needed:* a server that replays matches with Godot in headless (no-graphics) mode to settle disputes.

### 7.4 Accounts
- Sign-in is **automatic and anonymous** (no form to fill in), with optional **Google sign-in** to keep online matches when you switch phones.
- **Delete my online data** button in Settings, plus a web page for the same. Google requires this for apps that create accounts.

### 7.5 Safety tools: blocking, reporting, names
- **Block a player:** they can't invite you, join your matches or see when you're online, and you won't see their name or invites. Blocks are enforced by the server, not just hidden in the app.
- **Report a player** (e.g. for an offensive name): reports go to a private list in Firebase that you review (I'll include a simple guide). A name is **automatically hidden after 3 reports from different players** until you review it.
- **Display names** pass through a bad-word filter, and players can be renamed if they're reported.
- Display names are the only player-made content other players can see. These tools cover what Google expects for that, even in a friends-only game.

### 7.6 Cost (rough)
| Usage | Monthly cost |
|---|---|
| Development and small launch | **$0** (inside free allowances) |
| A few thousand active players | **~$0–10** |
| A hit (tens of thousands of daily players) | **~$25–100** |

Firebase's pay-as-you-go plan (required for Cloud Functions) needs a card on file. I'll walk you through setting a **budget alert** (e.g. $10) so there are no surprises. Push notifications are free.

---

## 8. Team setup: AI helpers (subagents)

I (the main session) plan, design interfaces, review every change, and run the tests. The implementation helpers live in `.claude/agents/` and run on **Sonnet 5.5**:

| Helper | Owns | Never touches |
|---|---|---|
| `core-sim-dev` | `game/core/`: math, RNG, terrain, ballistics, weapons, damage, economy, rounds + their tests | graphics, UI |
| `show-ui-dev` | `game/show/`, `game/ui/`: rendering, shaders, particles, controls, HUD, menus, shop, accessibility, audio | simulation rules |
| `ai-dev` | `game/ai/` + AI tests | simulation internals (uses its public interface only) |
| `backend-dev` | `firebase/`, `game/net/`: rules, Cloud Functions, rule tests, Godot network client | game rules |
| `release-eng` | `.github/workflows/`, Android export, signing, billing plugin, `store/` | gameplay code |
| `qa-tester` | Extra tests: determinism "golden" fingerprints, edge cases, bug hunts. Reports problems, doesn't fix gameplay code | — |

Each task I hand out states: files the helper may touch, the interface to follow, and **acceptance criteria** (specific tests that must pass). Tasks without dependencies on each other run **in parallel**. A task is marked done in `PROGRESS.md` only after I've reviewed it and the full test suite plus the build pass.

---

## 9. Testing and quality
- **Automated tests** (GUT framework, run headless, i.e. without a screen) for physics, terrain, damage, economy, shop, AI, save/load and determinism. Backend rules are tested in Firebase's local emulator.
- **Every push to GitHub** runs the tests, then builds a debug APK. Milestone builds are attached to a **GitHub Release** you can open on your phone.
- **Performance budget:** 60 fps on mid-range phones, with a hidden **FPS/frame-time overlay** (tap the version number 5 times).
  ⚠️ **Your S26 Ultra is a top-end phone and will hide slowness.** I'll keep strict frame-time budgets, and before release we'll test on a mid-range device. Firebase Test Lab offers a few free real-device tests per day, or you could borrow a cheaper phone (e.g. a Galaxy A-series).
- **Offline:** single-player and pass-and-play never touch the network.

---

## 10. Milestones and tasks

Each milestone ends with a plain-language summary and step-by-step phone test instructions for you.

### M1 — Plan (this document) ✅ once you approve

### M2 — Playable prototype (terrain, 2 tanks, 1 weapon, wind)
Parallel batch 1:
- `release-eng`: Godot project skeleton, GUT test setup, GitHub Actions (tests + debug APK), Android export settings (min API 26, landscape).
- `core-sim-dev`: fixed math + RNG + terrain grid/generation/carving/settling + ballistics with wind + Pulse Missile + damage + turn switching + fingerprint, all with tests.

Batch 2 (after batch 1):
- `show-ui-dev`: battlefield rendering (neon terrain shader), tanks, shell trail, explosion, basic touch aiming + power slider + Fire button, wind indicator.
- `qa-tester`: determinism golden tests.

**Done when:** you can install the APK, take turns with 2 tanks, see wind affect shots, and blow holes in collapsing terrain.

### M3 — Full single-player loop
- `core-sim-dev`: all 21 weapons, all items, fall damage, chutes, fuel/move, shields, rounds, money, shop logic, save/load.
- `show-ui-dev`: shop screen, round summary, match setup screen, weapon/item picker, auto-save/resume.
- `qa-tester`: weapon edge cases (splitters near the ceiling, tunnels under tanks, fire flowing into pits…).

### M4 — AI opponents
- `ai-dev`: aiming search, error model, wind handling, bracketing, weapon choice, shop strategy, target selection, 4 levels. Tests: e.g. *Expert hits a stationary target in ≤ 2 shots in 90% of seeded scenarios; Easy's first shot misses by a "believable" margin in 90%.*
- `show-ui-dev`: per-tank difficulty selection, AI "thinking" turret animation.

### M5 — Polish, sound, effects
- `show-ui-dev`: particles, screen shake, haptics, camera, menus, transitions, terrain themes, accessibility settings, generated sound effects, music channel, free/full gating screens.
- `show-ui-dev`: **Skin Studio** (editor, save/load skins on device, image import gated to the full version).
- `release-eng`: Google Play Billing plugin + "full unlock" (testable via Play's test purchases once the app is on a test track).

### M6 — Local pass-and-play
- `show-ui-dev`: "Pass to Player 2" screen (hides the shop/aim between players), 2–8 humans, mixed with AI.

### M7 — Online multiplayer
- `backend-dev`: Firebase project config, database rules + emulator tests, Cloud Functions (create/join by code, turn notifications, timeouts, purchase verification, data deletion, **block/report**), Godot network client, reconnect/resume.
- `show-ui-dev`: online lobby, invite/share, "Your matches" list, reconnecting states, block/report screens, display-name setup.
- `qa-tester`: two-device simulation tests (two headless game instances against the emulator), disconnect scenarios, tampered-action rejection.

### M8 — Play Store release prep
- `release-eng`: release signing (upload key + Play App Signing), AAB build on tagged releases, target API check, privacy policy (hosted free on GitHub Pages), Data Safety answers, store listing text, feature graphic, phone **and tablet** screenshots (captured automatically), content rating questionnaire answers, Play Pass application notes.

---

## 11. Store and legal checklist (prepared in M8)
- **Data Safety (draft):** collects an anonymous account ID, optional display name, online match data, and a device notification token. **No** location, contacts, ads, analytics or tracking. Encrypted in transit; users can request deletion. Purchases are handled by Google Play.
- **No ad SDKs, no analytics SDKs.** Crash reporting stays *off* unless you decide otherwise later.
- **Original IP:** no "Scorched Earth" name, weapon names, art, sounds or text. Everything is newly named and generated.
- **Google Play developer account (your action; your old one was closed, so you'll create a new one):**
  - Sign up at play.google.com/console ($25 one-time). Identity verification can take a few days to a couple of weeks, so **start during M2–M3**.
  - ⚠️ As a **new personal account**, you must run a **closed test with at least 12 testers who stay opted in for 14 days** before you can publish publicly. **Plan:** start the closed test around M5–M6 with the in-progress game, so the 14 days pass while we build online play. Start lining up 12+ friends now. They need Android phones and a Google account.
  - Set up a **payments profile** (needed to sell the unlock).
  - Once the account exists, test builds can also come through the Play Store's **internal testing** track, which is easier than installing APK files by hand.

---

## 12. Future ideas (not in the first release)
- **Matchmaking** with strangers.
- **Sharing skins** with friends or in a public gallery. This would need moderation (report, review, removal) because other people would see the content.
- **Player-made sounds** (e.g. record your own "fire" or "victory" sound), following the same model as skins: private to the creator first, sharing later only with moderation.
- Google Play Games achievements and leaderboards.
- Translations.
- Campaign / challenge mode (scripted puzzles: "hit the target with exactly one Riptide Anchor").
- Replays: watch or share a match, which is easy because a match is just a list of actions.
- Team modes and custom-rule presets shared via code.

---

## 13. Risks and how we handle them
| Risk | Plan |
|---|---|
| GDScript too slow for big terrain changes (e.g. Supernova) | Keep the grid modest, update only the changed region, profile early in M2; move hot loops to C++ (GDExtension) only if needed. |
| Results differ between phones | Whole-number math only, golden fingerprint tests in CI, fingerprint cross-check online. |
| Your test phone hides performance problems | Frame-time budgets, FPS overlay, test on a mid-range device before release. |
| Play Pass not accepted | The game works fine without it, since the free/unlock model stands alone. |
| Firebase cost surprise | Budget alerts; the action-list design uses very little data per match. |
| Cloud session can't download tools (see below) | Mirror workaround below; GitHub Actions runs every test and build anyway. |

**Environment note:** this cloud workspace can download files from **your own project's GitHub page** but not from other projects' release pages (such as Godot's). Workaround, no action needed from you: in M2, a small GitHub Actions job copies the official Godot program into your project's **Releases** page, and I download it from there. Google's Android download server (`dl.google.com`) now works, thanks to your network change.
