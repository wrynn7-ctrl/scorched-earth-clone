import assert from 'node:assert/strict';
import { makeCode, normalizeCode } from '../../functions/src/codes';
import { CODE_ALPHABET } from '../../functions/src/config';

describe('codes', () => {
  it('uses 32 characters with no 0, O, 1 or I', () => {
    assert.equal(CODE_ALPHABET.length, 32);
    assert.equal(new Set(CODE_ALPHABET).size, 32);
    for (const bad of '01OI') assert.ok(!CODE_ALPHABET.includes(bad));
  });

  it('makes codes of the requested length from the alphabet', () => {
    for (let i = 0; i < 50; i += 1) {
      const code = makeCode(8);
      assert.equal(code.length, 8);
      for (const ch of code) assert.ok(CODE_ALPHABET.includes(ch));
    }
  });

  it('is driven by the random source it is given', () => {
    assert.equal(makeCode(4, () => 0), 'AAAA');
    assert.equal(makeCode(3, () => 31), '999');
  });

  it('normalises what a player types and rejects what cannot be a code', () => {
    assert.equal(normalizeCode(' abc234 ', 6), 'ABC234');
    assert.equal(normalizeCode('abc23', 6), null);
    assert.equal(normalizeCode('ABC23O', 6), null);
    assert.equal(normalizeCode('ABC231', 6), null);
    assert.equal(normalizeCode(123456, 6), null);
    assert.equal(normalizeCode(undefined, 6), null);
  });
});
