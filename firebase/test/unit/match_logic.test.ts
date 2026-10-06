// Pure match logic: settings, seats, timers, teams (no emulator needed).
import assert from 'node:assert/strict';
import { buildNewSeats, buildSettings, freeSeatIndexes, mergeLobbySeats, parseSeatSpecs, parseTimers, seatName, teamsError } from '../../functions/src/match_logic';
import type { Seat } from '../../functions/src/rtdb';

const code = (fn: () => unknown): string | undefined => {
  try {
    fn();
  } catch (error) {
    const e = error as { code?: string; message?: string };
    return e.code ? `${e.code}:${e.message ?? ''}` : 'other';
  }
  return undefined;
};

const humans = (n: number): Seat[] => Array.from({ length: n }, () => ({ kind: 'human' as const, uid: 'u' }));

describe('match logic: teams', () => {
  it('mirrors the core rule: empty, or n entries 0..3 with at least two distinct values', () => {
    assert.equal(teamsError([], 4), '');
    assert.equal(teamsError([0, 1, 0, 1], 4), '');
    assert.equal(teamsError([0, 3], 2), '');
    assert.equal(teamsError([0, 0], 2), 'invalid_settings');
    assert.equal(teamsError([0, 1, 2], 4), 'invalid_settings');
    assert.equal(teamsError([0, 4], 2), 'invalid_settings');
    assert.equal(teamsError([-1, 0], 2), 'invalid_settings');
    assert.equal(teamsError([0, 1.5], 2), 'invalid_settings');
    assert.equal(teamsError(['a', 'b'], 2), 'invalid_settings');
  });
});

describe('match logic: timers', () => {
  it('defaults and accepts the documented ranges', () => {
    assert.deepEqual(parseTimers(undefined), { liveSec: 60, asyncHours: 72, asyncTimeout: 'auto' });
    assert.deepEqual(parseTimers({ liveSec: 0, asyncHours: 1, asyncTimeout: 'end' }), { liveSec: 0, asyncHours: 1, asyncTimeout: 'end' });
    assert.deepEqual(parseTimers({ liveSec: 600, asyncHours: 168 }), { liveSec: 600, asyncHours: 168, asyncTimeout: 'auto' });
  });

  it('rejects everything else', () => {
    for (const bad of [{ liveSec: 9 }, { liveSec: 601 }, { liveSec: 1.5 }, { asyncHours: 0 }, { asyncHours: 169 }, { asyncTimeout: 'x' }, 'text', [1]]) {
      assert.match(code(() => parseTimers(bad)) ?? '', /^invalid-argument/, JSON.stringify(bad));
    }
  });
});

describe('match logic: seats', () => {
  it('parses specs and defaults the CPU level to Normal', () => {
    const specs = parseSeatSpecs([{ kind: 'human', mine: true }, { kind: 'cpu' }, { kind: 'cpu', level: 4 }]);
    assert.deepEqual(specs.map((s) => [s.kind, s.level, s.mine]), [['human', 0, true], ['cpu', 2, false], ['cpu', 4, false]]);
  });

  it('rejects bad lists', () => {
    for (const bad of [[], [{ kind: 'human' }], 'x', [{ kind: 'human' }, { kind: 'bot' }], [{ kind: 'cpu', level: 9 }, { kind: 'human' }]]) {
      assert.match(code(() => parseSeatSpecs(bad)) ?? '', /^invalid-argument/, JSON.stringify(bad));
    }
  });

  it('builds new seats with the host in the marked ones and numbered names', () => {
    const seats = buildNewSeats(parseSeatSpecs([{ kind: 'human', mine: true }, { kind: 'human' }, { kind: 'human', mine: true }, { kind: 'cpu' }]), 'host', 'HANA');
    assert.deepEqual(seats[0], { kind: 'human', uid: 'host', name: 'HANA' });
    assert.deepEqual(seats[1], { kind: 'human' });
    assert.deepEqual(seats[2], { kind: 'human', uid: 'host', name: 'HANA 2' });
    assert.deepEqual(seats[3], { kind: 'cpu', level: 2, name: 'CPU 4' });
  });

  it('shortens a long host name so the numbered name still fits 12 characters', () => {
    const seats = buildNewSeats(parseSeatSpecs([{ kind: 'human', mine: true }, { kind: 'human', mine: true }]), 'host', 'ABCDEFGHIJKL');
    assert.equal(seats[1]?.name, 'ABCDEFGHIJ 2');
    assert.equal(seats[1]?.name?.length, 12);
  });

  it('refuses a lobby with no human seat', () => {
    assert.match(code(() => buildNewSeats(parseSeatSpecs([{ kind: 'cpu' }, { kind: 'cpu' }]), 'h', 'H')) ?? '', /no_human_seat/);
  });

  it('falls back when a typed seat name is blocked or empty', () => {
    assert.equal(seatName('Zed', 'X'), 'Zed');
    assert.equal(seatName('  Zed  ', 'X'), 'Zed');
    assert.equal(seatName('f u c k', 'X'), 'X');
    assert.equal(seatName('', 'X'), 'X');
    assert.equal(seatName(undefined, 'X'), 'X');
  });

  it('lists free human seats', () => {
    assert.deepEqual(freeSeatIndexes([{ kind: 'human', uid: 'a' }, { kind: 'human' }, { kind: 'cpu' }, { kind: 'human' }]), [1, 3]);
  });

  it('merges lobby edits: held seats carry over in any order, a dropped holder is an error', () => {
    const existing: Seat[] = [{ kind: 'human', uid: 'host', name: 'H' }, { kind: 'human', uid: 'ben', name: 'B' }, { kind: 'human' }];
    const merged = mergeLobbySeats(existing, parseSeatSpecs([{ kind: 'cpu' }, { kind: 'human', uid: 'ben' }, { kind: 'human', uid: 'host' }]), 'host', 'H');
    assert.deepEqual(merged.map((s) => s.uid), [undefined, 'ben', 'host']);
    assert.match(code(() => mergeLobbySeats(existing, parseSeatSpecs([{ kind: 'human', uid: 'host' }, { kind: 'cpu' }]), 'host', 'H')) ?? '', /seat_taken/);
    assert.match(code(() => mergeLobbySeats(existing, parseSeatSpecs([{ kind: 'human', uid: 'host' }, { kind: 'human', uid: 'zed' }]), 'host', 'H')) ?? '', /unknown_seat_holder/);
  });
});

