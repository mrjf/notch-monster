import test from 'node:test';
import assert from 'node:assert/strict';
import { HoverVisit, flightEndpoint, HoverPlay } from '../dist/hover-play.js';

const origin = {x: 500, y: 0};

test('hover visits are limited to the centered area below the menu bar', () => {
  for (const point of [{x: 440, y: 28}, {x: 560, y: 132}, {x: 500, y: 80}]) {
    assert.equal(new HoverVisit().sample(point, origin, 0), true);
  }
  for (const point of [{x: 439, y: 80}, {x: 561, y: 80}, {x: 500, y: 27}, {x: 500, y: 133}]) {
    assert.equal(new HoverVisit().sample(point, origin, 0), false);
  }
});

test('a visit waves once, ignores boundary wobbles, and requires exit plus cooldown', () => {
  const visit = new HoverVisit(), point = {x: 500, y: 80};
  assert.equal(visit.sample(point, origin, 0), true);
  assert.equal(visit.sample(point, origin, 2000), false);
  visit.sample({x: 565, y: 80}, origin, 2010);
  assert.equal(visit.sample(point, origin, 2020), false);
  visit.sample({x: 587, y: 80}, origin, 2030);
  assert.equal(visit.sample(point, origin, 2040), true);
  visit.sample({x: 500, y: 161}, origin, 2100);
  assert.equal(visit.sample(point, origin, 3439), false);
  assert.equal(visit.sample(point, origin, 3440), true);
});

test('a busy or button-held visit cannot fire when released without leaving', () => {
  const visit = new HoverVisit(), point = {x: 500, y: 80};
  assert.equal(visit.sample(point, origin, 0, false), false);
  assert.equal(visit.sample(point, origin, 2000), false);
  visit.sample({x: 500, y: 180}, origin, 2010);
  assert.equal(visit.sample(point, origin, 2020), true);
});

test('cursor flight goes outward and down but remains within the desktop', () => {
  assert.deepEqual(flightEndpoint({x: 480, y: 80}, origin, {width: 1000, height: 800}), {x: 226, y: 410});
  assert.deepEqual(flightEndpoint({x: 520, y: 80}, origin, {width: 1000, height: 800}), {x: 774, y: 410});
  for (const bounds of [{width: 320, height: 568}, {width: 1000, height: 400}]) {
    const center = {x: bounds.width / 2, y: 0};
    for (const side of [-1, 1]) {
      const point = {x: center.x + side * 60, y: 132};
      const end = flightEndpoint(point, center, bounds);
      assert.ok(end.x >= 12 && end.x <= bounds.width - 28);
      assert.ok(end.y >= 40 && end.y <= bounds.height - 32);
      assert.ok(end.y > point.y);
      assert.ok((end.x - point.x) * side > 0);
    }
  }
});

// Exercise the real controller with only browser plumbing and time replaced.
function playground(t, {saved, reduced = false} = {}) {
  let now = 0, nextID = 1, busy = false, modal = false, stored = saved, hides = 0;
  const frames = new Map(), drawn = [], sounds = [];
  class Element {
    constructor() { this.listeners = new Map(); this.dataset = {}; this.hidden = false; this.style = {}; }
    addEventListener(type, callback) {
      const list = this.listeners.get(type) ?? [];
      list.push(callback); this.listeners.set(type, list);
    }
    dispatch(type, event = {}) { for (const callback of this.listeners.get(type) ?? []) callback(event); }
    removeAttribute(name) { if (name === 'data-hover-play') delete this.dataset.hoverPlay; }
  }
  const cursor = new Element(); cursor.hidden = true;
  const desktop = new Element(), document = new Element(), window = new Element(), reducedMotion = new Element();
  const classes = new Set();
  desktop.classList = {add: name => classes.add(name), remove: name => classes.delete(name), contains: name => classes.has(name)};
  desktop.querySelector = selector => selector === '#flying-cursor' ? cursor : null;
  desktop.getBoundingClientRect = () => ({left: 20, top: 30});
  desktop.clientWidth = 1000; desktop.clientHeight = 800;
  document.hidden = false;
  document.querySelector = selector => selector === 'dialog[open]' && modal ? {} : null;
  reducedMotion.matches = reduced;
  const globals = {
    document, performance: {now: () => now},
    requestAnimationFrame: callback => { const id = nextID++; frames.set(id, callback); return id; },
    cancelAnimationFrame: id => frames.delete(id),
    addEventListener: window.addEventListener.bind(window)
  };
  const descriptors = new Map(Object.keys(globals).map(key => [key, Object.getOwnPropertyDescriptor(globalThis, key)]));
  for (const [key, value] of Object.entries(globals)) Object.defineProperty(globalThis, key, {configurable: true, writable: true, value});
  t.after(() => { for (const [key, descriptor] of descriptors) {
    if (descriptor) Object.defineProperty(globalThis, key, descriptor); else delete globalThis[key];
  }});
  const play = new HoverPlay({desktop, renderer: {draw: pose => drawn.push(pose), hide: () => { hides++; }},
    origin: () => origin, scale: () => 1, reducedMotion,
    sounds: {play: cue => sounds.push(cue)}, isBusy: () => busy,
    storage: {getItem: () => stored, setItem: (_, value) => { stored = value; }}});
  return {play, desktop, document, window, reducedMotion, cursor, drawn, sounds,
    stored: () => JSON.parse(stored), hides: () => hides, pending: () => frames.size,
    setBusy: value => { busy = value; }, setModal: value => { modal = value; },
    move(x = 500, y = 80, extra = {}) { desktop.dispatch('pointermove', {clientX: x + 20, clientY: y + 30, pointerType: 'mouse', buttons: 0, ...extra}); },
    advance(milliseconds) {
      const end = now + milliseconds;
      while (now < end) {
        now = Math.min(now + 16, end);
        const callbacks = [...frames.values()]; frames.clear();
        callbacks.forEach(callback => callback(now));
      }
    }
  };
}

