// Turn-change bookkeeping and push (ARCHITECTURE section 47): "Your matches" entries, the sweep queue, FCM to a player who
// is not online (mocked in the emulator and recorded at _test/fcm), and the match-over trigger.
import assert from 'node:assert/strict';
import { db, eventually, fcmFor, hostLobby, newUser, settle, value, type TestUser } from './harness';

interface Running {
  host: TestUser;
  bob: TestUser;
  matchId: string;
  code: string;
}

const HOUR = 3600 * 1000;

/** A started match: host (Hana), bob (Bob) and a CPU. Both humans have a push token. */
async function runningMatch(): Promise<Running> {
  const host = await newUser({ full: true, name: 'Hana' });
  const bob = await newUser({ name: 'Bob' });
  await host.registerPushToken();
  await bob.registerPushToken();
  const { matchId, code } = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human' }, { kind: 'cpu' }]);
  await bob.call('joinMatch', { code });
  await host.call('startMatch', { matchId });
  return { host, bob, matchId, code };
}

/** What a client does when a turn ends: set meta/turn (written as the server here; the rules are tested separately). */
async function setTurn(matchId: string, tank: number, uid: string, index: number, deadline = Date.now() + HOUR): Promise<void> {
  await db.ref(`matches/${matchId}/meta/turn`).set({ tank, uid, deadline: tank === -1 ? 0 : deadline, index });
}

const yourTurn = async (u: TestUser, matchId: string): Promise<unknown> => value(`userMatches/${u.uid}/${matchId}/yourTurn`);

describe('functions: onTurnChange', () => {
  it('flags whose turn it is on every member\'s list, and keeps the sweep queue current', async () => {
    const { host, bob, matchId } = await runningMatch();
    const deadline = Date.now() + 5 * HOUR;
    await setTurn(matchId, 1, bob.uid, 1, deadline);
    await eventually(async () => (await yourTurn(bob, matchId)) === true, 'bob flagged');
    assert.equal(await yourTurn(host, matchId), false);
    assert.equal(await value(`sweepQueue/${matchId}`), deadline);
    await setTurn(matchId, 0, host.uid, 2);
    await eventually(async () => (await yourTurn(host, matchId)) === true && (await yourTurn(bob, matchId)) === false, 'flags move with the turn');
  });

  it('pushes "Your turn" to a player who is not online, with the host\'s name and the match id', async () => {
    const { bob, matchId } = await runningMatch();
    await setTurn(matchId, 1, bob.uid, 1);
    await eventually(async () => (await fcmFor(bob.uid)).length === 1, 'turn push');
    const [push] = await fcmFor(bob.uid);
    assert.equal(push?.title, 'Craterline');
    assert.equal(push?.body, "Your turn in Hana's match");
    assert.deepEqual(push?.data, { type: 'turn', matchId });
    assert.equal(push?.collapseKey, `turn_${matchId}`);
    assert.equal(push?.tokenCount, 1);
    assert.equal(push?.channelId, 'turns', 'the notification channel the Android plugin creates');
  });

  it('pushes when the heartbeat is stale (older than 75 s) or missing, not when it is fresh', async () => {
    const { bob, matchId } = await runningMatch();
    await bob.setPresence(matchId, 5000);
    await setTurn(matchId, 1, bob.uid, 1);
    await eventually(async () => (await yourTurn(bob, matchId)) === true, 'turn recorded');
    await settle();
    assert.equal((await fcmFor(bob.uid)).length, 0, 'fresh presence: no push');

    await bob.setPresence(matchId, 74000);
    await setTurn(matchId, 1, bob.uid, 2);
    await settle();
    assert.equal((await fcmFor(bob.uid)).length, 0, '74 s old is still online');

    await bob.setPresence(matchId, 76000);
    await setTurn(matchId, 1, bob.uid, 3);
    await eventually(async () => (await fcmFor(bob.uid)).length === 1, 'push for a stale heartbeat');
  });

  it('sends nothing to a player with no push token', async () => {
    const host = await newUser({ full: true, name: 'Hana' });
    const bob = await newUser({ name: 'Bob' });
    const { matchId, code } = await hostLobby(host);
    await bob.call('joinMatch', { code });
    await host.call('startMatch', { matchId });
    await setTurn(matchId, 1, bob.uid, 1);
    await eventually(async () => (await yourTurn(bob, matchId)) === true, 'turn recorded');
    await settle();
    assert.equal((await fcmFor(bob.uid)).length, 0);
  });

  it('does not push twice when the same turn is written again', async () => {
    const { bob, matchId } = await runningMatch();
    await setTurn(matchId, 1, bob.uid, 1);
    await eventually(async () => (await fcmFor(bob.uid)).length === 1, 'first push');
    await db.ref(`matches/${matchId}/meta/turn/deadline`).set(Date.now() + 2 * HOUR);
    await settle();
    assert.equal((await fcmFor(bob.uid)).length, 1);
  });

  it('does not push for CPU turns, the shop or a turn that needs resolving', async () => {
    const { host, bob, matchId } = await runningMatch();
    await setTurn(matchId, 2, 'cpu', 1);
    await eventually(async () => (await value(`sweepQueue/${matchId}`)) !== null, 'cpu turn recorded');
    assert.equal(await yourTurn(bob, matchId), false);

    await setTurn(matchId, -2, 'any', 2);
    await eventually(async () => (await yourTurn(bob, matchId)) === true, 'shop flags everyone');
    assert.equal(await yourTurn(host, matchId), true);

    await setTurn(matchId, -1, 'any', 3);
    await eventually(async () => (await yourTurn(bob, matchId)) === false, 'resolve flags nobody');
    assert.equal(await yourTurn(host, matchId), false);
    await settle();
    assert.equal((await fcmFor(bob.uid)).length, 0);
    assert.equal((await fcmFor(host.uid)).length, 0);
  });

  it('schedules a no-deadline turn (needs resolve, shop) for the 14-day idle check', async () => {
    const { matchId } = await runningMatch();
    await setTurn(matchId, -2, 'any', 1);
    await eventually(async () => {
      const due = await value<number>(`sweepQueue/${matchId}`);
      return due !== null && Math.abs(due - (Date.now() + 14 * 24 * HOUR)) < 2 * HOUR;
    }, 'idle deadline queued');
  });
});

