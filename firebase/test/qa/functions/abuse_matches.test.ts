// M7-Q functions abuse, part 3: joining, starting, names through the real triggers, and the sweep racing a client write.
import assert from 'node:assert/strict';
import { bug } from '../bug';
import { runTimeoutSweep } from '../../../functions/src/sweep';
import { checkName } from '../../../functions/src/name_filter';
import { db, directDeps, hostLobby, settle, value } from '../../functions/harness';
import { inParallel, newUser, reasonOf, rest, sleep, type TestUser } from './qa_harness';

const HOUR = 3600 * 1000;
type Seat = { kind: string; uid?: string; name?: string };
const seatsOf = async (id: string): Promise<Seat[]> => (await value<Seat[]>(`matches/${id}/meta/seats`)) ?? [];

describe('QA functions: joining and starting', function () {
  this.timeout(240000);

  it('refuses a full match, a started match and a made-up code, with distinct reasons', async () => {
    const host = await newUser({ full: true, name: 'Host' });
    const [g1, g2, g3] = await inParallel(3, () => newUser());
    const lobby = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human' }, { kind: 'cpu' }]);
    await (g1 as TestUser).call('joinMatch', { code: lobby.code });
    assert.equal(await reasonOf((g2 as TestUser).call('joinMatch', { code: lobby.code })), 'RESOURCE_EXHAUSTED:match_full');
    await host.call('startMatch', { matchId: lobby.matchId });
    assert.equal(await reasonOf((g3 as TestUser).call('joinMatch', { code: lobby.code })), 'FAILED_PRECONDITION:not_joinable');
    assert.equal(await reasonOf((g3 as TestUser).call('joinMatch', { code: 'ZZZZZZ' })), 'NOT_FOUND:unknown_code');
    assert.equal(await reasonOf((g3 as TestUser).call('joinMatch', { code: 'ZZZZZ0' })), 'INVALID_ARGUMENT:bad_code');
    // the joined player can still "join" again (a re-open), and takes no second seat
    const again = await (g1 as TestUser).call<{ alreadyJoined: boolean; seats: number[] }>('joinMatch', { code: lobby.code });
    assert.deepEqual([again.alreadyJoined, again.seats], [true, [1]]);
  });

  it('joining your own match twice is a no-op that reports your seats', async () => {
    const host = await newUser({ full: true, name: 'Host' });
    const lobby = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human' }]);
    const first = await host.call<{ alreadyJoined: boolean; seats: number[] }>('joinMatch', { code: lobby.code });
    const second = await host.call<{ alreadyJoined: boolean; seats: number[] }>('joinMatch', { code: lobby.code });
    assert.deepEqual(first, { matchId: lobby.matchId, seats: [0], alreadyJoined: true });
    assert.deepEqual(second, first);
    assert.equal((await seatsOf(lobby.matchId)).filter((s) => s.uid === host.uid).length, 1);
  });

  it('checks the protocol: a mismatch is refused with both numbers, and a client-set protocol is believed', async () => {
    const host = await newUser({ full: true, name: 'Host', protocol: 1 });
    const old = await newUser({ name: 'Old', protocol: 2 });
    const lobby = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human' }]);
    try {
      await old.call('joinMatch', { code: lobby.code });
      assert.fail('should have been refused');
    } catch (error) {
      const e = error as { status: string; reason: string; details: unknown };
      assert.deepEqual([e.status, e.reason, e.details], ['FAILED_PRECONDITION', 'protocol_mismatch', { hostProtocol: 1, yourProtocol: 2 }]);
    }
    // Information: the number a player is judged by is one they can write themselves (rules: users/{uid}/protocol is
    // owner-writable). The client refuses a protocol it does not know anyway (OnlineMatch.open), so this only matters for a
    // modified client, which could also lie in ensureProfile.
    const set = await rest(old.token, 'PUT', `users/${old.uid}/protocol`, 1);
    assert.equal(set.status, 200);
    const joined = await old.call<{ alreadyJoined: boolean }>('joinMatch', { code: lobby.code });
    assert.equal(joined.alreadyJoined, false);
  });

  it('refuses bad seatCount values and more seats than are free', async () => {
    const host = await newUser({ full: true, name: 'Host' });
    const lobby = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human' }, { kind: 'human' }]);
    const g = await newUser();
    for (const bad of [0, -1, 5, 1.5, '2', true, null, [2], {}]) {
      assert.match(await reasonOf(g.call('joinMatch', { code: lobby.code, seatCount: bad })), /^INVALID_ARGUMENT/, JSON.stringify(bad));
    }
    assert.equal(await reasonOf(g.call('joinMatch', { code: lobby.code, seatCount: 3 })), 'RESOURCE_EXHAUSTED:not_enough_seats');
    assert.equal((await seatsOf(lobby.matchId)).filter((s) => s.uid === g.uid).length, 0);
  });

  const capProbe = async (existing: number): Promise<{ join: string; create: string }> => {
    const host = await newUser({ full: true, name: 'Host' });
    const g = await newUser();
    const lobby = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human' }]);
    const fake: Record<string, unknown> = {};
    for (let i = 0; i < existing; i += 1) fake[`userMatches/${g.uid}/qaFake${i}`] = { updated: 1, yourTurn: false, status: 'over' };
    await db.ref().update(fake);
    try {
      const join = await reasonOf(g.call('joinMatch', { code: lobby.code }));
      await db.ref(`users/${g.uid}/full`).set(true);
      const create = await reasonOf(g.call('createMatch', { settings: {}, seats: [{ kind: 'human' }, { kind: 'cpu' }] }));
      return { join, create };
    } finally {
      await db.ref(`userMatches/${g.uid}`).remove(); // only this test's own user
    }
  };

  it('refuses joining and hosting for a player who already has 41 matches', async () => {
    assert.deepEqual(await capProbe(41), { join: 'RESOURCE_EXHAUSTED:too_many_matches', create: 'RESOURCE_EXHAUSTED:too_many_matches' });
  });

  // BUG (low): the per-player cap is 41 matches, not the documented 40.
  //   input:    a player with exactly 40 entries in userMatches calls joinMatch (or createMatch).
  //   expected: RESOURCE_EXHAUSTED too_many_matches (ARCHITECTURE 51: "Caps: 40 matches"; firebase/README: `too_many_matches (40)`).
  //   actual:   allowed; the player ends with 41. The existing test seeds 41 entries, which hides the off-by-one.
  //   cause:    functions/src/matches.ts assertRoomForMatch(): `numChildren() > MAX_USER_MATCHES` should be `>=`.
  bug('BUG (low): refuses the 41st match (cap is 40)', async () => {
    assert.deepEqual(await capProbe(40), { join: 'RESOURCE_EXHAUSTED:too_many_matches', create: 'RESOURCE_EXHAUSTED:too_many_matches' });
  });

  it('treats a blocked pair as an unknown code in both directions', async () => {
    const host = await newUser({ full: true, name: 'Host' });
    const a = await newUser();
    const b = await newUser();
    const lobby = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human' }, { kind: 'human' }]);
    await a.call('block', { targetUid: host.uid });
    assert.equal(await reasonOf(a.call('joinMatch', { code: lobby.code })), 'NOT_FOUND:unknown_code');
    await host.call('block', { targetUid: b.uid });
    assert.equal(await reasonOf(b.call('joinMatch', { code: lobby.code })), 'NOT_FOUND:unknown_code');
  });

  // BUG (medium): the same account can take two seats by double-tapping JOIN (concurrent joinMatch).
  //   input:    one guest sends joinMatch {code} twice at the same moment, lobby with 3 free seats (it happens on some runs
  //             only: the probe hit it 1 in 1, the test below needs a few attempts).
  //   expected: one seat; the second call returns alreadyJoined: true with the same seat.
  //   actual:   both succeed with alreadyJoined: false, seats [2] and [1]: the guest now holds two seats ("Guest" twice, the
  //             second not numbered), so one fewer player can join and the match shows two seats for one phone.
  //   cause:    functions/src/matches.ts joinMatch(): the "already in the match" check reads meta BEFORE the transaction, and the
  //             transaction body only checks free seats, never whether `uid` already holds one.
  //   fix idea: repeat the `meta.seats.some(s => s.uid === uid)` check inside mutateMeta and return alreadyJoined there.
  bug('BUG (medium): a simultaneous double join takes only one seat', async () => {
    const host = await newUser({ full: true, name: 'Host' });
    let doubled = 0;
    for (let i = 0; i < 8; i += 1) {
      const g = await newUser({ name: 'Guest' });
      const lobby = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human' }, { kind: 'human' }, { kind: 'human' }]);
      await Promise.all([g.call('joinMatch', { code: lobby.code }), g.call('joinMatch', { code: lobby.code })]);
      if ((await seatsOf(lobby.matchId)).filter((s) => s.uid === g.uid).length > 1) doubled += 1;
    }
    assert.equal(doubled, 0, `${doubled} of 8 double-taps took two seats`);
  });

  it('starts exactly once when the host double-taps START, with one seed', async () => {
    const host = await newUser({ full: true, name: 'Host' });
    const g = await newUser();
    const lobby = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human' }, { kind: 'cpu' }]);
    await g.call('joinMatch', { code: lobby.code });
    const results = await Promise.all([reasonOf(host.call('startMatch', { matchId: lobby.matchId })), reasonOf(host.call('startMatch', { matchId: lobby.matchId }))]);
    assert.deepEqual([...results].sort(), ['FAILED_PRECONDITION:not_in_lobby', 'OK']);
    const meta = (await value<Record<string, any>>(`matches/${lobby.matchId}/meta`)) as Record<string, any>;
    assert.equal(meta.settings.seed, meta.seed);
    assert.ok(meta.seed > 0);
    assert.equal(meta.actionCount, 0);
  });

  it('refuses start before the seats are filled, by a guest, and edits after the start', async () => {
    const host = await newUser({ full: true, name: 'Host' });
    const g = await newUser();
    const lobby = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human' }, { kind: 'cpu' }]);
    assert.equal(await reasonOf(host.call('startMatch', { matchId: lobby.matchId })), 'FAILED_PRECONDITION:seats_not_filled');
    await g.call('joinMatch', { code: lobby.code });
    assert.equal(await reasonOf(g.call('startMatch', { matchId: lobby.matchId })), 'PERMISSION_DENIED:not_host');
    assert.equal(await reasonOf(g.call('updateLobby', { matchId: lobby.matchId, settings: { rounds: 9 } })), 'PERMISSION_DENIED:not_host');
    assert.equal(await reasonOf(host.call('updateLobby', { matchId: lobby.matchId, seats: [{ kind: 'human', uid: host.uid }, { kind: 'cpu' }, { kind: 'cpu' }] })), 'FAILED_PRECONDITION:seat_taken');
    await host.call('startMatch', { matchId: lobby.matchId });
    assert.equal(await reasonOf(host.call('updateLobby', { matchId: lobby.matchId, settings: { rounds: 9 } })), 'FAILED_PRECONDITION:not_in_lobby');
    assert.equal(await reasonOf(host.call('startMatch', { matchId: lobby.matchId })), 'FAILED_PRECONDITION:not_in_lobby');
  });

  it('a host who leaves the lobby closes it: the code is dead and the guest sees it abandoned', async () => {
    const host = await newUser({ full: true, name: 'Host' });
    const g = await newUser();
    const late = await newUser();
    const lobby = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human' }, { kind: 'human' }]);
    await g.call('joinMatch', { code: lobby.code });
    assert.equal(((await host.call('leaveMatch', { matchId: lobby.matchId })) as { status: string }).status, 'abandoned');
    assert.equal(await reasonOf(late.call('joinMatch', { code: lobby.code })), 'NOT_FOUND:unknown_code');
    assert.equal(await value(`matches/${lobby.matchId}/meta/status`), 'abandoned');
    await settle(800);
    assert.equal(await value(`userMatches/${g.uid}/${lobby.matchId}/status`), 'abandoned');
    assert.equal(await reasonOf(g.call('joinMatch', { code: lobby.code })), 'NOT_FOUND:unknown_code');
  });
});

