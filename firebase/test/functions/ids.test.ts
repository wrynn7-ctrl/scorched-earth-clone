// Ids a client sends (uids, match ids) end up inside database paths. They must be strict: letters, digits, "-" and "_", 8 to 128
// characters, no leading "__". The Admin SDK keeps its path tree in a plain object, so "matches/__proto__/meta" is not an ordinary
// key and a transaction on it never finished: startMatch and updateLobby hung for the whole 60 s function timeout (M7-QF-B).
import assert from 'node:assert/strict';
import { isSafeId } from '../../functions/src/errors';
import { hostLobby, newUser, type TestUser } from './harness';
import { CallError } from './harness';

describe('ids: the pure check', () => {
  it('accepts push ids and Auth uids, refuses everything else', () => {
    for (const ok of ['-Nabcdefghijklmnopqr', 'zXy12345AbCdEfGhIjKlMnOpQrSt', 'a_b-c_d-e', 'x'.repeat(128), 'constructor', 'toString']) assert.equal(isSafeId(ok), true, ok);
    for (const bad of ['__proto__', '__abcdefgh', '__', '_', 'short', '', 'x'.repeat(129), 'a/bcdefgh', 'a.bcdefgh', 'ab cdefgh', 'ünïcödeüü', 5, null, undefined, {}, ['abcdefgh']]) {
      assert.equal(isSafeId(bad), false, JSON.stringify(bad) ?? 'undefined');
    }
    assert.equal(isSafeId('a', 1), true, 'a caller may lower the minimum for ids it makes itself');
    assert.equal(isSafeId('__a', 1), false, 'but never allow a leading __');
  });
});

describe('functions: every callable that takes an id answers a bad id at once', function () {
  this.timeout(120000);
  let me: TestUser;
  let friend: TestUser;
  let matchId: string;

  before(async () => {
    me = await newUser({ full: true, name: 'Hana' });
    friend = await newUser({ name: 'Finn' });
    matchId = (await hostLobby(me)).matchId;
  });

  const fields: [string, string, () => Record<string, unknown>][] = [
    ['sendFriendRequestToUid', 'targetUid', () => ({ matchId })],
    ['sendFriendRequestToUid', 'matchId', () => ({ targetUid: friend.uid })],
    ['respondFriendRequest', 'fromUid', () => ({ accept: true })],
    ['removeFriend', 'friendUid', () => ({})],
    ['block', 'targetUid', () => ({})],
    ['unblock', 'targetUid', () => ({})],
    ['reportName', 'targetUid', () => ({})],
    ['updateLobby', 'matchId', () => ({ settings: { rounds: 2 } })],
    ['leaveMatch', 'matchId', () => ({})],
    ['startMatch', 'matchId', () => ({})],
    ['invite', 'matchId', () => ({ friendUid: friend.uid })],
    ['invite', 'friendUid', () => ({ matchId })],
  ];

  const answer = async (promise: Promise<unknown>): Promise<{ status: string; ms: number }> => {
    const started = Date.now();
    try {
      await Promise.race([promise, new Promise((_resolve, reject) => setTimeout(() => reject(new Error('HUNG')), 8000))]);
      return { status: 'OK', ms: Date.now() - started };
    } catch (error) {
      if (error instanceof CallError) return { status: error.status, ms: Date.now() - started };
      return { status: String((error as Error).message), ms: Date.now() - started };
    }
  };

  it('refuses prototype-like, short, long and path-like ids with INVALID_ARGUMENT', async () => {
    const wrong: string[] = [];
    for (const [name, field, rest] of fields) {
      for (const id of ['__proto__', '__abcdefgh', 'short', 'x'.repeat(129), 'a/bcdefgh']) {
        const got = await answer(me.call(name, { ...rest(), [field]: id }));
        if (got.status !== 'INVALID_ARGUMENT') wrong.push(`${name}.${field}=${id.slice(0, 12)}: ${got.status} after ${got.ms} ms`);
      }
    }
    assert.deepEqual(wrong, []);
  });

  it('answers ids that look fine but name nothing (and names of Object.prototype members) quickly, never with a hang or a crash', async () => {
    const wrong: string[] = [];
    const clean = new Set(['OK', 'NOT_FOUND', 'PERMISSION_DENIED', 'FAILED_PRECONDITION', 'INVALID_ARGUMENT']);
    for (const [name, field, rest] of fields) {
      for (const id of ['constructor', 'toString', 'hasOwnProperty', 'nonexistent12345']) {
        const got = await answer(me.call(name, { ...rest(), [field]: id }));
        if (!clean.has(got.status) || got.ms > 6000) wrong.push(`${name}.${field}=${id}: ${got.status} after ${got.ms} ms`);
      }
    }
    assert.deepEqual(wrong, []);
  });

  it('startMatch and updateLobby on a match that does not exist say unknown_match', async () => {
    for (const name of ['startMatch', 'updateLobby']) {
      await assert.rejects(me.call(name, { matchId: 'nonexistent12345', settings: { rounds: 2 } }), (e: CallError) => e.status === 'NOT_FOUND' && e.reason === 'unknown_match');
    }
  });
});
