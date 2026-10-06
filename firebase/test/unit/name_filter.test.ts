// Mirrors game/tests/ui/test_name_filter.gd case by case, so the server filter and the game filter stay in step.
// The characters the game font can draw come from name_glyphs.json (generated from the game by tools/firebase/gen_name_glyphs.sh);
// game/tests/net/test_name_glyph_table.gd checks that table against the game, game/tests/qa/test_name_filter_parity.gd the 2,000-string corpus.
import assert from 'node:assert/strict';
import { checkName, clean, FALLBACK_NAME, isAllowed, MAX_LENGTH } from '../../functions/src/name_filter';

const chr = (...codes: number[]): string => String.fromCodePoint(...codes);

describe('name filter: cleaning', () => {
  it('trims and collapses spaces', () => {
    assert.equal(clean('   Anna   Lee  '), 'Anna Lee');
    assert.equal(clean('a\t\nb'), 'a b');
    assert.equal(clean(`a${chr(0xa0)}${chr(0x2003)}b`), 'a b');
    assert.equal(clean(''), '');
    assert.equal(clean('   '), '');
  });

  it('caps at twelve characters', () => {
    assert.equal(clean('ABCDEFGHIJKLMNOP'), 'ABCDEFGHIJKL');
    assert.equal(clean('ABCDEFGHIJK MNOP'), 'ABCDEFGHIJK');
    assert.equal(clean('ABCDEFGHIJKL').length, MAX_LENGTH);
  });

  it('keeps one trailing space while the name is still being typed', () => {
    assert.equal(clean('ANNA ', false), 'ANNA ');
    assert.equal(clean('ANNA   ', false), 'ANNA ');
    assert.equal(clean(' ANNA', false), 'ANNA');
  });

  it('strips control and invisible characters', () => {
    assert.equal(clean(`A${chr(0)}B${chr(7)}C${chr(0x7f)}D`), 'ABCD');
    assert.equal(clean(`A${chr(0x200b)}B${chr(0x200d)}C${chr(0x202e)}D${chr(0xfeff)}E${chr(0xad)}F`), 'ABCDEF');
  });

  it('strips glyphs outside the Latin script (emoji, dingbats, CJK, Cyrillic, lone combining marks)', () => {
    assert.equal(clean(`Ann${chr(0x1f600)}a`), 'Anna');
    assert.equal(clean(`Ann${chr(0x2764)}a`), 'Anna');
    assert.equal(clean(`${chr(0x4f60)}${chr(0x597d)}Bob`), 'Bob');
    assert.equal(clean(`${chr(0x416)}enya`), 'enya');
    assert.equal(clean(`${chr(0x301)}Ann`), 'Ann');
  });

  it('keeps everything the game font can draw', () => {
    assert.equal(clean(`Zo${chr(0xeb)} J${chr(0xfc)}rgen`), `Zo${chr(0xeb)} J${chr(0xfc)}rgen`);
    assert.equal(clean('R2-D2 #1'), 'R2-D2 #1');
    assert.equal(clean("Mr. X's"), "Mr. X's");
  });
});

