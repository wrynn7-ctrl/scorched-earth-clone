// Test harness for the functions tests: signs users into the Auth emulator, calls callables over HTTP exactly as the Godot
// client will, and reads or seeds the database with the Admin SDK (which bypasses rules).
import { createHash, randomUUID } from 'node:crypto';
import { getDb } from '../../functions/src/admin';
import type { Deps } from '../../functions/src/deps';
import { RecordingSender } from '../../functions/src/push';

export const PROJECT = 'demo-craterline';
export const REGION = 'europe-west1';
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:9099';
const FUNCTIONS_HOST = process.env.FUNCTIONS_EMULATOR_HOST ?? '127.0.0.1:5001';

export const db = getDb();

/** An error returned by a callable: the HTTP-style status name, the reason string and any details. */
export class CallError extends Error {
  constructor(
    readonly status: string,
    readonly reason: string,
    readonly details: unknown,
  ) {
    super(`${status}: ${reason}`);
  }
}

interface CallBody {
  result?: unknown;
  error?: { status?: string; message?: string; details?: unknown };
}

async function post(url: string, body: unknown, headers: Record<string, string> = {}): Promise<{ status: number; json: CallBody | null; text: string }> {
  const response = await fetch(url, { method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(body) });
  const text = await response.text();
  try {
    return { status: response.status, json: JSON.parse(text) as CallBody, text };
  } catch {
    return { status: response.status, json: null, text };
  }
}

/** Calls a callable function. Pass a token for a signed-in call, or null for an anonymous one. */
export async function callWith<T = Record<string, unknown>>(name: string, data: unknown, token: string | null): Promise<T> {
  const url = `http://${FUNCTIONS_HOST}/${PROJECT}/${REGION}/${name}`;
  const headers: Record<string, string> = token ? { authorization: `Bearer ${token}` } : {};
  let attempt = 0;
  for (;;) {
    const { status, json, text } = await post(url, { data }, headers);
    // The functions emulator can still be loading code the first time a function is used: it answers 404 with plain text,
    // unlike a function that ran and returned NOT_FOUND (JSON with an error).
    if (json === null) {
      if (status === 404 && attempt < 40) {
        attempt += 1;
        await sleep(250);
        continue;
      }
      throw new Error(`non-JSON answer from ${url} (${status}): ${text.slice(0, 200)}`);
    }
    if (json.error) throw new CallError(json.error.status ?? String(status), json.error.message ?? '', json.error.details);
    return json.result as T;
  }
}

export class TestUser {
  constructor(
    readonly uid: string,
    readonly token: string,
  ) {}

  call<T = Record<string, unknown>>(name: string, data: unknown = {}): Promise<T> {
    return callWith<T>(name, data, this.token);
  }

  /** The user's own profile, read as the server. */
  async profile(): Promise<Record<string, unknown>> {
    return ((await db.ref(`users/${this.uid}`).get()).val() ?? {}) as Record<string, unknown>;
  }

  /** Registers a fake push token, so the (mocked) sender has someone to "deliver" to. */
  async registerPushToken(): Promise<void> {
    const token = `fake-token-${this.uid}-${'x'.repeat(30)}`;
    const hash = createHash('sha256').update(token).digest('hex').slice(0, 32);
    await db.ref(`users/${this.uid}/fcm/${hash}`).set(token);
  }

  /** Marks the user as present (a fresh heartbeat) or stale in a match. */
  async setPresence(matchId: string, ageMs: number | null): Promise<void> {
    await db.ref(`matches/${matchId}/presence/${this.uid}`).set(ageMs === null ? null : Date.now() - ageMs);
  }
}

export async function signUp(): Promise<TestUser> {
  const url = `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`;
  const { json } = await post(url, { returnSecureToken: true });
  const body = (json ?? {}) as unknown as { idToken?: string; localId?: string };
  if (!body.idToken || !body.localId) throw new Error('auth emulator did not sign the user up');
  return new TestUser(body.localId, body.idToken);
}

export interface NewUserOptions {
  name?: string;
  full?: boolean;
  protocol?: number;
}

/** A signed-in user with a profile (and optionally a name, the full version, a different protocol). */
export async function newUser(options: NewUserOptions = {}): Promise<TestUser> {
  const user = await signUp();
  await user.call('ensureProfile', { protocol: options.protocol ?? 1 });
  if (options.full) await user.call('testSetFull', { uid: user.uid });
  if (options.name) {
    await db.ref(`users/${user.uid}/name`).set(options.name);
    await eventually(async () => (await user.profile()).name === options.name, `name ${options.name} stored`);
  }
  return user;
}

export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Polls until `check` is true (triggers run asynchronously in the emulator). */
export async function eventually(check: () => Promise<boolean>, what: string, timeoutMs = 10000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    if (await check()) return;
    if (Date.now() > deadline) throw new Error(`timed out waiting for: ${what}`);
    await sleep(100);
  }
}

/** Waits a moment and asserts something did NOT happen (used for "no push was sent"). */
export async function settle(ms = 1200): Promise<void> {
  await sleep(ms);
}

export async function value<T = unknown>(path: string): Promise<T | null> {
  const snap = await db.ref(path).get();
  return snap.exists() ? (snap.val() as T) : null;
}

export interface FcmRecord {
  uid: string;
  tokenCount: number;
  title: string;
  body: string;
  data: Record<string, string>;
  collapseKey: string | null;
  channelId: string;
  at: number;
}

/** What the mocked sender "sent" to a user (the emulator records it at _test/fcm). */
export async function fcmFor(uid: string): Promise<FcmRecord[]> {
  const snap = await db.ref('_test/fcm').orderByChild('uid').equalTo(uid).get();
  const out: FcmRecord[] = [];
  snap.forEach((child) => {
    out.push(child.val() as FcmRecord);
  });
  return out.sort((a, b) => a.at - b.at);
}

/** Deps for calling handlers directly (sweep tests): real database, a clock the test controls, the recording sender. */
export function directDeps(clock: { now: number }): Deps {
  const now = (): number => clock.now;
  return {
    db,
    auth: () => {
      throw new Error('auth not available in direct deps');
    },
    now,
    rand: (max) => Math.floor(Math.random() * max),
    sender: new RecordingSender(db, now),
  };
}

export const uniqueName = (prefix: string): string => `${prefix}${randomUUID().slice(0, 4)}`.slice(0, 12);

/** Hosts a lobby with the given extra seats; returns ids. `seats` default: host + one open seat. */
export async function hostLobby(
  host: TestUser,
  seats: Record<string, unknown>[] = [{ kind: 'human', mine: true }, { kind: 'human' }],
  extra: Record<string, unknown> = {},
): Promise<{ matchId: string; code: string }> {
  return host.call<{ matchId: string; code: string }>('createMatch', { settings: { rounds: 2 }, seats, ...extra });
}

/** Makes two users friends the way players do: a request by code, then an accept. */
export async function befriend(a: TestUser, b: TestUser): Promise<void> {
  await a.call('sendFriendRequest', { code: (await b.profile()).friendCode });
  await b.call('respondFriendRequest', { fromUid: a.uid, accept: true });
}
