// The scheduled sweep (every 15 minutes): async turn timeouts, expired lobbies, dead matches, old finished matches
// (ARCHITECTURE section 46). The logic is a plain function of (deps, options) so the tests can drive it with a fake clock.
//
// How it finds work cheaply: sweepQueue/{matchId} holds the time a match next needs a look (see nextDue in matches.ts),
// kept up to date by createMatch/startMatch/onTurnChange. The sweep reads only the entries that are due.
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { LOBBY_TTL_MS, MAX_INSTANCES, REGION, TURN_NEEDS_RESOLVE } from './config';
import { defaultDeps, type Deps } from './deps';
import { cleanupFinished, err, finishMatch, mutateMeta, nextDue, syncMatch } from './matches';
import { humanUids, read, readMeta, type Meta } from './rtdb';

export interface SweepOptions {
  /** Only look at these matches (tests). They are examined whether or not the queue lists them. */
  matchIds?: string[];
  /** Most matches examined in one call. */
  limit?: number;
}

export interface SweepResult {
  /** Matches that got a `timeout` entry, and now wait for a client to resolve the turn. */
  timeouts: string[];
  /** Async matches that ended because the host chose "end the match on timeout". */
  ended: string[];
  /** Lobbies that expired, and matches nobody resolved for too long. */
  abandoned: string[];
  /** Finished matches removed after the retention period. */
  deleted: string[];
  /** Matches examined but not due yet (queue entry refreshed). */
  skipped: string[];
}

const DEFAULT_LIMIT = 200;

export async function runTimeoutSweep(deps: Deps, options: SweepOptions = {}): Promise<SweepResult> {
  const result: SweepResult = { timeouts: [], ended: [], abandoned: [], deleted: [], skipped: [] };
  const now = deps.now();
  const limit = options.limit ?? DEFAULT_LIMIT;
  const queue = new Map<string, number | null>();
  if (options.matchIds) {
    for (const id of options.matchIds) queue.set(id, await read<number>(deps.db, `sweepQueue/${id}`));
  } else {
    const due = await deps.db.ref('sweepQueue').orderByValue().endAt(now).limitToFirst(limit).get();
    due.forEach((child) => {
      queue.set(child.key, child.val() as number);
    });
  }
  for (const [matchId, dueAt] of queue) {
    try {
      await examine(deps, matchId, dueAt, result);
    } catch (error) {
      // One broken match must not stop the others; the next run tries again because its queue entry is untouched.
      console.error(`sweep: match ${matchId} failed`, error);
    }
  }
  return result;
}

async function examine(deps: Deps, matchId: string, dueAt: number | null, result: SweepResult): Promise<void> {
  const now = deps.now();
  const meta = await readMeta(deps.db, matchId);
  if (!meta) {
    await deps.db.ref(`sweepQueue/${matchId}`).remove();
    return;
  }
  const due = dueAt !== null && now >= dueAt;
  switch (meta.status) {
    case 'lobby':
      if (now >= meta.created + LOBBY_TTL_MS) {
        await finishMatch(deps, matchId, 'abandoned');
        result.abandoned.push(matchId);
        return;
      }
      break;
    case 'playing': {
      const turn = meta.turn;
      if (turn && turn.tank >= 0 && now > turn.deadline) {
        if (await timeoutTurn(deps, matchId, meta, result)) return;
      } else if ((!turn || turn.tank < 0) && due) {
        // Nobody resolved "needs resolve" / nobody finished the shop for a long time.
        await finishMatch(deps, matchId, 'abandoned');
        result.abandoned.push(matchId);
        return;
      }
      break;
    }
    default:
      if (due) {
        await deleteMatch(deps, matchId, meta);
        result.deleted.push(matchId);
        return;
      }
  }
  result.skipped.push(matchId);
  await deps.db.ref(`sweepQueue/${matchId}`).set(nextDue(meta, now));
}

/**
 * Writes the `timeout` entry for the turn that ran out of time, then bumps actionCount and marks the turn "needs resolve"
 * (or ends the match, when the host chose that). Safe against a player acting at the same moment:
 *  1. the entry is written only if actions/{count} is still free (a transaction), so a player's own write wins or loses cleanly;
 *  2. the count and turn change only if they still are what we saw.
 * If we die between the two steps the entry exists but the count did not move; the next run finds that entry and completes step 2.
 */
async function timeoutTurn(deps: Deps, matchId: string, meta: Meta, result: SweepResult): Promise<boolean> {
  const turn = meta.turn;
  if (!turn) return false;
  const count = meta.actionCount;
  const entry = { kind: 'timeout', tank: turn.tank };
  const written = await deps.db.ref(`matches/${matchId}/actions/${count}`).transaction((current: unknown) => (current === null ? entry : undefined));
  if (!written.committed) {
    const there = written.snapshot.val() as { kind?: string; tank?: number } | null;
    // Someone else's entry at this index means a player acted just before us: leave the match alone.
    if (!there || there.kind !== 'timeout' || there.tank !== turn.tank) return false;
  }
  const end = meta.timers.asyncTimeout === 'end';
  const next = await mutateMeta(deps, matchId, (current): { meta: Meta; result: Meta } | ReturnType<typeof err> => {
    if (current.status !== 'playing' || current.actionCount !== count || current.turn?.index !== turn.index) {
      return err('aborted', 'moved_on');
    }
    const advanced: Meta = {
      ...current,
      actionCount: count + 1,
      turn: { tank: TURN_NEEDS_RESOLVE, uid: 'any', deadline: 0, index: turn.index + 1 },
      status: end ? 'over' : 'playing',
    };
    return { meta: advanced, result: advanced };
  }).catch((error: unknown) => {
    if (error && typeof error === 'object' && 'code' in error && (error as { code: string }).code === 'aborted') return null;
    throw error;
  });
  if (!next) return false;
  if (end) {
    await cleanupFinished(deps, matchId, next);
    result.ended.push(matchId);
  } else {
    await syncMatch(deps, matchId, next);
    result.timeouts.push(matchId);
  }
  return true;
}

/** Removes a finished match and every pointer to it. */
async function deleteMatch(deps: Deps, matchId: string, meta: Meta): Promise<void> {
  const updates: Record<string, null> = { [`matches/${matchId}`]: null, [`sweepQueue/${matchId}`]: null };
  for (const uid of humanUids(meta.seats)) updates[`userMatches/${uid}/${matchId}`] = null;
  const code = await read<string>(deps.db, `matchCodes/${meta.code}`);
  if (code === matchId) updates[`matchCodes/${meta.code}`] = null;
  await deps.db.ref().update(updates);
}

export const timeoutSweep = onSchedule(
  { schedule: 'every 15 minutes', region: REGION, timeoutSeconds: 300, maxInstances: Math.min(MAX_INSTANCES, 1) },
  async () => {
    const result = await runTimeoutSweep(defaultDeps());
    console.log('timeoutSweep', JSON.stringify(result));
  },
);
