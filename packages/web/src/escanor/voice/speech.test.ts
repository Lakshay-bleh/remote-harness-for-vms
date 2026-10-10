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

describe('chunkForSpeech', () => {
  it('keeps a short reply in one piece', async () => {
    const { chunkForSpeech } = await import('./speech');
    assert.deepEqual(chunkForSpeech('All good.'), ['All good.']);
    assert.deepEqual(chunkForSpeech('   '), []);
  });

  it('never drops anything: a long reply is spoken whole, a sentence or two at a time', async () => {
    const { chunkForSpeech } = await import('./speech');
    const sentences = Array.from({ length: 40 }, (_, i) => `Service number ${i + 1} is healthy and answered in ${i + 10} milliseconds.`);
    const text = sentences.join(' ');
    assert.ok(text.length > 1500);
    const chunks = chunkForSpeech(text, 200);
    assert.ok(chunks.length > 5);
    assert.ok(chunks.every((c) => c.length <= 200), 'every piece fits the engine');
    assert.equal(chunks.join(' '), text, 'nothing is cut');
    // Pieces end at a sentence, so the voice never stops mid-sentence.
    assert.ok(chunks.every((c) => /\.$/.test(c)));
  });

  it('breaks one very long sentence at a comma, then at a space', async () => {
    const { chunkForSpeech } = await import('./speech');
    const long = `${'word '.repeat(30).trim()}, ${'more '.repeat(30).trim()}`;
    const chunks = chunkForSpeech(long, 100);
    assert.ok(chunks.every((c) => c.length <= 100));
    assert.equal(chunks.join(' ').replace(/\s+/g, ' '), long);
  });
});

describe('pickVoice', () => {
  it('prefers a natural voice in the person’s language over a robotic or foreign one', async () => {
    const { pickVoice } = await import('./speech');
    const voices = [
      { name: 'eSpeak English', lang: 'en-US' },
      { name: 'Google français', lang: 'fr-FR' },
      { name: 'Google US English', lang: 'en-US' },
      { name: 'Daniel', lang: 'en-GB' },
    ];
    assert.equal(pickVoice(voices, 'en-US')?.name, 'Google US English');
    assert.equal(pickVoice(voices, 'de-DE'), undefined);
  });
});

describe('speakInPieces', () => {
  it('says every piece in order, and stops between pieces when cancelled', async () => {
    const { speakInPieces } = await import('./speech');
    const said: string[] = [];
    const text = Array.from({ length: 12 }, (_, i) => `Sentence ${i + 1} is here and it has a few words in it.`).join(' ');
    await speakInPieces(text, async (p) => void said.push(p), () => false, 120);
    assert.equal(said.join(' '), text);
    assert.ok(said.length > 1);

    const some: string[] = [];
    await speakInPieces(text, async (p) => void some.push(p), () => some.length >= 2, 120);
    assert.equal(some.length, 2);
  });
});
