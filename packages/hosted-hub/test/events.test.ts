import assert from 'node:assert/strict';
import { test } from 'node:test';
import { agentMessageUid, approvalEvent, describeTool, resultEvent } from '../src/events.js';

test('describes what Claude wants to do in a few words', () => {
  assert.equal(describeTool('Bash', { command: 'npm test\nnpm run lint' }), 'Run: npm test');
  assert.equal(describeTool('Edit', { file_path: '/home/me/app/src/app.ts' }), 'Edit: app.ts');
  assert.equal(describeTool('WebFetch', { url: 'https://example.com' }), 'Open: https://example.com');
  assert.equal(describeTool('mcp__escanor__escanor_invoke', {}), 'Use escanor invoke (escanor)');
  assert.equal(describeTool('Task', {}), 'Use Task');
  assert.ok(describeTool('Bash', { command: 'x'.repeat(300) }).length <= 106);
});

test('an approval event names the machine, the chat and the action', () => {
  const e = approvalEvent({ vmId: 'v', vmName: 'laptop', sessionId: 's', title: 'Fix login', requestId: 'r', toolName: 'Bash', input: { command: 'ls' } });
  assert.deepEqual(e, { kind: 'approval', vmId: 'v', vmName: 'laptop', sessionId: 's', title: 'Fix login', text: 'Run: ls', requestId: 'r' });
});

test('a finished turn is done or failed; anything else is no event', () => {
  const base = { vmId: 'v', vmName: 'laptop', sessionId: 's', title: 'Fix login' };
  assert.equal(resultEvent({ ...base, message: { type: 'result', subtype: 'success', result: 'All tests pass.\nDetails…' } })?.text, 'All tests pass.');
  assert.equal(resultEvent({ ...base, message: { type: 'result', subtype: 'success', result: 'ok' } })?.kind, 'done');
  assert.equal(resultEvent({ ...base, message: { type: 'result', subtype: 'error_max_turns' } })?.kind, 'failed');
  assert.equal(resultEvent({ ...base, message: { type: 'result', subtype: 'success', is_error: true, result: 'API error' } })?.kind, 'failed');
  assert.equal(resultEvent({ ...base, message: { type: 'assistant' } }), null);
});

test('resent copies are recognised by uuid or request id', () => {
  assert.equal(agentMessageUid({ type: 'sdk_message', message: { uuid: 'u' } }), 'sdk:u');
  assert.equal(agentMessageUid({ type: 'permission_request', requestId: 'r' }), 'perm:r');
  assert.equal(agentMessageUid({ type: 'sdk_message', message: {} }), undefined);
});
