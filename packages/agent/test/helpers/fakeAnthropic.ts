// A fake Anthropic Messages API, so a REAL Claude Code process can run a REAL tool call with no
// network and no key. On each fresh user message the "model" asks to call the Escanor MCP tool
// (if the session has it); once the tool result is back it answers "done".
import http from 'node:http';
import type { AddressInfo } from 'node:net';

const usage = { input_tokens: 10, output_tokens: 5 };

function sse(res: http.ServerResponse, events: Array<[string, unknown]>) {
  res.writeHead(200, { 'content-type': 'text/event-stream' });
  for (const [event, data] of events) res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  res.end();
}

const start = (model: string) =>
  ['message_start', { type: 'message_start', message: { id: 'msg_t', type: 'message', role: 'assistant', model, content: [], stop_reason: null, usage } }] as [string, unknown];

function reply(res: http.ServerResponse, model: string, block: unknown, delta: unknown, stop: string) {
  sse(res, [
    start(model),
    ['content_block_start', { type: 'content_block_start', index: 0, content_block: block }],
    ['content_block_delta', { type: 'content_block_delta', index: 0, delta }],
    ['content_block_stop', { type: 'content_block_stop', index: 0 }],
    ['message_delta', { type: 'message_delta', delta: { stop_reason: stop }, usage: { output_tokens: 5 } }],
    ['message_stop', { type: 'message_stop' }],
  ]);
}

export async function startFakeAnthropic() {
  const server = http.createServer(async (req, res) => {
    const chunks: Buffer[] = [];
    for await (const c of req) chunks.push(c as Buffer);
    let body: any = {};
    try {
      body = JSON.parse(Buffer.concat(chunks).toString() || '{}');
    } catch {
      /* not JSON */
    }
    if (!req.url?.startsWith('/v1/messages')) {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end('{}');
      return;
    }
    if (!body.stream) {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ id: 'm', type: 'message', role: 'assistant', model: body.model, content: [{ type: 'text', text: 'ok' }], stop_reason: 'end_turn', usage }));
      return;
    }
    const tool = (body.tools ?? []).map((t: any) => t.name).find((n: string) => n.startsWith('mcp__escanor__'));
    const last = body.messages?.[body.messages.length - 1];
    const hasToolResult = Array.isArray(last?.content) && last.content.some((c: any) => c.type === 'tool_result');
    if (tool && !hasToolResult) {
      reply(res, body.model, { type: 'tool_use', id: 'toolu_1', name: tool, input: {} }, { type: 'input_json_delta', partial_json: '{}' }, 'tool_use');
    } else {
      reply(res, body.model, { type: 'text', text: '' }, { type: 'text_delta', text: hasToolResult ? 'done' : 'no escanor tool available' }, 'end_turn');
    }
  });
  await new Promise<void>((r) => server.listen(0, '127.0.0.1', r));
  return { url: `http://127.0.0.1:${(server.address() as AddressInfo).port}`, close: () => server.close() };
}
