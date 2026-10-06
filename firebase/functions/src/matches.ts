// Matches: lobby, join, leave, start, invites (ARCHITECTURE section 45). Clients never create or edit a match
// directly; these handlers do, with transactions on `meta` so two players can never claim the same seat.
import { HttpsError } from 'firebase-functions/v2/https';
import { allocateCode, normalizeCode } from './codes';
import {
  CPU_LEVEL_NORMAL,
  IDLE_TTL_MS,
  LOBBY_TTL_MS,
  MATCH_CODE_LENGTH,
  MAX_USER_MATCHES,
  RETENTION_MS,
  TURN_NEEDS_RESOLVE,
  TURN_SHOP,
} from './config';
import type { Deps } from './deps';
import { asObject, fail, isSafeId, reqId } from './errors';
import {
  buildNewSeats,
  buildSettings,
  freeSeatIndexes,
  mergeLobbySeats,
  numberedSeatName,
  parseSeatSpecs,
  parseTimers,
  seatName,
} from './match_logic';
import {
  displayName,
  exists,
  humanUids,
  isBlockedEither,
  normalizeSeats,
  read,
  readMeta,
  type Meta,
  type MatchStatus,
  type Seat,
  type Turn,
  type UserMatchEntry,
  type UserRecord,
} from './rtdb';


/** Drops `undefined` values: the Realtime Database refuses them. */
function plain<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

async function requireUser(deps: Deps, uid: string): Promise<UserRecord> {
  const user = await read<UserRecord>(deps.db, `users/${uid}`);
  if (!user?.friendCode) return fail('failed-precondition', 'no_profile');
  return user;
}

async function requireMeta(deps: Deps, matchId: string): Promise<Meta> {
  const meta = await readMeta(deps.db, matchId);
  if (!meta) return fail('not-found', 'unknown_match');
  return meta;
}

function hostNameOf(meta: Pick<Meta, 'hostUid' | 'seats'>): string {
  return meta.seats.find((s) => s.uid === meta.hostUid)?.name ?? 'PLAYER';
}

async function assertRoomForMatch(deps: Deps, uid: string): Promise<void> {
  // A player may be in at most MAX_USER_MATCHES matches, so one that already has that many cannot join or host another.
  const mine = await deps.db.ref(`userMatches/${uid}`).orderByKey().limitToFirst(MAX_USER_MATCHES).get();
  if (mine.numChildren() >= MAX_USER_MATCHES) fail('resource-exhausted', 'too_many_matches');
}

/**
 * Runs `change` on meta inside a transaction. `change` returns the new meta and a result, or an HttpsError to abort.
 * It may run more than once (the SDK retries on a conflict), so it must not have side effects.
 */
export async function mutateMeta<T>(deps: Deps, matchId: string, change: (meta: Meta) => { meta: Meta; result: T } | HttpsError): Promise<T> {
  // A transaction on a path that holds nothing is wasted work, and on a prototype-like key (`__proto__`) it never finishes at all:
  // refuse bad ids and missing matches before starting one.
  if (!isSafeId(matchId, 1)) return fail('invalid-argument', 'bad_matchId');
  if (!(await exists(deps.db, `matches/${matchId}/meta/hostUid`))) return fail('not-found', 'unknown_match');
  let outcome: { result: T } | undefined;
  let failure: HttpsError | undefined;
  const done = await deps.db.ref(`matches/${matchId}/meta`).transaction((raw: Meta | null) => {
    failure = undefined;
    outcome = undefined;
    if (raw === null) return raw; // first pass has no data; the SDK retries with the real value
    const meta: Meta = { ...raw, seats: normalizeSeats(raw.seats) };
    const verdict = change(meta);
    if (verdict instanceof HttpsError) {
      failure = verdict;
      return undefined;
    }
    outcome = { result: verdict.result };
    return plain(verdict.meta);
  });
  if (failure) throw failure;
  if (!done.committed || !done.snapshot.exists() || !outcome) return fail('not-found', 'unknown_match');
  return outcome.result;
}

