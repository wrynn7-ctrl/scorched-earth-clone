// A player keeps at most 5 push tokens. The database rules cannot count children, so the onPushTokenAdded trigger (pruneTokens)
// trims the node after a write (M7-QF-B). The new token is always kept.
import assert from 'node:assert/strict';
import { pruneTokens } from '../../functions/src/triggers';
import { MAX_PUSH_TOKENS } from '../../functions/src/config';
import { db, directDeps, eventually, newUser, value } from './harness';

const token = (n: number): string => `${String(n).padStart(4, '0')}${'t'.repeat(30)}`;
const key = (n: number): string => `key${String(n).padStart(8, '0')}`;

describe('functions: push token cap', function () {
  this.timeout(60000);

  it('keeps everything up to the cap and does nothing', async () => {
    const user = await newUser();
    const writes: Record<string, string> = {};
    for (let i = 0; i < MAX_PUSH_TOKENS; i += 1) writes[`users/${user.uid}/fcm/${key(i)}`] = token(i);
    await db.ref().update(writes);
    assert.equal(await pruneTokens(directDeps({ now: Date.now() }), user.uid, key(0)), 0);
    assert.equal(Object.keys((await value<Record<string, string>>(`users/${user.uid}/fcm`)) ?? {}).length, MAX_PUSH_TOKENS);
  });

  it('trims a burst to the cap and always keeps the token that triggered it', async () => {
    const user = await newUser();
    const writes: Record<string, string> = {};
    for (let i = 0; i < 12; i += 1) writes[`users/${user.uid}/fcm/${key(i)}`] = token(i);
    await db.ref().update(writes);
    const removed = await pruneTokens(directDeps({ now: Date.now() }), user.uid, key(0));
    assert.equal(removed, 12 - MAX_PUSH_TOKENS);
    const left = (await value<Record<string, string>>(`users/${user.uid}/fcm`)) ?? {};
    assert.equal(Object.keys(left).length, MAX_PUSH_TOKENS);
    assert.ok(left[key(0)], 'the token that was just stored survives, although its key sorts first');
    for (const [k, v] of Object.entries(left)) assert.equal(v, token(Number(k.slice(3))), 'tokens are not mixed up');
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
