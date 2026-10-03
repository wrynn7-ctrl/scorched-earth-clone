# PROGRESS

| Milestone | Status |
|---|---|
| M1 — Clarifying questions → PLAN.md → approval | ✅ Approved 2026-10-02 |
| M2 — Playable prototype | ✅ Done 2026-10-02 (owner tested on S26 Ultra: smooth, looks good) |
| M3 — Full single-player loop | ✅ Done 2026-10-02 (owner: works well; edge + scrollbar fixes confirmed on device) |
| M4 — AI opponents | ✅ Done 2026-10-03 (owner: very good; Easy too sharp → retune; angle buttons → screen-relative) |
| M5 — Polish, sound, effects | 🟡 In progress (started while owner tests M4) |
| M6 — Local pass-and-play | ⬜ Not started |
| M7 — Online multiplayer | ⬜ Not started |
| M8 — Play Store release prep | ⬜ Not started |

## Log

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
| M4-T Owner feedback: Easy CPU dials in too fast → weaker/inconsistent correction | ai-dev | 🟡 running |
| M5-ANGLE Owner feedback: ◀/▶ move the barrel toward screen left/right; readout = elevation on facing side + facing marker | show-ui-dev | ✅ reviewed |
| M5-C Free tier: ≤ 4 tanks, rounds ≤ 5 in core | core-sim-dev | ✅ reviewed |
| M5-A Sound: generated sfx (sfxr-style), AudioDirector, volumes, music bus | show-ui-dev | ✅ reviewed (31 sfx, 1.4 MB; needs ear-check on device) |
| M5-B Terrain themes (5), follow-cam, transitions, title polish | show-ui-dev | ✅ reviewed (327 show+ui tests) |
| M5-R Gradle builds, Play Billing plugin, AAB in CI | release-eng | ✅ reviewed (APK 79 MB arm64; AAB 53 MB both ABIs; CI to verify) |
| M5-E Entitlement service, free/full gating UI, Unlock screen, Play Billing setup guide | show-ui-dev | 🟡 running |
| M5-S Skin Studio (editor, local skins, image import for full) | show-ui-dev | 🟡 running |
| M5-P Polish: shop quantity steppers, left-handed layout, multi-touch, camera-follow toggle in Settings + persistence, overlay fade-out, smoother Ice Circuit moon | show-ui-dev | ⬜ wave 3 |
| M5-Q QA pass | qa-tester | ⬜ end |

## Decisions / notes
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
- Team mode (if added later): AI already guards teammates from splash after M4-F; ally-lob verification exists but is unexercised while team == id.
- Aim adjustments made before an autosave aren't restored (aim isn't in sim state); tank returns to its stored angle/power.
- Shop buys 1 bundle / sells 1 unit per tap; consider quantity steppers in M5 polish.
- Seeds for golden fixtures v2 were searched for full weapon/item coverage; re-search if the QA bot changes.

## Open items for the owner
- Pick a final title (PLAN.md §2); "Craterline" is the working title.
- ✅ Network domains added (GitHub release downloads still blocked by per-repo policy; mirror workaround planned).
- Create a new Google Play developer account during M2–M3; line up 12+ testers for the 14-day closed test (start ~M5–M6).