export const err = (code: ConstructorParameters<typeof HttpsError>[0], reason: string, details?: unknown): HttpsError =>
  new HttpsError(code, reason, details);

// ------------------------------------------------------------------------------------------------------------------
// Bookkeeping shared with the triggers and the sweep
// ------------------------------------------------------------------------------------------------------------------

/** When the sweep should look at this match next (a value for sweepQueue/{matchId}), or null for "never". */
export function nextDue(meta: Pick<Meta, 'status' | 'created' | 'turn'>, changedAt: number): number | null {
  switch (meta.status) {
    case 'lobby':
      return meta.created + LOBBY_TTL_MS;
    case 'playing':
      return meta.turn && meta.turn.tank >= 0 ? meta.turn.deadline : changedAt + IDLE_TTL_MS;
    default:
      return changedAt + RETENTION_MS;
  }
}

export function yourTurnFor(uid: string, status: MatchStatus, turn: Turn | undefined): boolean {
  if (status !== 'playing' || !turn) return false;
  return turn.tank === TURN_SHOP || turn.uid === uid;
}

/**
 * Updates the "Your matches" entry of every human member and the sweep queue. A member who has no entry yet is skipped
 * unless listed in `newMembers` (a player who left must not be put back on the list by a late update).
 */
export async function syncMatch(deps: Deps, matchId: string, meta: Meta, newMembers: readonly string[] = []): Promise<void> {
  const now = deps.now();
  const hostName = hostNameOf(meta);
  await Promise.all(
    humanUids(meta.seats).map((uid) => {
      const entry: UserMatchEntry = { updated: now, yourTurn: yourTurnFor(uid, meta.status, meta.turn), status: meta.status, hostName };
      const ref = deps.db.ref(`userMatches/${uid}/${matchId}`);
      if (newMembers.includes(uid)) return ref.set(entry);
      // Update an existing entry only. The first pass of a transaction sees no data, so it answers "null" (a no-op when the
      // entry really is missing, a retry with the real value when it is not).
      return ref.transaction((current: UserMatchEntry | null) => (current === null ? null : entry));
    }),
  );
  await deps.db.ref(`sweepQueue/${matchId}`).set(nextDue(meta, now));
}

/** Everything that follows a match ending: the code expires, members' lists show the result, deletion is scheduled. */
export async function cleanupFinished(deps: Deps, matchId: string, meta: Meta): Promise<void> {
  const codeOwner = await read<string>(deps.db, `matchCodes/${meta.code}`);
  if (codeOwner === matchId) await deps.db.ref(`matchCodes/${meta.code}`).remove();
  await syncMatch(deps, matchId, meta);
}

/** lobby/playing -> over/abandoned. Returns the final meta, or null when the match was already finished. */
export async function finishMatch(deps: Deps, matchId: string, status: 'over' | 'abandoned'): Promise<Meta | null> {
  let changed = false;
  const meta = await mutateMeta(deps, matchId, (current) => {
    changed = current.status === 'lobby' || current.status === 'playing';
    const next: Meta = changed ? { ...current, status } : current;
    return { meta: next, result: next };
  });
  if (!changed) return null;
  await cleanupFinished(deps, matchId, meta);
  return meta;
}

// ------------------------------------------------------------------------------------------------------------------
// createMatch / updateLobby
// ------------------------------------------------------------------------------------------------------------------

export interface CreateResult {
  matchId: string;
  code: string;
}

export async function createMatch(deps: Deps, uid: string, raw: unknown): Promise<CreateResult> {
  const data = asObject(raw);
  const host = await requireUser(deps, uid);
  if (host.full !== true) return fail('permission-denied', 'full_required');
  await assertRoomForMatch(deps, uid);
  const hostName = displayName(host);
  const seats = buildNewSeats(parseSeatSpecs(data.seats), uid, hostName);
  const settings = buildSettings(data.settings, seats);
  const timers = parseTimers(data.timers);
  const matchId = deps.db.ref('matches').push().key;
  if (!matchId) return fail('internal', 'no_match_id');
  const code = await allocateCode(deps.db, 'matchCodes', MATCH_CODE_LENGTH, matchId, deps.rand);
  if (!code) return fail('resource-exhausted', 'no_free_code');
  const now = deps.now();
  const meta: Meta = {
    hostUid: uid,
    code,
    protocol: host.protocol ?? 0,
    created: now,
    status: 'lobby',
    settings,
    seed: 0,
    seats,
    timers,
    actionCount: 0,
  };
  try {
    await deps.db.ref().update(plain({ [`matches/${matchId}/meta`]: meta }));
    await syncMatch(deps, matchId, meta, [uid]);
  } catch (error) {
    await deps.db.ref(`matchCodes/${code}`).remove();
    throw error;
  }
  return { matchId, code };
}

