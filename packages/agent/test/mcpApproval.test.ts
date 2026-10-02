import assert from 'node:assert/strict';
import test from 'node:test';
import type { ManagedMcpServer } from '@remote-harness/shared';
import { isAutoAllowedMcpTool, parseMcpToolName } from '../src/mcpApproval.ts';

const server = (name: string, extra: Partial<ManagedMcpServer> = {}): ManagedMcpServer => ({ name, url: 'https://x.example/', updatedAt: '', ...extra });

test('a tool name is split into server and tool on the first "__" after the prefix', () => {
  assert.deepEqual(parseMcpToolName('mcp__escanor__escanor_invoke'), { server: 'escanor', tool: 'escanor_invoke' });
  assert.deepEqual(parseMcpToolName('mcp__a__b__c'), { server: 'a', tool: 'b__c' });
  for (const bad of ['escanor_invoke', 'mcp__', 'mcp____x', 'mcp__a', 'mcp__a__', 'mcp__A__x']) assert.equal(parseMcpToolName(bad), null, bad);
});

test('auto-approval of one server never spills onto another whose name merely starts the same', () => {
  const servers = [server('a', { autoAllow: true }), server('ab', { autoAllow: false })];
  assert.equal(isAutoAllowedMcpTool(servers, 'mcp__a__anything', {}), true);
  assert.equal(isAutoAllowedMcpTool(servers, 'mcp__ab__anything', {}), false);
  assert.equal(isAutoAllowedMcpTool(servers, 'mcp__a_b__anything', {}), false);
});

test('a server whose name contains "__" is never trusted (its tools would be indistinguishable from another server\'s)', () => {
  const servers = [server('a', { autoAllow: false }), server('a__b', { autoAllow: true })];
  assert.equal(isAutoAllowedMcpTool(servers, 'mcp__a__b__tool', {}), false);
  assert.equal(isAutoAllowedMcpTool(servers, 'mcp__a__tool', {}), false);
});

test('autoAllow false asks; autoAllowReads lets plain reads through; the playbook tool list still works', () => {
  const s = server('escanor', { autoAllow: false, autoAllowReads: true, autoAllowTools: ['github.create_issue'] });
  assert.equal(isAutoAllowedMcpTool([s], 'mcp__escanor__escanor_invoke', { tool_id: 'github.list_repos' }), true);
  assert.equal(isAutoAllowedMcpTool([s], 'mcp__escanor__escanor_invoke', { tool_id: 'github.delete_repo' }), false);
  assert.equal(isAutoAllowedMcpTool([s], 'mcp__escanor__escanor_invoke', { tool_id: 'github.create_issue' }), true);
  assert.equal(isAutoAllowedMcpTool([s], 'mcp__escanor__escanor_invoke', { tool_id: 'database_query', arguments: { sql: 'DELETE FROM t' } }), false);
});

test('an unknown server is not approved', () => {
  assert.equal(isAutoAllowedMcpTool([server('escanor', { autoAllow: true })], 'mcp__repo_declared__run', {}), false);
  assert.equal(isAutoAllowedMcpTool([], 'mcp__escanor__x', {}), false);
});
