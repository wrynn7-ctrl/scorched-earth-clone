// The scheduled sweep, driven with a fake clock (ARCHITECTURE section 46): async timeouts, expired lobbies, dead matches,
// old finished matches.
import assert from 'node:assert/strict';
import { runTimeoutSweep } from '../../functions/src/sweep';
import { db, directDeps, hostLobby, newUser, settle, value, type TestUser } from './harness';

const HOUR = 3600 * 1000;
const DAY = 24 * HOUR;

interface Running {
  host: TestUser;
  bob: TestUser;
  matchId: string;
  code: string;
}

async function startedMatch(timers: Record<string, unknown> = {}): Promise<Running> {
  const host = await newUser({ full: true, name: 'Hana' });
  const bob = await newUser({ name: 'Bob' });
  const { matchId, code } = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human' }, { kind: 'cpu' }], { timers });
  await bob.call('joinMatch', { code });
  await host.call('startMatch', { matchId });
  return { host, bob, matchId, code };
}

/** Puts a started match in the middle of play: 5 entries in the log and bob (tank 1) on turn until `deadline`. */
async function bobsTurn(match: Running, deadline: number): Promise<void> {
  const writes: Record<string, unknown> = {};
  for (let i = 0; i < 5; i += 1) writes[`matches/${match.matchId}/actions/${i}`] = { kind: 'pass', tank: 0 };
  writes[`matches/${match.matchId}/meta/actionCount`] = 5;
  writes[`matches/${match.matchId}/meta/turn`] = { tank: 1, uid: match.bob.uid, deadline, index: 4 };
  await db.ref().update(writes);
  await settle(1200); // let the turn trigger finish its own bookkeeping before the test takes over
}