describe('match logic: settings', () => {
  it('builds canonical settings: known keys only, controllers from the seats, seed 0', () => {
    const seats: Seat[] = [{ kind: 'human', uid: 'a' }, { kind: 'cpu', level: 3 }, { kind: 'human' }];
    const settings = buildSettings({ rounds: 5, mystery: 'x', controllers: [4, 4, 4], seed: 99, full_unlocked: false }, seats);
    assert.deepEqual(settings, {
      seed: 0,
      num_tanks: 3,
      rounds: 5,
      wind_max: 100,
      start_money: 10000,
      full_unlocked: true,
      controllers: [0, 3, 0],
      mode: 0,
      friendly_fire: true,
    });
  });

  it('rejects out-of-range values with a reason a client can show', () => {
    const seats = humans(2);
    const cases: [Record<string, unknown>, string][] = [
      [{ rounds: 0 }, 'bad_rounds'],
      [{ rounds: 21 }, 'bad_rounds'],
      [{ wind_max: -1 }, 'bad_wind_max'],
      [{ start_money: 1_000_001 }, 'bad_start_money'],
      [{ mode: 5 }, 'bad_mode'],
      [{ friendly_fire: 1 }, 'bad_friendly_fire'],
      [{ teams: 'x' }, 'bad_teams'],
      [{ teams: [0, 0] }, 'bad_teams'],
      [{ theme: 'A B' }, 'bad_theme'],
      [{ num_tanks: 4 }, 'num_tanks_mismatch'],
    ];
    for (const [input, reasonText] of cases) assert.match(code(() => buildSettings(input, seats)) ?? '', new RegExp(reasonText), JSON.stringify(input));
  });

  it('normalises Love Edition and refuses a love lobby that is not a duel of two humans', () => {
    const settings = buildSettings({ mode: 1, rounds: 9, wind_max: 80, start_money: 500 }, humans(2));
    assert.deepEqual([settings.rounds, settings.wind_max, settings.start_money, settings.mode], [1, 30, 0, 1]);
    assert.match(code(() => buildSettings({ mode: 1 }, humans(3))) ?? '', /love_needs_two_humans/);
    assert.match(code(() => buildSettings({ mode: 1 }, [...humans(1), { kind: 'cpu' }])) ?? '', /love_needs_two_humans/);
    assert.match(code(() => buildSettings({ mode: 1, teams: [0, 1] }, humans(2))) ?? '', /love_has_no_teams/);
  });

  it('keeps valid teams and drops an empty team list', () => {
    assert.deepEqual(buildSettings({ teams: [0, 1] }, humans(2)).teams, [0, 1]);
    assert.equal('teams' in buildSettings({ teams: [] }, humans(2)), false);
  });
});
