export const SOUND_SETS = Object.freeze({
  fuzzy: 'Fuzzy',
  rubber: 'Rubber',
  arcade: 'Arcade'
});
const EVENTS = ['reach', 'file', 'window'];
const STORAGE_KEY = 'notch-monster-sounds';

// Samples are made with Earshot and already levelled for short UI feedback.
// Creating/resuming the audio context happens only inside a user gesture.
export class SoundEffects {
  constructor({storage, createContext, fetchAudio, now} = {}) {
    try { this.storage = storage ?? globalThis.localStorage; } catch {}
    this.createContext = createContext ?? (() => {
      const Context = globalThis.AudioContext ?? globalThis.webkitAudioContext;
      return Context ? new Context() : null;
    });
    this.fetchAudio = fetchAudio ?? (url => fetch(url));
    this.now = now ?? (() => performance.now());
    let saved;
    try { saved = JSON.parse(this.storage?.getItem(STORAGE_KEY) ?? 'null'); } catch {}
    this.enabled = typeof saved?.enabled === 'boolean' ? saved.enabled : false;
    this.set = Object.hasOwn(SOUND_SETS, saved?.set) ? saved.set : 'fuzzy';
    this.context = null;
    this.buffers = new Map();
    this.active = new Map();
    this.requests = new Map();
    this.generation = 0;
    this.lastReach = -Infinity;
  }

  unlock() {
    if (!this.enabled) return;
    try {
      this.context ??= this.createContext();
      if (!this.context) return;
      if (this.context.state !== 'running') void this.context.resume().catch(() => {});
      for (const event of EVENTS) void this.load(this.set, event);
    } catch { /* Audio is optional; a blocked context must never block a drag. */ }
  }

  setEnabled(enabled) {
    this.enabled = Boolean(enabled);
    this.stop();
    this.save();
  }

  selectSet(set) {
    if (!Object.hasOwn(SOUND_SETS, set)) return;
    this.set = set;
    this.stop();
    this.save();
    if (this.context && this.enabled) {
      for (const event of EVENTS) void this.load(set, event);
    }
  }

  save() {
    try { this.storage?.setItem(STORAGE_KEY, JSON.stringify({enabled: this.enabled, set: this.set})); } catch {}
  }

  load(set, event) {
    if (!this.context) return Promise.resolve(null);
    const key = `${set}-${event}`;
    if (!this.buffers.has(key)) {
      const context = this.context;
      const promise = Promise.resolve().then(() => this.fetchAudio(`./assets/sounds/${key}.wav`))
        .then(response => { if (!response.ok) throw new Error('Sound unavailable'); return response.arrayBuffer(); })
        .then(data => context.decodeAudioData(data))
        .catch(() => { this.buffers.delete(key); return null; });
      this.buffers.set(key, promise);
    }
    return this.buffers.get(key);
  }

  async play(event, {preview = false} = {}) {
    if (!EVENTS.includes(event) || !this.enabled || !this.context) return false;
    const started = this.now();
    if (event === 'reach' && !preview) {
      // Small direction changes may re-enter reach; do not chatter every frame.
      if (started - this.lastReach < 240) return false;
      this.lastReach = started;
    }
    const channel = preview ? 'preview' : event === 'reach' ? 'reach' : 'yank';
    this.cancel(channel);
    const request = {}, generation = this.generation;
    this.requests.set(channel, request);
    const buffer = await this.load(this.set, event);
    // Slow first fetches may warm the cache, but cannot sound after the action.
    const tooLate = !preview && this.now() - started > (event === 'reach' ? 120 : 220);
    if (!buffer || tooLate || !this.enabled || this.generation !== generation ||
        this.requests.get(channel) !== request || this.context.state !== 'running') return false;
    try {
      const source = this.context.createBufferSource();
      source.buffer = buffer;
      source.connect(this.context.destination);
      this.active.set(channel, source);
      source.onended = () => {
        source.disconnect();
        if (this.active.get(channel) === source) this.active.delete(channel);
      };
      source.start();
      return true;
    } catch { return false; }
  }

  cancel(channel) {
    this.requests.delete(channel);
    const source = this.active.get(channel);
    this.active.delete(channel);
    if (source) {
      try { source.stop(); source.disconnect(); } catch {}
    }
  }

  cancelReach() { this.cancel('reach'); }

  stop() {
    this.generation++;
    this.requests.clear();
    for (const channel of [...this.active.keys()]) this.cancel(channel);
    this.lastReach = -Infinity;
  }
}
