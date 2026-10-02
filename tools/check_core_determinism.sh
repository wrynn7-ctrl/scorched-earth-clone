#!/usr/bin/env bash
# Static check of the determinism rules for game/core (see CLAUDE.md rule 3/4).
# Scans game/core/**/*.gd, ignoring comments and string literals, and fails with
# file:line for every forbidden construct. Passes on an empty or missing game/core.
# Env: CORE_DIR overrides the directory to scan (used for self-tests).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="${CORE_DIR:-${ROOT}/game/core}"

if [[ ! -d "${CORE_DIR}" ]]; then
  echo "check_core_determinism: OK (no ${CORE_DIR}, nothing to scan)"
  exit 0
fi

FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "${CORE_DIR}" -type f -name '*.gd' | LC_ALL=C sort)
if (( ${#FILES[@]} == 0 )); then
  echo "check_core_determinism: OK (no .gd files under ${CORE_DIR})"
  exit 0
fi

# POSIX awk only (works with mawk and gawk). Per line: blank out string literals and
# comments with a small state machine, then test each rule against what is left.
OUT="$(awk '
function word(w)  { return "(^|[^A-Za-z0-9_])" w "([^A-Za-z0-9_]|$)" }
function call(w)  { return "(^|[^A-Za-z0-9_])" w "[ \t]*[(]" }
function add(name, re) { n++; names[n] = name; res[n] = re }
BEGIN {
  add("float",                  word("float"))
  add("float constant",         word("(PI|TAU|INF|NAN)"))
  add("decimal literal",        "(^|[^A-Za-z0-9_.])[0-9][0-9_]*[.][0-9]*")
  add("decimal literal",        "(^|[^A-Za-z0-9_])[.][0-9]+")
  add("exponent literal",       "(^|[^A-Za-z0-9_.])[0-9][0-9_]*[eE][+-]?[0-9]+")
  add("random (randf/randi/randomize)", word("(randf|randi|randomize|rand_from_seed|randfn)[a-z_]*"))
  add("RandomNumberGenerator",  word("RandomNumberGenerator"))
  add("Time.",                  "(^|[^A-Za-z0-9_])Time[.]")
  add("OS.",                    "(^|[^A-Za-z0-9_])OS[.]")
  add("FileAccess",             word("FileAccess"))
  add("float math builtin",     call("(sin|cos|tan|asin|acos|sqrt|pow|exp|log|deg_to_rad|rad_to_deg)"))
  add("atan",                   word("atan2?"))
  add("lerp",                   word("lerp[a-z_]*"))
  add("float vector/rect (use Vector2i/Rect2i)", "(^|[^A-Za-z0-9_])(Vector[234]|Rect2|PackedFloat(32|64)Array|PackedVector[234]Array)([^A-Za-z0-9_]|$)")
  add("Node / scene tree",      word("(Node|Node2D|Node3D|SceneTree)"))
  add("get_tree/get_node/$",    word("(get_tree|get_node)") "|" "[$]")
}
FNR == 1 { tri = "" }
{
  line = $0; out = ""; i = 1; L = length(line)
  while (i <= L) {
    if (tri != "") {                                  # inside a triple-quoted string
      if (substr(line, i, 3) == tri) { tri = ""; i += 3 } else i++
      continue
    }
    c = substr(line, i, 1)
    t = substr(line, i, 3)
    if (t == "\"\"\"" || t == "\047\047\047") { tri = t; out = out "\"\""; i += 3; continue }
    if (c == "#") break                               # comment: drop the rest
    if (c == "\"" || c == "\047") {                   # single-line string literal
      q = c; i++
      while (i <= L) {
        d = substr(line, i, 1)
        if (d == "\\") { i += 2; continue }
        if (d == q) { i++; break }
        i++
      }
      out = out "\"\""
      continue
    }
    out = out c; i++
  }
  hits = ""
  for (k = 1; k <= n; k++)
    if (out ~ res[k] && index(hits, names[k]) == 0) hits = hits (hits == "" ? "" : ", ") names[k]
  if (hits != "") {
    src = $0; sub(/^[ \t]+/, "", src)
    printf "%s:%d: [%s] %s\n", FILENAME, FNR, hits, src
  }
}
' "${FILES[@]}")"

if [[ -n "${OUT}" ]]; then
  echo "${OUT//${ROOT}\//}" >&2
  COUNT="$(printf '%s\n' "${OUT}" | wc -l | tr -d ' ')"
  echo "check_core_determinism: FAILED (${COUNT} offending line(s) in game/core)" >&2
  exit 1
fi
echo "check_core_determinism: OK (${#FILES[@]} file(s) scanned)"
