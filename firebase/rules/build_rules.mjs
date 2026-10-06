// Generates ../database.rules.json (ARCHITECTURE sections 44-46).
//
//   node rules/build_rules.mjs           write database.rules.json
//   node rules/build_rules.mjs --check   exit 1 when the committed file is out of date (CI and test.sh)
//
// Why a generator: the action log rules need the same condition repeated for every position in a batch
// (rules have no loops), and named pieces such as `isMember` are far easier to review than one long string.
// Read the pieces in the first half of this file; the tree at the bottom only wires them to paths.
//
// How the rules see a multi-path update (verified in the emulator, see test/rules): `data` and `root` are the
// database BEFORE the write, `newData` is what the node will hold AFTER it, and `newData.parent()` sees the other
// paths of the same update. That is what lets "actions/k + actionCount + turn in one update" be checked atomically.
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// ---------------------------------------------------------------------------------------------------------------
// Numbers shared with ARCHITECTURE and the client. Change them here and in docs/ARCHITECTURE.md together.
// ---------------------------------------------------------------------------------------------------------------
const MAX_TANKS = 8; // SimConstants.MAX_TANKS
const MAX_BATCH = 16; // most log entries one update may append (1 human action + CPU turns + CPU shop visits)
const PRESET_COUNT = 8; // quick messages in the client preset table (section 48)
const MSG_INTERVAL_MS = 3000; // one quick message per 3 s per player
const PRESENCE_FRESH_MS = 75000; // "online" means a heartbeat younger than this (section 45)
const DEADLINE_SLACK_MS = 120000; // allowed client clock error when a deadline is written
const NAME_MAX = 12; // NameFilter.MAX_LENGTH
const PROTOCOL_MAX = 1000000;
const MAX_ANGLE = 1800; // SimConstants.MAX_ANGLE
const MAX_POWER = 1000; // SimConstants.MAX_POWER
const MOVE_MAX_DX = 200; // SimConstants.MOVE_MAX_DX
const MAX_QTY = 99; // SimConstants.INVENTORY_CAP

// Turn markers in meta/turn.tank (section 46).
const TURN_NEEDS_RESOLVE = -1; // a client must replay, append CPU entries and set the real turn
const TURN_SHOP = -2; // the shop phase: every human seat may buy, sell and ready

// ---------------------------------------------------------------------------------------------------------------
// Small helpers that build rule expressions
// ---------------------------------------------------------------------------------------------------------------
const and = (...parts) => `(${parts.join(' && ')})`;
const or = (...parts) => `(${parts.join(' || ')})`;
const oneLine = (text) => text.replace(/\s+/g, ' ').trim();

const signedIn = 'auth != null';
const isInt = (v) => `${v}.isNumber() && ${v}.val() % 1 == 0`;
const intBetween = (v, lo, hi) => `${isInt(v)} && ${v}.val() >= ${lo} && ${v}.val() <= ${hi}`;
const isWord = (v, maxLen = 32) => `${v}.isString() && ${v}.val().matches(/^[a-z][a-z0-9_]{0,${maxLen - 1}}$/)`;

/** True when a block exists between the two uids, in either direction. */
const blockedBetween = (a, b) =>
  or(
    `root.child('blocks').child(${a}).child(${b}).exists()`,
    `root.child('blocks').child(${b}).child(${a}).exists()`,
  );

// ---------------------------------------------------------------------------------------------------------------
// Match-level pieces. They are used below the `matches/$mid` wildcard, so `$mid` is in scope.
// ---------------------------------------------------------------------------------------------------------------
const META = "root.child('matches').child($mid).child('meta')";
/** Membership is the server-written `userMatches/{uid}/{matchId}` entry (created by createMatch / joinMatch). */
const isMember = and(signedIn, "root.child('userMatches').child(auth.uid).child($mid).exists()");
const status = `${META}.child('status').val()`;
const isPlaying = `${status} == 'playing'`;

const OLD_COUNT = `${META}.child('actionCount').val()`;
const turnOf = (field) => `${META}.child('turn').child('${field}').val()`;
const turnTank = turnOf('tank');
const seatField = (tankExpr, field, base = META) => `${base}.child('seats').child(${tankExpr} + '').child('${field}').val()`;

