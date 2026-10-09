import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { AgentToHubMessage } from '@remote-harness/shared';
import { SessionRegistry } from '../src/registry.ts';
import { TerminalSessionSync, slim } from '../src/terminalSessions.ts';

const msg = (uuid: string) => ({ type: 'user' as const, uuid, session_id: 's', message: { role: 'user', content: uuid }, parent_tool_use_id: null, parent_agent_id: null });

function setup(opts: { live?: Set<string> } = {}) {
  const base = mkdtempSync(join(tmpdir(), 'terminal-sync-'));
  const root = join(base, 'work');
  mkdirSync(join(root, 'proj'), { recursive: true });
  const registry = new SessionRegistry(join(base, 'data'));
  const sent: AgentToHubMessage[] = [];
  const sessions = new Map<string, { cwd: string; lastModified: number; msgs: ReturnType<typeof msg>[] }>();
  const sync = new TerminalSessionSync({
    workspaceRoot: root,
    registry,
    send: (m) => sent.push(m),
    isLive: (id) => opts.live?.has(id) ?? false,
    accountId: 'default',
    list: (async () =>
      [...sessions].map(([sessionId, s]) => ({ sessionId, cwd: s.cwd, lastModified: s.lastModified, summary: `title ${sessionId}` }))) as never,
    read: (async (id: string) => sessions.get(id)?.msgs ?? []) as never,
  });
  return { root, base, registry, sent, sessions, sync };
}

describe('TerminalSessionSync', () => {
  it('imports a terminal session inside the workspace with its history, then marks it idle', async () => {
    const t = setup();
    t.sessions.set('a', { cwd: join(t.root, 'proj'), lastModified: 1, msgs: [msg('1'), msg('2')] });
    await t.sync.syncOnce();
    assert.deepEqual(t.sent.map((m) => m.type), ['session_created', 'sdk_message', 'sdk_message', 'session_ended']);
    assert.equal((t.sent[0] as { tempId: string }).tempId, 'a');
    const entry = t.registry.get('a');
    assert.equal(entry?.source, 'terminal');
    assert.equal(entry?.title, 'title a');
    assert.equal(entry?.syncedUuid, '2');
  });

  it('ignores sessions outside the workspace', async () => {
    const t = setup();
    t.sessions.set('out', { cwd: t.base, lastModified: 1, msgs: [msg('1')] });
    await t.sync.syncOnce();
    assert.deepEqual(t.sent, []);
    assert.equal(t.registry.get('out'), undefined);
  });

  it('sends only new messages when the session continues in the terminal, and nothing when unchanged', async () => {
    const t = setup();
    const s = { cwd: t.root, lastModified: 1, msgs: [msg('1')] };
    t.sessions.set('a', s);
    await t.sync.syncOnce();
    t.sent.length = 0;
    await t.sync.syncOnce();
    assert.deepEqual(t.sent, [], 'unchanged transcript is not resent');
    s.msgs.push(msg('2'), msg('3'));
    s.lastModified = 2;
    await t.sync.syncOnce();
    assert.deepEqual(t.sent.map((m) => (m.type === 'sdk_message' ? (m.message as { uuid: string }).uuid : m.type)), ['2', '3', 'session_ended']);
  });

  it('does not resend sessions the agent made (the hub has them) and skips live ones', async () => {
    const t = setup({ live: new Set(['live']) });
    t.registry.upsert({ sessionId: 'own', cwd: t.root, title: 'x', createdAt: 'x', accountId: 'default' });
    t.sessions.set('own', { cwd: t.root, lastModified: 1, msgs: [msg('1')] });
    t.sessions.set('live', { cwd: t.root, lastModified: 1, msgs: [msg('1')] });
    await t.sync.syncOnce();
    assert.deepEqual(t.sent, []);
    assert.equal(t.registry.get('own')?.syncedUuid, '1');
    assert.equal(t.registry.get('live'), undefined);
  });

  it('markSynced records the end of a chat the agent ran so it is not sent twice', async () => {
    const t = setup();
    t.registry.upsert({ sessionId: 'own', cwd: t.root, title: 'x', createdAt: 'x', accountId: 'default', syncedUuid: '1', syncedMtime: 1 });
    t.sessions.set('own', { cwd: t.root, lastModified: 5, msgs: [msg('1'), msg('2'), msg('3')] });
    await t.sync.markSynced('own', t.root);
    await t.sync.syncOnce();
    assert.deepEqual(t.sent, []);
  });

  it('slim cuts huge tool output and drops huge images but keeps normal content', () => {
    const big = 'x'.repeat(50_000);
    const out = slim({ content: [{ type: 'tool_result', content: big }, { type: 'image', source: { type: 'base64', data: big + big + big + big + big + big + big } }, { type: 'text', text: 'hi' }] });
    assert.ok((out.content[0] as { content: string }).content.length < 21_000);
    assert.deepEqual(out.content[1], { type: 'text', text: '[image too large to show here]' });
    assert.deepEqual(out.content[2], { type: 'text', text: 'hi' });
  });
});
