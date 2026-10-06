#!/usr/bin/env bash
# Regenerates game/tests/qa/fixtures/name_filter_corpus.json (the 2,000 strings + the server filter's verdicts) for the
# GDScript parity test. Needs firebase/node_modules (npm ci in firebase/).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -z "$ROOT" ] || [ ! -d "$ROOT/firebase/node_modules" ]; then
  echo "firebase/node_modules not found: run npm ci in firebase/ first" >&2
  exit 2
fi
cd "$ROOT/firebase"
./node_modules/.bin/tsx test/qa/unit/gen_name_corpus_main.ts
