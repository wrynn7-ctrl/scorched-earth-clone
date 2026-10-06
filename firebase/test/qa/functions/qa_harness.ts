// Helpers for the M7-Q functions tests, on top of test/functions/harness.ts. Every helper cleans up only what it made.
import { createHash } from 'node:crypto';
import { CallError, db, newUser, type TestUser } from '../../functions/harness';

export { CallError, db, newUser };
export type { TestUser };

export const DB_HOST = process.env.FIREBASE_DATABASE_EMULATOR_HOST ?? '127.0.0.1:9000';
export const NAMESPACE = 'demo-craterline-default-rtdb';
const FUNCTIONS_HOST = process.env.FUNCTIONS_EMULATOR_HOST ?? '127.0.0.1:5001';

export const sleep = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

/** A client write or read through the database REST API with a real ID token (the rules apply). */
export async function rest(token: string | null, method: 'GET' | 'PUT' | 'PATCH' | 'DELETE', path: string, body?: unknown): Promise<{ status: number; json: unknown }> {
  const auth = token ? `&auth=${encodeURIComponent(token)}` : '';
  const response = await fetch(`http://${DB_HOST}/${path}.json?ns=${NAMESPACE}${auth}`, {
    method,
    headers: { 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    json = text;
  }
  return { status: response.status, json };
}

/** A callable invoked with an arbitrary raw body (the standard harness always wraps `{data}`). */
export async function rawCall(name: string, rawBody: string, token: string | null, contentType = 'application/json'): Promise<{ status: number; text: string }> {
  const headers: Record<string, string> = { 'content-type': contentType };
  if (token) headers.authorization = `Bearer ${token}`;
  const response = await fetch(`http://${FUNCTIONS_HOST}/demo-craterline/europe-west1/${name}`, { method: 'POST', headers, body: rawBody });
  return { status: response.status, text: await response.text() };
}

const b64 = (value: unknown): string => Buffer.from(JSON.stringify(value)).toString('base64url');

/** An unsigned ("alg: none") token such as the emulators themselves hand out; a real project refuses it. */
export function unsignedToken(uid: string, extra: Record<string, unknown> = {}): string {
  const now = Math.floor(Date.now() / 1000);
  const payload = { iss: 'https://securetoken.google.com/demo-craterline', aud: 'demo-craterline', auth_time: now, user_id: uid, sub: uid, iat: now, exp: now + 3600, firebase: { identities: {}, sign_in_provider: 'anonymous' }, ...extra };
  return `${b64({ alg: 'none', typ: 'JWT' })}.${b64(payload)}.`;
}

/** The status of a failed call, or 'OK' when it worked, or 'TRANSPORT:<message>' for anything that is not a clean callable answer. */
export async function outcome(promise: Promise<unknown>): Promise<string> {
  try {
    await promise;
    return 'OK';
  } catch (error) {
    if (error instanceof CallError) return error.status;
    return `TRANSPORT:${String((error as Error).message).slice(0, 80)}`;
  }
}

export async function reasonOf(promise: Promise<unknown>): Promise<string> {
  try {
    await promise;
    return 'OK';
  } catch (error) {
    if (error instanceof CallError) return `${error.status}:${error.reason}`;
    return `TRANSPORT:${String((error as Error).message).slice(0, 80)}`;
  }
}

export const TEST_TOKEN_HASH = createHash('sha256').update('test-full').digest('hex');

/** Frees the shared emulator test purchase token, but only if `user` is the one holding it. */
export async function releaseTestToken(user: TestUser): Promise<void> {
  const snap = await db.ref(`purchaseTokens/${TEST_TOKEN_HASH}`).get();
  if (snap.val() === user.uid) await db.ref(`purchaseTokens/${TEST_TOKEN_HASH}`).remove();
}

/** Runs `make` for 0..count-1, at most `limit` at a time (the functions emulator chokes on bursts of more than a few dozen calls). */
export async function inParallel<T>(count: number, make: (index: number) => Promise<T>, limit = 10): Promise<T[]> {
  const out: T[] = [];
  for (let start = 0; start < count; start += limit) {
    const chunk = Array.from({ length: Math.min(limit, count - start) }, (_unused, k) => make(start + k));
    out.push(...(await Promise.all(chunk)));
  }
  return out;
}
