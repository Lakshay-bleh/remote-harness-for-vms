// A minimal stateless streamable-HTTP MCP server named "escanor" with one tool. It records the
// Authorization header and JSON-RPC method of every request, so a test can prove what a real
// Claude Code session actually sent.
import http from 'node:http';
import type { AddressInfo } from 'node:net';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';

export type Seen = { auth: string | undefined; rpc: string | undefined };

export async function startMockMcp() {
  const seen: Seen[] = [];
  const server = http.createServer(async (req, res) => {
    const chunks: Buffer[] = [];
    for await (const c of req) chunks.push(c as Buffer);
    const body = chunks.length ? JSON.parse(Buffer.concat(chunks).toString()) : undefined;
    seen.push({ auth: req.headers.authorization, rpc: body?.method });
    const mcp = new McpServer({ name: 'escanor', version: '1' });
    mcp.tool('escanor_list_providers', 'List providers', async () => ({ content: [{ type: 'text', text: 'github,vercel' }] }));
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
