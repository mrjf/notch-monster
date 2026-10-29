import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import * as attachment from '../dist/attachment.js';

// Execute the production event handlers. Only browser plumbing, drawing and
// time are replaced; attachment, pointer dispatch and consumption stay real.
const source = readFileSync(new URL('../dist/demo.js', import.meta.url), 'utf8')
  .replace(/^import .*;\n/gm, '');

function playground({fileHome = {x: 750, y: 200}} = {}) {
  let now = 0, nextID = 1, rendered = null;
  const frames = new Map(), timers = new Map();
  class Element {
    constructor(id, home = {x: 0, y: 0}, kind) {
      this.id = id; this.home = home; this.style = {};
      this.dataset = kind ? {kind, label: kind === 'file' ? 'test.pdf' : 'Safari window'} : {};
      this.textContent = ''; this.hidden = false; this.listeners = new Map();
      this.offsetWidth = kind === 'window' ? 760 : 104;
      this.offsetHeight = kind === 'window' ? 445 : 84;
      const classes = new Set(), captures = new Set();
      this.classList = {add: name => classes.add(name), remove: name => classes.delete(name)};
      this.setPointerCapture = id => captures.add(id);
      this.hasPointerCapture = id => captures.has(id);
      this.releasePointerCapture = id => captures.delete(id);
    }
    addEventListener(type, handler) { this.listeners.set(type, handler); }
    querySelector() { return null; }
    querySelectorAll() { return []; }
    removeAttribute(name) { if (name === 'data-consumed') delete this.dataset.consumed; }
    getBoundingClientRect() {
      const left = parseFloat(this.style.left), top = parseFloat(this.style.top);
      return {left: Number.isFinite(left) ? left : this.home.x, top: Number.isFinite(top) ? top : this.home.y,
        width: this.offsetWidth, height: this.offsetHeight};
    }
    animate() { return {cancel() {}}; }
    contains() { return false; }
    focus() {}
  }
  const ids = ['desktop', 'monster-canvas', 'notch', 'demo-status', 'snack-count', 'desktop-hint',
    'notch-cue', 'empty-desktop', 'feed-one', 'reset-demo', 'safari-light', 'trash-icon',
    'dock-safari', 'dock-finder', 'dock-trash'];
  const elements = Object.fromEntries(ids.map(id => [id, new Element(id)]));
  const window = new Element('demo-browser', {x: 120, y: 200}, 'window');
  const file = new Element('demo-pdf', fileHome, 'file');
  const items = [window, file];
  Object.assign(elements.desktop, {clientWidth: 1000, clientHeight: 800});
  const context = vm.createContext({
    ...attachment,
    document: {querySelector: selector => elements[selector.slice(1)], querySelectorAll: () => items, activeElement: null},
    matchMedia: () => ({matches: false}),
    performance: {now: () => now},
    requestAnimationFrame: callback => { const id = nextID++; frames.set(id, callback); return id; },
    setTimeout: (callback, delay) => { const id = nextID++; timers.set(id, {callback, at: now + delay}); return id; },
    ResizeObserver: class { observe() {} },
    MonsterArm: class { resize() {} hide() { rendered = null; } draw(pose) { rendered = pose; } },
    SoundEffects: class { unlock() {} play() {} cancelReach() {} stop() {} },
    installSoundSettings() {},
    HoverPlay: class { cancel() {} }
  });
  new vm.Script(source, {filename: 'demo.js'}).runInContext(context);
  function pointer(type, x, y) {
    file.listeners.get(type)({button: 0, pointerId: 1, clientX: x, clientY: y,
      currentTarget: file, preventDefault() {}});
  }
  async function advance(milliseconds) {
    const end = now + milliseconds;
    while (now < end) {
      now = Math.min(now + 16, end);
      const callbacks = [...frames.values()]; frames.clear();
      callbacks.forEach(callback => callback(now));
      for (const [id, timer] of timers) {
        if (timer.at <= now) { timers.delete(id); timer.callback(); }
      }
      await Promise.resolve(); await Promise.resolve();
    }
  }
  return {file, pointer, advance, hand: () => rendered?.hand,
    status: () => elements['demo-status'].textContent,
    approach() { pointer('pointerdown', fileHome.x + 50, fileHome.y + 20); pointer('pointermove', 500, 80); }};
}

async function expectConsumed(page) {
  await page.advance(500);
  assert.equal(page.file.dataset.consumed, 'true');
  assert.equal(page.file.hidden, true);
  assert.match(page.status(), /Trash/);
}
async function expectKept(page) {
  await page.advance(500);
  assert.equal(page.file.dataset.consumed, undefined);
  assert.equal(page.file.hidden, false);
}

