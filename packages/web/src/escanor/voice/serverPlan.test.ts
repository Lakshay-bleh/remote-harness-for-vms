import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { handleUtterance, type AssistantDeps } from './assistant';
import { appsForServer, planToActions, type ServerPlan } from './serverPlan';

const plan = (over: Partial<ServerPlan>): ServerPlan => ({ source: 'llm', say: '', actions: [], needs: null, ...over });

describe('planToActions', () => {
  it('turns what the server decided into things this phone can do', () => {
    const { actions, skipped } = planToActions({
      actions: [
        { type: 'open_app', id: 'com.supercell.clashofclans', label: 'Clash of Clans' },
        { type: 'web_search', query: 'lo-fi', url: 'https://www.youtube.com/results?search_query=lo-fi' },
        { type: 'alarm', hour: 6, minute: 30 },
      ],
    });
    assert.deepEqual(actions, [
      { type: 'open_package', package: 'com.supercell.clashofclans', label: 'Clash of Clans' },
      { type: 'open_url', url: 'https://www.youtube.com/results?search_query=lo-fi' },
      { type: 'alarm', hour: 6, minute: 30 },
    ]);
    assert.equal(skipped, 0);
  });

  it('hands back the spoken name when the phone could not list its apps, so the phone looks it up itself', () => {
    assert.deepEqual(planToActions({ actions: [{ type: 'open_app', id: '', label: 'clash of clans', unresolved: true }] }).actions, [{ type: 'open_app', name: 'clash of clans' }]);
  });

  it('never passes on anything that does not look right', () => {
    const bad = [
      { type: 'open_url', url: 'javascript:alert(1)' },
      { type: 'open_url', url: 'http://plain.example' },
      { type: 'open_app', id: '', label: 'x' },
      { type: 'alarm', hour: 99, minute: 0 },
      { type: 'timer', seconds: -5 },
      { type: 'volume', change: 'max' },
      { type: 'call' },
      { type: 'media', action: 'next' },
      { type: 'rm -rf' },
      null,
    ] as never;
    assert.deepEqual(planToActions({ actions: bad }), { actions: [], skipped: 10 });
    assert.deepEqual(planToActions({ actions: 'nope' as never }), { actions: [], skipped: 0 });
  });

  it('does at most three things from one sentence', () => {
    const many = Array.from({ length: 6 }, (_, i) => ({ type: 'timer', seconds: 10 + i })) as never;
    assert.equal(planToActions({ actions: many }).actions.length, 3);
  });

  it('lists the phone’s apps the way the server wants them', () => {
    assert.deepEqual(appsForServer([{ label: 'YouTube', package: 'com.yt' }]), [{ id: 'com.yt', label: 'YouTube' }]);
  });
});

function rig(resolve?: AssistantDeps['resolve']) {
  const log: string[] = [];
  const d: AssistantDeps = {
    device: {
      listApps: async () => ({ apps: [{ label: 'YouTube', package: 'com.yt' }] }),
      launchPackage: async ({ package: p }: { package: string }) => (log.push(`launch:${p}`), { ok: true }),
      openUrl: async ({ url }: { url: string }) => (log.push(`url:${url}`), { ok: true }),
    } as never,
    hasComputer: false,
    toComputer: async () => '',
    toAssistant: async (t) => void log.push(`assistant:${t}`),
    go: () => undefined,
    resolve,
  };
  return { d, log };
}

describe('a sentence the phone’s own rules do not settle goes to the server', () => {
  it('opens the app the server chose, by package (open the game with the clans)', async () => {
    const { d, log } = rig(async () => plan({ source: 'llm', say: 'Opening Clash of Clans.', actions: [{ type: 'open_app', id: 'com.supercell.clashofclans', label: 'Clash of Clans' }] }));
    const r = await handleUtterance('start the game where I build a village', d);
    assert.deepEqual(log, ['launch:com.supercell.clashofclans']);
    assert.deepEqual(r, { ok: true, say: 'Opening Clash of Clans.', kind: 'phone' });
  });

  it('asks the server when "open <name>" is not found on the phone, because the server may know the app by another name', async () => {
    const { d, log } = rig(async () => plan({ source: 'rules', say: 'Opening Clash of Clans.', actions: [{ type: 'open_app', id: 'com.supercell.clashofclans', label: 'Clash of Clans' }] }));
    const r = await handleUtterance('open coc', d); // the phone's own matching finds no "coc"
    assert.deepEqual(log, ['launch:com.supercell.clashofclans']);
    assert.equal(r.ok, true);
  });

  it('keeps the phone’s own answer when the server cannot be reached, so nothing gets worse', async () => {
    const { d } = rig(async () => null);
    const r = await handleUtterance('open coc', d);
    assert.equal(r.ok, false);
    assert.match(r.say, /couldn’t find an app called coc/);
  });

  it('speaks the server’s question and listens again', async () => {
    const { d, log } = rig(async () => plan({ needs: 'clarify', say: 'Clash of Clans or Clash Royale?' }));
    assert.deepEqual(await handleUtterance('play my favourite supercell game', d), { ok: true, say: 'Clash of Clans or Clash Royale?', kind: 'phone', ask: true });
    assert.deepEqual(log, []);
  });

  it('hands a sentence that is not a device task to the Escanor assistant, as before', async () => {
    for (const answer of [plan({ not_device: true, source: 'llm' }), plan({ source: 'none', not_device: true }), null]) {
      const { d, log } = rig(async () => answer);
      const r = await handleUtterance('why is production slow', d);
      assert.deepEqual(log, ['assistant:why is production slow']);
      assert.equal(r.kind, 'assistant');
    }
  });

  it('speaks what went wrong at the server (a model that is down, a limit reached) instead of staying silent', async () => {
    const { d, log } = rig(async () => plan({ source: 'error', say: 'I couldn’t reach my AI model just now. Try again in a moment.' }));
    const r = await handleUtterance('play the village game', d);
    assert.equal(r.ok, false);
    assert.match(r.say, /couldn’t reach my AI model/);
    assert.deepEqual(log, []);
  });

  it('refuses to run something the server sent that does not look right', async () => {
    const { d, log } = rig(async () => plan({ actions: [{ type: 'open_url', url: 'javascript:alert(1)' } as never] }));
    const r = await handleUtterance('do the odd thing', d);
    assert.equal(r.ok, false);
    assert.match(r.say, /cannot do it yet/);
    assert.deepEqual(log, []);
  });

  it('works with no server brain at all (older behaviour)', async () => {
    const { d, log } = rig(undefined);
    await handleUtterance('why is production slow', d);
    assert.deepEqual(log, ['assistant:why is production slow']);
  });
});
