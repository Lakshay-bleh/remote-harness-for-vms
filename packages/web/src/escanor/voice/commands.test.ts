import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { canonicalizeName, parseVoiceCommand, parseClock, parseDuration, stripWake } from './commands';

const ctx = { hasComputer: true };

describe('wake phrase and the name', () => {
  it('strips "hey escanor" however it was heard', () => {
    for (const said of ['hey escanor open youtube', 'Hey Escaner, open youtube', 'ok es canor open youtube', 'hey ex canor open youtube']) assert.equal(stripWake(said), 'open youtube', said);
  });
  it('leaves ordinary sentences alone', () => {
    assert.equal(stripWake('open the scanner app'), 'open the scanner app');
    assert.equal(canonicalizeName('escalator'), 'escalator');
  });
});

describe('phone actions', () => {
  it('opens an app or a site by name', () => {
    assert.deepEqual(parseVoiceCommand('open youtube', ctx), { kind: 'phone', action: { type: 'open_app', name: 'youtube' } });
    assert.deepEqual(parseVoiceCommand('Hey Escanor, launch WhatsApp', ctx), { kind: 'phone', action: { type: 'open_app', name: 'whatsapp' } });
    assert.deepEqual(parseVoiceCommand('start the camera', ctx), { kind: 'phone', action: { type: 'open_app', name: 'camera' } });
  });
  it('calls a number or a name', () => {
    assert.deepEqual(parseVoiceCommand('call mom', ctx), { kind: 'phone', action: { type: 'call', who: 'mom' } });
    assert.deepEqual(parseVoiceCommand('call 98765 43210', ctx), { kind: 'phone', action: { type: 'call', who: '9876543210' } });
  });
  it('sets alarms and timers', () => {
    assert.deepEqual(parseVoiceCommand('set an alarm for 7:30 am', ctx), { kind: 'phone', action: { type: 'alarm', hour: 7, minute: 30 } });
    assert.deepEqual(parseVoiceCommand('wake me up at 6 pm', ctx), { kind: 'phone', action: { type: 'alarm', hour: 18, minute: 0 } });
    assert.deepEqual(parseVoiceCommand('set a timer for 5 minutes', ctx), { kind: 'phone', action: { type: 'timer', seconds: 300 } });
    assert.deepEqual(parseVoiceCommand('timer 1 hour 30 minutes', ctx), { kind: 'phone', action: { type: 'timer', seconds: 5400 } });
  });
  it('controls the torch and the volume', () => {
    assert.deepEqual(parseVoiceCommand('turn on the flashlight', ctx), { kind: 'phone', action: { type: 'torch', on: true } });
    assert.deepEqual(parseVoiceCommand('torch off', ctx), { kind: 'phone', action: { type: 'torch', on: false } });
    assert.deepEqual(parseVoiceCommand('volume up', ctx), { kind: 'phone', action: { type: 'volume', change: 'up' } });
    assert.deepEqual(parseVoiceCommand('mute', ctx), { kind: 'phone', action: { type: 'volume', change: 'mute' } });
  });
  it('presses the media keys for "pause the music", "next song", "previous track", and nothing looser', () => {
    const media = (t: string) => parseVoiceCommand(t, ctx);
    assert.deepEqual(media('pause the music'), { kind: 'phone', action: { type: 'media', action: 'playpause' } });
    assert.deepEqual(media('resume'), { kind: 'phone', action: { type: 'media', action: 'playpause' } });
    assert.deepEqual(media('next song'), { kind: 'phone', action: { type: 'media', action: 'next' } });
    assert.deepEqual(media('skip this track'), { kind: 'phone', action: { type: 'media', action: 'next' } });
    assert.deepEqual(media('previous track'), { kind: 'phone', action: { type: 'media', action: 'previous' } });
    assert.equal(media('play despacito on spotify').kind, 'assistant');
    assert.deepEqual(media('stop'), { kind: 'stop' });
  });
  it('searches the web and opens a settings screen', () => {
    assert.deepEqual(parseVoiceCommand('search for best pizza near me', ctx), { kind: 'phone', action: { type: 'web_search', query: 'best pizza near me' } });
    assert.deepEqual(parseVoiceCommand('open wifi settings', ctx), { kind: 'phone', action: { type: 'settings', screen: 'wifi' } });
    assert.deepEqual(parseVoiceCommand('open bluetooth settings', ctx), { kind: 'phone', action: { type: 'settings', screen: 'bluetooth' } });
  });
});

