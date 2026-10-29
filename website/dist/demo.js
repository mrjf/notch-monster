import { MonsterArm } from './monster.js?v=aperture-clip';
import { CaptureGesture, canFeedOnRelease } from './attachment.js?v=deliberate-backoff';
import { SoundEffects } from './sounds.js?v=muted-default';
import { installSoundSettings } from './sound-settings.js?v=hover-play';
import { HoverPlay } from './hover-play.js?v=hover-play';

const desktop = document.querySelector('#desktop');
const canvas = document.querySelector('#monster-canvas');
const notch = document.querySelector('#notch');
const status = document.querySelector('#demo-status');
const counter = document.querySelector('#snack-count');
const hint = document.querySelector('#desktop-hint');
const cue = document.querySelector('#notch-cue');
const empty = document.querySelector('#empty-desktop');
const feedButton = document.querySelector('#feed-one');
const resetButton = document.querySelector('#reset-demo');
const safariLight = document.querySelector('#safari-light');
const trashIcon = document.querySelector('#trash-icon');
const renderer = new MonsterArm(canvas);
// Keep hold through ordinary trackpad wobble; an intentional pull still lets go.
const attachment = new CaptureGesture(48, 1);
const sounds = new SoundEffects();
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
const items = [...document.querySelectorAll('.demo-item')].map(element => ({element, x: 0, y: 0, consumed: false}));
const animations = new Set();
let drag = null, busy = false, snacks = 0, revision = 0, frameID = 0;
let width = 0, height = 0;
let arm = {phase: 'hidden', point: {x: 0, y: 0}, hand: {x: 0, y: 0}, direction: {x: 0, y: 1}, curl: 0, entered: 0};

// Top-center keeps the shaft's entire clipped base inside the shallow notch,
// even when the hand reaches almost horizontally along the menu bar.
const origin = () => ({x: width / 2, y: 0});
const radius = () => Math.min(210, width * .42);
const armScale = () => width < 560 ? .82 : 1;
const updateAttachment = point => attachment.update(point, origin(), radius(), performance.now());
const clamp = (value, low, high) => Math.max(low, Math.min(high, value));
const mix = (a, b, t) => ({x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t});
const ease = t => 1 - Math.pow(1 - t, 3);
const pause = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const pointFromEvent = event => { const rect = desktop.getBoundingClientRect(); return {x: event.clientX - rect.left, y: event.clientY - rect.top}; };
const hoverPlay = new HoverPlay({desktop, renderer, origin, scale: armScale, reducedMotion, sounds,
  isBusy: () => Boolean(drag || busy || arm.phase !== 'hidden')});
installSoundSettings(sounds, hoverPlay);
function place(item, x, y) {
  item.element.classList.remove('at-home');
  item.x = x; item.y = y;
  item.element.style.left = `${x}px`; item.element.style.top = `${y}px`;
}
function holdPosition(item) {
  const rect = item.element.getBoundingClientRect(), bounds = desktop.getBoundingClientRect();
  place(item, rect.left - bounds.left, rect.top - bounds.top);
}
function say(message) { if (status.textContent !== message) status.textContent = message; }
function hideInstructions() { cue.style.opacity = '0'; hint.style.opacity = '0'; }