describe('functions: timeoutSweep (fake clock)', () => {
  it('leaves a turn alone until its deadline passes, and queues it for then', async () => {
    const match = await startedMatch();
    const deadline = Date.now() + 10 * HOUR;
    await bobsTurn(match, deadline);
    const clock = { now: deadline - 1000 };
    const result = await runTimeoutSweep(directDeps(clock), { matchIds: [match.matchId] });
    assert.deepEqual(result.timeouts, []);
    assert.deepEqual(result.skipped, [match.matchId]);
    assert.equal(await value(`matches/${match.matchId}/meta/actionCount`), 5);
    assert.equal(await value(`sweepQueue/${match.matchId}`), deadline);
  });

  it('writes the timeout entry once the deadline has passed, and marks the turn "needs resolve"', async () => {
    const match = await startedMatch();
    const deadline = Date.now() + 10 * HOUR;
    await bobsTurn(match, deadline);
    const clock = { now: deadline + 1000 };
    const result = await runTimeoutSweep(directDeps(clock), { matchIds: [match.matchId] });
    assert.deepEqual(result.timeouts, [match.matchId]);
    assert.deepEqual(await value(`matches/${match.matchId}/actions/5`), { kind: 'timeout', tank: 1, async: 1 });
    assert.equal(await value(`matches/${match.matchId}/meta/actionCount`), 6);
    assert.deepEqual(await value(`matches/${match.matchId}/meta/turn`), { tank: -1, uid: 'any', deadline: 0, index: 5 });
    assert.equal(await value(`matches/${match.matchId}/meta/status`), 'playing');
    assert.equal(await value(`userMatches/${match.bob.uid}/${match.matchId}/yourTurn`), false);
    // Waiting for a client now, with the 14-day idle limit (the turn trigger also refreshes it, using the real clock).
    await settle(1200);
    assert.ok(((await value<number>(`sweepQueue/${match.matchId}`)) ?? 0) > Date.now() + 13 * DAY);
  });

  it('does not time out the same turn twice', async () => {
    const match = await startedMatch();
    const deadline = Date.now() + 10 * HOUR;
    await bobsTurn(match, deadline);
    const clock = { now: deadline + 1000 };
    await runTimeoutSweep(directDeps(clock), { matchIds: [match.matchId] });
    const again = await runTimeoutSweep(directDeps(clock), { matchIds: [match.matchId] });
    assert.deepEqual(again.timeouts, []);
    assert.equal(await value(`matches/${match.matchId}/meta/actionCount`), 6);
    assert.equal(await value(`matches/${match.matchId}/actions/6`), null);
  });

  it('ends the match instead when the host chose "end on timeout"', async () => {
    const match = await startedMatch({ asyncTimeout: 'end' });
    const deadline = Date.now() + 10 * HOUR;
    await bobsTurn(match, deadline);
    const clock = { now: deadline + 1000 };
    const result = await runTimeoutSweep(directDeps(clock), { matchIds: [match.matchId] });
    assert.deepEqual(result.ended, [match.matchId]);
    assert.deepEqual(await value(`matches/${match.matchId}/actions/5`), { kind: 'timeout', tank: 1, async: 1 });
    assert.equal(await value(`matches/${match.matchId}/meta/status`), 'over');
    assert.equal(await value(`matchCodes/${match.code}`), null);
    assert.equal(await value(`userMatches/${match.host.uid}/${match.matchId}/status`), 'over');
    await settle(1200); // the match-over trigger refreshes the queue with the real clock
    assert.ok(((await value<number>(`sweepQueue/${match.matchId}`)) ?? 0) > Date.now() + 29 * DAY, 'deletion is scheduled for 30 days on');
  });

  it('leaves the match alone when a player\'s own entry is already in that slot (they acted just before the sweep)', async () => {
    const match = await startedMatch();
    const deadline = Date.now() + 10 * HOUR;
    await bobsTurn(match, deadline);
    await db.ref(`matches/${match.matchId}/actions/5`).set({ kind: 'pass', tank: 1 });
    const result = await runTimeoutSweep(directDeps({ now: deadline + 1000 }), { matchIds: [match.matchId] });
    assert.deepEqual(result.timeouts, []);
    assert.deepEqual(await value(`matches/${match.matchId}/actions/5`), { kind: 'pass', tank: 1 }, 'the player\'s entry is untouched');
    assert.equal(await value(`matches/${match.matchId}/meta/actionCount`), 5);
  });

  it('finishes a half-done timeout (entry written, count not bumped) on the next run', async () => {
    const match = await startedMatch();
    const deadline = Date.now() + 10 * HOUR;
    await bobsTurn(match, deadline);
    await db.ref(`matches/${match.matchId}/actions/5`).set({ kind: 'timeout', tank: 1, async: 1 });
    const result = await runTimeoutSweep(directDeps({ now: deadline + 1000 }), { matchIds: [match.matchId] });
    assert.deepEqual(result.timeouts, [match.matchId]);
    assert.equal(await value(`matches/${match.matchId}/meta/actionCount`), 6);
    assert.equal(await value(`matches/${match.matchId}/meta/turn/tank`), -1);
    assert.equal(await value(`matches/${match.matchId}/actions/6`), null, 'no second entry');
  });

  it('abandons a match that nobody resolved for 14 days, but not one that is still waiting its time', async () => {
    const match = await startedMatch(); // starts with the "needs resolve" turn
    await settle(1200);
    const clock = { now: Date.now() + 15 * DAY };
    await db.ref(`sweepQueue/${match.matchId}`).set(clock.now + HOUR);
    const early = await runTimeoutSweep(directDeps(clock), { matchIds: [match.matchId] });
    assert.deepEqual(early.abandoned, []);
    assert.equal(await value(`sweepQueue/${match.matchId}`), clock.now + 14 * DAY);

    await db.ref(`sweepQueue/${match.matchId}`).set(clock.now - 1);
    const late = await runTimeoutSweep(directDeps(clock), { matchIds: [match.matchId] });
    assert.deepEqual(late.abandoned, [match.matchId]);
    assert.equal(await value(`matches/${match.matchId}/meta/status`), 'abandoned');
    assert.equal(await value(`matchCodes/${match.code}`), null);
    assert.equal(await value(`userMatches/${match.bob.uid}/${match.matchId}/status`), 'abandoned');
  });

  it('abandons a shop that has been stuck for 14 days', async () => {
    const match = await startedMatch();
    await db.ref(`matches/${match.matchId}/meta/turn`).set({ tank: -2, uid: 'any', deadline: Date.now() + HOUR, index: 1 });
    await settle(1200);
    const clock = { now: Date.now() + 15 * DAY };
    await db.ref(`sweepQueue/${match.matchId}`).set(clock.now - 1);
    const result = await runTimeoutSweep(directDeps(clock), { matchIds: [match.matchId] });
    assert.deepEqual(result.abandoned, [match.matchId]);
  });

  it('expires a lobby nobody started after a day, and keeps a fresh one', async () => {
    const host = await newUser({ full: true });
    const stale = await hostLobby(host);
    const fresh = await hostLobby(host);
    await settle(500);
    const clock = { now: Date.now() + 25 * HOUR };
    await db.ref(`matches/${fresh.matchId}/meta/created`).set(clock.now - HOUR);
    const result = await runTimeoutSweep(directDeps(clock), { matchIds: [stale.matchId, fresh.matchId] });
    assert.deepEqual(result.abandoned, [stale.matchId]);
    assert.deepEqual(result.skipped, [fresh.matchId]);
    assert.equal(await value(`matches/${stale.matchId}/meta/status`), 'abandoned');
    assert.equal(await value(`matchCodes/${stale.code}`), null);
    assert.equal(await value(`userMatches/${host.uid}/${stale.matchId}/status`), 'abandoned');
    assert.equal(await value(`matches/${fresh.matchId}/meta/status`), 'lobby');
    assert.equal(await value(`matchCodes/${fresh.code}`), fresh.matchId);
  });

  it('deletes a finished match, and every pointer to it, after the retention period', async () => {
    const match = await startedMatch();
    await db.ref(`matches/${match.matchId}/meta/status`).set('over');
    await settle(1500);
    const clock = { now: Date.now() + 31 * DAY };
    const early = await runTimeoutSweep(directDeps({ now: Date.now() + 10 * DAY }), { matchIds: [match.matchId] });
    assert.deepEqual(early.deleted, []);
    assert.ok(await value(`matches/${match.matchId}/meta`), 'still there after 10 days');
    await db.ref(`sweepQueue/${match.matchId}`).set(clock.now - 1);
    const result = await runTimeoutSweep(directDeps(clock), { matchIds: [match.matchId] });
    assert.deepEqual(result.deleted, [match.matchId]);
    assert.equal(await value(`matches/${match.matchId}`), null);
    assert.equal(await value(`userMatches/${match.host.uid}/${match.matchId}`), null);
    assert.equal(await value(`userMatches/${match.bob.uid}/${match.matchId}`), null);
    assert.equal(await value(`sweepQueue/${match.matchId}`), null);
  });

  it('without a match list, examines only the queue entries that are due', async () => {
    const dueMatch = await startedMatch();
    const laterMatch = await startedMatch();
    await bobsTurn(dueMatch, Date.now() + 2 * HOUR);
    await bobsTurn(laterMatch, Date.now() + 30 * HOUR);
    const clock = { now: Date.now() + 3 * HOUR };
    const result = await runTimeoutSweep(directDeps(clock));
    assert.ok(result.timeouts.includes(dueMatch.matchId), 'the due match timed out');
    assert.ok(!result.timeouts.includes(laterMatch.matchId));
    assert.ok(!result.skipped.includes(laterMatch.matchId), 'a match that is not due is not even examined');
    assert.equal(await value(`matches/${laterMatch.matchId}/meta/actionCount`), 5);
  });

  it('forgets a queue entry whose match no longer exists, and survives a broken one', async () => {
    await db.ref('sweepQueue/ghostmatch').set(1);
    const result = await runTimeoutSweep(directDeps({ now: Date.now() }), { matchIds: ['ghostmatch'] });
    assert.deepEqual(result.timeouts, []);
    assert.equal(await value('sweepQueue/ghostmatch'), null);
  });
});
