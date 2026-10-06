#!/usr/bin/env bash
# Generates firebase/functions/src/name_glyphs.json: the characters the game's NameFilter can keep (its font can draw them).
# Needs Godot (tools/setup_godot.sh). Run it again whenever NameFilter, its font or the font's import changes, and commit the
# result. The GUT test game/tests/net/test_name_glyph_table.gd fails when the committed file is out of date.
#
#   tools/firebase/gen_name_glyphs.sh            write the JSON file
#   tools/firebase/gen_name_glyphs.sh --check    exit 1 when the committed file differs
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -z "$ROOT" ] || [ ! -f "$ROOT/game/project.godot" ]; then
  echo "game/project.godot not found (looked in '$ROOT')" >&2
  exit 2
fi
TARGET="$ROOT/firebase/functions/src/name_glyphs.json"
GODOT="$("$ROOT/tools/setup_godot.sh")"

# Make sure class_name scripts are registered (a fresh checkout has no cache).
if [ ! -f "$ROOT/game/.godot/global_script_class_cache.cfg" ]; then
  "$GODOT" --headless --path "$ROOT/game" --import >/dev/null 2>&1
fi

OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT
"$GODOT" --headless --path "$ROOT/game" -s "$ROOT/tools/firebase/gen_name_glyphs.gd" -- "$OUT" >&2

if [ "${1:-}" = "--check" ]; then
  if ! cmp -s "$OUT" "$TARGET"; then
    echo "name_glyphs.json is out of date. Run: tools/firebase/gen_name_glyphs.sh and commit it." >&2
    exit 1
  fi
  echo "name_glyphs.json is up to date"
else
  cp "$OUT" "$TARGET"
  echo "wrote $TARGET"
fi
