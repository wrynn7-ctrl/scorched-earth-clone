#!/usr/bin/env bash
# Runs all GUT tests headless. Extra args are passed through to GUT
# (e.g. `tools/run_tests.sh -gselect=test_terrain`).
#
# Exit code is non-zero if: Godot exits non-zero, any test fails, no tests ran, or the
# output contains script/parse errors (GUT can exit 0 when a test script fails to load).
# Env: GODOT_BIN (override binary), GUT_TIMEOUT (seconds, default 600).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME="${ROOT}/game"
GODOT="$("${ROOT}/tools/setup_godot.sh")"
TIMEOUT="${GUT_TIMEOUT:-600}"

LOG_DIR="$(mktemp -d)"
trap 'rm -rf "${LOG_DIR}"' EXIT

# Import step: registers class_name scripts (global_script_class_cache.cfg) and imports
# assets such as the translation CSV. Needed on a fresh checkout, and again whenever a
# .gd file is newer than the cache (a new class_name was added).
CACHE="${GAME}/.godot/global_script_class_cache.cfg"
if [[ ! -f "${CACHE}" ]] || [[ -n "$(find "${GAME}" -path "${GAME}/.godot" -prune -o -name '*.gd' -newer "${CACHE}" -print -quit)" ]]; then
  echo "run_tests: importing project..." >&2
  if ! timeout "${TIMEOUT}" "${GODOT}" --headless --path "${GAME}" --import >"${LOG_DIR}/import.log" 2>&1; then
    cat "${LOG_DIR}/import.log" >&2
    echo "run_tests: FAILED (project import failed)" >&2
    exit 1
  fi
fi

set +e
timeout "${TIMEOUT}" "${GODOT}" --headless --path "${GAME}" -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests -ginclude_subdirs -gexit "$@" 2>&1 | tee "${LOG_DIR}/run.log"
GODOT_STATUS="${PIPESTATUS[0]}"
set -e

# Strip ANSI colour codes so patterns and counts match reliably.
CLEAN="${LOG_DIR}/clean.log"
sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g' "${LOG_DIR}/run.log" >"${CLEAN}"

count() { awk -v k="$1" '$0 ~ "^"k"[ \t]+[0-9]+" { n = $NF } END { print n + 0 }' "${CLEAN}"; }
SCRIPTS="$(count 'Scripts')"
TESTS="$(count 'Tests')"
PASSING="$(count 'Passing Tests')"
FAILING="$(count 'Failing Tests')"

PROBLEMS=()
(( GODOT_STATUS == 124 )) && PROBLEMS+=("timed out after ${TIMEOUT}s")
(( GODOT_STATUS != 0 && GODOT_STATUS != 124 )) && PROBLEMS+=("godot exit code ${GODOT_STATUS}")
(( FAILING > 0 )) && PROBLEMS+=("${FAILING} failing test(s)")
(( TESTS == 0 )) && PROBLEMS+=("no tests ran")
ERR_LINES="$(grep -n -i -E 'SCRIPT ERROR|Parse Error|failed to load|Failed to compile|Compile Error' "${CLEAN}" || true)"
if [[ -n "${ERR_LINES}" ]]; then
  PROBLEMS+=("script/parse errors in output")
  echo "---- run_tests: script errors detected ----" >&2
  echo "${ERR_LINES}" >&2
fi

if (( ${#PROBLEMS[@]} > 0 )); then
  IFS=';'; echo "run_tests: FAILED (${PROBLEMS[*]}) - scripts=${SCRIPTS} tests=${TESTS} passing=${PASSING} failing=${FAILING}" >&2
  exit 1
fi
echo "run_tests: OK - scripts=${SCRIPTS} tests=${TESTS} passing=${PASSING} failing=${FAILING}"
