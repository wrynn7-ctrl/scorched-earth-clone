#!/usr/bin/env bash
# Runs selected firebase mocha files inside the emulators (QA helper; does not replace tools/firebase/test.sh).
#
#   tools/qa/fb_mocha.sh rules     'test/qa/rules/**/*.test.ts'
#   tools/qa/fb_mocha.sh functions 'test/qa/functions/**/*.test.ts' [more globs...]
#
# `rules` starts only the database emulator; `functions` starts auth + database + functions (and builds functions first).
set -euo pipefail

# shellcheck source=tools/firebase/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../firebase/lib.sh"

KIND="${1:-}"
shift || true
if [ -z "$KIND" ] || [ "$#" -eq 0 ]; then
  echo "usage: $0 rules|functions <glob> [glob...]" >&2
  exit 2
fi

globs=""
for g in "$@"; do
  globs+="$(printf '%q' "$g") "
done
cmd="npx mocha --config test/.mocharc.json $globs"

case "$KIND" in
  rules) emulators_exec database "$cmd" ;;
  functions)
    prepare_functions
    emulators_exec auth,database,functions "$cmd"
    ;;
  *)
    echo "unknown kind '$KIND'" >&2
    exit 2
    ;;
esac
