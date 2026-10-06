// A player keeps at most 5 push tokens. The database rules cannot count children, so the onPushTokenAdded trigger (pruneTokens)
// trims the node after a write (M7-QF-B). The new token is always kept.
import assert from 'node:assert/strict';
import { pruneTokens, trimTokens } from '../../functions/src/triggers';
import { MAX_PUSH_TOKENS } from '../../functions/src/config';
import { db, directDeps, eventually, newUser, value } from './harness';

const token = (n: number): string => `${String(n).padStart(4, '0')}${'t'.repeat(30)}`;
const key = (n: number): string => `key${String(n).padStart(8, '0')}`;

describe('functions: push token cap', function () {
  this.timeout(60000);

  it('trimTokens keeps everything up to the cap', () => {
    const tokens: Record<string, string> = {};
    for (let i = 0; i < MAX_PUSH_TOKENS; i += 1) tokens[key(i)] = token(i);
    assert.deepEqual(trimTokens(tokens, key(0)), tokens);
  });

  it('trimTokens cuts a burst to the cap and always keeps the token that triggered it', () => {
    const tokens: Record<string, string> = {};
    for (let i = 0; i < 12; i += 1) tokens[key(i)] = token(i);
    for (const keep of [key(0), key(7), key(11)]) {
      const left = trimTokens(tokens, keep);
      assert.equal(Object.keys(left).length, MAX_PUSH_TOKENS);
      assert.ok(left[keep], `the token that was just stored (${keep}) survives, although the others sort around it`);
      for (const [k, v] of Object.entries(left)) assert.equal(v, token(Number(k.slice(3))), 'tokens are not mixed up');
    }
  });

  it('pruneTokens trims what the database holds (the trigger may get there first: both end at the cap)', async () => {
    const user = await newUser();
    const writes: Record<string, string> = {};
    for (let i = 0; i < 12; i += 1) writes[`users/${user.uid}/fcm/${key(i)}`] = token(i);
    await db.ref().update(writes);
    const removed = await pruneTokens(directDeps({ now: Date.now() }), user.uid, key(3));
    assert.ok(removed >= 0 && removed <= 12 - MAX_PUSH_TOKENS);
    await eventually(async () => Object.keys((await value<Record<string, string>>(`users/${user.uid}/fcm`)) ?? {}).length === MAX_PUSH_TOKENS, 'at the cap', 20000);
  });

  it('is run by the database trigger: a client that writes 40 tokens at once ends with 5', async () => {
    const user = await newUser();
    const writes: Record<string, string> = {};
    for (let i = 0; i < 40; i += 1) writes[`users/${user.uid}/fcm/${key(i)}`] = token(i);
    await db.ref().update(writes);
    await eventually(async () => Object.keys((await value<Record<string, string>>(`users/${user.uid}/fcm`)) ?? {}).length <= MAX_PUSH_TOKENS, 'trimmed to the cap', 20000);
    assert.equal(Object.keys((await value<Record<string, string>>(`users/${user.uid}/fcm`)) ?? {}).length, MAX_PUSH_TOKENS);
  });

  it('leaves a normal phone alone: one token, a refreshed one, and pushes still find it', async () => {
    const user = await newUser();
    await user.registerPushToken();
    await db.ref(`users/${user.uid}/fcm/${key(1)}`).set(token(1));
    await new Promise((resolve) => setTimeout(resolve, 800));
    assert.equal(Object.keys((await value<Record<string, string>>(`users/${user.uid}/fcm`)) ?? {}).length, 2);
  });
});
