// createMatch, updateLobby, joinMatch, leaveMatch, startMatch, invite (ARCHITECTURE section 45).
import assert from 'node:assert/strict';
import { CODE_ALPHABET } from '../../functions/src/config';
import { befriend, type CallError, callWith, db, eventually, fcmFor, hostLobby, newUser, settle, signUp, value, type TestUser } from './harness';

const status = (s: string) => (e: CallError) => e.status === s;
const reason = (s: string, r: string) => (e: CallError) => e.status === s && e.reason === r;

interface Seat {
  kind: string;
  uid?: string;
  name?: string;
  level?: number;
}
const seatsOf = async (matchId: string): Promise<Seat[]> => (await value<Seat[]>(`matches/${matchId}/meta/seats`)) ?? [];
const metaOf = async (matchId: string): Promise<Record<string, any>> => (await value<Record<string, any>>(`matches/${matchId}/meta`)) ?? {};  

describe('functions: createMatch', () => {
  it('lets only a full owner host', async () => {
    const free = await newUser();
    await assert.rejects(hostLobby(free), reason('PERMISSION_DENIED', 'full_required'));
    assert.equal(await value(`userMatches/${free.uid}`), null);
  });

  it('creates a lobby: code, meta, seats, settings, timers, host entry and sweep entry', async () => {
    const host = await newUser({ full: true, name: 'Hana', protocol: 3 });
    const { matchId, code } = await host.call<{ matchId: string; code: string }>('createMatch', {
      settings: { rounds: 4, wind_max: 60, start_money: 5000, friendly_fire: false, theme: 'ice' },
      seats: [{ kind: 'human', mine: true }, { kind: 'cpu', level: 3 }, { kind: 'human' }],
      timers: { liveSec: 45, asyncHours: 24, asyncTimeout: 'end' },
    });
    assert.equal(code.length, 6);
    for (const ch of code) assert.ok(CODE_ALPHABET.includes(ch));
    assert.equal(await value(`matchCodes/${code}`), matchId);
    const meta = await metaOf(matchId);
    assert.equal(meta.hostUid, host.uid);
    assert.equal(meta.code, code);
    assert.equal(meta.protocol, 3);
    assert.equal(meta.status, 'lobby');
    assert.equal(meta.actionCount, 0);
    assert.equal(meta.seed, 0);
    assert.deepEqual(meta.timers, { liveSec: 45, asyncHours: 24, asyncTimeout: 'end' });
    assert.deepEqual(meta.seats[0], { kind: 'human', uid: host.uid, name: 'Hana' });
    assert.deepEqual(meta.seats[1], { kind: 'cpu', level: 3, name: 'CPU 2' });
    assert.deepEqual(meta.seats[2], { kind: 'human' });
    assert.deepEqual(meta.settings, {
      seed: 0,
      num_tanks: 3,
      rounds: 4,
      wind_max: 60,
      start_money: 5000,
      full_unlocked: true,
      controllers: [0, 3, 0],
      mode: 0,
      friendly_fire: false,
      theme: 'ice',
    });
    const entry = await value<Record<string, unknown>>(`userMatches/${host.uid}/${matchId}`);
    assert.equal(entry?.status, 'lobby');
    assert.equal(entry?.yourTurn, false);
    assert.equal(entry?.hostName, 'Hana');
    assert.equal(await value(`sweepQueue/${matchId}`), (meta.created as number) + 24 * 3600 * 1000);
  });

  it('applies timer defaults (live 60 s, async 72 h, auto-play)', async () => {
    const host = await newUser({ full: true });
    const { matchId } = await hostLobby(host);
    assert.deepEqual((await metaOf(matchId)).timers, { liveSec: 60, asyncHours: 72, asyncTimeout: 'auto' });
  });

  it('gives each phone-sharing seat its own name', async () => {
    const host = await newUser({ full: true, name: 'Hana' });
    const { matchId } = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human', mine: true, name: 'Ben' }, { kind: 'human', mine: true }]);
    const seats = await seatsOf(matchId);
    assert.deepEqual(seats.map((s) => s.name), ['Hana', 'Ben', 'Hana 3']);
    assert.ok(seats.every((s) => s.uid === host.uid));
  });

  it('claims the first human seat for the host when none is marked, and filters typed seat names', async () => {
    const host = await newUser({ full: true, name: 'Hana' });
    const { matchId } = await hostLobby(host, [{ kind: 'cpu' }, { kind: 'human', name: 'f u c k' }, { kind: 'human' }]);
    const seats = await seatsOf(matchId);
    assert.equal(seats[1]?.uid, host.uid);
    assert.equal(seats[1]?.name, 'Hana', 'a blocked typed name falls back to the player name');
    assert.equal(seats[2]?.uid, undefined);
    assert.equal(seats[0]?.level, 2, 'a CPU with no level is Normal');
  });

  it('validates the seats', async () => {
    const host = await newUser({ full: true });
    const bad = (seats: unknown) => assert.rejects(host.call('createMatch', { seats }), status('INVALID_ARGUMENT'));
    await bad([{ kind: 'human' }]);
    await bad(Array.from({ length: 9 }, () => ({ kind: 'human' })));
    await bad('seats');
    await bad(undefined);
    await bad([{ kind: 'robot' }, { kind: 'human' }]);
    await bad([{ kind: 'cpu', level: 0 }, { kind: 'human' }]);
    await bad([{ kind: 'cpu', level: 5 }, { kind: 'human' }]);
    await bad([{ kind: 'cpu' }, { kind: 'cpu' }]); // nobody to play
    await bad([{ kind: 'human' }, 5]);
  });

  it('validates the settings and the timers', async () => {
    const host = await newUser({ full: true });
    const seats = [{ kind: 'human', mine: true }, { kind: 'human' }];
    const bad = (settings: unknown, timers?: unknown) => assert.rejects(host.call('createMatch', { seats, settings, timers }), status('INVALID_ARGUMENT'));
    await bad({ rounds: 0 });
    await bad({ rounds: 21 });
    await bad({ rounds: 1.5 });
    await bad({ wind_max: 101 });
    await bad({ start_money: -1 });
    await bad({ start_money: 1_000_001 });
    await bad({ mode: 2 });
    await bad({ friendly_fire: 'yes' });
    await bad({ num_tanks: 3 });
    await bad({ teams: [0, 1, 2] }); // wrong length
    await bad({ teams: [1, 1] }); // one team only
    await bad({ teams: [0, 4] }); // team out of range
    await bad({ theme: 'Bad Theme' });
    await bad({}, { liveSec: 5 });
    await bad({}, { liveSec: 601 });
    await bad({}, { asyncHours: 0 });
    await bad({}, { asyncHours: 169 });
    await bad({}, { asyncTimeout: 'maybe' });
  });

  it('accepts valid teams and keeps them', async () => {
    const host = await newUser({ full: true });
    const { matchId } = await host.call<{ matchId: string }>('createMatch', {
      seats: [{ kind: 'human', mine: true }, { kind: 'human' }, { kind: 'cpu' }, { kind: 'cpu' }],
      settings: { teams: [0, 0, 1, 1], friendly_fire: false },
    });
    const settings = (await metaOf(matchId)).settings;
    assert.deepEqual(settings.teams, [0, 0, 1, 1]);
    assert.deepEqual(settings.controllers, [0, 0, 2, 2]);
  });

  it('builds a Love Edition duel: two humans, 1 round, gentle wind, no money, no teams, no CPUs', async () => {
    const host = await newUser({ full: true });
    const humans = [{ kind: 'human', mine: true }, { kind: 'human' }];
    const { matchId } = await host.call<{ matchId: string }>('createMatch', { seats: humans, settings: { mode: 1, rounds: 5, wind_max: 90, start_money: 9999 } });
    const settings = (await metaOf(matchId)).settings;
    assert.equal(settings.mode, 1);
    assert.equal(settings.rounds, 1);
    assert.equal(settings.wind_max, 30);
    assert.equal(settings.start_money, 0);
    await assert.rejects(host.call('createMatch', { seats: [{ kind: 'human', mine: true }, { kind: 'cpu' }], settings: { mode: 1 } }), status('INVALID_ARGUMENT'));
    await assert.rejects(host.call('createMatch', { seats: [...humans, { kind: 'human' }], settings: { mode: 1 } }), status('INVALID_ARGUMENT'));
    await assert.rejects(host.call('createMatch', { seats: humans, settings: { mode: 1, teams: [0, 1] } }), status('INVALID_ARGUMENT'));
  });

  it('refuses signed-out callers and users with no profile', async () => {
    await assert.rejects(callWith('createMatch', {}, null), status('UNAUTHENTICATED'));
    const bare = await signUp();
    await assert.rejects(bare.call('createMatch', { seats: [] }), reason('FAILED_PRECONDITION', 'no_profile'));
  });

  it('gives different matches different codes', async () => {
    const host = await newUser({ full: true });
    const a = await hostLobby(host);
    const b = await hostLobby(host);
    assert.notEqual(a.code, b.code);
    assert.notEqual(a.matchId, b.matchId);
  });

  it('stops a player collecting an unbounded number of matches', async () => {
    const host = await newUser({ full: true });
    const seeded: Record<string, unknown> = {};
    for (let i = 0; i < 41; i += 1) seeded[`userMatches/${host.uid}/old${i}`] = { updated: 1, yourTurn: false, status: 'over' };
    await db.ref().update(seeded);
    await assert.rejects(hostLobby(host), reason('RESOURCE_EXHAUSTED', 'too_many_matches'));
  });
});

