import { test } from 'node:test';
import assert from 'node:assert/strict';
import { canMatchDock, parseBarHeight } from './prefs.ts';

test('parseBarHeight: accepts whole numbers in range', () => {
    assert.equal(parseBarHeight('36', 28, 64), 36);
    assert.equal(parseBarHeight(' 40 ', 28, 64), 40);
});

test('parseBarHeight: rounds fractions', () => {
    assert.equal(parseBarHeight('36.6', 28, 64), 37);
});

test('parseBarHeight: clamps to the allowed range', () => {
    assert.equal(parseBarHeight('10', 28, 64), 28);
    assert.equal(parseBarHeight('500', 28, 64), 64);
});

test('parseBarHeight: ignores empty and non-numeric text', () => {
    assert.equal(parseBarHeight('', 28, 64), null);
    assert.equal(parseBarHeight('abc', 28, 64), null);
    assert.equal(parseBarHeight('Infinity', 28, 64), null);
});

test('canMatchDock: only when the Dock height is one the bar supports', () => {
    assert.equal(canMatchDock(36, 28, 64), true);
    assert.equal(canMatchDock(0, 28, 64), false);
    assert.equal(canMatchDock(80, 28, 64), false);
});
