// The 2,000-string corpus the QA name-filter parity test feeds to BOTH filters (the server's TypeScript port and the game's
// GDScript NameFilter). Deterministic: the same seed always gives the same strings. The TypeScript verdicts are stored next to
// the strings in game/tests/qa/fixtures/name_filter_corpus.json, and the GDScript test replays them.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { clean, isAllowed } from '../../../functions/src/name_filter';

export interface CorpusEntry {
  /** The raw input. */
  s: string;
  /** TypeScript `clean(s)`. */
  clean: string;
  /** TypeScript `isAllowed(s)`. */
  allowed: boolean;
}

export const CORPUS_SIZE = 2000;
export const CORPUS_SEED = 20261006;

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

interface Lists {
  SUBSTRINGS: string[];
  WORDS: string[];
  PREFIXES: string[];
  SUFFIXES: string[];
}

const LEET_BACK: Record<string, string> = { a: '4@', e: '3', i: '1!|', o: '0', s: '5$', t: '7+', b: '8', g: '9', c: '(' };
const ACCENT_BACK: Record<string, string> = { a: 'àáâãäå', e: 'èéêë', i: 'ìíîï', o: 'òóôõöø', u: 'ùúûü', n: 'ñ', c: 'ç', y: 'ýÿ' };
const MASKS = '*#%?';
const FORMAT = ['​', '‍', '⁠', '­', '﻿', '‮', '‪'];
const COMBINING = ['́', '̈', '̧'];
const SEPARATORS = [' ', '.', '-', '_', ',', '/', '~', '\t'];
const INNOCENT = ['Scunthorpe', 'Cassie', 'Dickens', 'Assess', 'Classic', 'Mass', 'Bassoon', 'Peacock', 'Hancock', 'Cocktail', 'Shiitake', 'Analyst', 'Grape', 'Therapist', 'Penistone', 'Anna', 'Hana K', 'Finn', 'Zoë', 'José', 'Müller', 'Ångström', 'Søren', 'Æsir', 'Çelik', 'Nuño', 'Œuvre', 'Ünal', 'ÿes', 'µ-man', 'ŁÓDŹ', 'Ωmega', 'ЯDark', 'ΑΒΓ', '日本', '😀', '€uro', '™mark', '×times', '÷div', '¿que?', '¡hola!', '§sect', '°deg', 'ªmas', 'ºmas'];

const WIDE = (text: string): string =>
  Array.from(text)
    .map((ch) => (ch >= '!' && ch <= '~' ? String.fromCharCode(ch.charCodeAt(0) + 0xfee0) : ch))
    .join('');