describe('using the phone itself', () => {
  const act = (say: string) => (parseVoiceCommand(say, { hasComputer: true }) as { kind: string; action?: unknown }).action;
  it('presses the phone\u2019s buttons', () => {
    assert.deepEqual(act('go home'), { type: 'control', op: 'home' });
    assert.deepEqual(act('go to the home screen'), { type: 'control', op: 'home' });
    assert.deepEqual(act('go back'), { type: 'control', op: 'back' });
    assert.deepEqual(act('show recent apps'), { type: 'control', op: 'recents' });
    assert.deepEqual(act('open notifications'), { type: 'control', op: 'notifications' });
    assert.deepEqual(act('quick settings'), { type: 'control', op: 'quick_settings' });
    assert.deepEqual(act('lock the phone'), { type: 'control', op: 'lock' });
    assert.deepEqual(act('take a screenshot'), { type: 'control', op: 'screenshot' });
    assert.deepEqual(act('scroll down'), { type: 'control', op: 'scroll_down' });
    assert.deepEqual(act('scroll up'), { type: 'control', op: 'scroll_up' });
  });
  it('taps what is on the screen by its words, and types', () => {
    assert.deepEqual(act('tap Send'), { type: 'tap_text', text: 'send' });
    assert.deepEqual(act('click on the sign in button'), { type: 'tap_text', text: 'sign in' });
    assert.deepEqual(act('type hello there'), { type: 'type_text', text: 'hello there' });
  });
  it('keeps the case of what is typed', () => {
    assert.deepEqual(act('type Meet me at 5 PM.'), { type: 'type_text', text: 'Meet me at 5 PM' });
  });
  it('reads the screen only when asked', () => {
    assert.deepEqual(act('what is on my screen'), { type: 'read_screen' });
    assert.deepEqual(act('read the screen'), { type: 'read_screen' });
  });
  it('opens a website by its address, however the dots were heard', () => {
    assert.deepEqual(act('go to google.com'), { type: 'open_url', url: 'https://google.com' });
    assert.deepEqual(act('open github dot com'), { type: 'open_url', url: 'https://github.com' });
  });
  it('does not mistake an app name or a question for any of these', () => {
    assert.deepEqual(act('open youtube'), { type: 'open_app', name: 'youtube' });
    assert.equal(act('why is the build back to failing'), undefined);
  });
  it('searches for what was said, not for the word google', () => {
    assert.deepEqual(act('search google for cats'), { type: 'web_search', query: 'cats' });
    assert.deepEqual(act('google best pizza near me'), { type: 'web_search', query: 'best pizza near me' });
  });
});

describe('the computer', () => {
  it('goes to the computer when asked to, and sends the rest of the sentence', () => {
    assert.deepEqual(parseVoiceCommand('on my computer open youtube', ctx), { kind: 'computer', text: 'open youtube' });
    assert.deepEqual(parseVoiceCommand('tell my laptop to show my containers', ctx), { kind: 'computer', text: 'show my containers' });
    assert.deepEqual(parseVoiceCommand('ask my pc what is using my memory', ctx), { kind: 'computer', text: 'what is using my memory' });
    assert.deepEqual(parseVoiceCommand('open youtube on my computer', ctx), { kind: 'computer', text: 'open youtube' });
  });
  it('says there is no computer to ask when none is paired, instead of guessing', () => {
    assert.deepEqual(parseVoiceCommand('on my computer open youtube', { hasComputer: false }), { kind: 'no_computer', text: 'open youtube' });
  });
});

describe('everything else', () => {
  it('goes to the assistant', () => {
    assert.deepEqual(parseVoiceCommand('why is checkout slow', ctx), { kind: 'assistant', text: 'why is checkout slow' });
    assert.deepEqual(parseVoiceCommand('hey escanor what needs my attention', ctx), { kind: 'assistant', text: 'what needs my attention' });
  });
  it('moves around the app', () => {
    assert.deepEqual(parseVoiceCommand('go to my computers', ctx), { kind: 'go', tab: 'computers' });
    assert.deepEqual(parseVoiceCommand('show settings', ctx), { kind: 'go', tab: 'settings' });
    assert.deepEqual(parseVoiceCommand('open the chat', ctx), { kind: 'go', tab: 'assistant' });
  });
  it('stops on cancel, and ignores silence', () => {
    for (const w of ['cancel', 'never mind', 'stop', 'forget it']) assert.deepEqual(parseVoiceCommand(w, ctx), { kind: 'stop' }, w);
    for (const w of ['', '   ', 'hey escanor']) assert.deepEqual(parseVoiceCommand(w, ctx), { kind: 'empty' }, w);
  });
});

describe('parseClock', () => {
  it('reads times people say', () => {
    assert.deepEqual(parseClock('7 am'), { hour: 7, minute: 0 });
    assert.deepEqual(parseClock('7:30 pm'), { hour: 19, minute: 30 });
    assert.deepEqual(parseClock('12 am'), { hour: 0, minute: 0 });
    assert.deepEqual(parseClock('12 pm'), { hour: 12, minute: 0 });
    assert.deepEqual(parseClock('quarter past 6'), { hour: 6, minute: 15 });
    assert.deepEqual(parseClock('18:45'), { hour: 18, minute: 45 });
    assert.deepEqual(parseClock('half past 9 am'), { hour: 9, minute: 30 });
  });
  it('refuses nonsense', () => {
    for (const bad of ['', 'banana', '25 am', '7:75', '13 pm']) assert.equal(parseClock(bad), null, bad);
  });
});

describe('parseDuration', () => {
  it('adds up hours, minutes and seconds', () => {
    assert.equal(parseDuration('5 minutes'), 300);
    assert.equal(parseDuration('1 hour 30 minutes'), 5400);
    assert.equal(parseDuration('90 seconds'), 90);
    assert.equal(parseDuration('half an hour'), 1800);
    assert.equal(parseDuration('two minutes'), 120);
  });
  it('refuses nonsense and absurd lengths', () => {
    assert.equal(parseDuration('soon'), null);
    assert.equal(parseDuration('0 minutes'), null);
    assert.equal(parseDuration('9999 hours'), null);
  });
});