test('a fast approach and release feeds before the reach animation finishes', async () => {
  const page = playground();
  page.approach(); page.pointer('pointerup', 500, 80);
  await expectConsumed(page);
});

test('a fast toss is caught when one pointer event skips across the entire grab zone', async () => {
  const page = playground();
  page.pointer('pointerdown', 800, 220);
  page.pointer('pointermove', 200, 80);
  page.pointer('pointerup', 200, 80);
  await expectConsumed(page);
});

test('a fast throw can overshoot the top of the notch without stopping', async () => {
  const page = playground();
  page.pointer('pointerdown', 800, 220);
  page.pointer('pointermove', 520, 90);
  page.pointer('pointermove', 500, 10);
  page.pointer('pointermove', 495, -70);
  page.pointer('pointerup', 495, -70);
  await expectConsumed(page);
});

test('a toss through the opening feeds even when mouse-up happens outside the page', async () => {
  const page = playground();
  page.pointer('pointerdown', 800, 220);
  page.pointer('pointermove', 520, 90);
  page.pointer('pointermove', 500, -70);
  // No pointerup: browsers may deliver it to browser chrome instead of the page.
  await expectConsumed(page);
});

test('a single release event can carry a toss through the grab zone', async () => {
  const page = playground();
  page.pointer('pointerdown', 800, 220);
  page.pointer('pointerup', 200, 80);
  await expectConsumed(page);
});

test('stopping after a fast overshoot keeps the accepted offer ready', async () => {
  const page = playground();
  page.pointer('pointerdown', 800, 220);
  page.pointer('pointermove', 520, 90);
  page.pointer('pointermove', 200, 80);
  await page.advance(500);
  page.pointer('pointerup', 200, 80);
  await expectConsumed(page);
});

test('a tiny wobble after a fast overshoot still feeds after a pause', async () => {
  const page = playground();
  page.pointer('pointerdown', 800, 220);
  page.pointer('pointermove', 200, 80);
  await page.advance(500);
  page.pointer('pointermove', 201, 80);
  page.pointer('pointerup', 201, 80);
  await expectConsumed(page);
});

test('clearly backing farther away after the toss still lets the item go', async () => {
  const page = playground();
  page.pointer('pointerdown', 800, 220);
  page.pointer('pointermove', 200, 80);
  await page.advance(500);
  page.pointer('pointermove', 150, 80);
  await page.advance(200);
  page.pointer('pointerup', 150, 80);
  await expectKept(page);
});

test('a fast drag passing far below the notch stays on the desktop', async () => {
  const page = playground();
  page.pointer('pointerdown', 800, 300);
  page.pointer('pointermove', 200, 300);
  page.pointer('pointerup', 200, 300);
  await expectKept(page);
});

test('a release-only wobble keeps the accepted drop even before the hand arrives', async t => {
  for (const delay of [0, 10, 20]) {
    await t.test(`release after ${delay} ms`, async () => {
      const page = playground();
      page.approach(); await page.advance(delay);
      page.pointer('pointerup', 500, 94);
      await expectConsumed(page);
    });
  }
});

test('a quick release just beyond the top edge keeps the accepted drop', async () => {
  const page = playground();
  page.pointer('pointerdown', 800, 220);
  page.pointer('pointermove', 500, 15);
  page.pointer('pointerup', 500, -1);
  await expectConsumed(page);
});

test('a release that supplies the first in-reach sample feeds immediately', async () => {
  const page = playground();
  page.pointer('pointerdown', 800, 220);
  page.pointer('pointerup', 500, 80);
  await expectConsumed(page);
});

test('release-only grace is bounded and cannot swallow a large final jump', async t => {
  await t.test('48 pixels still feeds the accepted drop', async () => {
    const page = playground();
    page.approach();
    page.pointer('pointerup', 500, 128);
    await expectConsumed(page);
  });
  await t.test('49 pixels clear of the hand keeps the item', async () => {
    const page = playground();
    page.approach();
    page.pointer('pointerup', 500, 129);
    await expectKept(page);
  });
});

test('a modest outward move still feeds before the first animation frame', async () => {
  const page = playground();
  page.approach();
  page.pointer('pointermove', 500, 94);
  page.pointer('pointerup', 500, 94);
  await expectConsumed(page);
});

test('a quick drop farther below the notch is already in reach', async () => {
  const page = playground();
  page.pointer('pointerdown', 800, 220);
  page.pointer('pointermove', 500, 200);
  page.pointer('pointerup', 500, 200);
  await expectConsumed(page);
});