export interface UpdateLobbyResult {
  seats: Seat[];
}

/** Host edits of a lobby: settings, timers and the seat layout (CPUs, free seats). Held seats are carried over. */
export async function updateLobby(deps: Deps, uid: string, raw: unknown): Promise<UpdateLobbyResult> {
  const data = asObject(raw);
  const matchId = reqId(data, 'matchId');
  const host = await requireUser(deps, uid);
  const specs = data.seats === undefined ? undefined : parseSeatSpecs(data.seats);
  const timers = data.timers === undefined ? undefined : parseTimers(data.timers);
  const hostName = displayName(host);
  const result = await mutateMeta(deps, matchId, (meta): { meta: Meta; result: UpdateLobbyResult } | HttpsError => {
    if (meta.hostUid !== uid) return err('permission-denied', 'not_host');
    if (meta.status !== 'lobby') return err('failed-precondition', 'not_in_lobby');
    try {
      const nextSeats = specs ? mergeLobbySeats(meta.seats, specs, uid, hostName) : meta.seats;
      const settings = data.settings === undefined && !specs ? meta.settings : buildSettings(mergeSettings(meta.settings, data.settings), nextSeats);
      return { meta: { ...meta, seats: nextSeats, settings, timers: timers ?? meta.timers }, result: { seats: nextSeats } };
    } catch (error) {
      if (error instanceof HttpsError) return error;
      throw error;
    }
  });
  const meta = await requireMeta(deps, matchId);
  await syncMatch(deps, matchId, meta);
  return result;
}

/** Sent settings replace the stored ones key by key, so a client may send only what the host changed. */
function mergeSettings(current: Record<string, unknown>, sent: unknown): Record<string, unknown> {
  const base: Record<string, unknown> = { ...current };
  delete base.seed;
  delete base.num_tanks;
  delete base.controllers;
  delete base.full_unlocked;
  const fromClient = asObject(sent, 'settings');
  const merged = { ...base, ...fromClient };
  // `teams` that was sent as an empty list means "no teams".
  if (Array.isArray(fromClient.teams) && fromClient.teams.length === 0) delete merged.teams;
  return merged;
}

// ------------------------------------------------------------------------------------------------------------------
// joinMatch / leaveMatch / startMatch
// ------------------------------------------------------------------------------------------------------------------

export interface JoinResult {
  matchId: string;
  /** The seat indexes now held by this player. */
  seats: number[];
  alreadyJoined: boolean;
}

