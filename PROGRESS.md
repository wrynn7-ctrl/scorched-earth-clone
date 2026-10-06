# PROGRESS

| Milestone | Status |
|---|---|
| M1 — Clarifying questions → PLAN.md → approval | ✅ Approved 2026-10-02 |
| M2 — Playable prototype | ✅ Done 2026-10-02 (owner tested on S26 Ultra: smooth, looks good) |
| M3 — Full single-player loop | ✅ Done 2026-10-02 (owner: works well; edge + scrollbar fixes confirmed on device) |
| M4 — AI opponents | ✅ Done 2026-10-03 (owner: very good; Easy too sharp → retune; angle buttons → screen-relative) |
| M5 — Polish, sound, effects | ✅ Done 2026-10-04 (owner: sound redesign "much better"; audio delay fix "works great") |
| M6 — Local pass-and-play | 🟡 Built + QA green; waiting for owner phone test |
| M7 — Online multiplayer | 🟡 In progress (emulator-first) |
| M8 — Play Store release prep | ⬜ Not started |

## Log

### 2026-10-06
- M7 decisions (owner): emulator first, real Firebase project later; friends list + codes; quick messages only; online supports CPUs, teams, Love Edition, shared-phone seats.
- M6 build published; owner moved on to M7 (M6 phone feedback still welcome).

### 2026-10-05
- M6 decisions (owner): banner only between human turns; names remembered; teams yes (team per tank in setup, friendly fire chosen per match, own wallet + team win bonus); sudden death after 10 × tank-count total turns.

### 2026-10-04
- Owner confirmed the sound redesign and the 48 kHz audio-delay fix on the phone. **M5 done.**
- Owner tested the M5 build: works well. Sound redo requested (heavy sci-fi with real bass; Love Edition soothing and romantic; vibration with a toggle). Contract in ARCHITECTURE §33a.

### 2026-10-03
- Owner request: secret **Love Edition** (tap logo 7× → hidden button; 2 players, hearts fill the opponent's love meter from 0; hearts burst and grow flowers; smiley over the winner). Contract in ARCHITECTURE §37.

### 2026-10-02
- Asked clarifying questions; received answers (Godot 4, live + async friends-only online via Firebase, neon/synthwave, free-to-try + one unlock + Play Pass, Android 8.0+, phones + tablets, GitHub Actions builds, English first).
- Wrote PLAN.md draft.
- PLAN v2: Skin Studio (private, image import = full version), block/report/name filter, new Play account timeline, Godot download workaround.

- Plan approved (image import in M5; reports: review list + auto-hide after 3 reports).
- Godot 4.7.2 mirrored into this repo's release `tools-godot-4.7.2` (workaround for the container's download policy).
- Added CLAUDE.md (rules for all agents), docs/ARCHITECTURE.md (binding technical contract), and 6 subagent definitions in .claude/agents/.

## M2 tasks
| Task | Agent | Status |
|---|---|---|
| M2-F Project foundation (project.godot, GUT, test runner, determinism check) | release-eng | ✅ reviewed (GUT 9.7.1) |
| M2-C Core simulation (math, RNG, terrain, ballistics, damage, turns, fingerprint) | core-sim-dev | ✅ reviewed (91 tests; generate 6 ms, shot 10 ms, fingerprint 13 ms) |
| M2-CI GitHub Actions: tests + debug APK + Android export | release-eng | ✅ reviewed (CI green end-to-end: tests → APK → dev-latest release) |
| M2-S1 Neon visuals + touch controls (standalone demo) | show-ui-dev | ✅ reviewed (screenshots in docs/screenshots) |
| M2-S2 Wire visuals to the simulation (playable 2-tank game) | show-ui-dev | ✅ reviewed (200 tests total) |
| M2-Q Determinism golden tests, edge cases, fuzz | qa-tester | ✅ reviewed (6 golden replays, 300-match fuzz; 2 low bugs fixed) |