describe('functions: joinMatch', () => {
  let host: TestUser;
  let matchId: string;
  let code: string;
  beforeEach(async () => {
    host = await newUser({ full: true, name: 'Hana' });
    ({ matchId, code } = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human' }, { kind: 'human' }]));
  });

  it('takes a free seat for the joiner (code in any case) and lists the match for them', async () => {
    const ben = await newUser({ name: 'Ben' });
    const result = await ben.call<{ matchId: string; seats: number[]; alreadyJoined: boolean }>('joinMatch', { code: code.toLowerCase() });
    assert.deepEqual(result, { matchId, seats: [1], alreadyJoined: false });
    assert.deepEqual((await seatsOf(matchId))[1], { kind: 'human', uid: ben.uid, name: 'Ben' });
    const entry = await value<Record<string, unknown>>(`userMatches/${ben.uid}/${matchId}`);
    assert.equal(entry?.status, 'lobby');
    assert.equal(entry?.hostName, 'Hana');
    // The host's list still shows the match, now refreshed.
    assert.ok(await value(`userMatches/${host.uid}/${matchId}`));
  });

  it('is idempotent for a player who is already in', async () => {
    const ben = await newUser();
    await ben.call('joinMatch', { code });
    const again = await ben.call<{ alreadyJoined: boolean; seats: number[] }>('joinMatch', { code });
    assert.equal(again.alreadyJoined, true);
    assert.deepEqual(again.seats, [1]);
    assert.equal((await seatsOf(matchId)).filter((s) => s.uid === ben.uid).length, 1);
  });

  it('lets one phone take several seats, with their own names', async () => {
    const ben = await newUser({ name: 'Ben' });
    const result = await ben.call<{ seats: number[] }>('joinMatch', { code, seatCount: 2, names: ['Ben', 'Cy'] });
    assert.deepEqual(result.seats, [1, 2]);
    const seats = await seatsOf(matchId);
    assert.deepEqual([seats[1]?.name, seats[2]?.name], ['Ben', 'Cy']);
    assert.ok(seats[1]?.uid === ben.uid && seats[2]?.uid === ben.uid);
  });

  it('refuses when the match is full or too few seats are free', async () => {
    await (await newUser()).call('joinMatch', { code });
    const late = await newUser();
    await assert.rejects(late.call('joinMatch', { code, seatCount: 2 }), reason('RESOURCE_EXHAUSTED', 'not_enough_seats'));
    await (await newUser()).call('joinMatch', { code });
    await assert.rejects(late.call('joinMatch', { code }), reason('RESOURCE_EXHAUSTED', 'match_full'));
  });

  it('never gives one seat to two players who join at the same moment', async () => {
    const joiners = await Promise.all(Array.from({ length: 5 }, () => newUser()));
    const outcomes = await Promise.allSettled(joiners.map((u) => u.call('joinMatch', { code })));
    assert.equal(outcomes.filter((o) => o.status === 'fulfilled').length, 2, 'two free seats, two winners');
    const uids = (await seatsOf(matchId)).map((s) => s.uid);
    assert.equal(new Set(uids).size, 3);
    assert.ok(uids.every(Boolean));
  });

  it('refuses unknown or malformed codes and an unusable seat count', async () => {
    const ben = await newUser();
    await assert.rejects(ben.call('joinMatch', { code: 'ZZZZZZ' }), reason('NOT_FOUND', 'unknown_code'));
    await assert.rejects(ben.call('joinMatch', { code: 'abc' }), status('INVALID_ARGUMENT'));
    await assert.rejects(ben.call('joinMatch', {}), status('INVALID_ARGUMENT'));
    await assert.rejects(ben.call('joinMatch', { code, seatCount: 0 }), status('INVALID_ARGUMENT'));
    await assert.rejects(ben.call('joinMatch', { code, seatCount: 5 }), status('INVALID_ARGUMENT'));
  });

  it('refuses a player on a different protocol, saying which versions differ, until they update', async () => {
    const old = await newUser({ protocol: 2 });
    await assert.rejects(old.call('joinMatch', { code }), (e: CallError) => {
      const details = e.details as { hostProtocol: number; yourProtocol: number };
      return e.status === 'FAILED_PRECONDITION' && e.reason === 'protocol_mismatch' && details.hostProtocol === 1 && details.yourProtocol === 2;
    });
    assert.equal((await seatsOf(matchId))[1]?.uid, undefined, 'no seat was taken');
    await old.call('ensureProfile', { protocol: 1 }); // the player updated the game
    assert.deepEqual((await old.call<{ seats: number[] }>('joinMatch', { code })).seats, [1]);
  });

  it('treats a player the host blocked as if the code did not exist', async () => {
    const ben = await newUser();
    await host.call('block', { targetUid: ben.uid });
    await assert.rejects(ben.call('joinMatch', { code }), reason('NOT_FOUND', 'unknown_code'));
    assert.equal((await seatsOf(matchId))[1]?.uid, undefined);
  });

  it('treats a host the joiner blocked as if the code did not exist', async () => {
    const ben = await newUser();
    await ben.call('block', { targetUid: host.uid });
    await assert.rejects(ben.call('joinMatch', { code }), reason('NOT_FOUND', 'unknown_code'));
  });

  it('refuses a joiner who is blocked (either way) with any player already seated', async () => {
    const [cy, dee, eve] = [await newUser(), await newUser(), await newUser()];
    await cy.call('joinMatch', { code });
    await dee.call('block', { targetUid: cy.uid }); // dee blocked cy
    await assert.rejects(dee.call('joinMatch', { code }), reason('NOT_FOUND', 'unknown_code'));
    await eve.call('joinMatch', { code }).catch(() => undefined); // takes the last seat; no block involved
    const frank = await newUser();
    await cy.call('block', { targetUid: frank.uid }); // cy blocked frank (the other direction)
    await assert.rejects(frank.call('joinMatch', { code }), status('NOT_FOUND'));
  });

  it('refuses once the match has started or was abandoned', async () => {
    const ben = await newUser();
    await ben.call('joinMatch', { code });
    await (await newUser()).call('joinMatch', { code });
    await host.call('startMatch', { matchId });
    await assert.rejects((await newUser()).call('joinMatch', { code }), reason('FAILED_PRECONDITION', 'not_joinable'));
  });

  it('refuses a player with no profile', async () => {
    const bare = await signUp();
    await assert.rejects(bare.call('joinMatch', { code }), reason('FAILED_PRECONDITION', 'no_profile'));
  });
});

describe('functions: updateLobby', () => {
  let host: TestUser;
  let matchId: string;
  let code: string;
  beforeEach(async () => {
    host = await newUser({ full: true, name: 'Hana' });
    ({ matchId, code } = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human' }]));
  });

  it('lets the host add a CPU, change the level and the settings, and the timers', async () => {
    const result = await host.call<{ seats: Seat[] }>('updateLobby', {
      matchId,
      seats: [{ kind: 'human', uid: host.uid }, { kind: 'human' }, { kind: 'cpu', level: 4 }],
      settings: { rounds: 7, teams: [] },
      timers: { liveSec: 0, asyncHours: 48, asyncTimeout: 'end' },
    });
    assert.equal(result.seats.length, 3);
    const meta = await metaOf(matchId);
    assert.deepEqual(meta.seats[2], { kind: 'cpu', level: 4, name: 'CPU 3' });
    assert.equal(meta.settings.num_tanks, 3);
    assert.equal(meta.settings.rounds, 7);
    assert.deepEqual(meta.settings.controllers, [0, 0, 4]);
    assert.deepEqual(meta.timers, { liveSec: 0, asyncHours: 48, asyncTimeout: 'end' });
  });

  it('changes only what was sent: other settings stay', async () => {
    await host.call('updateLobby', { matchId, settings: { wind_max: 20 } });
    const settings = (await metaOf(matchId)).settings;
    assert.equal(settings.wind_max, 20);
    assert.equal(settings.rounds, 2);
  });

  it('carries seats players already hold, wherever the host moves them, and refuses to drop one', async () => {
    const ben = await newUser({ name: 'Ben' });
    await ben.call('joinMatch', { code });
    await host.call('updateLobby', {
      matchId,
      seats: [{ kind: 'cpu', level: 2 }, { kind: 'human', uid: ben.uid }, { kind: 'human', uid: host.uid }],
    });
    const seats = await seatsOf(matchId);
    assert.equal(seats[1]?.uid, ben.uid);
    assert.equal(seats[1]?.name, 'Ben');
    assert.equal(seats[2]?.uid, host.uid);
    await assert.rejects(
      host.call('updateLobby', { matchId, seats: [{ kind: 'human', uid: host.uid }, { kind: 'cpu' }, { kind: 'cpu' }] }),
      reason('FAILED_PRECONDITION', 'seat_taken'),
    );
    await assert.rejects(
      host.call('updateLobby', { matchId, seats: [{ kind: 'human', uid: host.uid }, { kind: 'human', uid: 'someoneelse' }] }),
      reason('FAILED_PRECONDITION', 'unknown_seat_holder'),
    );
  });

  it('lets the host claim an extra seat for the shared phone', async () => {
    await host.call('updateLobby', { matchId, seats: [{ kind: 'human', uid: host.uid }, { kind: 'human', mine: true, name: 'Zed' }] });
    const seats = await seatsOf(matchId);
    assert.deepEqual([seats[1]?.uid, seats[1]?.name], [host.uid, 'Zed']);
  });

  it('refuses everyone but the host, and a lobby that already started', async () => {
    const ben = await newUser();
    await ben.call('joinMatch', { code });
    await assert.rejects(ben.call('updateLobby', { matchId, settings: { rounds: 3 } }), reason('PERMISSION_DENIED', 'not_host'));
    await host.call('startMatch', { matchId });
    await assert.rejects(host.call('updateLobby', { matchId, settings: { rounds: 3 } }), reason('FAILED_PRECONDITION', 'not_in_lobby'));
  });

  it('refuses settings that do not fit the seats, and unknown matches', async () => {
    await assert.rejects(host.call('updateLobby', { matchId, settings: { teams: [0, 1, 1] } }), status('INVALID_ARGUMENT'));
    await assert.rejects(host.call('updateLobby', { matchId, settings: { rounds: 99 } }), status('INVALID_ARGUMENT'));
    await assert.rejects(host.call('updateLobby', { matchId: 'nope12345' }), status('NOT_FOUND'));
    await assert.rejects(host.call('updateLobby', {}), status('INVALID_ARGUMENT'));
  });
});

describe('functions: leaveMatch', () => {
  it('frees a joiner\'s seat in a lobby and removes their entry', async () => {
    const host = await newUser({ full: true });
    const { matchId, code } = await hostLobby(host);
    const ben = await newUser();
    await ben.call('joinMatch', { code });
    assert.deepEqual(await ben.call('leaveMatch', { matchId }), { status: 'left' });
    assert.deepEqual((await seatsOf(matchId))[1], { kind: 'human' });
    assert.equal(await value(`userMatches/${ben.uid}/${matchId}`), null);
    // The seat can be taken again.
    await (await newUser()).call('joinMatch', { code });
  });

  it('abandons the lobby when the host leaves it: the code stops working and members see "abandoned"', async () => {
    const host = await newUser({ full: true });
    const { matchId, code } = await hostLobby(host);
    const ben = await newUser();
    await ben.call('joinMatch', { code });
    assert.deepEqual(await host.call('leaveMatch', { matchId }), { status: 'abandoned' });
    assert.equal((await metaOf(matchId)).status, 'abandoned');
    assert.equal(await value(`matchCodes/${code}`), null);
    assert.equal(await value(`userMatches/${ben.uid}/${matchId}/status`), 'abandoned');
    await assert.rejects((await newUser()).call('joinMatch', { code }), reason('NOT_FOUND', 'unknown_code'));
  });

  it('hands a leaver\'s seats to CPU Normal in a running match, and asks for a resolve if it was their turn', async () => {
    const host = await newUser({ full: true, name: 'Hana' });
    const { matchId, code } = await hostLobby(host);
    const ben = await newUser({ name: 'Ben' });
    await ben.call('joinMatch', { code });
    await host.call('startMatch', { matchId });
    await db.ref(`matches/${matchId}/meta/turn`).set({ tank: 1, uid: ben.uid, deadline: Date.now() + 3600000, index: 1 });
    assert.deepEqual(await ben.call('leaveMatch', { matchId }), { status: 'playing' });
    const meta = await metaOf(matchId);
    assert.deepEqual(meta.seats[1], { kind: 'cpu', level: 2, name: 'Ben' });
    assert.deepEqual(meta.turn, { tank: -1, uid: 'any', deadline: 0, index: 2 });
    assert.equal(meta.status, 'playing');
    assert.equal(await value(`userMatches/${ben.uid}/${matchId}`), null);
    assert.ok(await value(`userMatches/${host.uid}/${matchId}`), 'the remaining player still has the match');
  });

  it('also asks for a resolve in the shop, which the new CPU has not visited; other turns stay', async () => {
    const host = await newUser({ full: true });
    const { matchId, code } = await hostLobby(host);
    const ben = await newUser();
    await ben.call('joinMatch', { code });
    await host.call('startMatch', { matchId });
    await db.ref(`matches/${matchId}/meta/turn`).set({ tank: -2, uid: 'any', deadline: Date.now() + 3600000, index: 1 });
    await ben.call('leaveMatch', { matchId });
    assert.equal((await metaOf(matchId)).turn.tank, -1);

    const { matchId: m2, code: c2 } = await hostLobby(host);
    const cy = await newUser();
    await cy.call('joinMatch', { code: c2 });
    await host.call('startMatch', { matchId: m2 });
    await db.ref(`matches/${m2}/meta/turn`).set({ tank: 0, uid: host.uid, deadline: Date.now() + 3600000, index: 1 });
    await cy.call('leaveMatch', { matchId: m2 });
    assert.equal((await metaOf(m2)).turn.tank, 0, 'the host\'s turn is untouched');
  });

  it('abandons a running match when the last human leaves', async () => {
    const host = await newUser({ full: true });
    const { matchId, code } = await hostLobby(host);
    const ben = await newUser();
    await ben.call('joinMatch', { code });
    await host.call('startMatch', { matchId });
    await ben.call('leaveMatch', { matchId });
    assert.deepEqual(await host.call('leaveMatch', { matchId }), { status: 'abandoned' });
    assert.equal((await metaOf(matchId)).status, 'abandoned');
    assert.equal(await value(`matchCodes/${code}`), null);
  });

  it('just removes the list entry for a finished match, and refuses non-members', async () => {
    const host = await newUser({ full: true });
    const { matchId } = await hostLobby(host);
    await host.call('leaveMatch', { matchId }); // abandoned
    assert.equal(await value(`userMatches/${host.uid}/${matchId}`), null);
    await assert.rejects(host.call('leaveMatch', { matchId }), reason('NOT_FOUND', 'not_a_member'));
    await assert.rejects((await newUser()).call('leaveMatch', { matchId }), reason('NOT_FOUND', 'not_a_member'));
    await assert.rejects(host.call('leaveMatch', {}), status('INVALID_ARGUMENT'));
  });

  it('clears a list entry whose match no longer exists', async () => {
    const user = await newUser();
    await db.ref(`userMatches/${user.uid}/gone12345`).set({ updated: 1, yourTurn: false, status: 'over' });
    assert.deepEqual(await user.call('leaveMatch', { matchId: 'gone12345' }), { status: 'abandoned' });
    assert.equal(await value(`userMatches/${user.uid}/gone12345`), null);
  });
});

describe('functions: startMatch', () => {
  it('starts a full lobby: playing, a seed, "needs resolve" as the first turn, every member updated', async () => {
    const host = await newUser({ full: true });
    const { matchId, code } = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human' }, { kind: 'cpu' }]);
    const ben = await newUser();
    await ben.call('joinMatch', { code });
    const { seed } = await host.call<{ seed: number }>('startMatch', { matchId });
    assert.ok(Number.isInteger(seed) && seed >= 1 && seed <= 0x7ffffffe);
    const meta = await metaOf(matchId);
    assert.equal(meta.status, 'playing');
    assert.equal(meta.seed, seed);
    assert.equal(meta.settings.seed, seed);
    assert.deepEqual(meta.turn, { tank: -1, uid: 'any', deadline: 0, index: 0 });
    assert.equal(meta.actionCount, 0);
    assert.equal(typeof meta.started, 'number');
    for (const user of [host, ben]) {
      const entry = await value<Record<string, unknown>>(`userMatches/${user.uid}/${matchId}`);
      assert.equal(entry?.status, 'playing');
    }
    assert.equal(await value(`matchCodes/${code}`), matchId, 'the code lives until the match ends');
  });

  it('picks a different seed for each match', async () => {
    const host = await newUser({ full: true });
    const seeds = new Set<number>();
    for (let i = 0; i < 3; i += 1) {
      const { matchId } = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'cpu' }]);
      seeds.add((await host.call<{ seed: number }>('startMatch', { matchId })).seed);
    }
    assert.equal(seeds.size, 3);
  });

  it('refuses while a human seat is still empty, for non-hosts, and twice', async () => {
    const host = await newUser({ full: true });
    const { matchId, code } = await hostLobby(host);
    await assert.rejects(host.call('startMatch', { matchId }), reason('FAILED_PRECONDITION', 'seats_not_filled'));
    const ben = await newUser();
    await ben.call('joinMatch', { code });
    await assert.rejects(ben.call('startMatch', { matchId }), reason('PERMISSION_DENIED', 'not_host'));
    await assert.rejects((await newUser()).call('startMatch', { matchId }), reason('PERMISSION_DENIED', 'not_host'));
    await host.call('startMatch', { matchId });
    await assert.rejects(host.call('startMatch', { matchId }), reason('FAILED_PRECONDITION', 'not_in_lobby'));
    await assert.rejects(host.call('startMatch', { matchId: 'nope12345' }), status('NOT_FOUND'));
  });
});