describe('functions: onMatchOver', () => {
  it('expires the code, updates every list and tells players who are away (not those who are online)', async () => {
    const { host, bob, matchId, code } = await runningMatch();
    await host.setPresence(matchId, 1000); // the player who finished the match is looking at it
    await db.ref(`matches/${matchId}/meta/status`).set('over');
    await eventually(async () => (await value(`matchCodes/${code}`)) === null, 'code removed');
    await eventually(async () => (await value(`userMatches/${bob.uid}/${matchId}/status`)) === 'over', 'list updated');
    assert.equal(await value(`userMatches/${host.uid}/${matchId}/status`), 'over');
    assert.equal(await yourTurn(bob, matchId), false);
    await eventually(async () => (await fcmFor(bob.uid)).length === 1, 'push to the away player');
    const [push] = await fcmFor(bob.uid);
    assert.equal(push?.data.type, 'over');
    assert.equal(push?.data.matchId, matchId);
    await settle();
    assert.equal((await fcmFor(host.uid)).length, 0, 'the online player is not pushed');
    const due = await value<number>(`sweepQueue/${matchId}`);
    assert.ok(due !== null && Math.abs(due - (Date.now() + 30 * 24 * HOUR)) < 2 * HOUR, 'deletion is scheduled in 30 days');
  });

  it('expires the code for an abandoned match without a push', async () => {
    const { bob, matchId, code } = await runningMatch();
    await db.ref(`matches/${matchId}/meta/status`).set('abandoned');
    await eventually(async () => (await value(`matchCodes/${code}`)) === null, 'code removed');
    await eventually(async () => (await value(`userMatches/${bob.uid}/${matchId}/status`)) === 'abandoned', 'list updated');
    await settle();
    assert.equal((await fcmFor(bob.uid)).length, 0);
  });

  it('only acts on a change to a finished state', async () => {
    const { bob, matchId, code } = await runningMatch();
    await db.ref(`matches/${matchId}/meta/seed`).set(1234);
    await settle();
    assert.equal(await value(`matchCodes/${code}`), matchId);
    assert.equal(await value(`userMatches/${bob.uid}/${matchId}/status`), 'playing');
  });
});