describe('QA functions: names through the real triggers', function () {
  this.timeout(240000);

  const NAMES: string[] = [
    'Anna', 'a b  c', '  padded  ', 'ÅÉÎÕÜ', 'ＡＢＣ', '😀😀', 'Hi😀', 'a​b', 'a‮b', '‮evil', 'x́y', 'tab\there', 'new\nline',
    'f*ckyou', 'sh1thead', 'ＦＵＣＫ', 'Привет', 'こんにちは', 'a\u0000b', 'x'.repeat(12), 'x'.repeat(13), '1234567890123', 'mixed 😀 text', '﻿BOM', 'dot.dot', "a'b\"c", '<b>x</b>',
  ];

  it('stores, for every client-written name, exactly what the server filter says, and never anything unprintable', async () => {
    const u = await newUser();
    const problems: string[] = [];
    for (const raw of NAMES) {
      const put = await rest(u.token, 'PUT', `users/${u.uid}/name`, raw);
      if (put.status !== 200) continue; // refused by the rules (length etc.)
      const want = checkName(raw).name;
      let stored = '';
      for (let i = 0; i < 40; i += 1) {
        stored = ((await value<string>(`users/${u.uid}/name`)) ?? '') as string;
        if (stored === want) break;
        await sleep(100);
      }
      if (stored !== want) problems.push(`${JSON.stringify(raw)} -> stored ${JSON.stringify(stored)}, filter says ${JSON.stringify(want)}`);
      if (/[\u0000-\u001f\u007f-\u009f​-‏‪-‮⁠-⁯﻿\ud800-\udfff]/.test(stored)) problems.push(`${JSON.stringify(raw)} stored unprintable ${JSON.stringify(stored)}`);
    }
    assert.deepEqual(problems, []);
  });

  it('filters seat names given to createMatch and joinMatch with the same rules', async () => {
    const host = await newUser({ full: true, name: 'Hana' });
    const g = await newUser({ name: 'Gus' });
    const lobby = await host.call<{ matchId: string; code: string }>('createMatch', {
      settings: { rounds: 1 },
      seats: [{ kind: 'human', mine: true, name: 'f*ckyou' }, { kind: 'human', mine: true, name: '😀😀' }, { kind: 'cpu', name: 'a‮b' }, { kind: 'human' }],
    });
    const seats = await seatsOf(lobby.matchId);
    assert.equal(seats[0]?.name, 'Hana', 'blocked seat name falls back to the host name');
    assert.equal(seats[1]?.name, 'Hana 2');
    assert.equal(seats[2]?.name, 'ab');
    await g.call('joinMatch', { code: lobby.code, names: ['sh1thead'] });
    assert.equal((await seatsOf(lobby.matchId))[3]?.name, 'Gus');
    for (const huge of ['x'.repeat(2_000_000), '😀'.repeat(500_000)]) {
      const started = Date.now();
      const l2 = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human' }]);
      const h = await newUser();
      await h.call('joinMatch', { code: l2.code, names: [huge] });
      assert.ok(Date.now() - started < 15000, 'a 2 MB name must not stall the function');
    }
  });

  // BUG (medium): a profanity-filter bypass: an unfiltered name can reach every player through the seat of a match.
  //   input:    a client writes users/{uid}/name = "f*ckyou" (allowed by the rules: only length is checked) and calls joinMatch /
  //             createMatch at once, before the onNameWrite trigger has replaced the name with PLAYER.
  //   expected: the seat (and invite fromName, friend request name, userMatches hostName) never carries a name that fails the
  //             filter, because handlers re-check the stored name or the trigger finishes first.
  //   actual:   about 1 in 3 attempts in the emulator put "f*ckyou" into meta/seats/N/name, which is permanent (seats are not
  //             re-checked), visible to everybody in the match and in the lobby list.
  //   cause:    functions/src/matches.ts uses displayName(user) = users/{uid}/name straight from the database for the seat
  //             (`seatName(undefined, fallback)` returns the fallback without checkName), and friends.ts / invite() use it for
  //             request names and invites. The name trigger is asynchronous.
  //   fix idea: run checkName() inside displayName() (cheap and pure), or write the name through a callable.
  bug('BUG (medium): a freshly written bad name never reaches a seat before the trigger fixes it', async () => {
    const host = await newUser({ full: true, name: 'Host' });
    let leaks = 0;
    for (let i = 0; i < 12; i += 1) {
      const g = await newUser({ name: 'Okay' });
      const lobby = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human' }]);
      await rest(g.token, 'PUT', `users/${g.uid}/name`, 'f*ckyou');
      await g.call('joinMatch', { code: lobby.code });
      if ((await seatsOf(lobby.matchId)).some((s) => s.name === 'f*ckyou')) leaks += 1;
    }
    assert.equal(leaks, 0, `${leaks} of 12 joins carried the bad name`);
  });
});

