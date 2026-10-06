# Shared by tools/firebase/test.sh and tools/firebase/with_emulators.sh (source it, do not run it).
# Sets ROOT, FB and PROJECT, makes loopback calls bypass a proxy, installs npm dependencies when missing, and defines
# `prepare_functions` (build + local secret stub) and `emulators_exec <only> <command string>`.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FB="$ROOT/firebase"
if [ -z "$ROOT" ] || [ ! -f "$FB/firebase.json" ]; then
  echo "firebase/firebase.json not found (looked in '$FB')" >&2
  exit 2
fi

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
  (cd "$FB" && ./node_modules/.bin/firebase emulators:exec --project "$PROJECT" --only "$only" "$script")
}

# The functions emulator loads functions/lib, so build first.
prepare_functions() {
  (cd "$FB" && npm run --silent build)
}