// The entry being written, at actions/$i.
const entry = (field) => `newData.child('${field}').val()`;
const eKind = entry('kind');
const eTank = entry('tank');
const eSeatUid = seatField(eTank, 'uid');
const eSeatKind = seatField(eTank, 'kind');
const AIM_KINDS = ['fire', 'move', 'use_item', 'pass'];
const SHOP_KINDS = ['buy', 'sell', 'ready'];
const kindIn = (kinds) => or(...kinds.map((k) => `${eKind} == '${k}'`));

/** Heartbeat of the turn holder is fresh (so a live skip is fair). */
const holderOnline = and(
  `root.child('matches').child($mid).child('presence').child(${turnOf('uid')}).exists()`,
  `now - root.child('matches').child($mid).child('presence').child(${turnOf('uid')}).val() < ${PRESENCE_FRESH_MS}`,
);
/**
 * A timeout entry comes in two kinds (ARCHITECTURE 52):
 *  - `async: 1`  after the hard deadline: the AI plays the turn (or the match ends);
 *  - without it  a live skip, after the live deadline and only while the turn holder's heartbeat is fresh.
 */
const timeoutDue = or(
  and(`newData.hasChild('async')`, `now > ${turnOf('deadline')}`),
  and(
    `!newData.hasChild('async')`,
    `${META}.child('turn').child('liveDeadline').exists()`,
    `now > ${turnOf('liveDeadline')}`,
    holderOnline,
  ),
);

/** Conditions for the FIRST entry of an update (it is judged against the turn as it is now). */
const firstEntryOk = or(
  and(kindIn(AIM_KINDS), `${turnTank} >= 0`, `${eTank} == ${turnTank}`, `${eSeatUid} == auth.uid`),
  and(kindIn(SHOP_KINDS), `${turnTank} == ${TURN_SHOP}`, `${eSeatUid} == auth.uid`),
  and(
    `${eKind} == 'auto'`,
    `${eSeatKind} == 'cpu'`,
    or(`${turnTank} == ${TURN_NEEDS_RESOLVE}`, and(`${eTank} == ${turnTank}`, `${turnOf('uid')} == 'cpu'`)),
  ),
  and(`${eKind} == 'auto_shop'`, `${eSeatKind} == 'cpu'`, or(`${turnTank} == ${TURN_NEEDS_RESOLVE}`, `${turnTank} == ${TURN_SHOP}`)),
  and(
    `${eKind} == 'timeout'`,
    `${eSeatKind} == 'human'`, // a CPU seat never times out: its turns are `auto` entries
    or(and(`${turnTank} >= 0`, `${eTank} == ${turnTank}`), `${turnTank} == ${TURN_SHOP}`),
    timeoutDue,
  ),
);
/** Entries after the first one in the same update: the CPU turns that follow, or more shop entries by the same player. */
const followingEntryOk = or(
  and(kindIn(SHOP_KINDS), `${turnTank} == ${TURN_SHOP}`, `${eSeatUid} == auth.uid`),
  and(kindIn(['auto', 'auto_shop']), `${eSeatKind} == 'cpu'`),
);

// Where the new actionCount sits relative to the current one, seen from actions/$i.
const NEW_COUNT_FROM_ACTION = "newData.parent().parent().child('meta').child('actionCount').val()";
const indexIs = (offset) => `$i == (${OLD_COUNT} + ${offset}) + ''`;
const followingIndex = or(
  ...Array.from({ length: MAX_BATCH - 1 }, (_, n) => and(indexIs(n + 1), `${NEW_COUNT_FROM_ACTION} > ${OLD_COUNT} + ${n + 1}`)),
);

const actionWrite = oneLine(`
  ${signedIn} && !data.exists() && newData.exists() && ${isPlaying} && ${isMember} && (
    (${indexIs(0)} && ${NEW_COUNT_FROM_ACTION} > ${OLD_COUNT} && ${firstEntryOk})
    || (${followingIndex} && ${followingEntryOk})
  )
`);