describe('QA functions: the sweep racing a client write at the same log index', function () {
  this.timeout(300000);

  async function dueMatch(host: TestUser, guest: TestUser): Promise<{ id: string; count: number }> {
    const lobby = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human' }, { kind: 'cpu' }]);
    await guest.call('joinMatch', { code: lobby.code });
    await host.call('startMatch', { matchId: lobby.matchId });
    const writes: Record<string, unknown> = {};
    for (let i = 0; i < 2; i += 1) writes[`matches/${lobby.matchId}/actions/${i}`] = { kind: 'pass', tank: 0 };
    writes[`matches/${lobby.matchId}/meta/actionCount`] = 2;
    writes[`matches/${lobby.matchId}/meta/turn`] = { tank: 0, uid: host.uid, deadline: Date.now() - 2000, index: 1 };
    await db.ref().update(writes);
    await settle(700);
    return { id: lobby.matchId, count: 2 };
  }

  async function checkConsistent(id: string, count: number): Promise<{ kind: string; turnTank: number }> {
    const meta = (await value<Record<string, any>>(`matches/${id}/meta`)) as Record<string, any>;
    const actions = (await value<unknown[]>(`matches/${id}/actions`)) ?? [];
    const entries = Array.isArray(actions) ? actions : Object.values(actions as Record<string, unknown>);
    assert.equal(entries.length, meta.actionCount, 'actionCount equals the number of entries');
    assert.equal(meta.actionCount, count + 1, 'exactly one entry was appended');
    assert.equal(meta.turn.index, 2, 'the turn index moved exactly once');
    const entry = entries[count] as { kind: string; tank: number; async?: number };
    assert.ok(entry, 'the contested slot holds an entry');
    assert.equal(await value(`matches/${id}/actions/${count + 1}`), null, 'no orphan entry after the contested slot');
    return { kind: entry.kind, turnTank: meta.turn.tank as number };
  }

  it('lets a client async-timeout and the sweep race: one entry, one turn change, either winner', async () => {
    const host = await newUser({ full: true, name: 'Host' });
    const guest = await newUser({ name: 'Guest' });
    const wins = { client: 0, sweep: 0 };
    for (let round = 0; round < 10; round += 1) {
      const { id, count } = await dueMatch(host, guest);
      const clientWrite = async (): Promise<number> => {
        await sleep(round % 4 === 0 ? 0 : (round * 7) % 25);
        const r = await rest(guest.token, 'PATCH', `matches/${id}`, {
          [`actions/${count}`]: { kind: 'timeout', tank: 0, async: 1 },
          'meta/actionCount': count + 1,
          'meta/turn': { tank: -1, uid: 'any', deadline: 0, index: 2 },
        });
        return r.status;
      };
      const sweep = async (): Promise<string[]> => {
        await sleep(round % 4 === 1 ? 0 : (round * 11) % 25);
        return (await runTimeoutSweep(directDeps({ now: Date.now() + 1000 }), { matchIds: [id] })).timeouts;
      };
      const [status, timeouts] = await Promise.all([clientWrite(), sweep()]);
      const done = await checkConsistent(id, count);
      assert.equal(done.kind, 'timeout');
      assert.equal(done.turnTank, -1);
      const clientOk = status === 200;
      const sweepOk = timeouts.includes(id);
      assert.ok(clientOk !== sweepOk, `exactly one writer reports success (client ${status}, sweep ${String(sweepOk)})`);
      if (clientOk) wins.client += 1;
      else wins.sweep += 1;
    }
    console.log(`      async-timeout race: client won ${wins.client}, sweep won ${wins.sweep}`);
  });

  it('lets the holder\'s own late action and the sweep race: either the shot or the timeout, never both', async () => {
    const host = await newUser({ full: true, name: 'Host' });
    const guest = await newUser({ name: 'Guest' });
    const wins = { holder: 0, sweep: 0 };
    for (let round = 0; round < 10; round += 1) {
      const { id, count } = await dueMatch(host, guest);
      const holderWrite = async (): Promise<number> => {
        await sleep((round * 5) % 20);
        const r = await rest(host.token, 'PATCH', `matches/${id}`, {
          [`actions/${count}`]: { kind: 'fire', tank: 0, angle: 450, power: 500, weapon: 'spark_dart' },
          'meta/actionCount': count + 1,
          'meta/turn': { tank: 1, uid: guest.uid, deadline: Date.now() + HOUR, index: 2 },
        });
        return r.status;
      };
      const sweep = async (): Promise<string[]> => {
        await sleep((round * 3) % 20);
        return (await runTimeoutSweep(directDeps({ now: Date.now() + 1000 }), { matchIds: [id] })).timeouts;
      };
      const [status, timeouts] = await Promise.all([holderWrite(), sweep()]);
      const done = await checkConsistent(id, count);
      if (status === 200) {
        assert.equal(done.kind, 'fire');
        assert.equal(done.turnTank, 1);
        assert.deepEqual(timeouts, [], 'the sweep must leave a match alone when a player acted first');
        wins.holder += 1;
      } else {
        assert.equal(done.kind, 'timeout');
        assert.equal(done.turnTank, -1);
        assert.deepEqual(timeouts, [id]);
        wins.sweep += 1;
      }
    }
    console.log(`      holder-vs-sweep race: holder won ${wins.holder}, sweep won ${wins.sweep}`);
  });

  it('completes a half-done sweep (entry written, count not bumped) on the next run, without a second entry', async () => {
    const host = await newUser({ full: true, name: 'Host' });
    const guest = await newUser({ name: 'Guest' });
    const { id, count } = await dueMatch(host, guest);
    await db.ref(`matches/${id}/actions/${count}`).set({ kind: 'timeout', tank: 0, async: 1 }); // step 1 only
    const result = await runTimeoutSweep(directDeps({ now: Date.now() + 1000 }), { matchIds: [id] });
    assert.deepEqual(result.timeouts, [id]);
    await checkConsistent(id, count);
    const again = await runTimeoutSweep(directDeps({ now: Date.now() + 1000 }), { matchIds: [id] });
    assert.deepEqual(again.timeouts, []);
    await checkConsistent(id, count);
  });

  // Information (low): the sweep also times out a CPU turn that nobody drove for the whole deadline (e.g. a batch stopped at
  // the 16-entry cap with every client away). The rules forbid a client timeout on a CPU seat; the sweep writes it as admin.
  it('documents: a stuck CPU turn past its deadline gets a `timeout` entry from the sweep', async () => {
    const host = await newUser({ full: true, name: 'Host' });
    const guest = await newUser({ name: 'Guest' });
    const { id, count } = await dueMatch(host, guest);
    await db.ref(`matches/${id}/meta/turn`).set({ tank: 2, uid: 'cpu', deadline: Date.now() - 2000, index: 1 });
    const result = await runTimeoutSweep(directDeps({ now: Date.now() + 1000 }), { matchIds: [id] });
    assert.deepEqual(result.timeouts, [id]);
    assert.deepEqual(await value(`matches/${id}/actions/${count}`), { kind: 'timeout', tank: 2, async: 1 });
  });
});
