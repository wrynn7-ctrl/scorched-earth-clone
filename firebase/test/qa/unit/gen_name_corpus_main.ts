// Writes game/tests/qa/fixtures/name_filter_corpus.json (run through tools/qa/gen_name_corpus.sh).
import { writeFileSync } from 'node:fs';
import { buildCorpus, entriesFor, FIXTURE_PATH, loadBlocklist, serialize } from './name_corpus';

const entries = entriesFor(buildCorpus(loadBlocklist()));
writeFileSync(FIXTURE_PATH, serialize(entries));
console.log(`wrote ${entries.length} strings to ${FIXTURE_PATH} (${entries.filter((e) => !e.allowed).length} blocked, ${entries.filter((e) => e.clean !== e.s).length} changed by clean)`);