// Entry shape: exactly the fields of one kind, each inside its legal range (section 19 and 46).
const ENTRY_KINDS = {
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
// Fields a kind may carry in addition (all optional).
const OPTIONAL_FIELDS = { timeout: ['async'] };
const ENTRY_FIELDS = ['tank', 'angle', 'power', 'weapon', 'dx', 'item', 'qty', 'level', 'async'];
const entryShape = oneLine(
  or(
    ...Object.entries(ENTRY_KINDS).map(([kind, fields]) =>
      and(
        `${eKind} == '${kind}'`,
        `newData.hasChildren([${['kind', ...fields].map((f) => `'${f}'`).join(', ')}])`,
        ...ENTRY_FIELDS.filter((f) => !fields.includes(f) && !(OPTIONAL_FIELDS[kind] ?? []).includes(f)).map((f) => `!newData.hasChild('${f}')`),
      ),
    ),
  ),
);
const actionFields = {
  kind: { '.validate': `newData.isString() && newData.val().matches(/^(${Object.keys(ENTRY_KINDS).join('|')})$/)` },
  tank: { '.validate': intBetween('newData', 0, MAX_TANKS - 1) },
  angle: { '.validate': intBetween('newData', 0, MAX_ANGLE) },
  power: { '.validate': intBetween('newData', 1, MAX_POWER) },
  weapon: { '.validate': isWord('newData') },
  dx: { '.validate': `${intBetween('newData', -MOVE_MAX_DX, MOVE_MAX_DX)} && newData.val() != 0` },
  item: { '.validate': isWord('newData') },
  qty: { '.validate': intBetween('newData', 1, MAX_QTY) },
  level: { '.validate': intBetween('newData', 1, 4) }, // CPU level: CTRL_EASY..CTRL_EXPERT
  async: { '.validate': intBetween('newData', 1, 1) }, // timeout entries only: written after the hard deadline
  $other: { '.validate': false },
};

// meta/actionCount, meta/turn and meta/status are the only meta fields a client may touch, and only together
// with a new log entry (or, for the turn, to resolve a "needs resolve" marker).
const countBump = (newData) => `${newData}.child('actionCount').val() > ${OLD_COUNT}`;
const everyNewEntryExists = and(
  ...Array.from({ length: MAX_BATCH }, (_, n) =>
    or(
      `newData.val() <= data.val() + ${n}`,
      `newData.parent().parent().child('actions').child((data.val() + ${n}) + '').exists()`,
    ),
  ),
);
const actionCountRule = {
  '.write': oneLine(`
    ${signedIn} && newData.exists() && ${isPlaying} && ${isMember} && data.isNumber()
    && newData.val() > data.val() && newData.val() <= data.val() + ${MAX_BATCH} && ${everyNewEntryExists}
  `),
  '.validate': isInt('newData'),
};

const nTank = "newData.child('tank').val()";
const nUid = "newData.child('uid').val()";
const nDeadline = "newData.child('deadline').val()";
const nLive = "newData.child('liveDeadline').val()";
const turnRule = {
  '.write': oneLine(`
    ${signedIn} && newData.exists() && ${isPlaying} && ${isMember}
    && (${countBump("newData.parent()")} || ${turnTank} == ${TURN_NEEDS_RESOLVE})
  `),
  '.validate': oneLine(`
    newData.hasChildren(['tank', 'uid', 'deadline', 'index'])
    && ${or(
      and(`${nTank} < 0`, `${nUid} == 'any'`),
      and(
        `${nTank} >= 0`,
        or(`${nUid} == ${seatField(nTank, 'uid')}`, and(`${nUid} == 'cpu'`, `${seatField(nTank, 'kind')} == 'cpu'`)),
      ),
    )}
    && ${or(
      and(`${nTank} == ${TURN_NEEDS_RESOLVE}`, `${nDeadline} == 0`),
      and(
        `${nTank} != ${TURN_NEEDS_RESOLVE}`,
        `${nDeadline} >= now - ${DEADLINE_SLACK_MS}`,
        `${nDeadline} <= now + ${META}.child('timers').child('asyncHours').val() * 3600000 + ${DEADLINE_SLACK_MS}`,
      ),
    )}
    && ${or(
      `!newData.hasChild('liveDeadline')`,
      and(
        `${nTank} >= 0`,
        `${nLive} >= now - ${DEADLINE_SLACK_MS}`,
        `${nLive} <= now + ${META}.child('timers').child('liveSec').val() * 1000 + ${DEADLINE_SLACK_MS}`,
      ),
    )}
    && newData.child('index').val() == ${turnOf('index')} + 1
  `),
  tank: { '.validate': intBetween('newData', -2, MAX_TANKS - 1) },
  uid: { '.validate': 'newData.isString() && newData.val().length >= 1 && newData.val().length <= 64' },
  deadline: { '.validate': isInt('newData') },
  liveDeadline: { '.validate': isInt('newData') },
  index: { '.validate': `${isInt('newData')} && newData.val() >= 0` },
  $other: { '.validate': false },
};
const statusRule = {
  '.write': oneLine(`
    ${signedIn} && newData.exists() && (
      (newData.val() == 'over' && data.val() == 'playing' && ${isMember} && ${countBump('newData.parent()')})
      || (newData.val() == 'abandoned' && ${META}.child('hostUid').val() == auth.uid
          && (data.val() == 'playing' || data.val() == 'lobby'))
    )
  `),
  '.validate': "newData.isString() && newData.val().matches(/^(over|abandoned)$/)",
};

// Quick messages: one per MSG_INTERVAL_MS per player, kept in matches/$mid/lastMsg/$uid.
const msgSeatUid = seatField("newData.child('seat').val()", 'uid');
const lastMsgOf = (base, uidExpr) => `${base}.child('lastMsg').child(${uidExpr})`;
const msgRule = {
  '.write': oneLine(`
    ${signedIn} && !data.exists() && newData.exists() && ${isPlaying} && ${isMember} && $pid.length <= 30
    && ${lastMsgOf("newData.parent().parent()", 'auth.uid')}.val() == now
    && (!${lastMsgOf("root.child('matches').child($mid)", 'auth.uid')}.exists()
        || now >= ${lastMsgOf("root.child('matches').child($mid)", 'auth.uid')}.val() + ${MSG_INTERVAL_MS})
  `),
  '.validate': oneLine(`
    newData.hasChildren(['uid', 'seat', 'msg', 'at']) && newData.child('uid').val() == auth.uid
    && ${msgSeatUid} == auth.uid
  `),
  uid: { '.validate': 'newData.isString()' },
  seat: { '.validate': intBetween('newData', 0, MAX_TANKS - 1) },
  msg: { '.validate': intBetween('newData', 0, PRESET_COUNT - 1) },
  at: { '.validate': 'newData.val() == now' },
  $other: { '.validate': false },
};

// ---------------------------------------------------------------------------------------------------------------
// Account-level pieces
// ---------------------------------------------------------------------------------------------------------------
const isOwner = (uid) => and(signedIn, `auth.uid == ${uid}`);
/** Someone may see a user's public fields unless a block exists between the two of them. */
const mayReadProfile = and(signedIn, `!${blockedBetween('auth.uid', '$uid')}`);
const hasProfile = "root.child('users').child($uid).child('friendCode').exists()";

const rules = {
  rules: {
    // Everything not listed here is closed to clients (Admin SDK code in functions bypasses rules).
    '.read': false,
    '.write': false,

    // ---- users/{uid}: the owner reads all of it; others may read only the public fields below. --------------
    users: {
      $uid: {
        '.read': isOwner('$uid'),
        // Name: the client writes it (1..12 chars), a function re-checks it with the shared blocklist.
        name: {
          '.read': mayReadProfile,
          '.write': and(isOwner('$uid'), hasProfile, 'newData.exists()'),
          '.validate': `newData.isString() && newData.val().length >= 1 && newData.val().length <= ${NAME_MAX}`,
        },
        // Server-only: nameHidden (3 reports), friendCode, created, full (purchase). The owner reads them via $uid.
        nameHidden: { '.read': mayReadProfile },
        protocol: {
          '.read': mayReadProfile,
          '.write': and(isOwner('$uid'), hasProfile, 'newData.exists()'),
          '.validate': intBetween('newData', 0, PROTOCOL_MAX),
        },
        fcm: {
          $tokenHash: {
            '.write': and(isOwner('$uid'), hasProfile),
            '.validate': `$tokenHash.matches(/^[A-Za-z0-9_-]{8,64}$/) && newData.isString() && newData.val().length >= 20 && newData.val().length <= 4096`,
          },
        },
      },
    },

    // ---- friends, blocks, requests, invites, reports: all writes go through callable functions. ------------
    friendCodes: { '.read': false, '.write': false },
    friendRequests: { $to: { '.read': isOwner('$to'), '.write': false } },
    friends: { $uid: { '.read': isOwner('$uid'), '.write': false } },
    blocks: { $uid: { '.read': isOwner('$uid'), '.write': false } },
    invites: {
      $to: {
        '.read': isOwner('$to'),
        '.indexOn': ['at'],
        // The recipient may dismiss an invite; creating one is the `invite` function's job (it checks friendship and blocks).
        $matchId: { '.write': and(isOwner('$to'), '!newData.exists()') },
      },
    },
    reports: { '.read': false, '.write': false, '.indexOn': ['targetUid', 'at'] },
    nameReports: { '.read': false, '.write': false },
    // Emulator test data written by the mocked push sender; closed to clients, indexed so tests can query it.
    _test: { fcm: { '.read': false, '.write': false, '.indexOn': ['uid'] } },

    // ---- matches ------------------------------------------------------------------------------------------
    matchCodes: { '.read': false, '.write': false },
    sweepQueue: { '.read': false, '.write': false, '.indexOn': '.value' },

    // Reads are granted per child, not on matches/$mid, so a presence read can still be refused for a blocked pair.
    matches: {
      $mid: {
        meta: {
          '.read': isMember,
          actionCount: actionCountRule,
          turn: turnRule,
          status: statusRule,
        },
        actions: {
          '.read': isMember,
          $i: { '.write': actionWrite, '.validate': entryShape, ...actionFields },
        },
        fp: {
          '.read': isMember,
          $i: {
            $uid: {
              '.write': oneLine(`
                ${isOwner('$uid')} && !data.exists() && newData.exists() && ${isMember}
                && root.child('matches').child($mid).child('actions').child($i).exists()
              `),
              '.validate': 'newData.isString() && newData.val().matches(/^[0-9a-f]{16}$/)',
            },
          },
        },
        presence: {
          $uid: {
            '.read': and(isMember, `!${blockedBetween('auth.uid', '$uid')}`),
            '.write': and(isOwner('$uid'), isMember, 'newData.exists()'),
            '.validate': 'newData.val() == now',
          },
        },
        msgs: { '.read': isMember, $pid: msgRule },
        lastMsg: {
          '.read': isMember,
          $uid: {
            '.write': and(isOwner('$uid'), isMember, 'newData.exists()', `(!data.exists() || now >= data.val() + ${MSG_INTERVAL_MS})`),
            '.validate': 'newData.val() == now',
          },
        },
      },
    },

    userMatches: {
      $uid: {
        '.read': isOwner('$uid'),
        '.indexOn': ['updated'],
        // The owner may remove a finished match from the list. Everything else is written by functions.
        $mid: {
          '.write': and(
            isOwner('$uid'),
            '!newData.exists()',
            or("data.child('status').val() == 'over'", "data.child('status').val() == 'abandoned'"),
          ),
        },
      },
    },
  },
};

// Rules JSON must not contain `undefined` (JSON.stringify would drop the key silently), so fail loudly instead.
function failOnUndefined(key, value) {
  if (value === undefined) throw new Error(`undefined rule at "${key}"`);
  return value;
}
const text = `${JSON.stringify(rules, failOnUndefined, 2)}\n`;
const target = join(dirname(fileURLToPath(import.meta.url)), '..', 'database.rules.json');

if (process.argv.includes('--check')) {
  let current;
  try {
    current = readFileSync(target, 'utf8');
  } catch {
    current = '';
  }
  if (current !== text) {
    console.error('database.rules.json is out of date. Run: npm run rules:build (in firebase/) and commit the result.');
    process.exit(1);
  }
  console.log('database.rules.json is up to date');
} else {
  writeFileSync(target, text);
  console.log(`wrote ${target}`);
}
