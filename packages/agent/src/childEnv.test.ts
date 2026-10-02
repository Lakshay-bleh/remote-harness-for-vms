import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { childEnv } from './childEnv.js';

describe('childEnv', () => {
  const base = {
    PATH: '/usr/bin',
    HOME: '/home/u',
    HUB_TOKEN: 'secret-agent-token',
    HUB_URL: 'wss://hub.example/agent',
    ANTHROPIC_API_KEY: 'sk-ant-key',
  };

  it('never passes the hub credentials to the Claude child process', () => {
    const env = childEnv(base);
    assert.equal('HUB_TOKEN' in env, false);
    assert.equal('HUB_URL' in env, false);
  });

  it('keeps the variables Claude itself needs, including its own API key', () => {
    const env = childEnv(base);
    assert.equal(env.PATH, '/usr/bin');
    assert.equal(env.HOME, '/home/u');
    assert.equal(env.ANTHROPIC_API_KEY, 'sk-ant-key');
  });

  it('applies overrides such as CLAUDE_CONFIG_DIR and does not mutate the input', () => {
    const env = childEnv(base, { CLAUDE_CONFIG_DIR: '/p/claude1' });
    assert.equal(env.CLAUDE_CONFIG_DIR, '/p/claude1');
    assert.equal(base.HUB_TOKEN, 'secret-agent-token');
  });

  it('does not let an override re-introduce a hub credential', () => {
    const env = childEnv(base, { HUB_TOKEN: 'x' });
    assert.equal('HUB_TOKEN' in env, false);
  });
});