function drawArm(hand, curl, direction = arm.direction) {
  arm.hand = hand; arm.curl = curl;
  renderer.draw({origin: origin(), hand, curl, visible: 1, direction, scale: armScale()});
}
function hiddenPoint(direction = arm.direction) {
  const length = Math.max(1, Math.hypot(direction.x, direction.y));
  return {x: origin().x - direction.x / length * 76, y: origin().y - direction.y / length * 76};
}
function ensureFrame() { if (!frameID) frameID = requestAnimationFrame(tick); }
function tick(now) {
  frameID = 0;
  if (arm.phase === 'reaching') {
    const extension = reducedMotion.matches ? 1 : clamp((now - arm.entered) / 40, 0, 1);
    // Stay open while tracking. Curl only when the item is actually released
    // into the hand, so a closed fist never floats beside an unheld item.
    drawArm(mix(hiddenPoint(), arm.point, extension), 0);
    if (extension === 1) say('Ready when you are. Drop to feed, or move away to keep it.');
    ensureFrame();
  } else if (arm.phase === 'retreating') {
    const t = reducedMotion.matches ? 1 : clamp((now - arm.retreatStart) / 85, 0, 1);
    const curl = arm.retreatCurl * (1 - clamp((now - arm.retreatStart) / 45, 0, 1));
    drawArm(mix(arm.retreatFrom, hiddenPoint(), t), curl);
    if (t >= 1) { arm.phase = 'hidden'; renderer.hide(); } else ensureFrame();
  }
}
function approach(point) {
  if (updateAttachment(point)) {
    if (arm.phase !== 'reaching') {
      arm.phase = 'reaching'; arm.entered = performance.now();
      void sounds.play('reach');
      say('A snack? Release when you’re ready…');
    }
    arm.point = point;
    arm.direction = {x: point.x - origin().x, y: point.y - origin().y};
    ensureFrame();
  } else {
    if (arm.phase === 'reaching') say('The hand slips away. Bring it back, or keep it.');
    retreat();
  }
}
function retreat() {
  sounds.cancelReach();
  notch.classList.remove('gripping');
  if (arm.phase === 'hidden' || arm.phase === 'retreating') return;
  arm = {...arm, phase: 'retreating', retreatStart: performance.now(), retreatFrom: {...arm.hand}, retreatCurl: arm.curl};
  ensureFrame();
}

function animate(duration, update, token = revision) {
  return new Promise(resolve => {
    const start = performance.now();
    function frame(now) {
      if (token !== revision) { resolve(false); return; }
      const t = clamp((now - start) / duration, 0, 1);
      update(t);
      if (t < 1) requestAnimationFrame(frame); else resolve(true);
    }
    requestAnimationFrame(frame);
  });
}

function beginDrag(event, item) {
  if (drag || busy || item.consumed || event.button !== 0) return;
  hoverPlay.cancel();
  event.preventDefault();
  sounds.unlock();
  holdPosition(item);
  const point = pointFromEvent(event);
  attachment.reset();
  drag = {item, handle: event.currentTarget, id: event.pointerId, offset: {x: point.x - item.x, y: point.y - item.y}, start: point, lastPoint: point, moved: false};
  event.currentTarget.setPointerCapture(event.pointerId);
  item.element.classList.add('dragging');
  hideInstructions();
  say('Bring it toward the notch. Drop into the open hand to feed it.');
  approach(point);
}
function moveDrag(event) {
  if (!drag || drag.id !== event.pointerId) return;
  event.preventDefault();
  const point = pointFromEvent(event);
  const previous = drag.lastPoint;
  moveDraggedItem(point);
  approach(point);
  // A fast toss can leave the page through the browser chrome before its
  // mouse-up reaches us. Crossing the actual hole is itself a completed feed.
  if (attachment.attached && previous.y > 0 && point.y <= 0) {
    const t = previous.y / (previous.y - point.y);
    const crossingX = previous.x + (point.x - previous.x) * t;
    if (Math.abs(crossingX - origin().x) <= notch.offsetWidth / 2) releaseDrag(event);
  }
}
function moveDraggedItem(point) {
  drag.lastPoint = point;
  if (Math.hypot(point.x - drag.start.x, point.y - drag.start.y) > 4) drag.moved = true;
  place(drag.item,
    clamp(point.x - drag.offset.x, -drag.item.element.offsetWidth + 24, width - 24),
    clamp(point.y - drag.offset.y, -drag.item.element.offsetHeight + 24, height - 24));
}
function releaseDrag(event) {
  if (!drag || drag.id !== event.pointerId) return;
  event.preventDefault();
  const released = drag, point = pointFromEvent(event);
  // Snapshot readiness BEFORE processing the final coordinate. A release
  // wobble must not undo a grab just because the arm's first frame is pending.
  const readyPoint = attachment.attached ? released.lastPoint : null;
  const accepted = attachment.attached || (!attachment.withdrawn && updateAttachment(point));
  const canConsume = canFeedOnRelease({
    readyPoint, attached: accepted, withdrawn: attachment.withdrawn, phase: arm.phase,
    hand: arm.hand, point, scale: armScale()
  });
  // Some devices put the last movement only on pointerup.
  moveDraggedItem(point);
  attachment.reset();
  drag = null;
  if (released.handle.hasPointerCapture(event.pointerId)) released.handle.releasePointerCapture(event.pointerId);
  released.item.element.classList.remove('dragging');
  if (canConsume) void consume(released.item, point);
  else {
    retreat();
    if (released.moved) say('Still yours. Move toward the notch again to feed it.');
  }
}
function cancelDrag(event) {
  if (!drag || drag.id !== event.pointerId) return;
  attachment.reset();
  drag.item.element.classList.remove('dragging'); drag = null; retreat();
  say('Grab cancelled. Everything stays on the desktop.');
}

