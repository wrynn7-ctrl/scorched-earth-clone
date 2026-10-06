// M7-Q rules fuzz: random multi-path writes from one account (a member, the other member, an outsider or nobody) against a
// randomly chosen match state. Every write that SUCCEEDS is then checked against an independent model of the contract
// (firebase/README.md "The action log in the rules", ARCHITECTURE sections 44-46): the model looks only at what changed in
// the database (before / after snapshots taken with the rules off), never at the rules text.
//
// The holes the first QA pass found (stale turns, message batches, a CPU level chosen by the writer) are fixed and are now
// violations. What the rules cannot enforce is still recognised and COUNTED, not failed, so the fuzz keeps pointing at anything
// new:  fcm_flood (the rules cannot count tokens; the onPushTokenAdded function trims them to 5).
//
// Environment: QA_FUZZ_SEED (default 20261006), QA_FUZZ_N (default 700).
import assert from 'node:assert/strict';
import { get } from 'firebase/database';
import { type Database, anonymous, as, DEFAULT_SEATS, HOUR, MID, ref, seed, seedMatch, seedUsers, serverTimestamp, testEnv, update, useRulesEnv, type Seat } from '../../rules/helpers';

type Obj = Record<string, unknown>;

// ---------------------------------------------------------------------------------------------------------------
// Deterministic random numbers
// ---------------------------------------------------------------------------------------------------------------
function mulberry32(seedValue: number): () => number {
  let a = seedValue >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

class Rand {
  constructor(private readonly next: () => number) {}
  int(lo: number, hi: number): number {
    return lo + Math.floor(this.next() * (hi - lo + 1));
  }
  chance(p: number): boolean {
    return this.next() < p;
  }
  pick<T>(items: readonly T[]): T {
    return items[this.int(0, items.length - 1)];
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Snapshots and diffs
// ---------------------------------------------------------------------------------------------------------------
async function snapshot(): Promise<Obj> {
  let out: Obj = {};
  await testEnv().withSecurityRulesDisabled(async (ctx) => {
    const snap = await get(ref(ctx.database() as unknown as Database));
    out = (snap.val() ?? {}) as Obj;
  });
  return out;
}

function flatten(value: unknown, prefix: string, out: Map<string, unknown>): Map<string, unknown> {
  if (Array.isArray(value)) {
    value.forEach((v, i) => {
      if (v !== null && v !== undefined) flatten(v, `${prefix}/${i}`, out);
    });
  } else if (value !== null && typeof value === 'object') {
    for (const [k, v] of Object.entries(value as Obj)) flatten(v, `${prefix}/${k}`, out);
  } else if (value !== null && value !== undefined) {
    out.set(prefix, value);
  }
  return out;
}

function at(root: unknown, path: string): unknown {
  let node: unknown = root;
  for (const part of path.split('/').filter((p) => p !== '')) {
    if (node === null || typeof node !== 'object') return undefined;
    node = (node as Obj)[part];
  }
  return node;
}

interface Diff {
  added: string[];
  changed: string[];
  removed: string[];
}

function diff(before: Obj, after: Obj): Diff {
  const b = flatten(before, '', new Map());
  const a = flatten(after, '', new Map());
  const out: Diff = { added: [], changed: [], removed: [] };
  for (const [path, value] of a) {
    if (!b.has(path)) out.added.push(path);
    else if (b.get(path) !== value) out.changed.push(path);
  }
  for (const path of b.keys()) if (!a.has(path)) out.removed.push(path);
  return out;
}

// ---------------------------------------------------------------------------------------------------------------
// The contract model
// ---------------------------------------------------------------------------------------------------------------
const AIM = ['fire', 'move', 'use_item', 'pass'];
const SHOP = ['buy', 'sell', 'ready'];
const ID = /^[a-z][a-z0-9_]{0,31}$/;
const isInt = (v: unknown, lo: number, hi: number): v is number => typeof v === 'number' && Number.isInteger(v) && v >= lo && v <= hi;
const FIELDS: Record<string, string[]> = {
  fire: ['tank', 'angle', 'power', 'weapon'],
  move: ['tank', 'dx'],
  use_item: ['tank', 'item'],
  pass: ['tank'],
  buy: ['tank', 'item', 'qty'],
  sell: ['tank', 'item', 'qty'],
  ready: ['tank'],
  auto: ['tank', 'level'],
  auto_shop: ['tank', 'level'],
  timeout: ['tank'],
};

function entryShapeOk(e: unknown): boolean {
  if (e === null || typeof e !== 'object') return false;
  const o = e as Obj;
  const kind = o.kind;
  if (typeof kind !== 'string' || !(kind in FIELDS)) return false;
  const allowed = new Set(['kind', ...(FIELDS[kind] ?? []), ...(kind === 'timeout' ? ['async'] : [])]);
  for (const key of Object.keys(o)) if (!allowed.has(key)) return false;
  for (const key of ['kind', ...(FIELDS[kind] ?? [])]) if (!(key in o)) return false;
  if (!isInt(o.tank, 0, 7)) return false;
  if ('angle' in o && !isInt(o.angle, 0, 1800)) return false;
  if ('power' in o && !isInt(o.power, 1, 1000)) return false;
  if ('weapon' in o && !(typeof o.weapon === 'string' && ID.test(o.weapon))) return false;
  if ('item' in o && !(typeof o.item === 'string' && ID.test(o.item))) return false;
  if ('dx' in o && !(isInt(o.dx, -200, 200) && o.dx !== 0)) return false;
  if ('qty' in o && !isInt(o.qty, 1, 99)) return false;
  if ('level' in o && !isInt(o.level, 1, 4)) return false;
  if ('async' in o && o.async !== 1) return false;
  return true;
}

interface Verdict {
  violations: string[];
  tags: string[];
}

interface Window {
  t0: number;
  t1: number;
}

function seatsOf(root: unknown): Seat[] {
  const raw = at(root, `matches/${MID}/meta/seats`);
  if (Array.isArray(raw)) return raw as Seat[];
  if (raw && typeof raw === 'object') return Object.values(raw as Obj) as Seat[];
  return [];
}

/** What the contract says about the update that turned `before` into `after`, written by `actor` (null = signed out). */
function judge(before: Obj, after: Obj, actor: string | null, win: Window): Verdict {
  const v: Verdict = { violations: [], tags: [] };
  const d = diff(before, after);
  const all = [...d.added, ...d.changed, ...d.removed];
  if (all.length === 0) return v;
  const bad = (msg: string): void => {
    v.violations.push(msg);
  };
  if (actor === null) {
    bad(`signed-out client changed ${all.slice(0, 3).join(', ')}`);
    return v;
  }
  const base = `matches/${MID}`;
  const member = at(before, `userMatches/${actor}/${MID}`) !== undefined;
  const bStatus = at(before, `${base}/meta/status`);
  const bCount = at(before, `${base}/meta/actionCount`) as number;
  const bTurn = (at(before, `${base}/meta/turn`) ?? {}) as Obj;
  const bSeats = seatsOf(before);
  const timers = (at(before, `${base}/meta/timers`) ?? { liveSec: 60, asyncHours: 72 }) as { liveSec: number; asyncHours: number };

  // ---- log entries and the counters that move with them
  const newEntries = d.added.filter((p) => p.startsWith(`/${base}/actions/`)).map((p) => p.split('/')[4] ?? '');
  const entryIndexes = [...new Set(newEntries)].map(Number).sort((a, b) => a - b);
  const touchedOld = [...d.changed, ...d.removed].filter((p) => p.startsWith(`/${base}/actions/`));
  if (touchedOld.length > 0) bad(`existing log entry changed or removed: ${touchedOld[0]}`);
  const aCount = at(after, `${base}/meta/actionCount`) as number;
  const countMoved = aCount !== bCount;
  const k = entryIndexes.length;
  if (k > 0 || countMoved) {
    if (!member) bad('non-member touched the log or counter');
    if (bStatus !== 'playing') bad(`log written while status is ${String(bStatus)}`);
    if (k === 0) bad('actionCount moved without an entry');
    if (aCount !== bCount + k) bad(`actionCount ${bCount} -> ${aCount} with ${k} new entries`);
    entryIndexes.forEach((idx, n) => {
      if (idx !== bCount + n) bad(`entry index ${idx} is not consecutive from ${bCount}`);
    });
    if (k > 16) bad(`${k} entries in one update`);
    entryIndexes.forEach((idx, n) => {
      const e = at(after, `${base}/actions/${idx}`) as Obj;
      if (!entryShapeOk(e)) {
        bad(`malformed entry ${JSON.stringify(e)}`);
        return;
      }
      const kind = e.kind as string;
      const tank = e.tank as number;
      const seat = bSeats[tank];
      const holds = seat?.kind === 'human' && seat.uid === actor;
      const turnTank = bTurn.tank as number;
      if (n === 0) {
        if (AIM.includes(kind)) {
          if (!(turnTank >= 0 && tank === turnTank && holds)) bad(`first entry ${kind} tank ${tank} out of turn (turn ${JSON.stringify(bTurn)}) for ${actor}`);
        } else if (SHOP.includes(kind)) {
          if (!(turnTank === -2 && holds)) bad(`first entry ${kind} tank ${tank} outside the shop or for another seat`);
        } else if (kind === 'auto') {
          if (!(seat?.kind === 'cpu' && (turnTank === -1 || (tank === turnTank && bTurn.uid === 'cpu')))) bad(`first auto for tank ${tank} not due`);
        } else if (kind === 'auto_shop') {
          if (!(seat?.kind === 'cpu' && (turnTank === -1 || turnTank === -2))) bad(`first auto_shop for tank ${tank} not due`);
        } else if (kind === 'timeout') {
          const dueTurn = (turnTank >= 0 && tank === turnTank) || turnTank === -2;
          if (!(seat?.kind === 'human' && dueTurn)) bad(`timeout for tank ${tank} not on the turn`);
          else if (e.async === 1) {
            if (!(win.t1 > (bTurn.deadline as number))) bad('async timeout before the hard deadline');
          } else {
            const live = bTurn.liveDeadline as number | undefined;
            const beat = at(before, `${base}/presence/${String(bTurn.uid)}`) as number | undefined;
            if (!(live !== undefined && win.t1 > live)) bad('live skip before the live deadline');
            if (!(beat !== undefined && win.t0 - beat < 75000 + 5000)) bad('live skip while the holder is not present');
          }
        }
      } else {
        const okShop = SHOP.includes(kind) && turnTank === -2 && holds;
        const okCpu = (kind === 'auto' || kind === 'auto_shop') && seat?.kind === 'cpu';
        if (!(okShop || okCpu)) bad(`later entry ${kind} tank ${tank} is neither the writer's shop entry nor a CPU entry`);
        if (AIM.includes(kind) || kind === 'timeout') bad(`later entry of kind ${kind}`);
      }
      if (kind === 'auto' || kind === 'auto_shop') {
        if (seat?.kind === 'cpu' && seat.level !== e.level) bad(`${kind} for tank ${tank} at level ${String(e.level)}, the seat's is ${String(seat.level)}`);
      }
    });
  }

  // ---- the turn
  const turnPaths = all.filter((p) => p.startsWith(`/${base}/meta/turn`));
  if (turnPaths.length > 0) {
    const aTurn = at(after, `${base}/meta/turn`) as Obj | undefined;
    if (!member) bad('non-member changed the turn');
    if (!(k > 0 || bTurn.tank === -1)) bad('turn changed without a new entry and without a "needs resolve" marker');
    if (aTurn === undefined) bad('turn deleted');
    else {
      const t = aTurn;
      const keys = Object.keys(t);
      if (keys.some((x) => !['tank', 'uid', 'deadline', 'liveDeadline', 'index'].includes(x))) bad('extra turn field');
      if (!isInt(t.tank, -2, 7)) bad('turn tank out of range');
      if (t.index !== (bTurn.index as number) + 1) bad(`turn index ${String(t.index)} is not ${String(bTurn.index)}+1`);
      const seat = bSeats[t.tank as number];
      if ((t.tank as number) < 0) {
        if (t.uid !== 'any') bad('marker turn without uid any');
      } else if (!(t.uid === seat?.uid || (t.uid === 'cpu' && seat?.kind === 'cpu'))) bad(`turn uid ${String(t.uid)} does not hold seat ${String(t.tank)}`);
      if (t.tank === -1) {
        if (t.deadline !== 0) bad('needs-resolve turn with a deadline');
      } else {
        const deadline = t.deadline as number;
        if (!(typeof deadline === 'number' && deadline >= win.t0 - 5000 - 2000 && deadline <= win.t1 + timers.asyncHours * 3600000 + 120000 + 2000)) bad(`deadline ${String(t.deadline)} out of range`);
      }
      if ('liveDeadline' in t) {
        const live = t.liveDeadline as number;
        if (!((t.tank as number) >= 0 && typeof live === 'number' && live >= win.t0 - 5000 - 2000 && live <= win.t1 + timers.liveSec * 1000 + 122000)) bad('liveDeadline out of range or on a non-aim turn');
      }
    }
  }

  // ---- status
  const statusPaths = all.filter((p) => p === `/${base}/meta/status`);
  if (statusPaths.length > 0) {
    const aStatus = at(after, `${base}/meta/status`);
    const host = at(before, `${base}/meta/hostUid`);
    const okOver = aStatus === 'over' && bStatus === 'playing' && member && k > 0;
    const okAbandon = aStatus === 'abandoned' && host === actor && (bStatus === 'playing' || bStatus === 'lobby');
    if (!(okOver || okAbandon)) bad(`status ${String(bStatus)} -> ${String(aStatus)} by ${actor}`);
  }

  // ---- everything else under the match
  for (const p of all) {
    if (!p.startsWith(`/${base}/`)) continue;
    const rest = p.slice(base.length + 2);
    if (rest.startsWith('actions/') || rest === 'meta/actionCount' || rest.startsWith('meta/turn') || rest === 'meta/status') continue;
    if (rest === `presence/${actor}`) {
      const value = at(after, `${base}/presence/${actor}`) as number;
      if (!member) bad('presence by a non-member');
      if (!(typeof value === 'number' && value >= win.t0 - 2000 && value <= win.t1 + 2000)) bad(`presence value ${String(value)} is not server time`);
      if (d.removed.includes(p)) bad('presence deleted');
      continue;
    }
    if (rest === `lastMsg/${actor}`) {
      const value = at(after, `${base}/lastMsg/${actor}`) as number;
      const old = at(before, `${base}/lastMsg/${actor}`) as number | undefined;
      if (!member) bad('lastMsg by a non-member');
      if (!(typeof value === 'number' && value >= win.t0 - 2000 && value <= win.t1 + 2000)) bad('lastMsg is not server time');
      if (old !== undefined && !(value >= old + 3000 - 5)) bad('lastMsg moved inside 3 s');
      continue;
    }
    if (rest === `lastMsgKey/${actor}`) {
      if (!member) bad('lastMsgKey by a non-member');
      if (d.removed.includes(p)) bad('lastMsgKey deleted');
      if (!d.added.includes(`/${base}/lastMsg/${actor}`) && !d.changed.includes(`/${base}/lastMsg/${actor}`)) bad('lastMsgKey without a limiter bump');
      continue;
    }
    if (rest.startsWith('msgs/')) {
      if (d.removed.includes(p) || d.changed.includes(p)) bad('message edited or removed');
      continue;
    }
    if (rest.startsWith('fp/')) {
      const parts: string[] = rest.split('/');
      if (parts[2] !== actor) bad(`fingerprint written for ${String(parts[2])} by ${actor}`);
      if (!member) bad('fingerprint by a non-member');
      if (at(after, `${base}/actions/${String(parts[1])}`) === undefined) bad('fingerprint for a missing entry');
      if (!(d.added.includes(p) && typeof at(after, `${base}${'/'}fp/${String(parts[1])}/${String(parts[2])}`) === 'string' && /^[0-9a-f]{16}$/.test(at(after, `${base}/fp/${String(parts[1])}/${String(parts[2])}`) as string))) bad('fingerprint malformed or overwritten');
      continue;
    }
    bad(`forbidden match path changed: ${p}`);
  }
  // messages: contract = at most one new message per update, only with a limiter bump, fully valid
  const newMsgs = [...new Set(d.added.filter((p) => p.startsWith(`/${base}/msgs/`)).map((p) => p.split('/')[4]))];
  if (newMsgs.length > 0) {
    if (!member || bStatus !== 'playing') bad('message by a non-member or outside a running match');
    if (newMsgs.length > 1) bad(`${newMsgs.length} messages in one update`);
    if (at(after, `${base}/lastMsgKey/${actor}`) !== newMsgs[0]) bad('the message is not under the key lastMsgKey names');
    const limiterMoved = d.added.includes(`/${base}/lastMsg/${actor}`) || d.changed.includes(`/${base}/lastMsg/${actor}`);
    if (!limiterMoved) bad('message without a limiter bump');
    for (const id of newMsgs) {
      const m = at(after, `${base}/msgs/${String(id)}`) as Obj;
      const keys = Object.keys(m).sort().join(',');
      const seat = bSeats[m.seat as number];
      const okMsg = keys === 'at,msg,seat,uid' && m.uid === actor && isInt(m.msg, 0, 7) && isInt(m.seat, 0, 7) && seat?.uid === actor && typeof m.at === 'number' && Math.abs(m.at - win.t0) < 5000;
      if (!okMsg) bad(`invalid message ${JSON.stringify(m)}`);
    }
  }

  // ---- accounts
  for (const p of all) {
    if (p.startsWith(`/${base}/`)) continue;
    const parts = p.split('/').slice(1);
    if (parts[0] === 'users' && parts[1] === actor) {
      const field = parts[2];
      const value = at(after, `users/${actor}/${String(field)}`);
      const hasProfile = at(before, `users/${actor}/friendCode`) !== undefined;
      if (field === 'name') {
        if (!(hasProfile && typeof value === 'string' && value.length >= 1 && value.length <= 12)) bad(`name write ${JSON.stringify(value)}`);
      } else if (field === 'protocol') {
        if (!(hasProfile && isInt(value, 0, 1000000))) bad(`protocol write ${JSON.stringify(value)}`);
      } else if (field === 'fcm') {
        const hash = parts[3] ?? '';
        if (!(hasProfile && /^[A-Za-z0-9_-]{8,64}$/.test(hash))) bad(`fcm key ${hash}`);
        else if (d.removed.includes(p)) continue;
        else if (!(typeof value === 'object' && value !== null && typeof (value as Obj)[hash] === 'string')) bad('fcm token malformed');
        else {
          const tokens = Object.keys((at(after, `users/${actor}/fcm`) ?? {})).length;
          if (tokens > 5) v.tags.push('fcm_flood');
        }
      } else bad(`users/${actor}/${String(field)} written`);
      continue;
    }
    if (parts[0] === 'invites' && parts[1] === actor && d.removed.includes(p)) {
      if (at(after, `invites/${actor}/${String(parts[2])}`) !== undefined) bad('invite edited');
      continue;
    }
    if (parts[0] === 'userMatches' && parts[1] === actor && d.removed.includes(p)) {
      const mid = parts[2] ?? '';
      const st = at(before, `userMatches/${actor}/${mid}/status`);
      if (at(after, `userMatches/${actor}/${mid}`) !== undefined || !(st === 'over' || st === 'abandoned')) bad(`userMatches/${actor}/${mid} dropped while ${String(st)}`);
      continue;
    }
    bad(`forbidden path changed: ${p}`);
  }
  // de-duplicate tags
  v.tags = [...new Set(v.tags)];
  return v;
}

// ---------------------------------------------------------------------------------------------------------------
// Scenario and update generators
// ---------------------------------------------------------------------------------------------------------------
const ACTORS: (string | null)[] = ['host', 'host', 'bob', 'bob', 'cat', null];
const SEAT_LAYOUTS: Seat[][] = [
  DEFAULT_SEATS,
  [{ kind: 'human', uid: 'host', name: 'HOST' }, { kind: 'human', uid: 'bob', name: 'BOB' }],
  [{ kind: 'human', uid: 'host', name: 'HOST' }, { kind: 'human', uid: 'bob', name: 'BOB' }, { kind: 'cpu', level: 3, name: 'C1' }, { kind: 'cpu', level: 1, name: 'C2' }],
  [{ kind: 'cpu', level: 2, name: 'C1' }, { kind: 'human', uid: 'bob', name: 'BOB' }, { kind: 'human', uid: 'host', name: 'HOST' }],
];

function genValue(r: Rand, depth = 0): unknown {
  const kind = r.int(0, depth > 1 ? 9 : 12);
  switch (kind) {
    case 0: return null;
    case 1: return r.chance(0.5);
    case 2: return r.int(-3, 12);
    case 3: return r.pick([0, 1, 7, 8, 16, 99, 100, 1000, 1001, 1800, 1801, 1e6, 1e12, -1, -200, 201]);
    case 4: return r.int(0, 100) / 10;
    case 5: return r.pick(['', 'a', 'host', 'bob', 'cpu', 'any', 'fire', 'pass', 'over', 'playing', 'abandoned', 'x'.repeat(70), '3', '0123', '<script>', 'ünï😀']);
    case 6: return Date.now() + r.int(-3, 3) * HOUR;
    case 7: return serverTimestamp();
    case 8: return r.pick(['pulse_missile', 'spark_dart', 'shield', 'Bad-Id', 'x'.repeat(40)]);
    case 9: return r.int(0, 3);
    case 10: return [genValue(r, depth + 1), genValue(r, depth + 1)];
    default: {
      const o: Obj = {};
      for (let i = r.int(1, 4); i > 0; i -= 1) o[r.pick(['kind', 'tank', 'uid', 'level', 'msg', 'seat', 'at', 'a', 'since', 'name'])] = genValue(r, depth + 1);
      return o;
    }
  }
}

function genEntry(r: Rand, seats: Seat[], preferTank: number | null): Obj {
  const kind = r.pick(['fire', 'fire', 'move', 'use_item', 'pass', 'pass', 'buy', 'sell', 'ready', 'ready', 'auto', 'auto', 'auto_shop', 'timeout', 'timeout']);
  const tank = preferTank !== null && r.chance(0.7) ? preferTank : r.int(0, Math.min(8, seats.length));
  const e: Obj = { kind, tank };
  switch (kind) {
    case 'fire': e.angle = r.int(0, 1800); e.power = r.int(1, 1000); e.weapon = 'pulse_missile'; break;
    case 'move': e.dx = r.pick([-20, 5, 200, -200, 0, 201]); break;
    case 'use_item': e.item = 'shield'; break;
    case 'buy': case 'sell': e.item = 'shield'; e.qty = r.pick([1, 3, 99, 0, 100]); break;
    case 'auto': case 'auto_shop': e.level = r.pick([1, 2, 3, 4, 4, 0, 5]); break;
    case 'timeout': if (r.chance(0.6)) e.async = 1; break;
    default: break;
  }
  if (r.chance(0.07)) e[r.pick(['extra', 'angle', 'level', 'async'])] = genValue(r);
  if (r.chance(0.05)) delete e[r.pick(Object.keys(e))];
  return e;
}

interface Scene {
  seats: Seat[];
  count: number;
  turn: Obj;
  status: string;
  presence: Record<string, number>;
}

function genScene(r: Rand): Scene {
  const seats = r.pick(SEAT_LAYOUTS);
  const now = Date.now();
  const mode = r.int(0, 9);
  let turn: Obj;
  const deadline = r.chance(0.35) ? now - r.int(1, 5000) : now + HOUR;
  if (mode === 0) turn = { tank: -1, uid: 'any', deadline: 0, index: 3 };
  else if (mode === 1) turn = { tank: -2, uid: 'any', deadline, index: 3 };
  else {
    const tank = r.int(0, seats.length - 1);
    const seat = seats[tank];
    turn = { tank, uid: seat.kind === 'cpu' ? 'cpu' : seat.uid, deadline, index: 3 };
    if (r.chance(0.4) && seat.kind === 'human') turn.liveDeadline = now + r.int(-3000, 40000);
  }
  const presence: Record<string, number> = {};
  for (const uid of ['host', 'bob']) if (r.chance(0.6)) presence[uid] = now - r.pick([100, 5000, 74000, 80000, 600000]);
  return {
    seats,
    count: r.int(0, 5),
    turn,
    status: r.chance(0.85) ? 'playing' : r.pick(['lobby', 'over', 'abandoned']),
    presence,
  };
}

const M = (p: string): string => `matches/${MID}/${p}`;

function plausibleTurn(r: Rand, scene: Scene): Obj {
  const now = Date.now();
  const tank = r.chance(0.2) ? r.pick([-2, -1]) : r.int(0, scene.seats.length - 1);
  const seat = scene.seats[tank];
  const t: Obj = {
    tank,
    uid: tank < 0 ? 'any' : seat?.kind === 'cpu' ? 'cpu' : seat?.uid,
    deadline: tank === -1 ? 0 : now + r.pick([-130000, -100000, -1000, 60000, HOUR, 72 * HOUR, 73 * HOUR]),
    index: (scene.turn.index as number) + (r.chance(0.9) ? 1 : r.pick([0, 2, 3])),
  };
  if (r.chance(0.2)) t.uid = r.pick(['host', 'bob', 'cat', 'cpu', 'any']);
  if (tank >= 0 && r.chance(0.4)) t.liveDeadline = now + r.pick([-130000, -100000, -500, 30000, 60000, 200000]);
  if (r.chance(0.05)) t.extra = 1;
  return t;
}

/** An update shaped like an honest client's, for whatever role `actor` has in the scene. */
function validAppend(r: Rand, scene: Scene, actor: string | null): Obj {
  const now = Date.now();
  const turnTank = scene.turn.tank as number;
  const cpuSeats = scene.seats.flatMap((s, i) => (s.kind === 'cpu' ? [i] : []));
  const mine = scene.seats.flatMap((s, i) => (s.kind === 'human' && s.uid === actor ? [i] : []));
  const entries: Obj[] = [];
  const lvl = (tank: number): number => (scene.seats[tank]).level ?? 2;
  const aim = (tank: number): Obj => r.pick([
    { kind: 'fire', tank, angle: r.int(0, 1800), power: r.int(1, 1000), weapon: 'pulse_missile' },
    { kind: 'pass', tank },
    { kind: 'move', tank, dx: r.pick([-5, 7]) },
    { kind: 'use_item', tank, item: 'shield' },
  ]);
  if (turnTank >= 0) {
    const seat = scene.seats[turnTank];
    if (seat.kind === 'cpu') entries.push({ kind: 'auto', tank: turnTank, level: lvl(turnTank) });
    else if (seat.uid === actor && r.chance(0.8)) entries.push(aim(turnTank));
    else entries.push(r.chance(0.5) ? { kind: 'timeout', tank: turnTank, async: 1 } : { kind: 'timeout', tank: turnTank });
  } else if (turnTank === -1 && cpuSeats.length > 0) {
    entries.push({ kind: 'auto', tank: cpuSeats[0], level: lvl(cpuSeats[0]) });
  } else if (turnTank === -2) {
    if (mine.length > 0 && r.chance(0.8)) {
      for (const t of mine) {
        if (r.chance(0.5)) entries.push({ kind: 'buy', tank: t, item: 'shield', qty: r.int(1, 3) });
        entries.push({ kind: 'ready', tank: t });
      }
    } else if (cpuSeats.length > 0) entries.push({ kind: 'auto_shop', tank: cpuSeats[0], level: lvl(cpuSeats[0]) });
    else entries.push({ kind: 'timeout', tank: mine[0] ?? 0, async: 1 });
  } else entries.push(aim(r.int(0, scene.seats.length - 1)));
  const first = entries[0];
  const followCpu = cpuSeats.length > 0 && !SHOP.includes(first.kind as string) && first.kind !== 'auto_shop';
  for (let i = r.chance(0.5) && followCpu ? r.int(1, 3) : 0; i > 0; i -= 1) {
    entries.push({ kind: 'auto', tank: r.pick(cpuSeats), level: lvl(cpuSeats[0]) });
  }
  const out: Obj = {};
  entries.forEach((e, i) => {
    out[M(`actions/${scene.count + i}`)] = e;
  });
  out[M('meta/actionCount')] = scene.count + entries.length;
  if (r.chance(0.85)) {
    const tank = r.chance(0.15) ? r.pick([-2, -1]) : r.int(0, scene.seats.length - 1);
    const seat = scene.seats[tank];
    const t: Obj = {
      tank,
      uid: tank < 0 ? 'any' : seat?.kind === 'cpu' ? 'cpu' : seat?.uid,
      deadline: tank === -1 ? 0 : now + r.pick([60000, HOUR, 71 * HOUR]),
      index: (scene.turn.index as number) + 1,
    };
    if (tank >= 0 && r.chance(0.4)) t.liveDeadline = now + r.pick([5000, 30000]);
    out[M('meta/turn')] = t;
  }
  if (r.chance(0.05)) out[M('meta/status')] = 'over';
  // mutations: some updates stay perfectly valid
  for (let m = r.pick([0, 0, 0, 1, 1, 2]); m > 0; m -= 1) {
    const keys = Object.keys(out);
    const key = r.pick(keys);
    const how = r.int(0, 5);
    if (how === 0 && typeof out[key] === 'object' && out[key] !== null && !Array.isArray(out[key])) {
      const o = { ...(out[key] as Obj) };
      const field = r.pick(Object.keys(o));
      o[field] = genValue(r);
      out[key] = o;
    } else if (how === 1) delete out[key];
    else if (how === 2) out[key] = genValue(r);
    else if (how === 3) out[M(`actions/${scene.count + r.int(-1, 18)}`)] = aim(r.int(0, 3));
    else if (how === 4 && out[M('meta/actionCount')] !== undefined) out[M('meta/actionCount')] = (out[M('meta/actionCount')] as number) + r.pick([-1, 1, 3]);
    else out[M(`meta/${r.pick(['status', 'turn/index', 'settings/rounds'])}`)] = genValue(r);
  }
  return out;
}

function validMisc(r: Rand, scene: Scene, actor: string | null): Obj {
  const who = actor ?? 'host';
  switch (r.int(0, 6)) {
    case 0: return { [M(`presence/${who}`)]: serverTimestamp() };
    case 1: {
      const key = `m${r.int(0, 99999)}`;
      return { [M(`lastMsg/${who}`)]: serverTimestamp(), [M(`lastMsgKey/${who}`)]: key, [M(`msgs/${key}`)]: { uid: who, seat: scene.seats.findIndex((s) => s.uid === who), msg: r.int(0, 7), at: serverTimestamp() } };
    }
    case 2: return { [M(`fp/${r.int(0, Math.max(0, scene.count - 1))}/${who}`)]: '0123456789abcdef' };
    case 3: return { [`users/${who}/name`]: r.pick(['Anna', 'Bo', 'X'.repeat(12), '😀😀😀😀😀😀', 'a b c']) };
    case 4: return { [`users/${who}/protocol`]: r.int(0, 5) };
    case 5: return { [`users/${who}/fcm/${String(r.int(0, 99999999)).padStart(8, '0')}`]: 'x'.repeat(30) };
    default: return { [`invites/${who}/M9`]: null, [`userMatches/${who}/${MID}`]: r.chance(0.5) ? null : { updated: 1, yourTurn: true, status: 'over' } };
  }
}

function genUpdate(r: Rand, scene: Scene, actor: string | null): Obj {
  const mode = r.int(0, 9);
  if (mode <= 5) return validAppend(r, scene, actor);
  if (mode === 6 || mode === 7) return validMisc(r, scene, actor);
  const out: Obj = {};
  const parts = r.int(1, 3);
  for (let p = 0; p < parts; p += 1) {
    const which = r.int(0, 15);
    if (which <= 5) {
      // a log append, plausibly shaped for the current turn
      const turnTank = scene.turn.tank as number;
      const k = r.chance(0.08) ? r.int(15, 19) : r.int(1, 3);
      const entries: Obj[] = [];
      for (let i = 0; i < k; i += 1) {
        const prefer: number = i === 0 ? (turnTank >= 0 ? turnTank : -1) : scene.seats.findIndex((s) => s.kind === 'cpu');
        entries.push(genEntry(r, scene.seats, prefer >= 0 ? prefer : null));
      }
      const start = scene.count + (r.chance(0.9) ? 0 : r.pick([-1, 1, 2]));
      entries.forEach((e, i) => {
        out[M(`actions/${start + i}`)] = e;
      });
      out[M('meta/actionCount')] = r.chance(0.9) ? start + k : start + k + r.pick([-1, 1, 5]);
      if (r.chance(0.6)) out[M('meta/turn')] = plausibleTurn(r, scene);
      if (r.chance(0.07)) out[M('meta/status')] = r.pick(['over', 'abandoned', 'playing']);
    } else if (which === 6) {
      out[M('meta/turn')] = r.chance(0.5) ? plausibleTurn(r, scene) : genValue(r);
    } else if (which === 7) {
      out[M('meta/status')] = r.pick(['over', 'abandoned', 'playing', 'lobby', 'x']);
    } else if (which === 8) {
      const sub = r.pick(['settings/rounds', 'seats/1/uid', 'seats/2/level', 'timers/liveSec', 'hostUid', 'seed', 'protocol', 'code', 'turn/index', 'turn/deadline', 'turn/uid']);
      out[M(`meta/${sub}`)] = genValue(r);
    } else if (which === 9) {
      out[M(`presence/${r.pick(['host', 'bob', 'cat', actor ?? 'host'])}`)] = r.chance(0.6) ? serverTimestamp() : genValue(r);
    } else if (which === 10) {
      out[M(`fp/${r.int(0, scene.count + 2)}/${r.pick(['host', 'bob', 'cat'])}`)] = r.chance(0.7) ? r.pick(['0123456789abcdef', 'deadbeefdeadbeef', 'XYZ', '0123456789abcdeF']) : genValue(r);
    } else if (which === 11) {
      const n = r.chance(0.1) ? r.int(2, 4) : 1;
      const keys: string[] = [];
      for (let i = 0; i < n; i += 1) {
        const key = `m${r.int(0, 9999)}`;
        keys.push(key);
        out[M(`msgs/${key}`)] = r.chance(0.8) ? { uid: r.chance(0.9) ? actor : 'bob', seat: r.pick([0, 0, 1, 3, 9]), msg: r.pick([0, 3, 7, 8, -1, 1.5]), at: serverTimestamp() } : genValue(r);
      }
      if (r.chance(0.85)) out[M(`lastMsg/${actor ?? 'host'}`)] = serverTimestamp();
      if (r.chance(0.85)) out[M(`lastMsgKey/${actor ?? 'host'}`)] = r.chance(0.9) ? keys[0] : `m${r.int(0, 9999)}`;
    } else if (which === 12) {
      out[`users/${r.pick(['host', 'bob', 'cat', actor ?? 'bob'])}/${r.pick(['name', 'protocol', 'full', 'nameHidden', 'friendCode', 'created', 'purchase'])}`] = r.pick(['NEW', 'X'.repeat(13), 3, true, 'AAAAAAAA', 99999999]);
    } else if (which === 13) {
      const key = String(r.int(0, 999999)).padStart(8, '0');
      out[`users/${actor ?? 'bob'}/fcm/${r.chance(0.9) ? key : 'bad'}`] = r.chance(0.9) ? 'x'.repeat(r.pick([19, 20, 200])) : genValue(r);
    } else if (which === 14) {
      out[r.pick([`userMatches/${actor ?? 'bob'}/${MID}`, `userMatches/cat/${MID}`, `invites/${actor ?? 'bob'}/M9`, `friends/host/bob`, `blocks/${actor ?? 'bob'}/host`, `friendRequests/bob/cat`, `friendCodes/ZZZZZZZZ`, 'matchCodes/ZZZZZZ'])] = r.chance(0.5) ? null : genValue(r);
    } else {
      out[r.pick(['matches/M2/meta/status', `matches/${MID}/extra`, 'extra/x', `matches/${MID}/meta/actionCount`, 'sweepQueue/M1'])] = genValue(r);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------------------------------------------
describe('QA rules fuzz: every write that succeeds is one the contract permits', function () {
  useRulesEnv();
  this.timeout(600000);

  it('runs random multi-path writes and checks each success against the model', async () => {
    const seedValue = Number(process.env.QA_FUZZ_SEED ?? 20261006);
    const total = Number(process.env.QA_FUZZ_N ?? 700);
    const r = new Rand(mulberry32(seedValue));
    const stats = { attempted: 0, sdkRefused: 0, denied: 0, succeeded: 0, byTag: {} as Record<string, number>, byActor: {} as Record<string, number> };
    const problems: string[] = [];
    for (let n = 0; n < total; n += 1) {
      const scene = genScene(r);
      const actor = r.pick(ACTORS);
      const updateValues = genUpdate(r, scene, actor);
      const db = actor === null ? anonymous() : as(actor);
      await testEnv().clearDatabase();
      await seedUsers();
      await seedMatch({ seats: scene.seats, actionCount: scene.count, turn: scene.turn as never, status: scene.status, presence: scene.presence, members: ['host', 'bob'] });
      await seed({ 'invites/bob/M9': { fromUid: 'host', fromName: 'HOST', at: 1, code: 'ABC234', mode: 0 }, [`userMatches/cat/${MID}`]: null });
      if (r.chance(0.3)) await seed({ [M('lastMsg/host')]: Date.now() - r.pick([100, 2000, 4000]), [M('lastMsg/bob')]: Date.now() - r.pick([100, 4000]) });
      const before = await snapshot();
      const t0 = Date.now();
      stats.attempted += 1;
      let ok = false;
      try {
        await update(ref(db), updateValues);
        ok = true;
      } catch (error) {
        const text = String((error as Error).message);
        if (/PERMISSION_DENIED|permission_denied/i.test(text)) stats.denied += 1;
        else stats.sdkRefused += 1;
      }
      const t1 = Date.now();
      if (!ok) continue;
      stats.succeeded += 1;
      stats.byActor[String(actor)] = (stats.byActor[String(actor)] ?? 0) + 1;
      const after = await snapshot();
      const verdict = judge(before, after, actor, { t0, t1 });
      for (const tag of verdict.tags) stats.byTag[tag] = (stats.byTag[tag] ?? 0) + 1;
      if (verdict.violations.length > 0) {
        problems.push(`#${n} actor=${String(actor)} violations=${JSON.stringify(verdict.violations)}\n   update=${JSON.stringify(updateValues)}\n   scene=${JSON.stringify({ count: scene.count, turn: scene.turn, status: scene.status, presence: scene.presence })}`);
      }
    }
    console.log(`      fuzz seed=${seedValue}: ${JSON.stringify(stats)}`);
    assert.ok(stats.succeeded >= 150, `the fuzz must produce successful writes to be meaningful (got ${stats.succeeded})`);
    assert.deepEqual(problems, [], `${problems.length} write(s) the contract does not permit were accepted:\n${problems.slice(0, 5).join('\n')}`);
  });
});

// ---------------------------------------------------------------------------------------------------------------
// The model must itself be able to see violations (otherwise "no violations" proves nothing)
// ---------------------------------------------------------------------------------------------------------------
describe('QA rules fuzz: the contract model catches what it should (self-check, no database)', () => {
  const now = Date.now();
  const world = (extra: Obj = {}): Obj => ({
    users: { host: { friendCode: 'H', name: 'H' }, bob: { friendCode: 'B', name: 'B' } },
    userMatches: { host: { [MID]: { status: 'playing' } }, bob: { [MID]: { status: 'playing' } } },
    matches: {
      [MID]: {
        meta: {
          hostUid: 'host', status: 'playing', actionCount: 1, timers: { liveSec: 60, asyncHours: 72 },
          seats: [{ kind: 'human', uid: 'host' }, { kind: 'human', uid: 'bob' }, { kind: 'cpu', level: 2 }],
          turn: { tank: 0, uid: 'host', deadline: now + HOUR, index: 1 },
          ...extra,
        },
        actions: { 0: { kind: 'pass', tank: 0 } },
      },
    },
  });
  const w = { t0: now, t1: now + 50 };
  const withMeta = (b: Obj, patch: (m: Obj) => void): Obj => {
    const copy = JSON.parse(JSON.stringify(b)) as Obj;
    patch(((copy.matches as Obj)[MID] as Obj).meta as Obj);
    return copy;
  };
  const withActions = (b: Obj, add: Obj): Obj => {
    const copy = JSON.parse(JSON.stringify(b)) as Obj;
    Object.assign(((copy.matches as Obj)[MID] as Obj).actions as Obj, add);
    return copy;
  };

  it('accepts an honest append and rejects out-of-turn, over-long and unaccompanied changes', () => {
    const b = world();
    const honest = withMeta(withActions(b, { 1: { kind: 'pass', tank: 0 } }), (m) => {
      m.actionCount = 2;
      m.turn = { tank: 1, uid: 'bob', deadline: now + HOUR, index: 2 };
    });
    assert.deepEqual(judge(b, honest, 'host', w).violations, []);
    assert.notDeepEqual(judge(b, honest, 'bob', w).violations, []); // bob does not hold tank 0
    const outOfTurn = withMeta(withActions(b, { 1: { kind: 'pass', tank: 1 } }), (m) => { m.actionCount = 2; });
    assert.notDeepEqual(judge(b, outOfTurn, 'bob', w).violations, []);
    const noCount = withActions(b, { 1: { kind: 'pass', tank: 0 } });
    assert.notDeepEqual(judge(b, noCount, 'host', w).violations, []);
    const seventeen: Obj = {};
    for (let i = 1; i <= 17; i += 1) seventeen[i] = i === 1 ? { kind: 'pass', tank: 0 } : { kind: 'auto', tank: 2, level: 2 };
    assert.ok(judge(b, withMeta(withActions(b, seventeen), (m) => { m.actionCount = 18; }), 'host', w).violations.some((x) => x.includes('17 entries')));
    const rewrite = JSON.parse(JSON.stringify(b)) as Obj;
    (((rewrite.matches as Obj)[MID] as Obj).actions as Obj)[0] = { kind: 'pass', tank: 1 };
    assert.ok(judge(b, rewrite, 'host', w).violations.some((x) => x.includes('existing log entry')));
  });

  it('flags forbidden paths, wrong status transitions, forged presence and a fake auto', () => {
    const b = world();
    assert.notDeepEqual(judge(b, withMeta(b, (m) => { m.hostUid = 'bob'; }), 'bob', w).violations, []);
    assert.notDeepEqual(judge(b, withMeta(b, (m) => { m.status = 'over'; }), 'host', w).violations, []);
    const forged = JSON.parse(JSON.stringify(b)) as Obj;
    ((forged.matches as Obj)[MID] as Obj).presence = { host: 5 };
    assert.ok(judge(b, forged, 'host', w).violations.some((x) => x.includes('presence value')));
    const fake = withMeta(withActions(b, { 1: { kind: 'pass', tank: 0 }, 2: { kind: 'auto', tank: 1, level: 2 } }), (m) => { m.actionCount = 3; });
    assert.ok(judge(b, fake, 'host', w).violations.some((x) => x.includes('later entry')));
    const stolen = JSON.parse(JSON.stringify(b)) as Obj;
    (stolen.users as Obj).bob = { friendCode: 'B', name: 'B', full: true };
    assert.ok(judge(b, stolen, 'bob', w).violations.some((x) => x.includes('full')));
  });

  it('flags the holes that are now closed: a stale turn, a CPU level the seat does not have, a batch of messages', () => {
    const b = world();
    const stale = withMeta(withActions(b, { 1: { kind: 'pass', tank: 0 } }), (m) => {
      m.actionCount = 2;
      m.turn = { tank: 1, uid: 'bob', deadline: now - 100000, index: 2 };
    });
    assert.ok(judge(b, stale, 'host', w).violations.some((x) => x.includes('deadline')));
    const recent = withMeta(withActions(b, { 1: { kind: 'pass', tank: 0 } }), (m) => {
      m.actionCount = 2;
      m.turn = { tank: 1, uid: 'bob', deadline: now - 1000, index: 2 };
    });
    assert.deepEqual(judge(b, recent, 'host', w).violations, []); // inside the 5 s of latency slack
    const lvl = withMeta(withActions(b, { 1: { kind: 'pass', tank: 0 }, 2: { kind: 'auto', tank: 2, level: 4 } }), (m) => { m.actionCount = 3; });
    assert.ok(judge(b, lvl, 'host', w).violations.some((x) => x.includes('level')));
    const flood = JSON.parse(JSON.stringify(b)) as Obj;
    const mm = (flood.matches as Obj)[MID] as Obj;
    mm.lastMsg = { host: now };
    mm.lastMsgKey = { host: 'a' };
    mm.msgs = { a: { uid: 'host', seat: 0, msg: 1, at: now }, b: { uid: 'host', seat: 0, msg: 1, at: now } };
    assert.ok(judge(b, flood, 'host', w).violations.some((x) => x.includes('2 messages')));
  });
});
