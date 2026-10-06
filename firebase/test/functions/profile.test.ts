// ensureProfile and the name re-check trigger (ARCHITECTURE section 44).
import assert from 'node:assert/strict';
import { CODE_ALPHABET } from '../../functions/src/config';
import { callWith, CallError, db, eventually, newUser, signUp, value } from './harness';

describe('functions: ensureProfile', () => {
  it('creates the profile: friend code, name PLAYER, protocol, not full', async () => {
    const user = await signUp();
    const result = await user.call<{ friendCode: string; name: string; full: boolean; protocol: number; nameHidden: boolean; serverTime: number }>(
      'ensureProfile',
      { protocol: 7 },
    );
    assert.equal(result.friendCode.length, 8);
    for (const ch of result.friendCode) assert.ok(CODE_ALPHABET.includes(ch), `${ch} is in the alphabet`);
    assert.equal(result.name, 'PLAYER');
    assert.equal(result.protocol, 7);
    assert.equal(result.full, false);
    assert.equal(result.nameHidden, false);
    assert.ok(Math.abs(result.serverTime - Date.now()) < 60000, 'serverTime is close to now');
    const stored = await user.profile();
    assert.equal(stored.friendCode, result.friendCode);
    assert.equal(stored.full, false);
    assert.equal(typeof stored.created, 'number');
    assert.equal(await value(`friendCodes/${result.friendCode}`), user.uid);
  });

  it('is idempotent: a second call keeps the code and name, and updates the protocol', async () => {
    const user = await signUp();
    const first = await user.call<{ friendCode: string }>('ensureProfile', { protocol: 1 });
    await db.ref(`users/${user.uid}/name`).set('Zed');
    await eventually(async () => (await user.profile()).name === 'Zed', 'name saved');
    const second = await user.call<{ friendCode: string; name: string; protocol: number }>('ensureProfile', { protocol: 2 });
    assert.equal(second.friendCode, first.friendCode);
    assert.equal(second.name, 'Zed');
    assert.equal(second.protocol, 2);
    assert.equal((await user.profile()).protocol, 2);
  });

  it('works without arguments and gives every user a different code', async () => {
    const [a, b] = await Promise.all([signUp(), signUp()]);
    const [ra, rb] = await Promise.all([a.call<{ friendCode: string }>('ensureProfile'), b.call<{ friendCode: string }>('ensureProfile', {})]);
    assert.notEqual(ra.friendCode, rb.friendCode);
  });

  it('survives two simultaneous first calls from one user (one profile, no leaked code)', async () => {
    const user = await signUp();
    const [r1, r2] = await Promise.all([user.call<{ friendCode: string }>('ensureProfile'), user.call<{ friendCode: string }>('ensureProfile')]);
    assert.equal(r1.friendCode, r2.friendCode);
    assert.equal((await user.profile()).friendCode, r1.friendCode);
  });

  it('rejects signed-out callers and a bad protocol', async () => {
    await assert.rejects(callWith('ensureProfile', {}, null), (e: CallError) => e.status === 'UNAUTHENTICATED');
    const user = await signUp();
    await assert.rejects(user.call('ensureProfile', { protocol: -1 }), (e: CallError) => e.status === 'INVALID_ARGUMENT');
    await assert.rejects(user.call('ensureProfile', { protocol: 'x' }), (e: CallError) => e.status === 'INVALID_ARGUMENT');
    await assert.rejects(user.call('ensureProfile', 'nope'), (e: CallError) => e.status === 'INVALID_ARGUMENT');
  });
});

describe('functions: name re-check trigger', () => {
  const setName = async (uid: string, name: string): Promise<void> => {
    await db.ref(`users/${uid}/name`).set(name);
  };

  it('keeps a clean name', async () => {
    const user = await newUser();
    await setName(user.uid, 'Anna Lee');
    await new Promise((r) => setTimeout(r, 800));
    assert.equal((await user.profile()).name, 'Anna Lee');
  });

  it('replaces a blocked name with PLAYER', async () => {
    const user = await newUser({ name: 'Nice' });
    await setName(user.uid, 'f u c k');
    await eventually(async () => (await user.profile()).name === 'PLAYER', 'blocked name replaced');
  });

  it('stores the cleaned form of a messy name', async () => {
    const user = await newUser();
    await setName(user.uid, '  Anna    Lee  ');
    await eventually(async () => (await user.profile()).name === 'Anna Lee', 'name cleaned');
  });

  it('blocks look-alike spellings the same way the game does', async () => {
    const user = await newUser();
    await setName(user.uid, 'sh1t');
    await eventually(async () => (await user.profile()).name === 'PLAYER', 'leetspeak name replaced');
  });
});
