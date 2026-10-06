// Pure validation and construction of match settings, seats and timers (ARCHITECTURE sections 23, 39, 45). No database
// access, so the unit tests exercise it directly. The ranges mirror MatchSettings in game/core/match_settings.gd.
import {
  CPU_LEVEL_MAX,
  CPU_LEVEL_MIN,
  CPU_LEVEL_NORMAL,
  LOVE_WIND_MAX,
  MAX_ROUNDS,
  MAX_START_MONEY,
  MAX_TANKS,
  MAX_TEAMS,
  MAX_WIND,
  MIN_TANKS,
  MODE_LOVE,
} from './config';
import { asObject, fail, isInt, type Fields } from './errors';
import { checkName } from './name_filter';
import type { Seat, Timers } from './rtdb';

export interface SeatSpec {
  kind: 'human' | 'cpu';
  level: number;
  /** Seat played from the host's own phone (createMatch / updateLobby). */
  mine: boolean;
  /** For a human seat in updateLobby: the uid already holding it (it must match the stored seat). */
  uid?: string;
  name?: string;
}

export const DEFAULT_TIMERS: Timers = { liveSec: 60, asyncHours: 72, asyncTimeout: 'auto' };

export function parseTimers(raw: unknown): Timers {
  const data = asObject(raw, 'timers');
  const liveSec = data.liveSec ?? DEFAULT_TIMERS.liveSec;
  const asyncHours = data.asyncHours ?? DEFAULT_TIMERS.asyncHours;
  const asyncTimeout = data.asyncTimeout ?? DEFAULT_TIMERS.asyncTimeout;
  // liveSec 0 turns the live skip off; otherwise 10 s .. 10 min.
  if (!(liveSec === 0 || isInt(liveSec, 10, 600))) return fail('invalid-argument', 'bad_liveSec');
  if (!isInt(asyncHours, 1, 168)) return fail('invalid-argument', 'bad_asyncHours');
  if (asyncTimeout !== 'auto' && asyncTimeout !== 'end') return fail('invalid-argument', 'bad_asyncTimeout');
  return { liveSec: liveSec as number, asyncHours, asyncTimeout };
}

export function parseSeatSpecs(raw: unknown): SeatSpec[] {
  if (!Array.isArray(raw) || raw.length < MIN_TANKS || raw.length > MAX_TANKS) return fail('invalid-argument', 'bad_seats');
  return (raw as unknown[]).map((item) => {
    const seat = asObject(item, 'seat');
    if (seat.kind !== 'human' && seat.kind !== 'cpu') return fail('invalid-argument', 'bad_seat_kind');
    const level = seat.level ?? CPU_LEVEL_NORMAL;
    if (seat.kind === 'cpu' && !isInt(level, CPU_LEVEL_MIN, CPU_LEVEL_MAX)) return fail('invalid-argument', 'bad_cpu_level');
    const name = typeof seat.name === 'string' && seat.name.length <= 64 ? seat.name : undefined;
    const uid = typeof seat.uid === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(seat.uid) ? seat.uid : undefined;
    return {
      kind: seat.kind,
      level: seat.kind === 'cpu' ? (level as number) : 0,
      mine: seat.mine === true,
      uid,
      name,
    };
  });
}

/** A seat name from player-typed text: cleaned and filtered, or `fallback`. */
export function seatName(raw: string | undefined, fallback: string): string {
  if (raw === undefined) return fallback;
  const verdict = checkName(raw);
  return verdict.name === 'PLAYER' && !verdict.accepted ? fallback : verdict.name;
}

/** Seats for a new lobby: the host's seats are filled, the other human seats wait for joinMatch. */
export function buildNewSeats(specs: SeatSpec[], hostUid: string, hostName: string): Seat[] {
  const humans = specs.filter((s) => s.kind === 'human');
  if (humans.length === 0) return fail('invalid-argument', 'no_human_seat');
  const marked = humans.some((s) => s.mine);
  let claimed = 0;
  return specs.map((spec, index) => {
    if (spec.kind === 'cpu') return cpuSeat(spec, index);
    const mine = marked ? spec.mine : spec === humans[0];
    if (!mine) return { kind: 'human' };
    claimed += 1;
    return { kind: 'human', uid: hostUid, name: seatName(spec.name, claimed === 1 ? hostName : numberedSeatName(hostName, claimed)) };
  });
}

function cpuSeat(spec: SeatSpec, index: number): Seat {
  return { kind: 'cpu', level: spec.level, name: seatName(spec.name, `CPU ${index + 1}`) };
}

/** "ANNA" -> "ANNA 2", shortened so the result still fits a name (12 characters). */
export function numberedSeatName(name: string, n: number): string {
  const suffix = ` ${n}`;
  return `${name.slice(0, 12 - suffix.length)}${suffix}`;
}

/**
 * The seats after the host edits a lobby. Seats held by a player (the spec names their uid) must be carried over
 * unchanged, in any position; everything else the host may change freely. Returns the new list.
 */