## M3 tasks
| Task | Agent | Status |
|---|---|---|
| M2-UI-1 Owner feedback: angle ±0.1 buttons → neon up/down arrows | show-ui-dev | ✅ reviewed (202 tests) |
| M3 contract (ARCHITECTURE §16–§24) | lead | ✅ written |
| M3-C1 Phases, catalog, economy, shop/move/item actions, shields/chute/repair, saves | core-sim-dev | ✅ reviewed (329 core+qa tests; shot ≤14 ms) |
| M3-C2 Weapon behaviours (splitter, roller, tunneler, dirt, sludge, fire, seeker, beam, static, well, anchor) | core-sim-dev | ✅ reviewed (617 tests; all weapons < 40 ms) |
| M3-U1 Match setup, shop screen, weapon/item picker, move/item controls, round summary, autosave/continue, settings | show-ui-dev | ✅ reviewed (save 1.44 MB → 9.9 KB zstd) |
| M3-U2 HUD panels fade when tanks/action are behind them, off-screen shell marker, 21-weapon playback verification, small UI fixes | show-ui-dev | ✅ reviewed |
| M3-Q Weapon edge cases, economy invariants, save/load + JSON fuzz, golden replays v2 | qa-tester | ✅ reviewed (740 tests; 0 high/medium bugs) |
| M3-F Hardening: move dx overflow, save range validation, chute only when it saves HP | core-sim-dev | ✅ reviewed |
| M3-CI Split CI tests into parallel jobs, runner suite selection, timeout, pin Ubuntu 24.04 | release-eng | ✅ reviewed (CI 4 min, 759 tests) |
| M3-UI-EDGE Owner bug: on the S26 Ultra the HUD is laid out in a smaller rect (gaps right/left/bottom); re-layout on resize, canvas-unit safe area, diagnostics overlay | show-ui-dev | ⚠️ not fixed on device (diagnostics: display reports are sane; only the battle HUD is wrong) |
| M3-UI-EDGE-2 Battle HUD forced to the visible rect every layout pass + in-battle diagnostics (long-press pause) | show-ui-dev | ✅ confirmed working on owner's S26 Ultra |
| M3-UI-SCROLL Owner feedback: shop scrollbar too thin → ≥ 20 dp touch scrollbars everywhere + swipe-to-scroll | show-ui-dev | ✅ reviewed |

## M4 tasks
| Task | Agent | Status |
|---|---|---|
| M3-UI-ARROWS-2 Owner feedback: angle buttons show ◀ (−0.1°) and ▶ (+0.1°) | show-ui-dev | ✅ reviewed |
| M4 contract (ARCHITECTURE §27–§30) | lead | ✅ written |
| M4-C Controllers in settings + `last_fire_*` AI memory in TankState | core-sim-dev | ✅ reviewed |
| M4-A AiPlayer: aim solver, error model, weapon/item/shop/target choice, 4 levels + statistical tests | ai-dev | ✅ reviewed (retuned to human-like bands) |
| M4-U Setup AI slots, AI turn playback (thinking/turret sweep), AI shopping, CPU turn speed | show-ui-dev | ✅ reviewed (230 show+ui tests) |
| M4-Q AI fuzz, determinism across save/load, AiFlight drift guard, adversarial situations | qa-tester | ✅ reviewed (0 crashes/invalid actions in 7,179 turns; 4 issues found) |
| M4-F AI fixes: self-damage guard (all levels + teammates), Easy/Normal ammo buying (pacing), Expert/Hard repair at ≤ 20 HP, AiFlight sub-step terrain + real sky height | ai-dev | ✅ reviewed (0 self-hits in 6,194 shots; max round 116 turns; 0 drift; 1,038 tests green) |

