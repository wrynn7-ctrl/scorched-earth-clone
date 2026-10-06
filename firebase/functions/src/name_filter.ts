// Server-side port of game/ui/names/name_filter.gd (NameFilter). Pure and dependency-free, so the unit tests can run
// it without an emulator. Keep it in step with the GDScript file: the same cleaning rules, the same folding of case,
// accents and look-alike symbols, the same blocklist (generated into name_blocklist.json by
// tools/firebase/gen_name_blocklist.mjs). The test file mirrors test_name_filter.gd case by case.
//
// One deliberate difference: the game also drops characters its font cannot draw (it asks the font). A server has no
// font, so it keeps the structural rules exactly and then allows only Latin-script ranges (the range the game font
// covers). A glyph the font lacks would draw as an empty box, which is cosmetic, never a safety problem.
import blocklist from './name_blocklist.json';

export const MAX_LENGTH = 12;
export const FALLBACK_NAME = 'PLAYER';
const MIN_REAL_LETTERS = 2;
const WILDCARD = '?';
const MASKS: readonly string[] = ['*', '#', '%', '?'];
const LEET: Readonly<Record<string, string>> = {
  '0': 'o',
  '3': 'e',
  '4': 'a',
  '5': 's',
  '7': 't',
  '@': 'a',
  $: 's',
  '!': 'i',
  '8': 'b',
  '9': 'g',
  '+': 't',
  '(': 'c',
};
const ACCENTS: Readonly<Record<string, string>> = {
  a: 'àáâãäå',
  c: 'ç',
  e: 'èéêë',
  i: 'ìíîï',
  n: 'ñ',
  o: 'òóôõöø',
  u: 'ùúûü',
  y: 'ýÿ',
};
/** Latin-script code point ranges (inclusive) a name may use, besides the structural exclusions below. */
const LATIN_RANGES: readonly (readonly [number, number])[] = [
  [0x20, 0x7e],
  [0xa1, 0xff],
  [0x131, 0x131],
  [0x152, 0x153],
  [0x2bb, 0x2bc],
  [0x2c6, 0x2c6],
  [0x2da, 0x2da],
  [0x2dc, 0x2dc],
  [0x2000, 0x206f],
  [0x20ac, 0x20ac],
  [0x2122, 0x2122],
  [0x2191, 0x2191],
  [0x2193, 0x2193],
  [0x2212, 0x2212],
  [0x2215, 0x2215],
];

const LISTS: { SUBSTRINGS: string[]; WORDS: string[]; PREFIXES: string[]; SUFFIXES: string[] } = blocklist;

const accentMap = new Map<string, string>();
for (const [letter, chars] of Object.entries(ACCENTS)) {
  for (const ch of chars) accentMap.set(ch, letter);
}
const runsCache = new Map<string, [string, number][]>();

// --- cleaning ---------------------------------------------------------------------------------------------------

function isSpace(code: number): boolean {
  return (
    code === 0x20 ||
    code === 0x09 ||
    code === 0x0a ||
    code === 0x0d ||
    code === 0xa0 ||
    (code >= 0x2000 && code <= 0x200a) ||
    code === 0x202f ||
    code === 0x205f ||
    code === 0x3000
  );
}

/** A character the name may contain: printable, Latin script, and not an invisible or direction-changing format character. */
function isDrawable(code: number): boolean {
  if (code < 0x20 || (code >= 0x7f && code <= 0x9f) || code === 0xad) return false;
  // Combining marks would pile onto the neighbouring letter.
  if ((code >= 0x0300 && code <= 0x036f) || (code >= 0x1ab0 && code <= 0x1aff) || (code >= 0x20d0 && code <= 0x20ff)) {
    return false;
  }
  if (
    (code >= 0x200b && code <= 0x200f) ||
    (code >= 0x2028 && code <= 0x202e) ||
    (code >= 0x2060 && code <= 0x206f) ||
    code === 0xfeff ||
    code >= 0xfff0 ||
    (code >= 0xd800 && code <= 0xdfff) ||
    code > 0xffff
  ) {
    return false;
  }
  return LATIN_RANGES.some(([lo, hi]) => code >= lo && code <= hi);
}

