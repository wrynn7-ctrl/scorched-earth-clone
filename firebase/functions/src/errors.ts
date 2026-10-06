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

/** A uid or id used inside a database path: no slashes or dots, so a client can never address another path. */
export function reqId(data: Fields, key: string): string {
  const value = reqString(data, key, 128);
  if (!/^[A-Za-z0-9_-]+$/.test(value)) fail('invalid-argument', `bad_${key}`);
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