test('the hand reaches a newly offered item within fifty milliseconds', async () => {
  const page = playground();
  page.pointer('pointerdown', 800, 220);
  page.pointer('pointermove', 500, 200);
  await page.advance(50);
  assert.deepEqual({...page.hand()}, {x: 500, y: 200});
});

test('an eight-pixel outward wobble and pause keep the item attached', async () => {
  const page = playground();
  page.approach(); await page.advance(100);
  page.pointer('pointermove', 500, 88); await page.advance(300);
  assert.deepEqual({...page.hand()}, {x: 500, y: 88});
  page.pointer('pointerup', 500, 88);
  await expectConsumed(page);
});

test('you must back away a full hand width before he lets go', async () => {
  const page = playground();
  page.approach(); await page.advance(100);
  for (const y of [90, 100, 110, 115]) {
    page.pointer('pointermove', 500, y); await page.advance(100);
    assert.deepEqual({...page.hand()}, {x: 500, y});
  }
  await page.advance(500);
  page.pointer('pointerup', 500, 115);
  await expectConsumed(page);
});

test('the stronger hold also follows beyond the initial reach boundary', async () => {
  const page = playground();
  page.pointer('pointerdown', 800, 220);
  page.pointer('pointermove', 500, 208); await page.advance(100);
  page.pointer('pointermove', 500, 240); await page.advance(300);
  assert.deepEqual({...page.hand()}, {x: 500, y: 240});
  page.pointer('pointerup', 500, 240);
  await expectConsumed(page);
});

test('moving just beyond the top edge keeps the hand attached for the drop', async () => {
  const page = playground();
  page.pointer('pointerdown', 800, 220);
  page.pointer('pointermove', 500, 15);
  page.pointer('pointermove', 500, -1);
  page.pointer('pointerup', 500, -1);
  await expectConsumed(page);
});

test('a small wobble across the reach boundary does not drop an attached item', async () => {
  const page = playground();
  page.pointer('pointerdown', 800, 220);
  page.pointer('pointermove', 500, 208); await page.advance(100);
  page.pointer('pointermove', 500, 216); await page.advance(300);
  assert.deepEqual({...page.hand()}, {x: 500, y: 216});
  page.pointer('pointerup', 500, 216);
  await expectConsumed(page);
});

test('stopping with the hand on the item keeps the drop ready', async () => {
  const page = playground();
  page.approach(); await page.advance(400);
  assert.deepEqual({...page.hand()}, {x: 500, y: 80});
  page.pointer('pointerup', 500, 80);
  await expectConsumed(page);
});

test('a final pointer-up wobble still feeds when the rendered hand touches it', async () => {
  const page = playground();
  page.approach(); await page.advance(100);
  page.pointer('pointerup', 500, 86);
  // The pointer-up coordinate also moves the item, preserving its grab offset.
  assert.equal(parseFloat(page.file.style.top), 66);
  await expectConsumed(page);
});

test('a stationary hold already in reach feeds without crossing a drag threshold', async () => {
  const page = playground({fileHome: {x: 450, y: 60}});
  page.pointer('pointerdown', 500, 80); await page.advance(200);
  page.pointer('pointerup', 500, 80);
  await expectConsumed(page);
});

test('release during the first visible part of retreat still feeds on contact', async () => {
  const page = playground();
  page.approach(); await page.advance(100);
  page.pointer('pointermove', 500, 116);
  assert.ok(Math.abs(page.hand().y - 116) <= 36);
  page.pointer('pointerup', 500, 116);
  await expectConsumed(page);
});

test('a deliberate withdrawal followed by a pause keeps the item', async () => {
  const page = playground();
  page.approach(); await page.advance(100);
  page.pointer('pointermove', 500, 130); await page.advance(200);
  assert.equal(page.hand(), undefined);
  page.pointer('pointerup', 500, 130);
  await expectKept(page);
});

test('moving inward again after a deliberate withdrawal reattaches promptly', async () => {
  const page = playground();
  page.approach(); await page.advance(100);
  page.pointer('pointermove', 500, 130); await page.advance(200);
  assert.equal(page.hand(), undefined);
  page.pointer('pointermove', 500, 129); await page.advance(50);
  assert.deepEqual({...page.hand()}, {x: 500, y: 129});
  page.pointer('pointerup', 500, 129);
  await expectConsumed(page);
});

test('a large final jump clear of the hand keeps the item', async () => {
  const page = playground();
  page.approach(); await page.advance(100);
  page.pointer('pointerup', 500, 200);
  assert.equal(parseFloat(page.file.style.top), 180);
  await expectKept(page);
});