## M5 tasks
| Task | Agent | Status |
|---|---|---|
| M5 contract (ARCHITECTURE §32–§35: entitlement + free/full table, audio, themes, skins) | lead | ✅ written |
| M4-T Owner feedback: Easy CPU dials in too fast → weaker/inconsistent correction | ai-dev | ✅ reviewed (Easy 5/16/33% within 1/3/6 shots) |
| M5-ANGLE Owner feedback: ◀/▶ move the barrel toward screen left/right; readout = elevation on facing side + facing marker | show-ui-dev | ✅ reviewed |
| M5-C Free tier: ≤ 4 tanks, rounds ≤ 5 in core | core-sim-dev | ✅ reviewed |
| M5-A Sound: generated sfx (sfxr-style), AudioDirector, volumes, music bus | show-ui-dev | ✅ reviewed (31 sfx, 1.4 MB; needs ear-check on device) |
| M5-B Terrain themes (5), follow-cam, transitions, title polish | show-ui-dev | ✅ reviewed (327 show+ui tests) |
| M5-R Gradle builds, Play Billing plugin, AAB in CI | release-eng | ✅ reviewed (APK 79 MB arm64; AAB 53 MB both ABIs; CI to verify) |
| M5-E Entitlement service, free/full gating UI, Unlock screen, Play Billing setup guide | show-ui-dev | ✅ reviewed (real purchases need Play Console setup) |
| M5-S Skin Studio (editor, local skins, image import for full) | show-ui-dev | ✅ reviewed (Android picker untested on device) |
| M5-P Polish: shop quantity steppers, left-handed layout, multi-touch, camera-follow toggle in Settings + persistence, overlay fade-out, smoother Ice Circuit moon, Skin Studio preview framing + phone slider scrolling | show-ui-dev | ✅ reviewed (504 show+ui tests) |
| M5-AI CPU stalemate fix: move closer / best-effort shot when nothing can reach; buy fuel | ai-dev | ✅ reviewed (134 ai tests; max round 152) |
| LOVE-C Secret Love Edition — core mode (hearts fill the opponent's love meter; winner = shooter) | core-sim-dev | ✅ reviewed (530 core tests) |
| LOVE-A Love Edition — CPU fires hearts | ai-dev | ✅ reviewed (146 ai tests; turns to fill: Easy 21, Normal 11, Hard 5.5, Expert 4.8) |
| LOVE-U Love Edition — secret unlock (tap logo 7×), love theme, meters, heart/flower FX, smiley win, sfx | show-ui-dev | ✅ reviewed (563 show+ui tests) |
| M5-Q QA pass (M5 + Love Edition) | qa-tester | ✅ reviewed (1,531 tests; 0 critical/high/medium; 5 low bugs) |
| M5-QF QA fixes: love save win check, free saves with full-tier items, skin clamp/cap/opaque bake, billing grant-before-ack, audio type safety | core-sim-dev + show-ui-dev | ✅ reviewed (core 546, qa 292 green; 0 pending bugs) |
| M5-SND Owner feedback: sounds too wimpy → heavy sci-fi redesign (all sounds), soothing romantic Love sounds + sweeter win melody, vibration on shots/explosions (ARCHITECTURE §33a) | show-ui-dev | ✅ reviewed (35 sounds regenerated, 3.3 MB; 892 show+ui+qa tests; needs ear-check on device) |
| M5-LAT Owner: all sounds ~750 ms late on Bluetooth headphones → 48 kHz mix rate (native on current phones), audio latency line in diagnostics | lead | ✅ confirmed on owner's phone |

## M6 tasks
| Task | Agent | Status |
|---|---|---|
| M6 contract (ARCHITECTURE §39–§42: teams, friendly-fire option, sudden death at 10 turns × tanks, names, turn banner) | lead | ✅ written |
| M6-C Core: teams + team round end/pay + friendly-fire option + team standings; sudden death; save v4 | core-sim-dev | ✅ reviewed (939 core+qa tests; no-teams replays bit-identical to pre-M6) |
| M6-U1 Names (setup, remembered, filter) + turn banner + named shop hand-over | show-ui-dev | ✅ reviewed (662 show+ui tests; keyboard untested on device) |
| M6-A AI: enemy-only targeting, teammate guard per friendly-fire setting, never pass for teammate risk or in sudden death | ai-dev | ✅ reviewed (165 ai tests; 0 passes, ≤ 0.1% teammate hits, 0 self hits; no-teams actions identical) |
| M6-U2 Team chips + friendly-fire toggle in setup, team badges, team results, sudden-death banner | show-ui-dev | ✅ reviewed (1,014 show+ui+qa tests) |
| M6-Q QA pass | qa-tester | ✅ reviewed (1,895 tests; 0 critical/high; 1 medium + 4 low) |
| M6-QF QA fixes: dead-tank shield visuals/mismatch, safe meta reads, staggered name tags at 8 players, summary fit, name-filter look-alikes | show-ui-dev | ✅ reviewed (show 353, ui 373, qa 371 green; 0 pending bugs) |

## M7 tasks
| Task | Agent | Status |
|---|---|---|
| M7 contract (ARCHITECTURE §43–§50) | lead | ✅ written |
| M7-B Firebase backend: emulator project, data model, rules, functions (friend codes, requests, blocks, reports, names, invites, matches, timeouts, FCM mock, delete data, purchase stub) + tests + CI job | backend-dev | ✅ reviewed (264 emulator tests: 101 rules + 163 functions) |
| M7-N Godot net client: auth, RTDB REST + streaming, NetReplay (auto/timeout markers), optimistic append, presence, friends/invites API; multi-client tests vs emulator | backend-dev | ✅ reviewed (80 net tests; replay equivalent to offline; async-timeout flag follow-up in progress) |
| M7-U Online UI: name setup, Your matches, Friends, Join/Host, lobby, in-match status/timers, quick messages, player menu, settings | show-ui-dev | ✅ reviewed (1,439 show+ui+net+qa tests incl. two-phone UI flow vs emulator) |
| M7-R Android: FCM plugin, Google sign-in plugin, share sheet + deep links, FIREBASE_SETUP.md | release-eng | ✅ reviewed (APK +1.5 MB; builds with/without Firebase; Kotlin untested on device; CI steps applied) |
| M7-G Gaps: add-friend by uid for match members; send purchase token to verifyPurchase | backend-dev | ✅ reviewed (106 rules + 170 functions + 88 net + 660 ui tests) |
| M7-Q QA: multi-client emulator scenarios, disconnects, tampering | qa-tester | ✅ reviewed (rules attacks + 3,000-write fuzz, 20 chaos matches, 2,000-name parity; 7 medium + ~10 low) |
| M7-QF-B Backend/net fixes for M7-Q | backend-dev | 🟡 in progress |
| M7-QF-U UI fixes for M7-Q (back button with confirm, stale lobby ids, UI-flow test race) | show-ui-dev | ✅ reviewed (show+ui 1,025 green 5/5; UI-flow test 5/5) |

## Decisions / notes
- **Angle readout (owner-confirmed 2026-10-03):** always 0–90° elevation from the ground on the facing side, with a facing chevron. Pressing past 90° keeps turning over to the other side (the readout counts down, facing flips). Facing changes by drag or arrows only; no flip button.
- **S26 Ultra HUD edge bug — root cause confirmed** from the owner's in-battle diagnostics: the BattleHud root (a Control under a CanvasLayer) was left at a stale rect when the battle laid out before the Android window settled. LayoutGuard corrected it once ("layout corrections: HUD 1") and the HUD is 1950×900 afterwards. Keep LayoutGuard + diagnostics as a permanent safety net.
- Android package id is `com.wrynn7.craterline` for test builds. **Must be finalized before the first Play upload (it can never change).**
- Gradle builds since M5: minSdk 26 (Android 8), targetSdk 36. Test APK is arm64-only (79 MB); the Play AAB includes arm64 + armv7.
- The debug keystore is committed on purpose (public, debug-only), so test builds install over each other.

## Polish backlog (noticed in review; M5 unless it blocks earlier)
- ✅ Off-screen shell marker added (M3-U2). Follow-cam still optional for M5.
- ✅ Title subtitle backing plate (M3-U2).
- ✅ Settings persisted (M3-U1).
- Real multi-touch (aim + slider at once) untested; Android emulates touch as mouse.

## Carry-overs for M3 (from QA) — all ✅ done in M3

## Notes for later milestones
- Possible stalemate: two CPUs that can't reach each other (e.g. Spark Dart only, far apart, headwind) never move. Consider a CPU 'move closer' fallback or a round turn limit (sudden death) in a later polish pass.
- Team mode (if added later): AI already guards teammates from splash after M4-F; ally-lob verification exists but is unexercised while team == id.
- Aim adjustments made before an autosave aren't restored (aim isn't in sim state); tank returns to its stored angle/power.
- Shop buys 1 bundle / sells 1 unit per tap; consider quantity steppers in M5 polish.
- Easy vs Easy at the far map edges in strong wind can run 190–550 turns (M5-Q). Normal placement is fine (≤ 46). Consider a round turn limit / sudden death in M6.
- Test helpers that delete files must never follow symlinks or leave their own `user://` folder (a QA helper once wiped /tmp in the dev container).
- Seeds for golden fixtures v2 were searched for full weapon/item coverage; re-search if the QA bot changes.

## Open items for the owner
- Test builds now start in the **free** version. Debug toggle: Settings → tap version 5× → "Debug: full version".
- Play Billing: follow `docs/PLAY_BILLING_SETUP.md` once the Play developer account exists (product id `full_unlock`).
- Pick a final title (PLAN.md §2); "Craterline" is the working title.
- ✅ Network domains added (GitHub release downloads still blocked by per-repo policy; mirror workaround planned).
- Create a new Google Play developer account during M2–M3; line up 12+ testers for the 14-day closed test (start ~M5–M6).
