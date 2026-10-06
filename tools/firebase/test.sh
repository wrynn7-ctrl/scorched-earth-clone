#!/usr/bin/env bash
# Runs the whole Firebase backend test suite and exits non-zero on the first failure.
#
#   tools/firebase/test.sh             everything: static checks, rules tests, functions tests
#   tools/firebase/test.sh static      rules/blocklist freshness, typecheck, eslint, functions build
#   tools/firebase/test.sh rules       rules tests only (database emulator)
#   tools/firebase/test.sh functions   unit + functions tests (auth, database, functions emulators)
#
# The emulators need Java 21+ and Node 22+. They run fully offline against the demo project "demo-craterline"; the
# only download is the database emulator jar (cached in ~/.cache/firebase/emulators). Ports: see firebase/README.md.
set -euo pipefail

# shellcheck source=tools/firebase/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

STAGE="${1:-all}"
case "$STAGE" in
  all | static | rules | functions) ;;
  *)
    echo "usage: $0 [all|static|rules|functions]" >&2
    exit 2
    ;;
esac

if [ "$STAGE" = all ] || [ "$STAGE" = static ]; then
  echo "== static checks"
  (
    cd "$FB"
    npm run --silent rules:check
    npm run --silent blocklist:check
    npm run --silent build
    npm run --silent typecheck
    npm run --silent lint
  )
fi

if [ "$STAGE" = all ] || [ "$STAGE" = rules ]; then
  echo "== rules tests (database emulator)"
  emulators_exec database "npm run test:rules"
fi

if [ "$STAGE" = all ] || [ "$STAGE" = functions ]; then
  # The functions emulator loads functions/lib, so build first (the static stage does too, but may have been skipped).
  prepare_functions
  echo "== functions tests (auth + database + functions emulators)"
  emulators_exec auth,database,functions "npm run test:functions"
fi

echo "== firebase tests passed ($STAGE)"