for (const item of items) {
  const handle = item.element.querySelector('.drag-handle') || item.element;
  handle.addEventListener('pointerdown', event => beginDrag(event, item));
  handle.addEventListener('pointermove', moveDrag);
  handle.addEventListener('pointerup', releaseDrag);
  handle.addEventListener('pointercancel', cancelDrag);
  handle.addEventListener('lostpointercapture', event => {
    if (drag?.id !== event.pointerId) return;
    // Some browsers lose capture at release before the handle gets pointerup.
    // A canceled pointer has already cleared drag; held buttons still cancel.
    if (event.buttons === 0 && document.hasFocus?.() !== false) {
      const bounds = desktop.getBoundingClientRect(), point = drag.lastPoint;
      releaseDrag({pointerId: event.pointerId, clientX: point.x + bounds.left,
        clientY: point.y + bounds.top, preventDefault() {}});
    } else cancelDrag(event);
  });
  handle.addEventListener('click', event => {
    // Native button activation via Enter, Space, or assistive technology.
    if (event.detail === 0 && !busy && !item.consumed) void feedAutomatically(item);
  });
  item.element.addEventListener('dragstart', event => event.preventDefault());
}

async function feedAutomatically(item) {
  if (drag || busy || item.consumed) return;
  hoverPlay.cancel();
  sounds.unlock();
  holdPosition(item);
  attachment.reset();
  busy = true; const token = revision;
  hideInstructions();
  item.element.classList.add('dragging');
  const offset = {x: item.element.offsetWidth / 2, y: item.element.dataset.kind === 'window' ? 15 : 35};
  const start = {x: item.x + offset.x, y: item.y + offset.y};
  const target = {x: origin().x + Math.min(29, width * .05), y: 79};
  const moved = await animate(reducedMotion.matches ? 50 : 320, t => {
    const point = mix(start, target, ease(t));
    place(item, point.x - offset.x, point.y - offset.y);
    approach(point);
  }, token);
  if (!moved) return;
  await pause(reducedMotion.matches ? 30 : 170);
  if (token !== revision) return;
  item.element.classList.remove('dragging');
  await consume(item, target, true);
}

