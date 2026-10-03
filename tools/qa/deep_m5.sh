#!/usr/bin/env bash
# Runs the M5 fuzz files (Love Edition fuzz, free/full invariants) with more matches. Not part of the normal suite.
# Usage: tools/qa/deep_m5.sh [scale]
#   scale (default 3) multiplies the match counts: 3 -> 600 love matches and 300 free-mode matches (about 6 minutes).
# The per-match seeds are fixed, so a failure prints the match index and seed and can be replayed by re-running.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCALE="${1:-3}"
FAILED=0
for sel in test_m5_love_fuzz test_m5_free_full; do
  echo "deep_m5: ${sel} x${SCALE}" >&2
  if ! QA_M5_SCALE="${SCALE}" "${ROOT}/tools/run_tests.sh" --suite qa -gselect="${sel}" 2>&1 | tail -15; then
    FAILED=1
  fi
done
exit "${FAILED}"
