// An agent sends again what a dropped connection may have lost. The copies the hub already stored must not show twice.
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { agentMessageUid } from '@remote-harness/shared/validate';
import { DEFAULT_TENANT, openDb } from '../src/db.ts';

const dirs: string[] = [];
after(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));
const tenant = () => {
  const d = mkdtempSync(join(tmpdir(), 'hub-resend-'));
  dirs.push(d);
  return openDb(d).for(DEFAULT_TENANT);
};

test('an sdk message or permission prompt sent twice is stored once', () => {
  const t = tenant();
  const vm = t.upsertVm('vm');
  t.upsertSession({ id: 's', vmId: vm, cwd: '/', title: 'x', status: 'active', accountId: 'default' });
  const sdk = { type: 'sdk_message' as const, sessionId: 's', message: { type: 'assistant', uuid: 'u-1', message: { content: [] } } };
  const perm = { type: 'permission_request' as const, sessionId: 's', requestId: 'r-1', toolName: 'Bash', input: {} };
  assert.equal(t.insertAgentMessage({ sessionId: 's', vmId: vm, message: sdk.message, uid: agentMessageUid(sdk) }), true);
  assert.equal(t.insertAgentMessage({ sessionId: 's', vmId: vm, message: sdk.message, uid: agentMessageUid(sdk) }), false);
  assert.equal(t.insertAgentMessage({ sessionId: 's', vmId: vm, message: { type: 'permission_request' }, uid: agentMessageUid(perm) }), true);
  assert.equal(t.insertAgentMessage({ sessionId: 's', vmId: vm, message: { type: 'permission_request' }, uid: agentMessageUid(perm) }), false);
  // Without a uid there is nothing to tell copies apart by: both are kept.
  assert.equal(t.insertAgentMessage({ sessionId: 's', vmId: vm, message: { type: 'system' } }), true);
  assert.equal(t.insertAgentMessage({ sessionId: 's', vmId: vm, message: { type: 'system' } }), true);
  assert.equal(t.listMessages('s').length, 4);
});

test('a waiting chat is listed as waiting', () => {
  const t = tenant();
  const vm = t.upsertVm('vm');
  t.upsertSession({ id: 's', vmId: vm, cwd: '/', title: 'x', status: 'active', accountId: 'default' });
  t.touchSession('s', 'waiting', vm);
  assert.equal(t.listSessionsByVm(vm)[0].status, 'waiting');
});
