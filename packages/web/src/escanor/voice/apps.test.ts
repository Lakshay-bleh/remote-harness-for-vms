import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { matchApp, type InstalledApp } from './apps';

const apps: InstalledApp[] = [
  { label: 'YouTube', package: 'com.google.android.youtube' },
  { label: 'YouTube Music', package: 'com.google.android.apps.youtube.music' },
  { label: 'WhatsApp', package: 'com.whatsapp' },
  { label: 'Maps', package: 'com.google.android.apps.maps' },
  { label: 'Camera', package: 'com.sec.android.app.camera' },
  { label: 'Chrome', package: 'com.android.chrome' },
  { label: 'Samsung Internet', package: 'com.sec.android.app.sbrowser' },
  { label: 'Settings', package: 'com.android.settings' },
  { label: 'Phone', package: 'com.samsung.android.dialer' },
  { label: 'Gmail', package: 'com.google.android.gm' },
  { label: 'Spotify', package: 'com.spotify.music' },
];

describe('matchApp', () => {
  it('prefers an exact name over a longer one that starts with it', () => {
    assert.equal(matchApp('youtube', apps)?.package, 'com.google.android.youtube');
    assert.equal(matchApp('youtube music', apps)?.package, 'com.google.android.apps.youtube.music');
  });
  it('ignores case, spaces and punctuation, so how it was heard does not matter', () => {
    assert.equal(matchApp('Whats App', apps)?.package, 'com.whatsapp');
    assert.equal(matchApp("WhatsApp", apps)?.package, 'com.whatsapp');
    assert.equal(matchApp('you tube', apps)?.package, 'com.google.android.youtube');
  });
  it('knows the usual nicknames', () => {
    assert.equal(matchApp('google maps', apps)?.package, 'com.google.android.apps.maps');
    assert.equal(matchApp('browser', apps)?.package, 'com.android.chrome');
    assert.equal(matchApp('mail', apps)?.package, 'com.google.android.gm');
    assert.equal(matchApp('dialer', apps)?.package, 'com.samsung.android.dialer');
  });
  it('finds a word inside a longer label', () => {
    assert.equal(matchApp('internet', apps)?.package, 'com.sec.android.app.sbrowser');
  });
  it('says nothing found, rather than guessing, for an app that is not installed', () => {
    assert.equal(matchApp('tiktok', apps), null);
    assert.equal(matchApp('', apps), null);
    assert.equal(matchApp('a', apps), null); // too short to mean anything
  });
});
