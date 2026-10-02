#!/usr/bin/env bash
# Renders a scene under xvfb (software GL) and saves a PNG of the viewport.
#
#   tools/screenshot.sh <scene res path | main> <WxH> <dpi> <out.png> <seconds> [extra args]
#
#   scene     e.g. res://show/battle/battle_scene.tscn, or `main` for the project's main scene (title)
#   WxH       window size in pixels, e.g. 2340x1080 (phone) or 2048x1536 (tablet)
#   dpi       emulated screen density used by UiScale, e.g. 500 (phone) or 264 (tablet)
#   out.png   output file (relative paths are relative to your current directory)
#   seconds   real seconds to wait after the scene starts before capturing
#   extra     passed to the game as user args (after `--`), see game/show/shot_args.gd:
#             --seed=N --rounds=N --speed=F --aim=ANGLE,POWER --auto-fire --auto-play --auto-next
#
# Examples:
#   tools/screenshot.sh main 2340x1080 500 out/title.png 1.5
#   tools/screenshot.sh res://show/battle/battle_scene.tscn 2340x1080 500 out/aim.png 1.2 --seed=7
#
# Env: GODOT_BIN (see setup_godot.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME="${ROOT}/game"

if (( $# < 5 )); then
  sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
fi
SCENE="$1"; SIZE="$2"; DPI="$3"; OUT="$4"; SECONDS_WAIT="$5"
shift 5

[[ "${SIZE}" =~ ^[0-9]+x[0-9]+$ ]] || { echo "screenshot: size must look like 2340x1080, got '${SIZE}'" >&2; exit 2; }
command -v xvfb-run >/dev/null || { echo "screenshot: xvfb-run is required (apt install xvfb)" >&2; exit 1; }
W="${SIZE%x*}"; H="${SIZE#*x}"

mkdir -p "$(dirname "${OUT}")"
OUT="$(cd "$(dirname "${OUT}")" && pwd)/$(basename "${OUT}")"

GODOT="$("${ROOT}/tools/setup_godot.sh")"

# Make sure class_name scripts / translations are imported (same rule as run_tests.sh).
CACHE="${GAME}/.godot/global_script_class_cache.cfg"
if [[ ! -f "${CACHE}" ]] || [[ -n "$(find "${GAME}" -path "${GAME}/.godot" -prune -o \( -name '*.gd' -o -name 'strings.csv' \) -newer "${CACHE}" -print -quit)" ]]; then
  echo "screenshot: importing project..." >&2
  "${GODOT}" --headless --path "${GAME}" --import >/dev/null 2>&1 || { echo "screenshot: import failed" >&2; exit 1; }
fi

SCENE_ARG=()
if [[ "${SCENE}" != "main" ]]; then
  SCENE_ARG=("${SCENE}")
fi

rm -f "${OUT}"
# The virtual screen must be at least as large as the window.
xvfb-run -a -s "-screen 0 $((W + 200))x$((H + 200))x24" \
  "${GODOT}" --path "${GAME}" --rendering-driver opengl3 --resolution "${W}x${H}" "${SCENE_ARG[@]}" \
  -- "--shot=${OUT}" "--shot-time=${SECONDS_WAIT}" "--dpi=${DPI}" "$@" 2>&1 \
  | grep -E "^(shot:|SCRIPT ERROR|ERROR|WARNING: .*shot|.*Parse Error)" || true

[[ -s "${OUT}" ]] || { echo "screenshot: FAILED, no file written: ${OUT}" >&2; exit 1; }
echo "${OUT}"