async function consume(item, point, alreadyBusy = false) {
  if ((busy && !alreadyBusy) || item.consumed) return;
  sounds.cancelReach();
  attachment.reset();
  busy = true; const token = revision;
  arm.phase = 'feeding';
  arm.direction = {x: point.x - origin().x, y: point.y - origin().y};
  const startCurl = arm.curl;
  // Close around the dropped item, then yank without replaying the reach.
  if (startCurl < 1) {
    const closed = await animate(reducedMotion.matches ? 1 : 45, t => drawArm(point, startCurl + (1 - startCurl) * t), token);
    if (!closed) return;
  }
  notch.classList.add('gripping');
  const duration = reducedMotion.matches ? 100 : (item.element.dataset.kind === 'window' ? 220 : 150);
  const delta = {x: origin().x - point.x, y: origin().y - point.y};
  const anchor = {x: point.x - item.x, y: point.y - item.y};
  const ghosts = [];
  const isWindow = item.element.dataset.kind === 'window';
  void sounds.play(isWindow ? 'window' : 'file');
  if (isWindow && !reducedMotion.matches) {
    for (let i = 0; i < 12; i++) {
      const fragment = document.createElement('div');
      fragment.className = 'window-fragment'; fragment.setAttribute('aria-hidden', 'true');
      Object.assign(fragment.style, {left: `${item.x}px`, top: `${item.y}px`, width: `${item.element.offsetWidth}px`, height: `${item.element.offsetHeight}px`, clipPath: `polygon(${i / 12 * 100}% 0, ${(i + 1) / 12 * 100 + .1}% 0, ${(i + 1) / 12 * 100 + .1}% 100%, ${i / 12 * 100}% 100%)`, transformOrigin: `${anchor.x}px ${anchor.y}px`});
      const clone = item.element.cloneNode(true);
      clone.removeAttribute('id'); clone.removeAttribute('data-kind'); clone.classList.remove('dragging');
      clone.inert = true;
      clone.querySelectorAll('[id]').forEach(element => element.removeAttribute('id'));
      Object.assign(clone.style, {left: '0', top: '0', width: `${item.element.offsetWidth}px`, margin: '0'});
      fragment.append(clone); desktop.append(fragment); ghosts.push(fragment);
      const side = i % 2 ? 1 : -1;
      const animation = fragment.animate([
        {transform: 'translate(0,0) scale(1,1)', opacity: 1, filter: 'brightness(1)'},
        {offset: .45, transform: `translate(${delta.x * .63}px,${delta.y * .63}px) scale(.43,.76) skewY(${side * 9}deg) rotateY(${side * 40}deg)`, opacity: 1, filter: `brightness(${i % 2 ? .82 : 1.08})`},
        {transform: `translate(${delta.x}px,${delta.y}px) scale(.006,.012) skewY(${side * 16}deg) rotateY(${side * 74}deg)`, opacity: 0, filter: 'brightness(.7)'}
      ], {duration, easing: 'cubic-bezier(.2,.65,.3,1)', fill: 'forwards'});
      animations.add(animation);
    }
    item.element.style.visibility = 'hidden';
  } else {
    item.element.style.transformOrigin = `${anchor.x}px ${anchor.y}px`;
    const animation = item.element.animate(reducedMotion.matches ? [{opacity: 1}, {opacity: 0}] : [
      {transform: 'translate(0,0) scale(1)', opacity: 1},
      {offset: .8, transform: `translate(${delta.x * .97}px,${delta.y * .97}px) scale(.35)`, opacity: 1},
      {transform: `translate(${delta.x}px,${delta.y}px) scale(.01)`, opacity: 0}
    ], {duration, easing: 'cubic-bezier(.2,.65,.3,1)', fill: 'forwards'});
    animations.add(animation);
  }
  const completed = await animate(duration, t => drawArm(mix(point, origin(), ease(t)), 1), token);
  ghosts.forEach(ghost => ghost.remove());
  if (!completed) return;
  const itemHadFocus = item.element.contains(document.activeElement);
  const feedButtonHadFocus = document.activeElement === feedButton;
  item.consumed = true;
  item.element.hidden = true;
  item.element.dataset.consumed = 'true';
  item.element.style.visibility = '';
  animations.forEach(animation => animation.cancel()); animations.clear();
  arm.phase = 'hidden'; renderer.hide(); notch.classList.remove('gripping');
  snacks++; counter.textContent = `${snacks} / 4 snacks`;
  updateDock();
  busy = false;
  say(isWindow ? 'One less window. Nicely devoured.' : `${item.element.dataset.label} → Trash. Delicious.`);
  if (snacks === items.length) {
    empty.hidden = false; feedButton.disabled = true;
    say('All gone. One clean desktop, one extremely full monster.');
  }
  if (itemHadFocus || (feedButton.disabled && feedButtonHadFocus)) {
    resetButton.focus({preventScroll: true});
  }
}

