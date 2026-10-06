#!/usr/bin/env bash
# Runs a command with the Firebase emulators (auth, database, functions) up, then stops them. The standard
# FIREBASE_*_EMULATOR_HOST variables are set for the command (NetConfig.from_environment reads them).
#
#   tools/firebase/with_emulators.sh <command> [args...]
#   tools/firebase/with_emulators.sh env CRATERLINE_NET_EMULATOR=1 tools/run_tests.sh --suite net
#
# `tools/run_tests.sh --suite net` calls this by itself. Needs Java 21+ and Node 22+ (see tools/firebase/test.sh).
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <command> [args...]" >&2
  exit 2
fi
# shellcheck source=tools/firebase/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

prepare_functions
quoted=""
for arg in "$@"; do
  quoted+="$(printf '%q' "$arg") "
done
echo "== emulators (auth + database + functions) up; running: $*"
emulators_exec auth,database,functions "$quoted"
