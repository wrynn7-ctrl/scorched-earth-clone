#!/usr/bin/env bash
# Deliberately regenerates the golden replay fixtures in game/tests/qa/fixtures/.
# Run this ONLY when a simulation change is intentional, then review `git diff` of the
# fixtures and commit them with the change. Normal test runs never write fixtures.
#
# It runs the golden GUT test with QA_REGEN_GOLDEN=1 (the test then records instead of
# comparing), and afterwards re-runs it normally to prove the new fixtures replay cleanly.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "regen_golden: recording fixtures..." >&2
QA_REGEN_GOLDEN=1 "${ROOT}/tools/run_tests.sh" -gselect=test_golden_replays
echo "regen_golden: verifying fixtures replay cleanly..." >&2
"${ROOT}/tools/run_tests.sh" -gselect=test_golden_replays
echo "regen_golden: done. Review with: git -C '${ROOT}' diff --stat -- game/tests/qa/fixtures" >&2
