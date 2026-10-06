#!/usr/bin/env bash
# Runs GUT tests headless. Extra args are passed through to GUT.
#
# Selecting tests:
#   tools/run_tests.sh                          all of res://tests (one Godot process)
#   tools/run_tests.sh --suite core             one directory: res://tests/core
#   tools/run_tests.sh --suite show,ui          several suites, one Godot process each, timed separately
#   tools/run_tests.sh --suite=qa               (the = form works too)
#   tools/run_tests.sh -gdir=res://tests/core   a passed -gdir REPLACES the default (repeatable: one run each)
#   tools/run_tests.sh -gselect=test_terrain    filter by script name; combine with --suite to narrow further
# A suite name is any directory under game/tests (core, qa, show, ui, net, ...) or `all`.
# The `net` suite also runs the emulator integration tests: this script then re-runs itself inside
# tools/firebase/with_emulators.sh (Firebase emulators up, CRATERLINE_NET_EMULATOR=1; needs Java 21+ and Node 22+).
# `--suite all` does not start emulators: those tests report "pending" there.
# Note: with several suites plus -gselect, every suite must contain a match or it reports "no tests ran".
#
# Exit code is non-zero if: Godot exits non-zero, any test fails, no tests ran, or the
# output contains script/parse errors (GUT can exit 0 when a test script fails to load).
# Every selected suite is run even if an earlier one fails, so one run shows all the failures.
# Env: GODOT_BIN (override binary), GUT_TIMEOUT (seconds per Godot process, default 1500).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME="${ROOT}/game"
TESTS_DIR="${GAME}/tests"
TIMEOUT="${GUT_TIMEOUT:-1500}"

die() { echo "run_tests: ERROR: $*" >&2; exit 2; }

available_suites() {
  find "${TESTS_DIR}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | paste -sd' ' -
}

ORIG_ARGS=("$@")
# ---- Argument parsing: pull out --suite and -gdir=, pass everything else to GUT. ----
SUITES=()   # requested suite names
GDIRS=()    # explicit -gdir= values
PASS=()     # untouched GUT args
while (( $# > 0 )); do
  case "$1" in
    --suite)
      (( $# >= 2 )) || die "--suite needs a value (one of: $(available_suites) all; comma-separate several)"
      IFS=',' read -r -a _parts <<<"$2"; SUITES+=("${_parts[@]}"); shift 2 ;;
    --suite=*)
      IFS=',' read -r -a _parts <<<"${1#--suite=}"; SUITES+=("${_parts[@]}"); shift ;;
    -gdir=*)
      GDIRS+=("${1#-gdir=}"); shift ;;
    -h|--help)
      sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)
      PASS+=("$1"); shift ;;
  esac
done

