import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mix, parseHex, textOn, toHex } from './colors.ts';

test('parseHex: reads #rrggbb in any case', () => {
    assert.deepEqual(parseHex('#ff8000'), [255, 128, 0]);
    assert.deepEqual(parseHex(' #FF8000 '), [255, 128, 0]);
});

test('parseHex: rejects anything else', () => {
    for (const bad of ['', '#f80', 'ff8000', '#ff800', '#ff80000', '#gg8000', 'red']) {
        assert.equal(parseHex(bad), null, bad);
    }
});

test('toHex: pads and rounds', () => {
    assert.equal(toHex([0, 10, 255]), '#000aff');
    assert.equal(toHex([127.5, 0, 0]), '#800000');
});

test('mix: averages two colours', () => {
    assert.equal(mix('#000000', '#ffffff'), '#808080');
    assert.equal(mix('#ff0000', '#0000ff'), '#800080');
    assert.equal(mix('#ff0000', 'nope'), null);
});

test('textOn: black on light colours, white on dark ones', () => {
    assert.equal(textOn('#ffffff'), '#000000');
    assert.equal(textOn('#ffff00'), '#000000');
    assert.equal(textOn('#00ffff'), '#000000');
    assert.equal(textOn('#000000'), '#ffffff');
    assert.equal(textOn('#000080'), '#ffffff');
    assert.equal(textOn('#800000'), '#ffffff');
});

test('textOn: falls back to black for unreadable input', () => {
    assert.equal(textOn('nope'), '#000000');
});