export function mergeLobbySeats(existing: readonly Seat[], specs: SeatSpec[], hostUid: string, hostName: string): Seat[] {
  const held = new Map<string, Seat[]>();
  for (const seat of existing) {
    if (seat.kind === 'human' && seat.uid) held.set(seat.uid, [...(held.get(seat.uid) ?? []), seat]);
  }
  const carried = new Map<string, number>();
  let hostExtra = existing.filter((s) => s.uid === hostUid).length;
  const out = specs.map((spec, index): Seat => {
    if (spec.kind === 'cpu') return cpuSeat(spec, index);
    if (spec.uid) {
      const used = carried.get(spec.uid) ?? 0;
      const seat = held.get(spec.uid)?.[used];
      if (!seat) return fail('failed-precondition', 'unknown_seat_holder');
      carried.set(spec.uid, used + 1);
      return { ...seat };
    }
    if (spec.mine) {
      hostExtra += 1;
      return { kind: 'human', uid: hostUid, name: seatName(spec.name, numberedSeatName(hostName, hostExtra)) };
    }
    return { kind: 'human' };
  });
  for (const [uid, seats] of held) {
    if ((carried.get(uid) ?? 0) < seats.length) return fail('failed-precondition', 'seat_taken', { uid });
  }
  return out;
}

/** The core's `teams_error`: "" when `teams` is empty or n entries 0..3 with at least two distinct values. */
export function teamsError(teams: readonly unknown[], n: number): string {
  if (teams.length === 0) return '';
  if (teams.length !== n) return 'invalid_settings';
  let seen = 0;
  for (const value of teams) {
    if (!isInt(value, 0, MAX_TEAMS - 1)) return 'invalid_settings';
    seen |= 1 << value;
  }
  return (seen & (seen - 1)) === 0 ? 'invalid_settings' : '';
}

/**
 * Canonical settings for a lobby. Only known keys are kept; `controllers` is derived from the seats (so it can never
 * disagree with them); love mode is normalised the way `MatchSettings.clamped` does (1 round, wind at most 30, no
 * money); everything else out of range is an error. `seed` stays 0 until startMatch picks the real one.
 */
export function buildSettings(raw: unknown, seats: readonly Seat[]): Record<string, unknown> {
  const data: Fields = asObject(raw, 'settings');
  const n = seats.length;
  if (data.num_tanks !== undefined && data.num_tanks !== n) return fail('invalid-argument', 'num_tanks_mismatch');
  const mode = data.mode ?? 0;
  if (mode !== 0 && mode !== MODE_LOVE) return fail('invalid-argument', 'bad_mode');
  const love = mode === MODE_LOVE;
  let rounds = data.rounds ?? 1;
  let windMax = data.wind_max ?? MAX_WIND;
  let money = data.start_money ?? 10000;
  if (!isInt(rounds, 1, MAX_ROUNDS)) return fail('invalid-argument', 'bad_rounds');
  if (!isInt(windMax, 0, MAX_WIND)) return fail('invalid-argument', 'bad_wind_max');
  if (!isInt(money, 0, MAX_START_MONEY)) return fail('invalid-argument', 'bad_start_money');
  const friendlyFire = data.friendly_fire ?? true;
  if (typeof friendlyFire !== 'boolean') return fail('invalid-argument', 'bad_friendly_fire');
  const teams = data.teams ?? [];
  if (!Array.isArray(teams)) return fail('invalid-argument', 'bad_teams');
  if (love) {
    if (n !== 2 || seats.some((s) => s.kind !== 'human')) return fail('invalid-argument', 'love_needs_two_humans');
    if (teams.length > 0) return fail('invalid-argument', 'love_has_no_teams');
    rounds = 1;
    windMax = Math.min(windMax, LOVE_WIND_MAX);
    money = 0;
  }
  if (teamsError(teams as unknown[], n) !== '') return fail('invalid-argument', 'bad_teams');
  const theme = data.theme;
  if (theme !== undefined && (typeof theme !== 'string' || !/^[a-z][a-z0-9_]{0,23}$/.test(theme))) {
    return fail('invalid-argument', 'bad_theme');
  }
  const settings: Record<string, unknown> = {
    seed: 0,
    num_tanks: n,
    rounds,
    wind_max: windMax,
    start_money: money,
    // The host is a full owner, so the whole match plays with the full rules (ARCHITECTURE section 45).
    full_unlocked: true,
    controllers: seats.map((s) => (s.kind === 'cpu' ? (s.level ?? CPU_LEVEL_NORMAL) : 0)),
    mode,
    friendly_fire: friendlyFire,
  };
  // An empty list is not stored by the database, so it is simply left out.
  if (teams.length > 0) settings.teams = teams;
  if (theme !== undefined) settings.theme = theme;
  return settings;
}

/** The human seats that still wait for a player. */
export function freeSeatIndexes(seats: readonly Seat[]): number[] {
  const out: number[] = [];
  seats.forEach((seat, index) => {
    if (seat.kind === 'human' && !seat.uid) out.push(index);
  });
  return out;
}