export function buildCorpus(blocklist: Lists, size = CORPUS_SIZE, seedValue = CORPUS_SEED): string[] {
  const next = mulberry32(seedValue);
  const int = (lo: number, hi: number): number => lo + Math.floor(next() * (hi - lo + 1));
  const pick = <T>(items: readonly T[]): T => items[int(0, items.length - 1)];
  const words = [...blocklist.SUBSTRINGS, ...blocklist.WORDS];
  const out: string[] = [];

  const mutate = (word: string): string => {
    const kind = int(0, 11);
    const chars = Array.from(word);
    switch (kind) {
      case 0: return word.toUpperCase();
      case 1: return chars.map((c) => (LEET_BACK[c] && next() < 0.7 ? LEET_BACK[c]?.charAt(int(0, (LEET_BACK[c]?.length ?? 1) - 1)) : c)).join('');
      case 2: return chars.map((c) => (ACCENT_BACK[c] && next() < 0.7 ? Array.from(ACCENT_BACK[c] ?? c)[int(0, Array.from(ACCENT_BACK[c] ?? c).length - 1)] : c)).join('');
      case 3: return chars.join(pick(SEPARATORS));
      case 4: return chars.map((c) => (next() < 0.3 ? c + c : c)).join('');
      case 5: return chars.map((c, i) => (i > 0 && i < chars.length - 1 && next() < 0.35 ? pick(Array.from(MASKS)) : c)).join('');
      case 6: return chars.map((c) => c + (next() < 0.3 ? pick(FORMAT) : '')).join('');
      case 7: return chars.map((c) => c + (next() < 0.3 ? pick(COMBINING) : '')).join('');
      case 8: return WIDE(word);
      case 9: return chars.map((c) => (next() < 0.4 ? c.toUpperCase() : c)).join('');
      case 10: return word.replace(/f/g, 'ph').replace(/s/g, 'ß');
      default: return word;
    }
  };

  // 1. every blocked word, plain and mutated in a few ways (about 700 strings)
  for (const word of words) {
    out.push(word, word.toUpperCase(), `${word[0]?.toUpperCase() ?? ''}${word.slice(1)}`);
    for (let i = 0; i < 6; i += 1) out.push(mutate(word));
  }
  // 2. innocent names and look-alike words
  for (const name of INNOCENT) out.push(name, name.toUpperCase(), name.toLowerCase());
  // 3. words glued to prefixes and suffixes, and two words together
  while (out.length < 1100) {
    const w = pick(blocklist.WORDS);
    const parts = [next() < 0.4 ? pick(blocklist.PREFIXES) : '', w, next() < 0.2 ? pick(words) : '', next() < 0.4 ? pick(blocklist.SUFFIXES) : ''];
    out.push(mutate(parts.join(next() < 0.3 ? ' ' : '')));
  }
  // 3b. blocked words with one character the game font cannot draw inserted (the game deletes it, the server turns it into a
  //     separator): a word split this way is one word to the game and two to the server
  const FONT_GAPS = Array.from('^¤¥¦§©ª«¬®±²³µ·¹º»¼½¾ÐØÞðøþÿ™↑↓−∕ʻʼ˙');
  while (out.length < 1400) {
    const w = Array.from(pick(next() < 0.5 ? blocklist.WORDS : words));
    const at = int(1, Math.max(1, w.length - 1));
    out.push([...w.slice(0, at), pick(FONT_GAPS), ...w.slice(at)].join(''));
  }
  // 4. random text from several scripts and character classes
  const CLASSES: string[][] = [
    Array.from('abcdefghijklmnopqrstuvwxyz'),
    Array.from('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'),
    Array.from(' !"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~'),
    Array.from('¡¢£¤¥¦§¨©ª«¬®¯°±²³´µ¶·¸¹º»¼½¾¿×÷ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿ'),
    Array.from('ĀāĂăĄąĆćČčĎďĐđĒēĘęĚěĞğĪīİıŁłŃńŇňŌōŐőŒœŘřŚśŞşŠšŢţŤťŪūŮůŰűŹźŻżŽž'),
    Array.from('ΑΒΓΔΕΖΗΘαβγδεζηθ'),
    Array.from('АБВГДЕЖЗИЙабвгдежзий'),
    Array.from('日本語한국어العربية'),
    Array.from('😀😂❤🔥👍🎉'),
    Array.from('\u0001\u0007\u0008\u001B\u007F\u0080\u009F'), // no NUL: Godot's JSON parser cannot carry one in a String
    FORMAT.concat(COMBINING),
    Array.from('     　   \u0085'),
    Array.from('€™←↑→↓−∕‐‑‒–—―‖‘’“”†‡•…‰′″‹›'),
  ];
  while (out.length < size) {
    const len = int(1, 18);
    let text = '';
    const mixed = next() < 0.5;
    const cls = pick(CLASSES);
    for (let i = 0; i < len; i += 1) text += pick(mixed ? pick(CLASSES) : cls);
    out.push(text);
  }
  return out.slice(0, size);
}

export function entriesFor(strings: string[]): CorpusEntry[] {
  return strings.map((s) => ({ s, clean: clean(s), allowed: isAllowed(s) }));
}

export function loadBlocklist(): Lists {
  return JSON.parse(readFileSync(join(__dirname, '..', '..', '..', 'functions', 'src', 'name_blocklist.json'), 'utf8')) as Lists;
}

export const FIXTURE_PATH = join(__dirname, '..', '..', '..', '..', 'game', 'tests', 'qa', 'fixtures', 'name_filter_corpus.json');

export function serialize(entries: CorpusEntry[]): string {
  return `${JSON.stringify(entries)}\n`;
}
