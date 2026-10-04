import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { listenOnce, type SpeechPlugin } from './speech';

/** A speech recogniser we can drive: emit partials, then stop. */
function fakeRecogniser() {
  const handlers: Record<string, Array<(e: any) => void>> = {};
  const started: unknown[] = [];
  let stops = 0;
  const plugin: SpeechPlugin = {
    start: async (o) => (started.push(o), {}),
    stop: async () => void (stops += 1),
    addListener: async (name, fn) => {
      (handlers[name] ??= []).push(fn as (e: any) => void);
      return { remove: async () => void (handlers[name] = handlers[name].filter((h) => h !== fn)) };
    },
  };
  const emit = (name: string, e: unknown = {}) => (handlers[name] ?? []).slice().forEach((h) => h(e));
  return { plugin, emit, started, stops: () => stops, listeners: () => Object.values(handlers).reduce((n, l) => n + l.length, 0) };
}

describe('listenOnce', () => {
  it('shows what is heard as it comes, and resolves with the last thing heard when listening stops', async () => {
    const r = fakeRecogniser();
    const shown: string[] = [];
    const p = listenOnce(r.plugin, { onPartial: (t) => shown.push(t) });
    await new Promise((x) => setTimeout(x, 5));
    r.emit('partialResults', { matches: ['open'] });
    r.emit('partialResults', { matches: ['open youtube'] });
    r.emit('listeningState', { state: 'stopped' });
    assert.equal(await p, 'open youtube');
    assert.deepEqual(shown, ['open', 'open youtube']);
  });

  it('asks for partial results, no system dialog, and no beep', async () => {
    const r = fakeRecogniser();
    const p = listenOnce(r.plugin, {});
    await new Promise((x) => setTimeout(x, 5));
    r.emit('listeningState', { status: 'stopped' });
    await p;
    assert.deepEqual(r.started[0], { language: 'en-US', maxResults: 1, partialResults: true, popup: false, muteRecognizerBeep: true, allowForSilence: 1500 });
  });

  it('cleans up its listeners every time, so a second listen is not answered twice', async () => {
    const r = fakeRecogniser();
    const p = listenOnce(r.plugin, {});
    await new Promise((x) => setTimeout(x, 5));
    r.emit('listeningState', { state: 'stopped' });
    await p;
    assert.equal(r.listeners(), 0);
  });

  it('rejects with the recogniser’s own message when it errors', async () => {
    const r = fakeRecogniser();
    const p = listenOnce(r.plugin, {});
    await new Promise((x) => setTimeout(x, 5));
    r.emit('error', { message: 'No speech detected' });
    await assert.rejects(p, /No speech detected/);
    assert.equal(r.listeners(), 0);
  });

  it('gives up after the time limit with what it has, and stops the recogniser', async () => {
    const r = fakeRecogniser();
    const p = listenOnce(r.plugin, { timeoutMs: 40 });
    await new Promise((x) => setTimeout(x, 5));
    r.emit('partialResults', { matches: ['hello there'] });
    assert.equal(await p, 'hello there');
    assert.equal(r.stops(), 1);
  });

  it('can be cancelled, and then resolves with nothing', async () => {
    const r = fakeRecogniser();
    const ctl = new AbortController();
    const p = listenOnce(r.plugin, { signal: ctl.signal });
    await new Promise((x) => setTimeout(x, 5));
    r.emit('partialResults', { matches: ['never mind'] });
    ctl.abort();
    assert.equal(await p, '');
    assert.equal(r.stops(), 1);
  });

  it('ignores a "stopped" that arrives before anything was started listening (the stop of an earlier session)', async () => {
    const r = fakeRecogniser();
    const p = listenOnce(r.plugin, { timeoutMs: 60 });
    r.emit('listeningState', { state: 'stopped' }); // before start() has even resolved
    await new Promise((x) => setTimeout(x, 5));
    r.emit('partialResults', { matches: ['real words'] });
    r.emit('listeningState', { state: 'stopped' });
    assert.equal(await p, 'real words');
  });
});

describe('webSpeechPlugin', () => {
  it('is null where the browser has no recogniser', async () => {
    const { webSpeechPlugin } = await import('./speech');
    assert.equal(webSpeechPlugin({}), null);
  });

  it('speaks the plugin interface on top of a browser recogniser, so listenOnce works unchanged', async () => {
    const { webSpeechPlugin } = await import('./speech');
    let rec: any;
    class Fake {
      onresult: any; onerror: any; onend: any;
      constructor() { rec = this; }
      start() {}
      stop() { this.onend?.(); }
    }
    const plugin = webSpeechPlugin({ webkitSpeechRecognition: Fake })!;
    const p = listenOnce(plugin, {});
    await new Promise((x) => setTimeout(x, 5));
    rec.onresult({ results: [[{ transcript: 'open ' }], [{ transcript: 'youtube' }]] });
    rec.onend();
    assert.equal(await p, 'open youtube');
  });
});