/**
 * The name as it will be kept: trimmed, single spaces, drawable characters only, at most MAX_LENGTH of them.
 * "" when nothing is left. `final = false` keeps one trailing space (a field still being typed in).
 */
export function clean(raw: string, final = true): string {
  let out = '';
  // UTF-16 units: every character above U+FFFF is made of surrogates, which are dropped, like the GDScript original.
  for (let i = 0; i < raw.length; i += 1) {
    const code = raw.charCodeAt(i);
    if (isSpace(code)) {
      if (out !== '' && !out.endsWith(' ')) out += ' ';
    } else if (isDrawable(code)) {
      out += String.fromCharCode(code);
    }
    if (out.length >= MAX_LENGTH) break;
  }
  out = out.substring(0, MAX_LENGTH);
  return final ? out.trim() : out.replace(/^ +/, '');
}

/** False when `name` contains a blocked word. An empty name is allowed (nothing to object to). */
export function isAllowed(name: string): boolean {
  return folds(clean(name)).every((folded) => !isBlocked(folded));
}

export interface NameCheck {
  /** The name to store: the cleaned input, or FALLBACK_NAME when it is empty or blocked. */
  name: string;
  /** True when `name` is exactly what was asked for. */
  accepted: boolean;
}

/** What the server stores when a client writes `raw` as its name. */
export function checkName(raw: unknown): NameCheck {
  if (typeof raw !== 'string') return { name: FALLBACK_NAME, accepted: false };
  const cleaned = clean(raw);
  if (cleaned === '' || !isAllowed(cleaned)) return { name: FALLBACK_NAME, accepted: false };
  return { name: cleaned, accepted: cleaned === raw };
}

// --- matching ---------------------------------------------------------------------------------------------------

/**
 * Readings of the name as plain lowercase letters with single spaces between words. Ambiguous characters get their own
 * axis and the readings are the combinations (at most 32): "1"/"|" i or l, "v" v or u, the sharp s as ss or b,
 * "ph" f or ph, and the mask characters as one unknown letter or a separator.
 */
function folds(text: string): string[] {
  const lower = text.toLowerCase();
  const il = lower.includes('1') || lower.includes('|');
  const vu = lower.includes('v');
  const eszett = lower.includes('ß');
  const mask = MASKS.some((m) => lower.includes(m));
  const out: string[] = [];
  for (let a = 0; a < (il ? 2 : 1); a += 1) {
    for (let b = 0; b < (vu ? 2 : 1); b += 1) {
      for (let c = 0; c < (eszett ? 2 : 1); c += 1) {
        for (let d = 0; d < (mask ? 2 : 1); d += 1) {
          const folded = fold(lower, a === 1 ? 'l' : 'i', b === 1, c === 1 ? 'b' : 'ss', d === 0);
          out.push(folded);
          if (folded.includes('ph')) out.push(folded.replaceAll('ph', 'f'));
        }
      }
    }
  }
  return out;
}

function fold(lower: string, oneAs: string, vAsU: boolean, eszettAs: string, maskAsWildcard: boolean): string {
  let out = '';
  for (const rawCh of lower) {
    let ch = rawCh;
    const accent = accentMap.get(rawCh);
    if (accent !== undefined) {
      ch = accent;
    } else if (rawCh === '1' || rawCh === '|') {
      ch = oneAs;
    } else if (rawCh === 'v') {
      ch = vAsU ? 'u' : 'v';
    } else if (rawCh === 'ß') {
      ch = eszettAs;
    } else if (MASKS.includes(rawCh)) {
      ch = maskAsWildcard ? WILDCARD : ' ';
    } else if (Object.prototype.hasOwnProperty.call(LEET, rawCh)) {
      ch = LEET[rawCh] ?? rawCh;
    }
    const c = ch.codePointAt(0) ?? 0;
    out += (c >= 0x61 && c <= 0x7a) || ch === WILDCARD || Array.from(ch).length > 1 ? ch : ' ';
  }
  return out;
}

