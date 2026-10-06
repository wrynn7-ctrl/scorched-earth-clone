#!/usr/bin/env bash
# Runs the whole Firebase backend test suite and exits non-zero on the first failure.
#
#   tools/firebase/test.sh             everything: static checks, rules tests, functions tests
#   tools/firebase/test.sh static      rules/blocklist freshness, typecheck, eslint, functions build
#   tools/firebase/test.sh rules       rules tests only (database emulator)
#   tools/firebase/test.sh functions   unit + functions tests (auth, database, functions emulators)
#
# The emulators need Java 17+ and Node 22+. They run fully offline against the demo project "demo-craterline"; the
# only download is the database emulator jar (cached in ~/.cache/firebase/emulators). Ports: see firebase/README.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FB="$ROOT/firebase"
if [ -z "$ROOT" ] || [ ! -f "$FB/firebase.json" ]; then
  echo "firebase/firebase.json not found (looked in '$FB')" >&2
  exit 2
fi

STAGE="${1:-all}"
case "$STAGE" in
  all | static | rules | functions) ;;
  *)
    echo "usage: $0 [all|static|rules|functions]" >&2
    exit 2
    ;;
esac

PROJECT="demo-craterline"

# firebase-tools sends even its calls to the local emulators through HTTPS_PROXY (it ignores NO_PROXY). On a machine
# with a proxy, preload a small hook that keeps loopback requests direct. Without a proxy this changes nothing.
if [ -n "${HTTPS_PROXY:-}${https_proxy:-}${HTTP_PROXY:-}${http_proxy:-}" ]; then
  export NODE_OPTIONS="--require $ROOT/tools/firebase/loopback_direct.cjs ${NODE_OPTIONS:-}"
fi

install_if_missing() {
  local dir="$1" marker="$2"
  if [ ! -e "$dir/node_modules/.bin/$marker" ]; then
    echo "== npm ci in $dir"
    (cd "$dir" && npm ci --no-audit --no-fund)
  fi
}
install_if_missing "$FB" firebase
install_if_missing "$FB/functions" tsc

# The purchase function declares a Secret Manager secret; the emulator reads local overrides from this git-ignored file
# (without it the emulator only prints a warning). "-" means "use the runtime service account", which the emulator never needs.
if [ ! -e "$FB/functions/.secret.local" ]; then
  printf 'PLAY_SERVICE_ACCOUNT_JSON=-\n' > "$FB/functions/.secret.local"
fi

emulators_exec() {
  local only="$1" script="$2"
  (cd "$FB" && ./node_modules/.bin/firebase emulators:exec --project "$PROJECT" --only "$only" "npm run $script")
}

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
  emulators_exec database test:rules
fi

if [ "$STAGE" = all ] || [ "$STAGE" = functions ]; then
  # The functions emulator loads functions/lib, so build first (the static stage does too, but may have been skipped).
  (cd "$FB" && npm run --silent build)
  echo "== functions tests (auth + database + functions emulators)"
  emulators_exec auth,database,functions test:functions
fi

echo "== firebase tests passed ($STAGE)"
