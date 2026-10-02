#!/usr/bin/env bash
# Runs the M3 fuzz (game/tests/qa/test_fuzz_m3.gd) over many extra seeds. Not part of the normal suite.
# Usage: tools/qa/deep_fuzz.sh [first_seed] [batches] [matches_per_batch]
#   defaults: 1 batch count 8, 200 matches each (about 35 s per batch).
# Each batch uses root seed (first_seed + batch) * 1000003; a failing batch prints the match index and
# seed of every failure, which can be replayed by running that single batch again.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIRST="${1:-1}"
BATCHES="${2:-8}"
MATCHES="${3:-200}"
FAILED=0
for ((i = 0; i < BATCHES; i++)); do
  SEED=$(( (FIRST + i) * 1000003 ))
  echo "deep_fuzz: batch $i seed $SEED ($MATCHES matches)" >&2
  if ! QA_FUZZ_SEED="${SEED}" QA_FUZZ_MATCHES="${MATCHES}" "${ROOT}/tools/run_tests.sh" -gselect=test_fuzz_m3 2>&1 | tail -25; then
    FAILED=1
  fi
done
exit "${FAILED}"
