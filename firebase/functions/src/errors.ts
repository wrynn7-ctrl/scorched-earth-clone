// Argument parsing and the error vocabulary. Every error a client can act on carries a short snake_case reason as its
// message (for example "protocol_mismatch"); the code is the standard HttpsError code.
import { HttpsError } from 'firebase-functions/v2/https';

export type Fields = Record<string, unknown>;

export function fail(code: ConstructorParameters<typeof HttpsError>[0], reason: string, details?: unknown): never {
  throw new HttpsError(code, reason, details);
}

export function asObject(value: unknown, what = 'data'): Fields {
  if (value === undefined || value === null) return {};
  if (typeof value !== 'object' || Array.isArray(value)) return fail('invalid-argument', `${what}_not_an_object`);
  return value as Fields;
}

export function reqString(data: Fields, key: string, maxLength = 128): string {
  const value = data[key];
  if (typeof value !== 'string' || value.length === 0 || value.length > maxLength) fail('invalid-argument', `bad_${key}`);
  return value;
}

export function optString(data: Fields, key: string, maxLength = 128): string | undefined {
  return data[key] === undefined ? undefined : reqString(data, key, maxLength);
}

/**
 * Shortest and longest id (a uid or a match id) a callable accepts. Real ids are 20 (push ids) to 28 (Auth uids) characters,
 * so these bounds only keep junk out.
 */
export const ID_MIN_LENGTH = 8;
export const ID_MAX_LENGTH = 128;

/**
 * True for an id that is safe inside a database path: letters, digits, `-` and `_` only (no slashes or dots, so a client can
 * never address another path), the right length, and no leading `__`. The Admin SDK keeps its path tree in a plain object, so
 * `matches/__proto__/meta` is not an ordinary key there and a transaction on it never finishes (a 60 s hang per call).
 */
export function isSafeId(value: unknown, minLength = ID_MIN_LENGTH): value is string {
  return (
    typeof value === 'string' &&
    value.length >= minLength &&
    value.length <= ID_MAX_LENGTH &&
    !value.startsWith('__') &&
    /^[A-Za-z0-9_-]+$/.test(value)
  );
}

/** A uid or id used inside a database path (see isSafeId). */
export function reqId(data: Fields, key: string): string {
  const value = data[key];
  if (!isSafeId(value)) fail('invalid-argument', `bad_${key}`);
  return value;
}

export function isInt(value: unknown, lo: number, hi: number): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value >= lo && value <= hi;
}

export function optInt(data: Fields, key: string, lo: number, hi: number): number | undefined {
  const value = data[key];
  if (value === undefined) return undefined;
  if (!isInt(value, lo, hi)) fail('invalid-argument', `bad_${key}`);
  return value;
}

export function reqBool(data: Fields, key: string): boolean {
  const value = data[key];
  if (typeof value !== 'boolean') fail('invalid-argument', `bad_${key}`);
  return value;
}
