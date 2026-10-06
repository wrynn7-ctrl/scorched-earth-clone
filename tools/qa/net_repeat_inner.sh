#!/usr/bin/env bash
# Inner loop of net_repeat.sh (runs inside the emulators). Reads QA_REPEAT_RUNS, QA_REPEAT_SELECT, QA_REPEAT_LOGS, QA_REPEAT_ROOT.
set -uo pipefail
fails=0
for i in $(seq 1 "$QA_REPEAT_RUNS"); do
  log="$QA_REPEAT_LOGS/run_$i.log"
  start=$SECONDS
  if "$QA_REPEAT_ROOT/tools/run_tests.sh" --suite net -gselect="$QA_REPEAT_SELECT" ${QA_REPEAT_EXTRA:-} > "$log" 2>&1; then r=PASS; else r=FAIL; fails=$((fails + 1)); fi
  echo "QA_REPEAT run $i: $r ($((SECONDS - start))s) $log"
done
echo "QA_REPEAT summary: $fails failures in $QA_REPEAT_RUNS runs"
[ "$fails" -eq 0 ]
