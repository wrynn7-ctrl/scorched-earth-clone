// The committed corpus fixture must still describe the TypeScript filter: when name_filter.ts or the blocklist changes, regenerate
// it with tools/qa/gen_name_corpus.sh and look at what the GDScript parity test says (game/tests/qa/test_name_filter_parity.gd).
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { buildCorpus, CORPUS_SIZE, entriesFor, FIXTURE_PATH, loadBlocklist, serialize } from './name_corpus';

describe('QA name corpus', () => {
  it('builds 2,000 distinct-enough strings deterministically', () => {
    const a = buildCorpus(loadBlocklist());
    const b = buildCorpus(loadBlocklist());
    assert.equal(a.length, CORPUS_SIZE);
    assert.deepEqual(a, b);
    assert.ok(new Set(a).size > 1700, `${new Set(a).size} distinct`);
  });

  it('matches the committed fixture (regenerate with tools/qa/gen_name_corpus.sh after a filter change)', () => {
    const fresh = serialize(entriesFor(buildCorpus(loadBlocklist())));
    assert.equal(readFileSync(FIXTURE_PATH, 'utf8') === fresh, true, 'game/tests/qa/fixtures/name_filter_corpus.json is stale');
  });
});
