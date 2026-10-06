#!/usr/bin/env bash
# Runs one net test script N times against ONE emulator session and prints a pass/fail line per run.
#
#   tools/qa/net_repeat.sh <runs> <gut -gselect value> [log dir]      e.g.  tools/qa/net_repeat.sh 15 test_it_ui_flow
#
# Logs of every run go to <log dir> (default: a new directory made with mktemp). Exit code 0 when every run passed.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNS="${1:-}"
SELECT="${2:-}"
if [ -z "$RUNS" ] || [ -z "$SELECT" ]; then
  echo "usage: $0 <runs> <select> [log dir]" >&2
  exit 2
fi
LOGS="${3:-$(mktemp -d)}"
if [ -z "$LOGS" ]; then
  echo "no log dir" >&2
  exit 2
fi
mkdir -p "$LOGS"
export QA_REPEAT_RUNS="$RUNS" QA_REPEAT_SELECT="$SELECT" QA_REPEAT_LOGS="$LOGS" QA_REPEAT_ROOT="$ROOT"
exec "$ROOT/tools/firebase/with_emulators.sh" env CRATERLINE_NET_EMULATOR=1 "$ROOT/tools/qa/net_repeat_inner.sh"
