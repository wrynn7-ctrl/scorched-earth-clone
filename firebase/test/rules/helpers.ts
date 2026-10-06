// Shared fixtures for the Realtime Database rules tests. Every test starts from an empty database and seeds it with
// security rules switched off (that is the "server" side), then acts as a signed-in client.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { setLogLevel } from 'firebase/app';
import { ref, serverTimestamp, set, update, type Database } from 'firebase/database';

export { assertFails, assertSucceeds, ref, serverTimestamp, set, update };
export type { Database };

export const MID = 'M1';
export const HOUR = 3600 * 1000;

setLogLevel('silent');

let env: RulesTestEnvironment | undefined;

export async function startEnv(): Promise<RulesTestEnvironment> {
  env = await initializeTestEnvironment({
    projectId: 'demo-craterline',
    database: { rules: readFileSync(join(__dirname, '..', '..', 'database.rules.json'), 'utf8') },
  });
  return env;
}

export async function stopEnv(): Promise<void> {
  await env?.cleanup();
  env = undefined;
}

export function testEnv(): RulesTestEnvironment {
  if (!env) throw new Error('rules test environment not started');
  return env;
}

/** The database as a signed-in user. */
export function as(uid: string): Database {
  return testEnv().authenticatedContext(uid).database();
}

/** The database with no sign-in. */
export function anonymous(): Database {
  return testEnv().unauthenticatedContext().database();
}

/** Write seed data as the server (rules off). */
export async function seed(values: Record<string, unknown>): Promise<void> {
  await testEnv().withSecurityRulesDisabled(async (context) => {
    await update(ref(context.database()), values);
  });
}

export async function resetDb(): Promise<void> {
  await testEnv().clearDatabase();
}

export interface Seat {
  kind: 'human' | 'cpu';
  uid?: string;
  name?: string;
  level?: number;
}

export interface TurnState {
  tank: number;
  uid: string;
  deadline: number;
  liveDeadline?: number;
  index: number;
}

export interface MatchSeed {
  status?: string;
  seats?: Seat[];
  turn?: TurnState;
  actionCount?: number;
  timers?: { liveSec: number; asyncHours: number; asyncTimeout: string };
  members?: string[];
  presence?: Record<string, number>;
}

/** Users: host (full), bob, cat. Match M1 with seats 0 host, 1 bob, 2 CPU, 3 host (shared phone). */
export const DEFAULT_SEATS: Seat[] = [
  { kind: 'human', uid: 'host', name: 'HOST' },
  { kind: 'human', uid: 'bob', name: 'BOB' },
  { kind: 'cpu', level: 2, name: 'CPU' },
  { kind: 'human', uid: 'host', name: 'HOST 2' },
];

export function turnFor(tank: number, uid: string, index = 3, extra: Partial<TurnState> = {}): TurnState {
  return { tank, uid, deadline: Date.now() + HOUR, index, ...extra };
}

export async function seedUsers(): Promise<void> {
  const users: Record<string, unknown> = {};
  for (const [uid, code, full] of [
    ['host', 'HOSTCODE', true],
    ['bob', 'BOBCODE22', false],
    ['cat', 'CATCODE33', false],
  ] as const) {
    users[`users/${uid}`] = { name: uid.toUpperCase(), nameHidden: false, friendCode: code, created: 1, protocol: 1, full };
  }
  await seed(users);
}

export async function seedMatch(options: MatchSeed = {}): Promise<number> {
  const count = options.actionCount ?? 3;
  const values: Record<string, unknown> = {
    [`matches/${MID}/meta`]: {
      hostUid: 'host',
      code: 'ABC234',
      protocol: 1,
      created: 1,
      status: options.status ?? 'playing',
      settings: { seed: 7, num_tanks: 4, rounds: 3 },
      seed: 7,
      seats: options.seats ?? DEFAULT_SEATS,
      timers: options.timers ?? { liveSec: 60, asyncHours: 72, asyncTimeout: 'auto' },
      turn: options.turn ?? turnFor(0, 'host'),
      actionCount: count,
    },
  };
  for (let i = 0; i < count; i += 1) values[`matches/${MID}/actions/${i}`] = { kind: 'pass', tank: 0 };
  for (const uid of options.members ?? ['host', 'bob']) {
    values[`userMatches/${uid}/${MID}`] = { updated: 1, yourTurn: false, status: options.status ?? 'playing' };
  }
  for (const [uid, at] of Object.entries(options.presence ?? {})) values[`matches/${MID}/presence/${uid}`] = at;
  await seed(values);
  return count;
}

/** Sets up users and a running match, the starting point of most tests. */
export async function seedAll(options: MatchSeed = {}): Promise<number> {
  await seedUsers();
  return seedMatch(options);
}

/**
 * An update that appends `entries` to the log of M1 starting at `count` and bumps actionCount, optionally also
 * setting the turn. Extra paths can be merged in by the caller.
 */
export function append(count: number, entries: Record<string, unknown>[], turn?: TurnState): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  entries.forEach((entryValue, offset) => {
    out[`matches/${MID}/actions/${count + offset}`] = entryValue;
  });
  out[`matches/${MID}/meta/actionCount`] = count + entries.length;
  if (turn) out[`matches/${MID}/meta/turn`] = turn;
  return out;
}

export const fire = (tank: number): Record<string, unknown> => ({ kind: 'fire', tank, angle: 452, power: 610, weapon: 'pulse_missile' });
export const auto = (tank: number, level = 2): Record<string, unknown> => ({ kind: 'auto', tank, level });

/** Registers the mocha hooks every rules test file needs: one environment per file, an empty database per test. */
export function useRulesEnv(): void {
  before(async () => {
    await startEnv();
  });
  after(async () => {
    await stopEnv();
  });
  beforeEach(async () => {
    await resetDb();
  });
}
