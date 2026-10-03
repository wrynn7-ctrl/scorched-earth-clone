#!/usr/bin/env bash
# Deliberately regenerates the golden replay fixtures in game/tests/qa/fixtures/.
# Run this ONLY when a simulation change is intentional, then review `git diff` of the
# fixtures and commit them with the change. Normal test runs never write fixtures.
#
# It runs the golden GUT tests with QA_REGEN_GOLDEN=1 (the tests then record instead of
# comparing), and afterwards re-runs them normally to prove the new fixtures replay cleanly.
#   test_golden_replays  -> the six M2 fixtures (duel_2_tanks.json ... multi_round_3_tanks.json)
#   test_golden_m3       -> the four M3 shopping-bot fixtures (m3_*.json)
#   test_m5_love_golden  -> the six Love Edition fixtures (m5_love_*.json)
# Pass "m2", "m3" or "love" to regenerate only that family (default: all).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

WHICH="${1:-all}"
SELECTS=()
case "${WHICH}" in
  m2) SELECTS=(test_golden_replays) ;;
  m3) SELECTS=(test_golden_m3) ;;
  love) SELECTS=(test_m5_love_golden) ;;
  all) SELECTS=(test_golden_replays test_golden_m3 test_m5_love_golden) ;;
  *) echo "usage: regen_golden.sh [m2|m3|love|all]" >&2; exit 2 ;;
esac

for sel in "${SELECTS[@]}"; do
  echo "regen_golden: recording fixtures (${sel})..." >&2
  QA_REGEN_GOLDEN=1 "${ROOT}/tools/run_tests.sh" -gselect="${sel}"
done
for sel in "${SELECTS[@]}"; do
  echo "regen_golden: verifying fixtures replay cleanly (${sel})..." >&2
  "${ROOT}/tools/run_tests.sh" -gselect="${sel}"
done
echo "regen_golden: done. Review with: git -C '${ROOT}' diff --stat -- game/tests/qa/fixtures" >&2
