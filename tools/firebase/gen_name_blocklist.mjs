// Generates firebase/functions/src/name_blocklist.json from game/ui/names/name_blocklist.gd, so the server filters
// names with exactly the words the game does (ARCHITECTURE section 44).
//
//   node tools/firebase/gen_name_blocklist.mjs           write the JSON file
//   node tools/firebase/gen_name_blocklist.mjs --check   exit 1 if the committed JSON is out of date
//
// Run it again whenever name_blocklist.gd changes, and commit the result.
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const source = join(root, 'game', 'ui', 'names', 'name_blocklist.gd');
const target = join(root, 'firebase', 'functions', 'src', 'name_blocklist.json');
const LISTS = ['SUBSTRINGS', 'WORDS', 'PREFIXES', 'SUFFIXES'];

const gd = readFileSync(source, 'utf8');
const out = {};
for (const name of LISTS) {
  const match = new RegExp(`^const ${name}: PackedStringArray = \\[([^\\]]*)\\]`, 'm').exec(gd);
  if (!match) throw new Error(`const ${name} not found in ${source}`);
  // Drop comment lines first, then take every double-quoted word.
  const body = (match[1] ?? '')
    .split('\n')
    .filter((line) => !line.trim().startsWith('#'))
    .join('\n');
  const words = [...body.matchAll(/"([^"]*)"/g)].map((m) => m[1]);
  if (words.length === 0) throw new Error(`${name} is empty`);
  for (const w of words) {
    if (!/^[a-z]+$/.test(w)) throw new Error(`${name}: "${w}" is not lowercase letters only`);
  }
  out[name] = words;
}
const text = `${JSON.stringify(out, null, 2)}\n`;

if (process.argv.includes('--check')) {
  let current = '';
  try {
    current = readFileSync(target, 'utf8');
  } catch {
    current = '';
  }
  if (current !== text) {
    console.error('name_blocklist.json is out of date. Run: npm run blocklist:build (in firebase/) and commit it.');
    process.exit(1);
  }
  console.log('name_blocklist.json is up to date');
} else {
  writeFileSync(target, text);
  console.log(`wrote ${target} (${LISTS.map((n) => `${n}: ${out[n].length}`).join(', ')})`);
}
