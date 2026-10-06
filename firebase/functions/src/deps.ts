// The things handlers need from the outside world, passed in so tests can substitute a fake clock, fixed randomness,
// a recording push sender, and so on. Production code uses defaultDeps().
import { randomInt } from 'node:crypto';
import type { Auth } from 'firebase-admin/auth';
import type { Database } from 'firebase-admin/database';
import { getAuthAdmin, getDb } from './admin';
import type { RandomInt } from './codes';
import { defaultSender, type PushSender } from './push';

export interface Deps {
  db: Database;
  auth: () => Auth;
  now: () => number;
  /** Cryptographically strong: codes and seeds must not be guessable. */
  rand: RandomInt;
  sender: PushSender;
}

export function defaultDeps(): Deps {
  const db = getDb();
  const now = (): number => Date.now();
  return {
    db,
    auth: getAuthAdmin,
    now,
    rand: (max) => randomInt(max),
    sender: defaultSender(db, now),
  };
}