test('cursor batting defaults off and persists explicit choices', t => {
  const page = playground(t);
  assert.equal(page.play.batCursor, false);
  page.move(); assert.equal(page.desktop.dataset.hoverPlay, 'wave');
  page.play.setBatCursor(true);
  assert.deepEqual(page.stored(), {batCursor: true});
  page.play.setBatCursor(false);
  assert.deepEqual(page.stored(), {batCursor: false});
});

test('saved cursor batting launches at contact and restores the real cursor after flight', t => {
  const page = playground(t, {saved: '{"batCursor":true}'});
  page.move(); assert.equal(page.desktop.dataset.hoverPlay, 'swat');
  page.advance(114); assert.equal(page.cursor.hidden, true);
  page.advance(1);
  assert.equal(page.desktop.dataset.hoverPlay, 'flight');
  assert.equal(page.cursor.hidden, false);
  assert.equal(page.desktop.classList.contains('cursor-in-flight'), true);
  assert.match(page.cursor.style.transform, /translate\(500px, 80px\)/);
  page.advance(440);
  assert.equal(page.cursor.hidden, true);
  assert.equal(page.desktop.classList.contains('cursor-in-flight'), false);
  assert.equal(page.desktop.dataset.hoverPlay, undefined);
  assert.equal(page.pending(), 0);
});

test('damaged and non-boolean stored modes cannot enable cursor batting', async t => {
  for (const saved of ['{broken', 'null', '{"batCursor":"true"}', '{"batCursor":1}']) {
    await t.test(saved, t => assert.equal(playground(t, {saved}).play.batCursor, false));
  }
});

test('button-held, touch, busy, hidden and modal visits do not take the canvas', async t => {
  for (const condition of ['button', 'touch', 'busy', 'hidden', 'modal']) {
    await t.test(condition, t => {
      const page = playground(t);
      if (condition === 'busy') page.setBusy(true);
      if (condition === 'hidden') page.document.hidden = true;
      if (condition === 'modal') page.setModal(true);
      page.move(500, 80, condition === 'button' ? {buttons: 1} : condition === 'touch' ? {pointerType: 'touch'} : {});
      page.advance(200);
      assert.equal(page.drawn.length, 0);
      assert.equal(page.hides(), 0);
      assert.equal(page.cursor.hidden, true);
    });
  }
});

test('real movement during flight restores the cursor and cancels further frames', t => {
  const page = playground(t, {saved: '{"batCursor":true}'});
  page.move(); page.advance(120); page.move(503, 80);
  assert.equal(page.cursor.hidden, true);
  assert.equal(page.desktop.classList.contains('cursor-in-flight'), false);
  assert.equal(page.pending(), 0);
  const poses = page.drawn.length;
  page.advance(500); assert.equal(page.drawn.length, poses);
});

test('small real moves accumulate from contact so slow movement also cancels flight', t => {
  const page = playground(t, {saved: '{"batCursor":true}'});
  page.move(); page.advance(120);
  page.move(501, 80); page.move(502, 80);
  assert.equal(page.cursor.hidden, false);
  page.move(503, 80);
  assert.equal(page.cursor.hidden, true);
  assert.equal(page.pending(), 0);
});

test('cancellation hides only hover-owned artwork, never a drag canvas', t => {
  const page = playground(t);
  page.play.cancel(); assert.equal(page.hides(), 0);
  page.move(700, 200); page.move(); page.advance(32);
  assert.ok(page.drawn.length > 0);
  page.desktop.dispatch('pointerdown');
  assert.equal(page.hides(), 1);
  page.play.cancel(); assert.equal(page.hides(), 1);
  assert.equal(page.pending(), 0);
});

test('Escape, blur, leaving, hidden page and busy state stop an active flight', async t => {
  for (const cause of ['escape', 'blur', 'leave', 'hidden', 'busy']) {
    await t.test(cause, t => {
      const page = playground(t, {saved: '{"batCursor":true}'});
      page.move(); page.advance(120);
      if (cause === 'escape') page.document.dispatch('keydown', {key: 'Escape'});
      if (cause === 'blur') page.window.dispatch('blur');
      if (cause === 'leave') page.desktop.dispatch('pointerleave');
      if (cause === 'hidden') { page.document.hidden = true; page.document.dispatch('visibilitychange'); }
      if (cause === 'busy') { page.setBusy(true); page.advance(16); }
      assert.equal(page.cursor.hidden, true);
      assert.equal(page.desktop.classList.contains('cursor-in-flight'), false);
      assert.equal(page.pending(), 0);
    });
  }
});

test('reduced motion uses a short wave even when batting is enabled', t => {
  const page = playground(t, {saved: '{"batCursor":true}', reduced: true});
  page.move(); assert.equal(page.desktop.dataset.hoverPlay, 'wave');
  page.advance(200);
  assert.equal(page.cursor.hidden, true);
  assert.ok(page.drawn.length > 0);
  page.advance(220);
  assert.equal(page.desktop.dataset.hoverPlay, undefined);
  assert.equal(page.desktop.classList.contains('cursor-in-flight'), false);
});
