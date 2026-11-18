import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyOrder, dragTarget, moveItem, shiftFor } from './reorder.ts';

const STEP = 100;

test('dragTarget: small movement stays in place', () => {
  assert.deepEqual(dragTarget(2, 40, STEP, 5), { to: 2, offset: 40 });
});

test('dragTarget: crossing half a button moves one slot', () => {
  assert.equal(dragTarget(2, 60, STEP, 5).to, 3);
  assert.equal(dragTarget(2, -60, STEP, 5).to, 1);
});

test('dragTarget: clamps to the ends of the bar', () => {
  assert.deepEqual(dragTarget(1, -500, STEP, 5), { to: 0, offset: -100 });
  assert.deepEqual(dragTarget(1, 900, STEP, 5), { to: 4, offset: 300 });
});

test('shiftFor: dragging right slides the items in between left', () => {
  assert.deepEqual([0, 1, 2, 3, 4].map((j) => shiftFor(j, 1, 3, STEP)), [0, 0, -STEP, -STEP, 0]);
});

test('shiftFor: dragging left slides the items in between right', () => {
  assert.deepEqual([0, 1, 2, 3, 4].map((j) => shiftFor(j, 3, 1, STEP)), [0, STEP, STEP, 0, 0]);
});

test('shiftFor: no shifts when not moved', () => {
  assert.deepEqual([0, 1, 2].map((j) => shiftFor(j, 1, 1, STEP)), [0, 0, 0]);
});

test('moveItem: moves forwards and backwards without mutating the input', () => {
  const items = ['a', 'b', 'c', 'd'];
  assert.deepEqual(moveItem(items, 0, 2), ['b', 'c', 'a', 'd']);
  assert.deepEqual(moveItem(items, 3, 0), ['d', 'a', 'b', 'c']);
  assert.deepEqual(items, ['a', 'b', 'c', 'd']);
});

test('applyOrder: sorts known ids and keeps unknown ones at the end in arrival order', () => {
  const apps = ['x', 'b', 'y', 'a'].map((bundleId) => ({ bundleId }));
  assert.deepEqual(applyOrder(apps, ['a', 'b']).map((a) => a.bundleId), ['a', 'b', 'x', 'y']);
});
