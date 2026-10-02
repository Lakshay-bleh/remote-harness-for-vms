// A managed (Escanor worker) session against a real Claude Code process and a fake model: the assistant
// can work in its sandbox without a card, but publishing or leaving the sandbox still asks -- and the
// briefing for the assistant really reaches the model.
//   npm run test:integration
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import type { AgentToHubMessage, ManagedMcpServer } from '@remote-harness/shared';
import { SessionManager } from '../src/sessionManager.ts';
import { startFakeAnthropic } from './helpers/fakeAnthropic.ts';
import { startMockMcp } from './helpers/mockMcp.ts';

let root: string;
let api: Awaited<ReturnType<typeof startFakeAnthropic>>;
let mcp: Awaited<ReturnType<typeof startMockMcp>>;
let n = 0;
const managers: SessionManager[] = [];

before(async () => {
  root = mkdtempSync(join(tmpdir(), 'managed-it-'));
  api = await startFakeAnthropic();
  mcp = await startMockMcp();
  process.env.ANTHROPIC_BASE_URL = api.url;
  process.env.ANTHROPIC_API_KEY = 'sk-fake';
});
after(() => {
  for (const m of managers) m.shutdown();
  api.close();
  mcp.close();
  rmSync(root, { recursive: true, force: true });
});

function harness(opts: { managed: boolean; guide?: string }) {
  const dir = join(root, `s${n++}`);
  const out: AgentToHubMessage[] = [];
  const asked: Array<{ tool: string; input: any }> = [];
  const manager = new SessionManager(dir, join(dir, 'data'), [{ id: 'default', label: 'default', configDir: join(dir, 'cfg') }], (m) => out.push(m), opts);
  managers.push(manager);
  const seen = new Set<string>();
  const results = () => out.filter((m) => m.type === 'sdk_message' && (m.message as any)?.type === 'result').length;
  async function turn(answer: 'allow' | 'deny' = 'allow') {
    const target = results() + 1;
    const deadline = Date.now() + 60_000;
    while (Date.now() < deadline && results() < target) {
      await new Promise((r) => setTimeout(r, 200));
      for (const m of out) {
        if (m.type === 'permission_request' && !seen.has(m.requestId)) {
          seen.add(m.requestId);
          asked.push({ tool: m.toolName, input: m.input });
          manager.resolvePermission(m.requestId, answer);
        }
      }
    }
    assert.ok(results() >= target, 'timed out');
  }
  const say = (id: string, text: string) => manager.handleUserInput({ type: 'user_input', sessionId: id, tempId: id, text } as never);
  return { dir, manager, out, asked, turn, say };
}

test('in a managed worker a shell command runs at once, with no card', async () => {
  const h = harness({ managed: true });
  const marker = join(h.dir, 'made-by-assistant.txt');
  h.say('a', `bash[[mkdir -p ${h.dir} && echo hello > ${marker}]]`);
  await h.turn();
  assert.deepEqual(h.asked, [], 'no permission card for local work');
  assert.equal(existsSync(marker), true, 'and it really ran');
});

test('in a managed worker publishing still asks, and a "no" stops it', async () => {
  const h = harness({ managed: true });
  const marker = join(h.dir, 'pushed.txt');
  h.say('b', `bash[[mkdir -p ${h.dir} && git push origin fix && echo x > ${marker}]]`);
  await h.turn('deny');
  assert.equal(h.asked.length, 1);
  assert.equal(h.asked[0].tool, 'Bash');
  assert.match(h.asked[0].input.command, /git push/);
  assert.equal(existsSync(marker), false, 'denied: nothing ran');
});

test('an ordinary (unmanaged) session is unchanged: the same command asks', async () => {
  const h = harness({ managed: false });
  h.say('c', `bash[[mkdir -p ${h.dir} && echo hi]]`);
  await h.turn('deny');
  assert.equal(h.asked.length, 1);
  assert.equal(h.asked[0].tool, 'Bash');
});

test('the assistant briefing reaches the model in the system prompt', async () => {
  const before = api.systems.length;
  const h = harness({ managed: true, guide: 'ESCANOR-BRIEFING-MARKER: call escanor_connection_status first.' });
  h.say('d', 'hello');
  await h.turn();
  assert.ok(api.systems.slice(before).some((s) => s.includes('ESCANOR-BRIEFING-MARKER')), 'the model saw the briefing');
  assert.ok(api.systems.slice(before).some((s) => /Claude Code|software engineering/i.test(s)), 'and it is appended to, not replacing, the standard prompt');
});

