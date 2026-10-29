import test from 'node:test';
import assert from 'node:assert/strict';
import { DirectionalAttachment } from '../dist/attachment.js';

test('entering reach attaches and remaining still keeps the hand attached', () => {
  const hand = new DirectionalAttachment();
  assert.equal(hand.update(180, false), false);
  assert.equal(hand.update(120, true), true);
  assert.equal(hand.update(120, true), true);
});

test('small outward movement and pauses keep the hand attached', () => {
  const hand = new DirectionalAttachment();
  hand.update(90, true);
  for (const distance of [90.2, 89.8, 90.7, 92, 94, 94.79]) {
    assert.equal(hand.update(distance, true), true);
  }
  for (let i = 0; i < 60; i++) assert.equal(hand.update(94.79, true), true);
  assert.equal(hand.update(94.8, true), false);
});

test('subpixel inward jitter does not reattach after release', () => {
  const hand = new DirectionalAttachment();
  hand.update(90, true);
  assert.equal(hand.update(95, true), false);
  for (const distance of [94.8, 95.4, 94.6, 95]) {
    assert.equal(hand.update(distance, true), false);
  }
});

test('slow outward movement accumulates and releases while still in reach', () => {
  const hand = new DirectionalAttachment();
  hand.update(70, true);
  for (let step = 1; step < 20; step++) {
    assert.equal(hand.update(70 + step * .25, true), true);
  }
  assert.equal(hand.update(75, true), false);
});

test('a retreat stays detached when stopped, including the release sample', () => {
  const hand = new DirectionalAttachment();
  hand.update(70, true);
  hand.update(80, true);
  for (let i = 0; i < 60; i++) assert.equal(hand.update(80, true), false);
});

test('deliberate inward movement reattaches after retreat', () => {
  const hand = new DirectionalAttachment();
  hand.update(70, true);
  hand.update(80, true);
  assert.equal(hand.update(79.5, true), false);
  assert.equal(hand.update(79, true), true);
  assert.equal(hand.update(79, true), true);
});

test('direction changes are measured from subpixel radial extrema', () => {
  const hand = new DirectionalAttachment();
  hand.update(90, true);
  assert.equal(hand.update(89.5, true), true);
  assert.equal(hand.update(94.25, true), true);
  assert.equal(hand.update(94.5, true), false);
  assert.equal(hand.update(95, true), false);
  assert.equal(hand.update(94, true), true);
});

test('leaving reach and explicit cancellation both clear directional history', () => {
  const hand = new DirectionalAttachment();
  hand.update(70, true);
  hand.update(80, true);
  assert.equal(hand.update(140, false), false);
  assert.equal(hand.update(125, true), true);
  assert.equal(hand.update(130, true), false);
  hand.reset();
  assert.equal(hand.attached, false);
  assert.equal(hand.update(127, true), true);
});
