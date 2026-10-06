// Friend codes (8 characters) and match codes (6 characters) from an alphabet without look-alike characters.
import { randomInt } from 'node:crypto';
import type { Database } from 'firebase-admin/database';
import { CODE_ALPHABET } from './config';

export type RandomInt = (maxExclusive: number) => number;
const cryptoInt: RandomInt = (max) => randomInt(max);

export function makeCode(length: number, rand: RandomInt = cryptoInt): string {
  let out = '';
  for (let i = 0; i < length; i += 1) out += CODE_ALPHABET.charAt(rand(CODE_ALPHABET.length));
  return out;
}

/** Upper-cases and trims a code typed by a player; returns null when it cannot be a code of that length. */
export function normalizeCode(raw: unknown, length: number): string | null {
  if (typeof raw !== 'string') return null;
  const code = raw.trim().toUpperCase();
  if (code.length !== length) return null;
  for (const ch of code) {
    if (!CODE_ALPHABET.includes(ch)) return null;
  }
  return code;
}

/**
 * Claims a free code: writes `value` at `${basePath}/${code}` with a transaction so two callers can never get the same
 * code. Returns null after `attempts` collisions (practically never: 32^6 is a billion).
 */
export async function allocateCode(
  db: Database,
  basePath: string,
  length: number,
  value: string,
  rand: RandomInt = cryptoInt,
  attempts = 12,
): Promise<string | null> {
  for (let i = 0; i < attempts; i += 1) {
    const code = makeCode(length, rand);
    const result = await db.ref(`${basePath}/${code}`).transaction((current: unknown) => (current === null ? value : undefined));
    if (result.committed) return code;
  }
  return null;
}