// The whole point of the feature, in one scenario: a person reports a bug; the assistant checks what is
// connected, reads the real error, gets the code, runs the tests, fixes, re-runs until green, commits to a
// branch, and only then asks before publishing it and before opening the pull request.
test('the assistant works a whole fix loop: reads, edits, runs, iterates, and asks only before publishing', async () => {
  const dir = join(root, 'loop');
  const work = join(dir, 'work');
  mkdirSync(work, { recursive: true });
  // The "remote" lives inside the workspace here: a real one is a URL on the git proxy, and cloning from a path outside the
  // workspace is (rightly) something the policy asks about.
  const remote = join(work, 'remote.git');
  const seed = join(dir, 'seed');
  const git = (cwd: string, ...args: string[]) => execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', ...args], { cwd, stdio: 'pipe' }).toString();
  mkdirSync(seed, { recursive: true });
  git(seed, 'init', '-q', '-b', 'main');
  writeFileSync(join(seed, 'greet.py'), 'def greet(name):\n    return "Hello, " + name.upper()\n');
  writeFileSync(join(seed, 'test_greet.py'), 'from greet import greet\nassert greet("ada") == "Hello, ada", greet("ada")\nprint("PASS")\n');
  git(seed, 'add', '-A');
  git(seed, 'commit', '-q', '-m', 'initial');
  git(dir, 'clone', '-q', '--bare', seed, remote);
  const mainBefore = git(remote, 'rev-parse', 'main').trim();

  const h = harness({ managed: true });
  // harness() uses its own directory as the workspace; build the manager on ours instead.
  const out: AgentToHubMessage[] = [];
  const asked: Array<{ tool: string; input: any }> = [];
  const manager = new SessionManager(work, join(dir, 'data'), [{ id: 'default', label: 'default', configDir: join(dir, 'cfg') }], (m) => out.push(m), { managed: true });
  managers.push(manager);
  void h;
  await manager.setMcpServers([{ name: 'escanor', url: mcp.url, headers: { Authorization: 'Bearer tok' }, autoAllow: false, autoAllowReads: true, alwaysLoad: true, updatedAt: '' } as ManagedMcpServer]);

  const repo = join(work, 'repo'); // absolute: Claude Code's shell keeps its directory between commands
  const commit = 'GIT_AUTHOR_NAME=Escanor GIT_AUTHOR_EMAIL=a@e.in GIT_COMMITTER_NAME=Escanor GIT_COMMITTER_EMAIL=a@e.in';
  api.setScript([
    { tool: 'mcp__escanor__escanor_connection_status', input: {} },
    { tool: 'mcp__escanor__escanor_invoke', input: { tool_id: 'sentry.get_issue_logs', arguments: {} } },
    { tool: 'Bash', input: { command: `git clone -q ${remote} ${repo}` } },
    { tool: 'Bash', input: { command: `cd ${repo} && python3 test_greet.py` } }, // fails: the bug is real
    { tool: 'Bash', input: { command: `cd ${repo} && printf 'def greet(name):\\n    return "Hello, " + name\\n' > greet.py` } },
    { tool: 'Bash', input: { command: `cd ${repo} && python3 test_greet.py` } }, // passes now
    { tool: 'Bash', input: { command: `cd ${repo} && git checkout -q -b escanor/fix-greet && git add -A && ${commit} git -c user.name=E -c user.email=e@e.in commit -q -m "Fix greeting"` } },
    { tool: 'Bash', input: { command: `cd ${repo} && git push -q origin escanor/fix-greet` } },
    { tool: 'mcp__escanor__escanor_invoke', input: { tool_id: 'github.create_pull_request', arguments: { title: 'Fix greeting' } } },
  ]);
  const seen = new Set<string>();
  const results = () => out.filter((m) => m.type === 'sdk_message' && (m.message as any)?.type === 'result').length;
  manager.handleUserInput({ type: 'user_input', sessionId: 'loop', tempId: 'loop', text: 'greetings are broken in production, please fix' } as never);
  const deadline = Date.now() + 120_000;
  while (Date.now() < deadline && results() < 1) {
    await new Promise((r) => setTimeout(r, 200));
    for (const m of out) {
      if (m.type === 'permission_request' && !seen.has(m.requestId)) {
        seen.add(m.requestId);
        asked.push({ tool: m.toolName, input: m.input });
        manager.resolvePermission(m.requestId, 'allow');
      }
    }
  }
  api.setScript(null);
  if (process.env.DEBUG_LOOP) for (const m of out) if (m.type === 'sdk_message' && (m.message as any)?.type === 'user') console.log(JSON.stringify((m.message as any).message?.content ?? '').slice(0, 400));
  assert.ok(results() >= 1, 'the loop finished');

  // Everything local and every read ran without a card; exactly the two things that leave the sandbox asked.
  assert.deepEqual(asked.map((a) => a.tool), ['Bash', 'mcp__escanor__escanor_invoke'], `asked about: ${JSON.stringify(asked.map((a) => a.input.command ?? a.input.tool_id ?? a.input))}`);
  assert.match(asked[0].input.command, /git push/);
  assert.equal(asked[1].input.tool_id, 'github.create_pull_request');
  // The assistant looked at what was connected and read the real error first.
  assert.ok(mcp.seen.some((s) => s.rpc === 'tools/call' && s.tool === 'sentry.get_issue_logs'), 'it read the logs through Escanor');
  // The fix is real, verified by running the project's own test, and it reached the remote as a branch, not on main.
  assert.equal(git(remote, 'rev-parse', 'main').trim(), mainBefore, 'main is untouched');
  const branch = git(remote, 'show', 'escanor/fix-greet:greet.py');
  assert.match(branch, /return "Hello, " \+ name\n/);
  assert.equal(readFileSync(join(work, 'repo', 'greet.py'), 'utf8').includes('.upper()'), false);
});
