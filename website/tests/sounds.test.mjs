import test from 'node:test';
import assert from 'node:assert/strict';
import { SoundEffects } from '../dist/sounds.js';

function fixture({saved, enabled, delayed = false, unavailable = false} = {}) {
  let time = 0, contexts = 0, stored = saved;
  const fetched = [], sources = [], pending = [];
  const context = {
    state: 'suspended', destination: {},
    resume() { this.state = 'running'; return Promise.resolve(); },
    decodeAudioData: async () => ({duration: .2}),
    createBufferSource() {
      const source = {started: false, stopped: false, connect() {}, disconnect() {},
        start() { this.started = true; }, stop() { this.stopped = true; }};
      sources.push(source); return source;
    }
  };
  const sounds = new SoundEffects({
    storage: {getItem: () => stored, setItem: (_, value) => { stored = value; }},
    createContext: () => { contexts++; return context; },
    now: () => time,
    fetchAudio: url => {
      fetched.push(url);
      const response = {ok: !unavailable, arrayBuffer: async () => new ArrayBuffer(2)};
      return delayed ? new Promise(resolve => pending.push(() => resolve(response))) : Promise.resolve(response);
    }
  });
  if (enabled !== undefined) sounds.setEnabled(enabled);
  return {sounds, sources, fetched, contexts: () => contexts,
    stored: () => JSON.parse(stored), advance: value => { time += value; },
    async resolve() {
      await Promise.resolve();
      pending.splice(0).forEach(resolve => resolve());
      await Promise.resolve();
    }};
}

test('a fresh page stays muted through gestures and playback attempts', async () => {
  const page = fixture();
  assert.equal(page.sounds.enabled, false);
  assert.equal(page.sounds.set, 'fuzzy');
  assert.equal(page.contexts(), 0);
  assert.equal(page.fetched.length, 0);
  assert.equal(page.sources.length, 0);
  page.sounds.unlock();
  for (const event of ['reach', 'file', 'window']) {
    assert.equal(await page.sounds.play(event), false);
  }
  assert.equal(await page.sounds.play('window', {preview: true}), false);
  assert.equal(page.contexts(), 0);
  assert.equal(page.fetched.length, 0);
  assert.equal(page.sources.length, 0);
});

test('settings persist and unknown or damaged preferences use safe defaults', () => {
  const page = fixture();
  page.sounds.selectSet('rubber'); page.sounds.setEnabled(false);
  assert.deepEqual(page.stored(), {enabled: false, set: 'rubber'});
  const restored = fixture({saved: JSON.stringify(page.stored())});
  assert.equal(restored.sounds.enabled, false);
  assert.equal(restored.sounds.set, 'rubber');
  page.sounds.setEnabled(true);
  const enabled = fixture({saved: JSON.stringify(page.stored())});
  assert.equal(enabled.sounds.enabled, true);
  assert.equal(enabled.sounds.set, 'rubber');
  for (const saved of [undefined, null, '{broken', '{}', '{"set":"unknown"}', '{"enabled":"true"}']) {
    const fallback = fixture({saved});
    assert.equal(fallback.sounds.enabled, false);
    assert.equal(fallback.sounds.set, 'fuzzy');
  }
});

test('gesture unlock warms the selected set without playing, then plays at sample level', async () => {
  const page = fixture({enabled: true}); page.sounds.unlock();
  await Promise.resolve();
  assert.equal(page.contexts(), 1);
  assert.equal(page.fetched.length, 3);
  assert.equal(page.sources.length, 0);
  assert.equal(await page.sounds.play('file'), true);
  assert.equal(page.sources.length, 1);
  assert.equal(page.sources[0].started, true);
});

test('muting immediately stops playback and suppresses future and pending sounds', async () => {
  const page = fixture({enabled: true}); page.sounds.unlock();
  await page.sounds.play('window');
  page.sounds.setEnabled(false);
  assert.equal(page.sources[0].stopped, true);
  assert.equal(await page.sounds.play('file'), false);
  const delayed = fixture({enabled: true, delayed: true}); delayed.sounds.unlock();
  const play = delayed.sounds.play('file');
  delayed.sounds.setEnabled(false); await delayed.resolve();
  assert.equal(await play, false);
  assert.equal(delayed.sources.length, 0);
});

test('withdrawing the arm cancels a reach that is still loading', async () => {
  const page = fixture({enabled: true, delayed: true}); page.sounds.unlock();
  const play = page.sounds.play('reach');
  page.sounds.cancelReach(); await page.resolve();
  assert.equal(await play, false);
  assert.equal(page.sources.length, 0);
});

test('switching sets stops the old sound and invalidates late loads', async () => {
  const page = fixture({enabled: true, delayed: true}); page.sounds.unlock();
  const play = page.sounds.play('window');
  page.sounds.selectSet('arcade'); await page.resolve();
  assert.equal(await play, false);
  assert.equal(page.sources.length, 0);
  assert.ok(page.fetched.includes('./assets/sounds/arcade-window.wav'));
  assert.equal(await page.sounds.play('window'), true);
  page.sounds.selectSet('rubber');
  assert.equal(page.sources[0].stopped, true);
});

test('small reach reentries cannot chatter but a later reach can play', async () => {
  const page = fixture({enabled: true}); page.sounds.unlock();
  assert.equal(await page.sounds.play('reach'), true);
  page.sounds.cancelReach(); page.advance(100);
  assert.equal(await page.sounds.play('reach'), false);
  page.advance(150);
  assert.equal(await page.sounds.play('reach'), true);
  assert.equal(page.sources.length, 2);
});

test('slow first downloads warm the cache without delayed sound after the action', async () => {
  const page = fixture({enabled: true, delayed: true}); page.sounds.unlock();
  const play = page.sounds.play('file');
  page.advance(500); await page.resolve();
  assert.equal(await play, false);
  assert.equal(page.sources.length, 0);
  assert.equal(await page.sounds.play('file'), true);
});

test('preview is explicit, tolerates loading, and respects mute', async () => {
  const page = fixture({enabled: true, delayed: true}); page.sounds.unlock();
  const play = page.sounds.play('window', {preview: true});
  page.advance(500); await page.resolve();
  assert.equal(await play, true);
  page.sounds.setEnabled(false);
  assert.equal(page.sources[0].stopped, true);
  assert.equal(await page.sounds.play('window', {preview: true}), false);
});

test('unavailable audio fails silently without throwing into the drag handlers', async () => {
  const page = fixture({enabled: true, unavailable: true}); page.sounds.unlock();
  assert.equal(await page.sounds.play('file'), false);
  assert.equal(page.sources.length, 0);
});
