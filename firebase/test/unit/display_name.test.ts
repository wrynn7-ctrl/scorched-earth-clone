// displayName() is the one place that copies a player's name into a seat, an invite or a friend request. A client can write any
// name into users/{uid}/name and the onNameWrite trigger only fixes it a moment later, so a copy made in between must already
// be filtered (M7-QF-B).
import assert from 'node:assert/strict';
import { displayName } from '../../functions/src/rtdb';

describe('displayName', () => {
  it('passes a clean name through', () => {
    assert.equal(displayName({ name: 'Hana', friendCode: 'ABCD2345' }), 'Hana');
  });

  it('never returns a name the filter blocks, empty or malformed', () => {
    for (const name of ['f*ckyou', 'sh1thead', '', '   ', undefined]) {
      assert.equal(displayName({ name, friendCode: 'ABCD2345' }), 'PLAYER', JSON.stringify(name));
    }
    assert.equal(displayName({ name: 5 as unknown as string, friendCode: 'ABCD2345' }), 'PLAYER');
    assert.equal(displayName(null), 'PLAYER');
  });

  it('cleans a messy name the way the trigger will', () => {
    assert.equal(displayName({ name: '  Hana   K  ', friendCode: 'ABCD2345' }), 'Hana K');
    assert.equal(displayName({ name: 'Ha\u200bna', friendCode: 'ABCD2345' }), 'Hana');
  });

  it('shows a hidden name as PLAYER plus a short id', () => {
    assert.equal(displayName({ name: 'Rude', nameHidden: true, friendCode: 'ABCD2345' }), 'PLAYER ABCD');
  });
});
