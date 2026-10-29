const STORAGE_KEY = 'notch-monster-cursor-play';
const clamp = (value, low, high) => Math.max(low, Math.min(high, value));
const mix = (a, b, t) => ({x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t});
const ease = t => 1 - (1 - t) ** 3;

// A visit, not a timer: lingering or tiny boundary wobbles never repeat a swat.
export class HoverVisit {
  constructor() { this.armed = true; this.lastStarted = -Infinity; }
  sample(point, origin, now, eligible = true) {
    const dx = Math.abs(point.x - origin.x), dy = point.y - origin.y;
    const near = dx <= 60 && dy >= 28 && dy <= 132;
    const outside = dx > 86 || dy < 20 || dy > 160;
    if (outside) this.armed = true;
    if (!eligible) { if (!outside) this.armed = false; return false; }
    if (!near || !this.armed || now - this.lastStarted < 1400) return false;
    this.armed = false; this.lastStarted = now;
    return true;
  }
  cancel() { this.armed = false; }
}

export function flightEndpoint(point, origin, bounds) {
  const side = point.x < origin.x ? -1 : 1;
  const dx = point.x - origin.x;
  return {
    x: clamp(point.x + side * 230 + dx * 1.2, 12, Math.max(12, bounds.width - 28)),
    y: clamp(point.y + 330, 40, Math.max(40, bounds.height - 32))
  };
}

export class HoverPlay {
  constructor({desktop, renderer, origin, scale, reducedMotion, sounds, isBusy, storage}) {
    Object.assign(this, {desktop, renderer, origin, scale, reducedMotion, sounds, isBusy});
    try { this.storage = storage ?? globalThis.localStorage; } catch {}
    try { this.batCursor = JSON.parse(this.storage?.getItem(STORAGE_KEY) ?? 'null')?.batCursor === true; }
    catch { this.batCursor = false; }
    this.visit = new HoverVisit();
    this.phase = null; this.frame = 0; this.point = null;
    this.cursor = desktop.querySelector('#flying-cursor');
    desktop.addEventListener('pointermove', event => this.move(event));
    desktop.addEventListener('pointerleave', () => this.cancel());
    desktop.addEventListener('pointerdown', () => this.cancel(), true);
    desktop.addEventListener('dragenter', () => this.cancel());
    document.addEventListener('keydown', event => { if (event.key === 'Escape') this.cancel(); });
    document.addEventListener('visibilitychange', () => { if (document.hidden) this.cancel(); });
    globalThis.addEventListener('blur', () => this.cancel());
    reducedMotion.addEventListener('change', () => this.cancel());
  }

  setBatCursor(enabled) {
    this.batCursor = Boolean(enabled);
    this.cancel();
    try { this.storage?.setItem(STORAGE_KEY, JSON.stringify({batCursor: this.batCursor})); } catch {}
  }

  cancel({requireExit = true} = {}) {
    if (requireExit) this.visit.cancel();
    if (this.frame) cancelAnimationFrame(this.frame);
    this.frame = 0;
    // Never clear a drag's artwork when no hover animation owns the canvas.
    if (this.phase) this.renderer.hide();
    this.phase = null;
    this.desktop.classList.remove('cursor-in-flight');
    this.cursor.hidden = true;
    this.desktop.removeAttribute('data-hover-play');
  }

  move(event) {
    const rect = this.desktop.getBoundingClientRect();
    const point = {x: event.clientX - rect.left, y: event.clientY - rect.top};
    const eligible = event.pointerType === 'mouse' && event.buttons === 0 &&
      !this.isBusy() && !document.hidden && !document.querySelector('dialog[open]');
    if (!eligible) { this.cancel(); this.visit.sample(point, this.origin(), performance.now(), false); return; }
    if (this.phase === 'flight' && Math.hypot(point.x - this.launch.x, point.y - this.launch.y) > 2) {
      this.cancel(); return;
    }
    this.point = point;
    const origin = this.origin();
    if (this.phase && (Math.abs(point.x - origin.x) > 100 || point.y < 24 || point.y > 180)) this.cancel();
    if (this.phase) return;
    if (!this.visit.sample(point, origin, performance.now())) return;
    this.phase = this.batCursor && !this.reducedMotion.matches ? 'swat' : 'wave';
    this.started = performance.now();
    this.target = this.phase === 'wave' ? {x: origin.x, y: origin.y + 86 * this.scale()} : point;
    this.desktop.dataset.hoverPlay = this.phase;
    void this.sounds.play('reach');
    this.frame = requestAnimationFrame(now => this.tick(now));
  }

  draw(hand, curl = 0) {
    const origin = this.origin();
    this.renderer.draw({origin, hand, curl, visible: 1, scale: this.scale(),
      direction: {x: hand.x - origin.x, y: Math.max(1, hand.y - origin.y)}});
  }

  tick(now) {
    this.frame = 0;
    if (!this.phase) return;
    if (this.isBusy() || document.hidden || document.querySelector('dialog[open]')) { this.cancel(); return; }
    const elapsed = now - this.started, origin = this.origin();
    const hidden = {x: origin.x, y: origin.y - 78};
    if (this.phase === 'wave') {
      const reduced = this.reducedMotion.matches;
      const duration = reduced ? 400 : 830;
      let hand = {...this.target}, curl = 0;
      if (!reduced) {
        const wave = clamp((elapsed - 90) / 620, 0, 1);
        hand.x += Math.sin(wave * Math.PI * 4) * 19 * Math.sin(wave * Math.PI);
        curl = Math.sin(wave * Math.PI * 4) ** 2 * .28;
      }
      if (elapsed < 90) hand = mix(hidden, hand, ease(elapsed / 90));
      if (elapsed > duration - 100) hand = mix(hand, hidden, (elapsed - duration + 100) / 100);
      this.draw(hand, curl);
      if (elapsed >= duration) { this.cancel(); return; }
    } else if (this.phase === 'swat') {
      // Aim at the live pointer; contact and cursor launch share the same frame.
      this.target = {...this.point};
      const hand = mix(hidden, this.target, ease(clamp(elapsed / 115, 0, 1)));
      this.draw(hand);
      if (elapsed >= 115) {
        this.phase = 'flight'; this.hitAt = now;
        this.launch = {...this.target};
        this.endpoint = flightEndpoint(this.launch, origin, {width: this.desktop.clientWidth, height: this.desktop.clientHeight});
        this.cursor.hidden = false;
        this.desktop.classList.add('cursor-in-flight');
        this.desktop.dataset.hoverPlay = 'flight';
        this.positionCursor(this.launch, 0);
        void this.sounds.play('file');
      }
    } else if (this.phase === 'flight') {
      const t = clamp((now - this.hitAt) / 420, 0, 1);
      const point = mix(this.launch, this.endpoint, ease(t));
      point.y -= Math.sin(t * Math.PI) * 32;
      this.positionCursor(point, t);
      const retreat = clamp((now - this.hitAt - 35) / 100, 0, 1);
      this.draw(mix(this.launch, hidden, retreat));
      if (t >= 1) { this.cancel(); return; }
    }
    this.frame = requestAnimationFrame(time => this.tick(time));
  }

  positionCursor(point, t) {
    const side = this.endpoint.x < this.launch.x ? -1 : 1;
    this.cursor.style.transform = `translate(${point.x}px, ${point.y}px) rotate(${side * t * 300}deg)`;
    this.cursor.style.opacity = String(1 - clamp((t - .8) / .2, 0, 1));
  }
}
