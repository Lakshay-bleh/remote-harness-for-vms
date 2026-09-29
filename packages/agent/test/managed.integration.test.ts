// A managed (Escanor worker) session against a real Claude Code process and a fake model: the assistant
// can work in its sandbox without a card, but publishing or leaving the sandbox still asks -- and the
// briefing for the assistant really reaches the model.
//   npm run test:integration
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import type { AgentToHubMessage } from '@remote-harness/shared';
import { SessionManager } from '../src/sessionManager.ts';
import { startFakeAnthropic } from './helpers/fakeAnthropic.ts';

let root: string;
let api: Awaited<ReturnType<typeof startFakeAnthropic>>;
let n = 0;
const managers: SessionManager[] = [];

before(async () => {
  root = mkdtempSync(join(tmpdir(), 'managed-it-'));
  api = await startFakeAnthropic();
  process.env.ANTHROPIC_BASE_URL = api.url;
  process.env.ANTHROPIC_API_KEY = 'sk-fake';
});
after(() => {
  for (const m of managers) m.shutdown();
  api.close();
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