# Build the list of runs as "label|res://dir".
RUNS=()
if (( ${#GDIRS[@]} > 0 )); then
  (( ${#SUITES[@]} == 0 )) || die "use either --suite or -gdir=, not both"
  for d in "${GDIRS[@]}"; do
    [[ -n "${d}" ]] || die "empty -gdir= value"
    RUNS+=("${d}|${d}")
  done
elif (( ${#SUITES[@]} > 0 )); then
  declare -A SEEN=()
  for s in "${SUITES[@]}"; do
    [[ -n "${s}" ]] || die "empty suite name in --suite (valid: $(available_suites) all)"
    [[ -z "${SEEN[${s}]:-}" ]] || continue
    SEEN[${s}]=1
    if [[ "${s}" == "all" ]]; then
      RUNS+=("all|res://tests")
    elif [[ "${s}" =~ ^[A-Za-z0-9_]+$ && -d "${TESTS_DIR}/${s}" ]]; then
      RUNS+=("${s}|res://tests/${s}")
    else
      die "unknown suite '${s}'. Valid suites: $(available_suites) all"
    fi
  done
else
  RUNS+=("all|res://tests")
fi

# The net suite's integration tests talk to the Firebase emulators: start them around a second run of this script.
if [[ -z "${CRATERLINE_NET_EMULATOR:-}" ]]; then
  for entry in "${RUNS[@]}"; do
    if [[ "${entry%%|*}" == "net" || "${entry#*|}" == res://tests/net* ]]; then
      exec "${ROOT}/tools/firebase/with_emulators.sh" env CRATERLINE_NET_EMULATOR=1 "${ROOT}/tools/run_tests.sh" "${ORIG_ARGS[@]}"
    fi
  done
fi

GODOT="$("${ROOT}/tools/setup_godot.sh")"

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

# Pulls the number from a GUT summary line such as "Passing Tests   12" (0 if absent).
count() { awk -v k="$1" '$0 ~ "^"k"[ \t]+[0-9]+" { n = $NF } END { print n + 0 }' "$2"; }

T_SCRIPTS=0; T_TESTS=0; T_PASSING=0; T_FAILING=0
PROBLEMS=()
TIMING=()
RUN_INDEX=0
TOTAL_START="${SECONDS}"

for entry in "${RUNS[@]}"; do
  LABEL="${entry%%|*}"
  DIR="${entry#*|}"
  RUN_INDEX=$((RUN_INDEX + 1))
  RAW="${LOG_DIR}/run${RUN_INDEX}.log"
  CLEAN="${LOG_DIR}/clean${RUN_INDEX}.log"

  echo "run_tests: ---- suite '${LABEL}' (${DIR}) ----" >&2
  START="${SECONDS}"
  set +e
  timeout "${TIMEOUT}" "${GODOT}" --headless --path "${GAME}" -s addons/gut/gut_cmdln.gd \
    -gdir="${DIR}" -ginclude_subdirs -gexit "${PASS[@]}" 2>&1 | tee "${RAW}"
  GODOT_STATUS="${PIPESTATUS[0]}"
  set -e
  ELAPSED=$((SECONDS - START))

  # Strip ANSI colour codes so patterns and counts match reliably.
  sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g' "${RAW}" >"${CLEAN}"

  SCRIPTS="$(count 'Scripts' "${CLEAN}")"
  TESTS="$(count 'Tests' "${CLEAN}")"
  PASSING="$(count 'Passing Tests' "${CLEAN}")"
  FAILING="$(count 'Failing Tests' "${CLEAN}")"
  T_SCRIPTS=$((T_SCRIPTS + SCRIPTS)); T_TESTS=$((T_TESTS + TESTS))
  T_PASSING=$((T_PASSING + PASSING)); T_FAILING=$((T_FAILING + FAILING))

  P=()
  (( GODOT_STATUS == 124 )) && P+=("timed out after ${TIMEOUT}s")
  (( GODOT_STATUS != 0 && GODOT_STATUS != 124 )) && P+=("godot exit code ${GODOT_STATUS}")
  (( FAILING > 0 )) && P+=("${FAILING} failing test(s)")
  (( TESTS == 0 )) && P+=("no tests ran")
  ERR_LINES="$(grep -n -i -E 'SCRIPT ERROR|Parse Error|failed to load|Failed to compile|Compile Error' "${CLEAN}" || true)"
  if [[ -n "${ERR_LINES}" ]]; then
    P+=("script/parse errors in output")
    echo "---- run_tests: script errors detected in suite '${LABEL}' ----" >&2
    echo "${ERR_LINES}" >&2
  fi
  for p in "${P[@]}"; do PROBLEMS+=("${LABEL}: ${p}"); done

  STATE="ok"; (( ${#P[@]} == 0 )) || STATE="FAILED"
  TIMING+=("$(printf 'run_tests: suite %-10s %-6s %5ss  scripts=%s tests=%s passing=%s failing=%s' \
    "${LABEL}" "${STATE}" "${ELAPSED}" "${SCRIPTS}" "${TESTS}" "${PASSING}" "${FAILING}")")
done

TOTAL_ELAPSED=$((SECONDS - TOTAL_START))
echo "run_tests: ---- timing per suite ----"
printf '%s\n' "${TIMING[@]}"

if (( ${#PROBLEMS[@]} > 0 )); then
  IFS=';'; echo "run_tests: FAILED (${PROBLEMS[*]}) - scripts=${T_SCRIPTS} tests=${T_TESTS} passing=${T_PASSING} failing=${T_FAILING} time=${TOTAL_ELAPSED}s" >&2
  exit 1
fi
echo "run_tests: OK - scripts=${T_SCRIPTS} tests=${T_TESTS} passing=${T_PASSING} failing=${T_FAILING} time=${TOTAL_ELAPSED}s"
