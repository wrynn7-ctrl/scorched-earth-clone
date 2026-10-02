# PROGRESS

| Milestone | Status |
|---|---|
| M1 — Clarifying questions → PLAN.md → approval | ✅ Approved 2026-10-02 |
| M2 — Playable prototype | ✅ Done 2026-10-02 (owner tested on S26 Ultra: smooth, looks good) |
| M3 — Full single-player loop | 🟡 In progress |
| M4 — AI opponents | ⬜ Not started |
| M5 — Polish, sound, effects | ⬜ Not started |
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
| M3-F Hardening: move dx overflow, save range validation, chute only when it saves HP | core-sim-dev | 🟡 running |
| M3-CI Split CI tests into parallel jobs, runner suite selection, timeout, pin Ubuntu 24.04 | release-eng | 🟡 running |

## Decisions / notes
- Android package id is `com.wrynn7.craterline` for test builds. **Must be finalized before the first Play upload (it can never change).**
- Non-Gradle export gives minSdk 24 (still covers Android 8+). minSdk 26 / targetSdk 36 get enforced when Gradle builds are enabled (M5, needed for billing).
- The debug keystore is committed on purpose (public, debug-only), so test builds install over each other.

## Polish backlog (noticed in review; M5 unless it blocks earlier)
- ✅ Off-screen shell marker added (M3-U2). Follow-cam still optional for M5.
- ✅ Title subtitle backing plate (M3-U2).
- ✅ Settings persisted (M3-U1).
- Real multi-touch (aim + slider at once) untested; Android emulates touch as mouse.

## Carry-overs for M3 (from QA)
- Saves/Firebase: actions parsed from JSON have float fields → add `Simulation.normalize_action()` that int-casts before validation.
- Money for damage must use actual health removed (timeline `damage.amount` is nominal, not clamped).
- Validate/clamp `MatchSettings` (num_tanks 2..8, wind_max ≥ 0) inside `new_match` so the fingerprint stores clamped values.
- `tools/run_tests.sh` ignores `-gdir=` overrides (use `-gselect=`); fix when convenient.

## Open items for the owner
- Pick a final title (PLAN.md §2); "Craterline" is the working title.
- ✅ Network domains added (GitHub release downloads still blocked by per-repo policy; mirror workaround planned).
- Create a new Google Play developer account during M2–M3; line up 12+ testers for the 14-day closed test (start ~M5–M6).
