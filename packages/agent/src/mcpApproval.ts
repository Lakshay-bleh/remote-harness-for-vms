import { isReadOnlyMcpCall, isValidMcpServerName, mcpToolIdMatches, type ManagedMcpServer } from '@remote-harness/shared';

/** `mcp__<server>__<tool>` -> its parts. Server names cannot contain "__", so the first separator is unambiguous. */
export function parseMcpToolName(name: string): { server: string; tool: string } | null {
  if (!name.startsWith('mcp__')) return null;
  const rest = name.slice('mcp__'.length);
  const i = rest.indexOf('__');
  if (i <= 0) return null;
  const server = rest.slice(0, i);
  const tool = rest.slice(i + 2);
  if (!tool || !isValidMcpServerName(server)) return null;
  return { server, tool };
}

// Approval is decided per call, from the *current* set of hub-installed servers -- not baked into the session as an
// `allowedTools` rule at start. A start-time rule cannot be withdrawn from a running session, so turning auto-approve off
// would have kept approving in every chat already open. Deciding per call makes both directions take effect immediately,
// and fails closed: an unknown server, an unparseable name, or a flag that is not exactly `true` asks.
export function isAutoAllowedMcpTool(servers: Iterable<ManagedMcpServer>, toolName: string, input: Record<string, unknown>): boolean {
  const parsed = parseMcpToolName(toolName);
  if (!parsed) return false;
  const s = [...servers].find((x) => x.name === parsed.server && isValidMcpServerName(x.name));
  if (!s) return false;
  if (s.autoAllow === true) return true;
  // Not blanket-approved, but calls that only read may still go through without a card.
  if (s.autoAllowReads === true && isReadOnlyMcpCall(parsed.tool, input)) return true;
  // A playbook's own tools: named by the operator ahead of time, so no card.
  if (s.autoAllowTools?.length && parsed.tool === 'escanor_invoke' && mcpToolIdMatches(s.autoAllowTools, typeof input?.tool_id === 'string' ? input.tool_id : '')) return true;
  return false;
}