describe('name filter: blocklist', () => {
  const blocked = (words: string[]): void => {
    for (const w of words) assert.equal(isAllowed(w), false, `${w} is blocked`);
  };
  const fine = (words: string[]): void => {
    for (const w of words) assert.equal(isAllowed(w), true, `${w} is fine`);
  };

  it('blocks plain words', () => {
    blocked(['fuck', 'Shit', 'BITCH', 'cunt', 'dick', 'Nigger', 'faggot', 'pussy', 'whore', 'slut']);
  });

  it('folds case, leetspeak and repeats', () => {
    blocked([
      'FuCk', 'sh1t', '5hit', '$h!t', 'd1ck', 'dIcK', 'c0ck', 'a55', '@ss', '@$$', 'fuuuuck', 'shiiit', 'bitccch',
      'n1gger', 'b1tch', 'cunt', 'p0rn', '7it5', 'fuck',
    ]);
  });

  it('cannot be dodged with separators', () => {
    blocked(['f u c k', 'f.u.c.k', 'xx_fuck_xx', 'd i c k', 'BIG DICK', 'the shit', 'f_u_c_k']);
  });

  it('blocks compounds', () => {
    blocked(['dumbass', 'Fatass', 'dicks', 'asses', 'dickhead', 'shithead', 'bullshit', 'jackass', 'assdick', 'motherfucker']);
  });

  it('folds accents', () => {
    assert.equal(isAllowed(`f${chr(0xfc)}ck`), false);
    assert.equal(isAllowed(`sh${chr(0xef)}it`), false);
  });

  it('lets innocent names with blocked letters inside pass', () => {
    fine([
      'Scunthorpe', 'Cassie', 'Dickens', 'Assess', 'Assassin', 'Class', 'Pass', 'Bass', 'Grass', 'Mass Effect',
      'Penistone', 'Cockburn', 'Hancock', 'Peacock', 'Analyst', 'Titan', 'Shiitake', 'Spice', 'Niger', 'Nigeria',
      'Raccoon', 'Cocoon', 'Hello', 'Classic', 'Dickson', 'Therapist', 'Grape', 'Drape', 'Pakistan', 'Assam',
      'As', 'Passion', 'Cumin', 'Cumbria', 'Titus', 'Essex', 'Button', 'Butler', 'Anna', 'Max', 'Zoe', 'Craterline',
    ]);
  });

  it('lets realistic names with look-alike letters pass', () => {
    fine([
      'Phil', 'Sophia', 'Vicky', 'Victor', 'Vance', 'Raphael', 'Phuket', 'Stephen', 'Joseph', 'Olivia', 'Ivan',
      'Davina', 'Cassandra', 'Genevieve', 'Steve', 'Beth', 'Cob', 'C-3PO', 'R2-D2', 'Mr. T', 'Ace 99', 'Agent 8', '9Lives',
      'Dr. Who?', 'Nova+', '(Max)', 'Ann*', 'Lu|u', 'Vega', 'Vlad', 'Kovacs', 'Nguyen', 'Uhura', '***', 'Mr *', 'A*B',
    ]);
  });

  it('blocks look-alike spellings', () => {
    blocked([
      'fuck', '8itch', 'ni99er', 'sh1+', 'd|ck', 'phuck', '(unt', 'f*ck', 'f**k', 'sh*t', 'p*ssy', 'cunt', `${chr(0xdf)}hit`,
      `${chr(0xdf)}lut`, 'fvk', 'pvssy', 'f#ck', 'sh%t', 'f*u*c*k', 'Phuq', 'bi+ch', 'd1ck', 'SH*T', 'fu*k', 'c*nt', 'wh*re',
    ]);
  });

  it('does not block a name made of wildcards alone', () => {
    fine(['***', '*', 'a**', '**s', '?!?']);
  });

  it('allows an empty name', () => {
    assert.equal(isAllowed(''), true);
    assert.equal(isAllowed('   '), true);
  });

  it('only counts the first twelve characters', () => {
    assert.equal(isAllowed('ABCDEFGHIJKLfuck'), true);
    assert.equal(isAllowed('ABCDEFGfuck'), false);
  });

  it('blocks the v-for-u spelling of the two words GDScript spells with "v"', () => {
    assert.equal(isAllowed('fvck'), false);
    assert.equal(isAllowed('cvnt'), false);
  });
});

describe('name filter: what the server stores', () => {
  it('keeps a clean name as it is', () => {
    assert.deepEqual(checkName('Anna Lee'), { name: 'Anna Lee', accepted: true });
  });

  it('stores the cleaned form when the input needed cleaning', () => {
    assert.deepEqual(checkName('  Anna   Lee '), { name: 'Anna Lee', accepted: false });
    assert.deepEqual(checkName('ABCDEFGHIJKLMNOP'), { name: 'ABCDEFGHIJKL', accepted: false });
  });

  it('replaces a blocked, empty or non-string name with PLAYER', () => {
    assert.equal(FALLBACK_NAME, 'PLAYER');
    for (const bad of ['fuck', 'f u c k', '', '   ', '​​', 42, null, undefined, { a: 1 }]) {
      assert.deepEqual(checkName(bad), { name: 'PLAYER', accepted: false }, JSON.stringify(bad));
    }
  });

  it('accepts the fallback name itself', () => {
    assert.deepEqual(checkName('PLAYER'), { name: 'PLAYER', accepted: true });
  });
});

describe('name filter: the characters the game font cannot draw (exported from the game into name_glyphs.json)', () => {
  it('deletes them, as the game does, so a word cannot hide behind one', () => {
    assert.equal(clean(`sh${chr(0xac)}it`), 'shit');
    assert.equal(clean(`fu${chr(0xa7)}k`), 'fuk');
    assert.equal(clean(`pis${chr(0xae)}s`), 'piss');
    for (const word of [`sh${chr(0xac)}it`, `fu${chr(0xa7)}ck`, `arseh${chr(0xac)}ole`, `bit${chr(0xa5)}ch`, `c${chr(0x2122)}unt`, `pedo${chr(0xf8)}`]) {
      assert.equal(isAllowed(word), false, `${JSON.stringify(word)} is blocked`);
    }
    assert.equal(checkName(`sh${chr(0xac)}it`).name, FALLBACK_NAME);
  });

  it('keeps what the font draws: Latin letters with accents, a few symbols and punctuation, and nothing above U+FFFF', () => {
    assert.equal(clean(`${chr(0xc0)}${chr(0xe9)}${chr(0xf1)}${chr(0xfc)}${chr(0x152)}${chr(0x153)}`), `${chr(0xc0)}${chr(0xe9)}${chr(0xf1)}${chr(0xfc)}${chr(0x152)}${chr(0x153)}`);
    assert.equal(clean(`a${chr(0x20ac)}b${chr(0x2013)}c`), `a${chr(0x20ac)}b${chr(0x2013)}c`);
    assert.equal(clean(`a${chr(0x1f600)}b`), 'ab');
    assert.equal(clean('a^b'), 'ab', 'the font has no circumflex accent character');
  });
});