describe('functions: invite', () => {
  let host: TestUser;
  let ben: TestUser;
  let matchId: string;
  let code: string;
  beforeEach(async () => {
    host = await newUser({ full: true, name: 'Hana' });
    ben = await newUser({ name: 'Ben' });
    await befriend(host, ben);
    ({ matchId, code } = await hostLobby(host));
  });

  it('puts an invite (with the join code and the mode) in the friend\'s inbox, and notifies them', async () => {
    await ben.registerPushToken();
    await host.call('invite', { friendUid: ben.uid, matchId });
    const invite = await value<Record<string, unknown>>(`invites/${ben.uid}/${matchId}`);
    assert.equal(invite?.fromUid, host.uid);
    assert.equal(invite?.fromName, 'Hana');
    assert.equal(invite?.code, code);
    assert.equal(invite?.mode, 0);
    assert.equal(typeof invite?.at, 'number');
    assert.equal(await value(`invitesSent/${host.uid}/${matchId}/${ben.uid}`), true);
    await eventually(async () => (await fcmFor(ben.uid)).length === 1, 'invite push');
    const [push] = await fcmFor(ben.uid);
    assert.equal(push?.body, 'Hana invited you to a match');
    assert.deepEqual(push?.data, { type: 'invite', matchId });
  });

  it('marks Love Edition invites with their mode', async () => {
    const { matchId: loveId } = await host.call<{ matchId: string }>('createMatch', { seats: [{ kind: 'human', mine: true }, { kind: 'human' }], settings: { mode: 1 } });
    await host.call('invite', { friendUid: ben.uid, matchId: loveId });
    assert.equal(await value(`invites/${ben.uid}/${loveId}/mode`), 1);
  });

  it('lets a joined friend invite others too', async () => {
    const cy = await newUser();
    await befriend(ben, cy);
    await ben.call('joinMatch', { code });
    await ben.call('invite', { friendUid: cy.uid, matchId });
    assert.equal(await value(`invites/${cy.uid}/${matchId}/fromUid`), ben.uid);
  });

  it('refuses a non-friend, a blocked friend (either way), a non-member and yourself', async () => {
    const stranger = await newUser();
    await assert.rejects(host.call('invite', { friendUid: stranger.uid, matchId }), reason('PERMISSION_DENIED', 'not_friends'));
    await assert.rejects(stranger.call('invite', { friendUid: ben.uid, matchId }), reason('PERMISSION_DENIED', 'not_a_member'));
    await assert.rejects(host.call('invite', { friendUid: host.uid, matchId }), reason('FAILED_PRECONDITION', 'self'));
    // A block removes the friendship, so a stale friend entry is not enough either.
    await db.ref(`blocks/${ben.uid}/${host.uid}`).set(true);
    await assert.rejects(host.call('invite', { friendUid: ben.uid, matchId }), reason('PERMISSION_DENIED', 'not_friends'));
    await db.ref(`blocks/${ben.uid}/${host.uid}`).remove();
    await db.ref(`blocks/${host.uid}/${ben.uid}`).set(true);
    await assert.rejects(host.call('invite', { friendUid: ben.uid, matchId }), reason('PERMISSION_DENIED', 'not_friends'));
    assert.equal(await value(`invites/${ben.uid}/${matchId}`), null);
  });

  it('refuses someone already seated, and a match that is not a lobby any more', async () => {
    await ben.call('joinMatch', { code });
    await assert.rejects(host.call('invite', { friendUid: ben.uid, matchId }), reason('ALREADY_EXISTS', 'already_in_match'));
    const cy = await newUser();
    await befriend(host, cy);
    await host.call('startMatch', { matchId });
    await assert.rejects(host.call('invite', { friendUid: cy.uid, matchId }), reason('FAILED_PRECONDITION', 'not_in_lobby'));
    await assert.rejects(host.call('invite', { friendUid: cy.uid, matchId: 'nope12345' }), status('PERMISSION_DENIED'));
  });

  it('sends no push when the friend has no token', async () => {
    await host.call('invite', { friendUid: ben.uid, matchId });
    await settle();
    assert.equal((await fcmFor(ben.uid)).length, 0);
  });
});
