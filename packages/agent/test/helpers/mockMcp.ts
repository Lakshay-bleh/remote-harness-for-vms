// A minimal stateless streamable-HTTP MCP server named "escanor" with one tool. It records the
// Authorization header and JSON-RPC method of every request, so a test can prove what a real
// Claude Code session actually sent.
import http from 'node:http';
import type { AddressInfo } from 'node:net';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';

export type Seen = { auth: string | undefined; rpc: string | undefined; tool?: string };

export async function startMockMcp() {
  const seen: Seen[] = [];
  const server = http.createServer(async (req, res) => {
    const chunks: Buffer[] = [];
    for await (const c of req) chunks.push(c as Buffer);
    const body = chunks.length ? JSON.parse(Buffer.concat(chunks).toString()) : undefined;
    seen.push({ auth: req.headers.authorization, rpc: body?.method, tool: body?.params?.arguments?.tool_id });
    const mcp = new McpServer({ name: 'escanor', version: '1' });
    mcp.tool('escanor_list_providers', 'List providers', async () => ({ content: [{ type: 'text', text: 'github,vercel' }] }));
    // What the real server reports for a workspace; MOCK_MCP_CONNECTED lets a test choose it.
    mcp.tool('escanor_connection_status', 'Which providers are connected', async () => ({
      content: [{ type: 'text', text: JSON.stringify({ status: 'ok', connected: (process.env.MOCK_MCP_CONNECTED ?? 'github').split(',').filter(Boolean), not_connected: [], needs_refresh: [] }) }],
    }));
    mcp.tool('escanor_invoke', 'Run one tool by id', { tool_id: z.string(), arguments: z.record(z.any()).optional() }, async ({ tool_id }) => ({
      content: [{ type: 'text', text: tool_id === 'sentry.get_issue_logs' ? 'ERROR greet(): TypeError: can only concatenate str (not "NoneType") -- greet.py returns the upper-cased name' : `ran ${tool_id}` }],
    }));
    const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
    res.on('close', () => {
      void transport.close();
      void mcp.close();
    });
    await mcp.connect(transport);
    await transport.handleRequest(req, res, body);
  });
  await new Promise<void>((r) => server.listen(0, '127.0.0.1', r));
  const port = (server.address() as AddressInfo).port;
  return {
    url: `http://127.0.0.1:${port}/`,
    seen,
    toolCalls: () => seen.filter((s) => s.rpc === 'tools/call').length,
    close: () => server.close(),
  };
}