export async function joinMatch(deps: Deps, uid: string, raw: unknown): Promise<JoinResult> {
  const data = asObject(raw);
  const user = await requireUser(deps, uid);
  const code = normalizeCode(data.code, MATCH_CODE_LENGTH);
  if (!code) return fail('invalid-argument', 'bad_code');
  const seatCount = data.seatCount === undefined ? 1 : data.seatCount;
  if (typeof seatCount !== 'number' || !Number.isInteger(seatCount) || seatCount < 1 || seatCount > 4) {
    return fail('invalid-argument', 'bad_seatCount');
  }
  const names = Array.isArray(data.names) ? (data.names as unknown[]).map((n) => (typeof n === 'string' ? n : undefined)) : [];
  const matchId = await read<string>(deps.db, `matchCodes/${code}`);
  if (!matchId) return fail('not-found', 'unknown_code');
  const before = await readMeta(deps.db, matchId);
  if (!before) return fail('not-found', 'unknown_code');

  // A blocked pair looks like an unknown code: the block is never revealed.
  for (const other of new Set([before.hostUid, ...humanUids(before.seats)])) {
    if (other !== uid && (await isBlockedEither(deps.db, uid, other))) return fail('not-found', 'unknown_code');
  }
  if (before.seats.some((s) => s.uid === uid)) {
    const held = before.seats.flatMap((s, i) => (s.uid === uid ? [i] : []));
    return { matchId, seats: held, alreadyJoined: true };
  }
  if ((user.protocol ?? 0) !== before.protocol) {
    return fail('failed-precondition', 'protocol_mismatch', { hostProtocol: before.protocol, yourProtocol: user.protocol ?? 0 });
  }
  await assertRoomForMatch(deps, uid);
  const myName = displayName(user);
  // The "already in the match" check is repeated inside the transaction: two calls at the same moment (a double tap) both pass
  // the read above, and only the first to commit may take seats.
  const claimed = await mutateMeta(deps, matchId, (meta): { meta: Meta; result: { seats: number[]; already: boolean } } | HttpsError => {
    if (meta.seats.some((s) => s.uid === uid)) {
      return { meta, result: { seats: meta.seats.flatMap((s, i) => (s.uid === uid ? [i] : [])), already: true } };
    }
    if (meta.status !== 'lobby') return err('failed-precondition', 'not_joinable');
    const free = freeSeatIndexes(meta.seats);
    if (free.length === 0) return err('resource-exhausted', 'match_full');
    if (free.length < seatCount) return err('resource-exhausted', 'not_enough_seats', { free: free.length });
    const taken = free.slice(0, seatCount);
    const seats = meta.seats.map((seat, index): Seat => {
      const slot = taken.indexOf(index);
      if (slot < 0) return seat;
      const fallback = slot === 0 ? myName : numberedSeatName(myName, slot + 1);
      return { kind: 'human', uid, name: seatName(names[slot], fallback) };
    });
    return { meta: { ...meta, seats }, result: { seats: taken, already: false } };
  });
  const after = await requireMeta(deps, matchId);
  await syncMatch(deps, matchId, after, [uid]);
  return { matchId, seats: claimed.seats, alreadyJoined: claimed.already };
}

export interface LeaveResult {
  status: MatchStatus | 'left';
}

/** What happens to a player's seats when they leave a running match (or delete their data): they play on as CPU Normal. */
export function seatsToCpu(meta: Meta, uid: string, anonymous = false): Meta {
  const seats = meta.seats.map(
    (seat): Seat => (seat.uid === uid ? { kind: 'cpu', level: CPU_LEVEL_NORMAL, name: anonymous ? 'PLAYER' : (seat.name ?? 'CPU') } : seat),
  );
  const turn = meta.turn;
  const heldTurn = turn !== undefined && turn.tank >= 0 && meta.seats[turn.tank]?.uid === uid;
  // The turn (or the shop, which the new CPU has not visited) needs a client to replay and carry on.
  const resolve = turn !== undefined && (heldTurn || turn.tank === TURN_SHOP);
  const next: Meta = { ...meta, seats };
  if (resolve && turn) next.turn = { tank: TURN_NEEDS_RESOLVE, uid: 'any', deadline: 0, index: turn.index + 1 };
  if (humanUids(seats).length === 0) next.status = 'abandoned';
  return next;
}

export async function leaveMatch(deps: Deps, uid: string, raw: unknown): Promise<LeaveResult> {
  const matchId = reqId(asObject(raw), 'matchId');
  if (!(await exists(deps.db, `userMatches/${uid}/${matchId}`))) return fail('not-found', 'not_a_member');
  const meta = await readMeta(deps.db, matchId);
  // A list entry whose match is gone (deleted after the retention period) is simply cleared.
  const result: LeaveResult = meta ? await leaveWithMeta(deps, uid, matchId, meta) : { status: 'abandoned' };
  await deps.db.ref(`userMatches/${uid}/${matchId}`).remove();
  return result;
}

