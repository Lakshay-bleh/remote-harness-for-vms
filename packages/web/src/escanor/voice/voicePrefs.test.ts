import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { DEFAULT_VOICE_PREFS, parseVoicePrefs } from './voicePrefs';

describe('parseVoicePrefs', () => {
  it('starts with calling directly on and the wake word off', () => {
    assert.deepEqual(parseVoicePrefs(null), DEFAULT_VOICE_PREFS);
    assert.deepEqual(DEFAULT_VOICE_PREFS, { directCalls: true, wakeWord: false });
  });
  it('reads what was saved, field by field, and ignores damage', () => {
    assert.deepEqual(parseVoicePrefs('{"directCalls":false,"wakeWord":true}'), { directCalls: false, wakeWord: true });
    assert.deepEqual(parseVoicePrefs('{"directCalls":"no","wakeWord":1}'), DEFAULT_VOICE_PREFS);
    assert.deepEqual(parseVoicePrefs('not json'), DEFAULT_VOICE_PREFS);
    assert.deepEqual(parseVoicePrefs('[1]'), DEFAULT_VOICE_PREFS);
  });
});