function isBlocked(folded: string): boolean {
  const tokens = tokensOf(folded);
  if (containsSevere(tokens.join(''))) return true;
  return tokens.some((token) => isBlockedWord(token));
}

/** Words of the folded text; runs of single letters are glued together ("d i c k" is one word). */
function tokensOf(folded: string): string[] {
  const out: string[] = [];
  let singles = '';
  for (const part of folded.split(' ').filter((p) => p !== '')) {
    if (part.length === 1) {
      singles += part;
      continue;
    }
    if (singles !== '') {
      out.push(singles);
      singles = '';
    }
    out.push(part);
  }
  if (singles !== '') out.push(singles);
  return out;
}

function containsSevere(joined: string): boolean {
  for (const word of LISTS.SUBSTRINGS) {
    for (let start = 0; start < joined.length; start += 1) {
      for (const end of endsOf(joined, start, word)) {
        if (realLetters(joined.substring(start, end)) >= MIN_REAL_LETTERS) return true;
      }
    }
  }
  return false;
}

/** Letters that are not a wildcard. A match made mostly of wildcards ("***") proves nothing. */
function realLetters(text: string): number {
  return text.length - (text.split(WILDCARD).length - 1);
}

/** `token` is [prefix] + blocked word (+ blocked word) + [suffix], nothing else. */
function isBlockedWord(token: string): boolean {
  if (realLetters(token) < MIN_REAL_LETTERS) return false;
  const starts: number[] = [0];
  for (const prefix of LISTS.PREFIXES) starts.push(...endsOf(token, 0, prefix, true));
  const reached: number[] = [];
  for (const s of starts) {
    for (const word of LISTS.WORDS) reached.push(...endsOf(token, s, word));
  }
  // Optionally a second blocked word ("assdick").
  const glued: number[] = [...reached];
  for (const pos of reached) {
    for (const word of LISTS.WORDS) glued.push(...endsOf(token, pos, word));
  }
  for (const pos of glued) {
    if (pos === token.length) return true;
    for (const suffix of LISTS.SUFFIXES) {
      if (endsOf(token, pos, suffix, true).includes(token.length)) return true;
    }
  }
  return false;
}

/**
 * Every index where `word` can end when matched against `text` from `start`; each letter of the word may be repeated
 * ("fuuck"), never shortened. Empty when it does not match there. `exact` switches the repeats off; prefixes and
 * suffixes use it, or "Assess" would read as "ass" + "es" + "s".
 */
function endsOf(text: string, start: number, word: string, exact = false): number[] {
  const out: number[] = [];
  matchRuns(text, start, runsOf(word), 0, out, exact);
  return out;
}

function matchRuns(text: string, pos: number, runs: [string, number][], index: number, out: number[], exact: boolean): void {
  const run = runs[index];
  if (run === undefined) {
    out.push(pos);
    return;
  }
  const [letter, need] = run;
  let have = 0;
  while (pos + have < text.length && (text[pos + have] === letter || text[pos + have] === WILDCARD)) have += 1;
  const top = exact ? need : have;
  for (let count = need; count <= top; count += 1) {
    if (count <= have) matchRuns(text, pos + count, runs, index + 1, out, exact);
  }
}

/** "ass" -> [["a", 1], ["s", 2]] (cached). */
function runsOf(word: string): [string, number][] {
  const cached = runsCache.get(word);
  if (cached) return cached;
  const runs: [string, number][] = [];
  for (let i = 0; i < word.length; i += 1) {
    const last = runs[runs.length - 1];
    if (i > 0 && word[i] === word[i - 1] && last) {
      last[1] += 1;
    } else {
      runs.push([word.charAt(i), 1]);
    }
  }
  runsCache.set(word, runs);
  return runs;
}