/** Seat handling for one player leaving. The caller removes their userMatches entry. */
export async function leaveWithMeta(deps: Deps, uid: string, matchId: string, seen: Meta): Promise<LeaveResult> {
  if (seen.status === 'over' || seen.status === 'abandoned') return { status: seen.status };
  if (seen.status === 'lobby' && seen.hostUid === uid) {
    // The host leaving a lobby closes it.
    await finishMatch(deps, matchId, 'abandoned');
    return { status: 'abandoned' };
  }
  const updated = await mutateMeta(deps, matchId, (meta): { meta: Meta; result: Meta } | HttpsError => {
    if (meta.status === 'lobby') {
      const seats = meta.seats.map((seat): Seat => (seat.uid === uid ? { kind: 'human' } : seat));
      return { meta: { ...meta, seats }, result: { ...meta, seats } };
    }
    if (meta.status === 'playing') {
      const next = seatsToCpu(meta, uid);
      return { meta: next, result: next };
    }
    return { meta, result: meta };
  });
  if (updated.status === 'abandoned') await cleanupFinished(deps, matchId, updated);
  else await syncMatch(deps, matchId, updated);
  return { status: updated.status === 'lobby' ? 'left' : updated.status };
}

export interface StartResult {
  seed: number;
}

/** The host starts the match: picks the seed and marks the first turn "needs resolve" (the host's client sets it). */
export async function startMatch(deps: Deps, uid: string, raw: unknown): Promise<StartResult> {
  const matchId = reqId(asObject(raw), 'matchId');
  const seed = 1 + deps.rand(0x7ffffffe); // 1 .. 2^31 - 2, a positive int32 for Rng
  const now = deps.now();
  await mutateMeta(deps, matchId, (meta): { meta: Meta; result: true } | HttpsError => {
    if (meta.hostUid !== uid) return err('permission-denied', 'not_host');
    if (meta.status !== 'lobby') return err('failed-precondition', 'not_in_lobby');
    if (freeSeatIndexes(meta.seats).length > 0) return err('failed-precondition', 'seats_not_filled');
    if (humanUids(meta.seats).length === 0) return err('failed-precondition', 'no_human_seat');
    const started: Meta = {
      ...meta,
      status: 'playing',
      seed,
      settings: { ...meta.settings, seed },
      actionCount: 0,
      turn: { tank: TURN_NEEDS_RESOLVE, uid: 'any', deadline: 0, index: 0 },
    };
    return { meta: { ...started, started: now }, result: true };
  });
  const meta = await requireMeta(deps, matchId);
  await syncMatch(deps, matchId, meta);
  return { seed };
}

// ------------------------------------------------------------------------------------------------------------------
// invite
// ------------------------------------------------------------------------------------------------------------------

export async function invite(deps: Deps, uid: string, raw: unknown): Promise<{ invited: true }> {
  const data = asObject(raw);
  const friendUid = reqId(data, 'friendUid');
  const matchId = reqId(data, 'matchId');
  const me = await requireUser(deps, uid);
  if (friendUid === uid) return fail('failed-precondition', 'self');
  if (!(await exists(deps.db, `userMatches/${uid}/${matchId}`))) return fail('permission-denied', 'not_a_member');
  const meta = await requireMeta(deps, matchId);
  if (meta.status !== 'lobby') return fail('failed-precondition', 'not_in_lobby');
  if (!(await exists(deps.db, `friends/${uid}/${friendUid}`))) return fail('permission-denied', 'not_friends');
  if (await isBlockedEither(deps.db, uid, friendUid)) return fail('permission-denied', 'not_friends');
  if (meta.seats.some((s) => s.uid === friendUid)) return fail('already-exists', 'already_in_match');
  await deps.db.ref().update({
    // The invitee cannot read the match, so the invite carries the code and the mode (to hide Love invites).
    [`invites/${friendUid}/${matchId}`]: {
      fromUid: uid,
      fromName: displayName(me),
      at: deps.now(),
      code: meta.code,
      mode: typeof meta.settings.mode === 'number' ? meta.settings.mode : 0,
    },
    [`invitesSent/${uid}/${matchId}/${friendUid}`]: true,
  });
  return { invited: true };
}

