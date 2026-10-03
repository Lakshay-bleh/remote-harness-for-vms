import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { formatDuration, formatClock, runPhoneAction, type DevicePlugin } from './actions';

/** A phone that records what it was asked to do. */
function fakePhone(over: Partial<DevicePlugin> = {}) {
  const calls: Array<[string, unknown]> = [];
  const ok = async () => ({ ok: true });
  const rec = <K extends keyof DevicePlugin>(name: K, impl?: DevicePlugin[K]) => (async (o: unknown) => (calls.push([name, o]), impl ? (impl as (o: unknown) => unknown)(o) : { ok: true })) as unknown as DevicePlugin[K];
  const dev: DevicePlugin = {
    listApps: rec('listApps', (async () => ({ apps: [{ label: 'YouTube', package: 'com.yt' }, { label: 'WhatsApp', package: 'com.wa' }] })) as DevicePlugin['listApps']),
    launchPackage: rec('launchPackage'), openUrl: rec('openUrl'), dial: rec('dial'), callContact: rec('callContact'), setAlarm: rec('setAlarm'),
    setTimer: rec('setTimer'), setTorch: rec('setTorch'), setVolume: rec('setVolume'), openSettings: rec('openSettings'), ...over,
  };
  void ok;
  return { dev, calls };
}

describe('formatting', () => {
  it('says times and durations the way a person would', () => {
    assert.equal(formatClock(7, 30), '7:30 AM');
    assert.equal(formatClock(0, 0), '12:00 AM');
    assert.equal(formatClock(18, 5), '6:05 PM');
    assert.equal(formatDuration(300), '5 minutes');
    assert.equal(formatDuration(60), '1 minute');
    assert.equal(formatDuration(5400), '1 hour 30 minutes');
    assert.equal(formatDuration(45), '45 seconds');
  });
});

describe('runPhoneAction', () => {
  it('opens the installed app that matches, and says so', async () => {
    const { dev, calls } = fakePhone();
    const r = await runPhoneAction({ type: 'open_app', name: 'whats app' }, dev);
    assert.deepEqual(r, { ok: true, say: 'Opening WhatsApp.' });
    assert.deepEqual(calls.find(([n]) => n === 'launchPackage'), ['launchPackage', { package: 'com.wa' }]);
  });

  it('falls back to the website for a known site that has no app, and says it did not find an app otherwise', async () => {
    const { dev, calls } = fakePhone({ listApps: async () => ({ apps: [] }) });
    assert.deepEqual(await runPhoneAction({ type: 'open_app', name: 'github' }, dev), { ok: true, say: 'Opening github.com.' });
    assert.deepEqual(calls.find(([n]) => n === 'openUrl'), ['openUrl', { url: 'https://github.com' }]);
    const r = await runPhoneAction({ type: 'open_app', name: 'tiktok' }, dev);
    assert.equal(r.ok, false);
    assert.match(r.say, /couldn.t find an app called tiktok/i);
  });

  it('dials a number by opening the dialer, and tells the person to press call', async () => {
    const { dev, calls } = fakePhone();
    const r = await runPhoneAction({ type: 'call', who: '9876543210' }, dev);
    assert.equal(r.ok, true);
    assert.match(r.say, /dialer/);
    assert.match(r.say, /press call/i);
    assert.deepEqual(calls.find(([n]) => n === 'dial'), ['dial', { number: '9876543210' }]);
  });

  it('calls a contact by name, and passes on why it could not', async () => {
    const good = fakePhone({ callContact: async () => ({ ok: true, message: 'Mom' }) });
    assert.match((await runPhoneAction({ type: 'call', who: 'mom' }, good.dev)).say, /Mom/);
    const bad = fakePhone({ callContact: async () => ({ ok: false, message: 'I could not find zed in your contacts.' }) });
    assert.deepEqual(await runPhoneAction({ type: 'call', who: 'zed' }, bad.dev), { ok: false, say: 'I could not find zed in your contacts.' });
  });

  it('sets alarms and timers and confirms the time', async () => {
    const { dev, calls } = fakePhone();
    assert.deepEqual(await runPhoneAction({ type: 'alarm', hour: 7, minute: 30 }, dev), { ok: true, say: 'Alarm set for 7:30 AM.' });
    assert.deepEqual(await runPhoneAction({ type: 'timer', seconds: 300 }, dev), { ok: true, say: 'Timer set for 5 minutes.' });
    assert.deepEqual(calls.find(([n]) => n === 'setAlarm'), ['setAlarm', { hour: 7, minute: 30 }]);
  });

  it('torch, volume, search and settings', async () => {
    const { dev, calls } = fakePhone();
    assert.equal((await runPhoneAction({ type: 'torch', on: true }, dev)).say, 'Flashlight on.');
    assert.equal((await runPhoneAction({ type: 'volume', change: 'up' }, dev)).say, 'Volume up.');
    assert.equal((await runPhoneAction({ type: 'web_search', query: 'best pizza' }, dev)).say, 'Searching for best pizza.');
    assert.deepEqual(calls.find(([n]) => n === 'openUrl'), ['openUrl', { url: 'https://www.google.com/search?q=best%20pizza' }]);
    assert.equal((await runPhoneAction({ type: 'settings', screen: 'wifi' }, dev)).say, 'Opening Wi-Fi settings.');
  });

  it('reports a refusal from the phone in its own words', async () => {
    const { dev } = fakePhone({ setTorch: async () => ({ ok: false, message: 'This phone has no flashlight.' }) });
    assert.deepEqual(await runPhoneAction({ type: 'torch', on: true }, dev), { ok: false, say: 'This phone has no flashlight.' });
  });

  it('never throws: a plugin that blows up becomes a spoken problem', async () => {
    const { dev } = fakePhone({ setTimer: async () => { throw new Error('boom'); } });
    const r = await runPhoneAction({ type: 'timer', seconds: 60 }, dev);
    assert.equal(r.ok, false);
    assert.match(r.say, /could not/i);
  });

  it('without the Android app (a browser) only links work, and it says what is missing', async () => {
    const r = await runPhoneAction({ type: 'alarm', hour: 7, minute: 0 }, null);
    assert.equal(r.ok, false);
    assert.match(r.say, /Android app/);
  });
});
