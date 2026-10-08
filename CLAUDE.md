# Charred Horizons — project rules for every agent

Turn-based neon artillery game for Android, built with **Godot 4.7.2** and **typed GDScript**.
The plan lives in `PLAN.md`, status in `PROGRESS.md`, the technical contracts in `docs/ARCHITECTURE.md`.
Read `docs/ARCHITECTURE.md` before writing any code.

## Hard rules
1. **Stay inside the files your task assigns you.** If you need a change elsewhere, stop and report it.
2. **Do not commit, push, or create branches.** The lead reviews and commits.
3. **`game/core/` must be deterministic:** no `float`, no decimal literals, no `randf/randi/randomize`, no `Time`/`OS` calls,
   no `sin/cos/sqrt/pow` builtins, no iteration over Dictionary keys whose order could vary by insertion path, and no engine
   physics. Use `FixedMath` and `Rng`. `tools/check_core_determinism.sh` enforces this, and it must pass.
4. **`game/core/` never touches nodes, scenes, rendering, input, or files.** It's pure logic on `RefCounted` objects.
5. **Typed GDScript everywhere:** declare types on every variable, parameter and return (`var x: int = 0`, `-> void`).
   Warnings for untyped declarations are set to error in `project.godot`.
6. **Every behaviour change comes with GUT tests.** All tests must pass before you report done.
7. **Original IP only:** never use the names "Scorched Earth" or its weapon/item names. Use the names in PLAN.md §3.
8. **All user-visible text goes through `tr()`** with keys in `game/locale/strings.csv` (English column first).

## Commands
```bash
tools/setup_godot.sh                   # one-time: installs Godot 4.7.2 to ~/.local/godot (prints the path)
tools/run_tests.sh                     # runs all GUT tests headless; exit code 0 = all passed
tools/run_tests.sh -gselect=test_terrain   # run one test file
tools/check_core_determinism.sh        # static check of the determinism rules for game/core
```

## Style
- Files `snake_case.gd`, classes `PascalCase` via `class_name`, constants `UPPER_SNAKE`, private members `_leading_underscore`.
- Keep functions short; comment the *why*, not the *what*. Match the surrounding code.
- Tests live in `game/tests/<area>/test_<thing>.gd` and extend `GutTest`.

## Final report format (when your task is done)
- Files created or changed.
- The exact test command you ran and its summary line (passed/failed counts).
- Anything you could not finish, assumptions you made, and suggested follow-ups.