function reset(announce = true) {
  hoverPlay.cancel({requireExit: announce});
  revision++;
  sounds.stop();
  attachment.reset();
  if (drag) {
    if (drag.handle.hasPointerCapture(drag.id)) drag.handle.releasePointerCapture(drag.id);
    drag = null;
  }
  animations.forEach(animation => animation.cancel()); animations.clear();
  desktop.querySelectorAll('.window-fragment').forEach(element => element.remove());
  arm.phase = 'hidden'; arm.curl = 0; renderer.hide();
  notch.classList.remove('gripping');
  snacks = 0; busy = false; empty.hidden = true; feedButton.disabled = false;
  counter.textContent = '0 / 4 snacks';
  items.forEach(item => {
    item.consumed = false; item.element.hidden = false;
    item.element.removeAttribute('data-consumed');
    item.element.style.visibility = ''; item.element.style.transform = ''; item.element.style.transformOrigin = '';
    item.element.classList.remove('dragging');
    placeAtHome(item);
  });
  updateDock();
  hint.style.opacity = '1'; cue.style.opacity = '1';
  if (announce) say('Fresh snacks. Drag toward the notch, or tap an item to try it.');
}
function placeAtHome(item) {
  item.element.style.left = '';
  item.element.style.top = '';
  item.element.classList.add('at-home');
}
function updateDock() {
  safariLight.hidden = items[0].consumed;
  trashIcon.src = items.some(item => item.consumed && item.element.dataset.kind === 'file')
    ? './assets/snow-leopard/trash-full.png' : './assets/snow-leopard/trash.png';
}
function restoreItem(item) {
  item.consumed = false;
  item.element.hidden = false;
  item.element.removeAttribute('data-consumed');
  item.element.style.visibility = '';
  item.element.style.transform = '';
  item.element.style.transformOrigin = '';
  placeAtHome(item);
  snacks = items.filter(item => item.consumed).length;
  counter.textContent = `${snacks} / 4 snacks`;
  feedButton.disabled = false;
  empty.hidden = true;
  updateDock();
}
document.querySelector('#dock-safari').addEventListener('click', () => {
  if (busy || drag) return;
  restoreItem(items[0]);
  say('Safari is back. Drag its title bar toward the notch to feed it again.');
});
document.querySelector('#dock-finder').addEventListener('click', () => reset());
document.querySelector('#dock-trash').addEventListener('click', () => {
  if (busy || drag) return;
  items.forEach((item, index) => { if (index > 0) restoreItem(item); });
  say('Your pretend files are back on the desktop.');
});
resetButton.addEventListener('click', () => reset());
feedButton.addEventListener('click', () => { const next = items.find(item => !item.consumed); if (next) void feedAutomatically(next); });
// This playground never accepts or reads an actual file dropped from the OS.
desktop.addEventListener('dragover', event => event.preventDefault());
desktop.addEventListener('drop', event => { event.preventDefault(); say('Only the pretend items, please. Your real files stay yours.'); });
new ResizeObserver(() => {
  // CSS keeps untouched items at home. Resizing must not move parked items
  // or restore snacks that the monster has already eaten.
  if (width !== desktop.clientWidth || height !== desktop.clientHeight) hoverPlay.cancel();
  width = desktop.clientWidth; height = desktop.clientHeight;
  renderer.resize();
}).observe(desktop);
width = desktop.clientWidth; height = desktop.clientHeight;
renderer.resize(); reset(false);
