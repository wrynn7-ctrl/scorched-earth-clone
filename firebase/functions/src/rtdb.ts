// Typed helpers over the Realtime Database Admin SDK, and the shapes of the data model (ARCHITECTURE sections 44-46).
import type { Database } from 'firebase-admin/database';

export interface UserRecord {
  name?: string;
  nameHidden?: boolean;
  friendCode?: string;
  created?: number;
  protocol?: number;
  full?: boolean;
  purchase?: { at: number; orderId?: string; tokenHash: string };
  fcm?: Record<string, string>;
}

export type MatchStatus = 'lobby' | 'playing' | 'over' | 'abandoned';

export interface Seat {
  kind: 'human' | 'cpu';
  uid?: string;
  name?: string;
  level?: number;
}

export interface Timers {
  liveSec: number;
  asyncHours: number;
  asyncTimeout: 'auto' | 'end';
}

export interface Turn {
  tank: number;
  uid: string;
  deadline: number;
  liveDeadline?: number;
  index: number;
}

export interface Meta {
  hostUid: string;
  code: string;
  protocol: number;
  created: number;
  status: MatchStatus;
  settings: Record<string, unknown>;
  seed: number;
  seats: Seat[];
  timers: Timers;
  turn?: Turn;
  actionCount: number;
  /** When startMatch ran (ms). */
  started?: number;
}

export interface UserMatchEntry {
  updated: number;
  yourTurn: boolean;
  status: MatchStatus;
  hostName?: string;
}

/** Reads a value, or null when the path holds nothing. */
export async function read<T>(db: Database, path: string): Promise<T | null> {
  const snap = await db.ref(path).get();
  return snap.exists() ? (snap.val() as T) : null;
}

export async function exists(db: Database, path: string): Promise<boolean> {
  return (await db.ref(path).get()).exists();
}

/** Realtime Database returns a dense array as an array and anything else as an object; accept both. */
export function normalizeSeats(raw: unknown): Seat[] {
  if (Array.isArray(raw)) return (raw as (Seat | null)[]).map((s) => s ?? { kind: 'human' });
  if (raw && typeof raw === 'object') {
    const entries = Object.entries(raw as Record<string, Seat>).sort(([a], [b]) => Number(a) - Number(b));
    return entries.map(([, seat]) => seat);
  }
  return [];
}

export async function readMeta(db: Database, matchId: string): Promise<Meta | null> {
  const raw = await read<Meta>(db, `matches/${matchId}/meta`);
  if (!raw) return null;
  return { ...raw, seats: normalizeSeats(raw.seats) };
}

export function humanUids(seats: readonly Seat[]): string[] {
  const out = new Set<string>();
  for (const seat of seats) {
    if (seat.kind === 'human' && seat.uid) out.add(seat.uid);
  }
  return [...out];
}

export async function isBlockedEither(db: Database, a: string, b: string): Promise<boolean> {
  const [ab, ba] = await Promise.all([exists(db, `blocks/${a}/${b}`), exists(db, `blocks/${b}/${a}`)]);
  return ab || ba;
}

/** The name other players see: "PLAYER 1AB2" when a name was auto-hidden after reports. */
export function displayName(user: UserRecord | null): string {
  if (!user) return 'PLAYER';
  if (user.nameHidden) return `PLAYER ${(user.friendCode ?? '').slice(0, 4)}`.trim();
  return user.name && user.name !== '' ? user.name : 'PLAYER';
}
