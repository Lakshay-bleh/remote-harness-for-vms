import type { MessageDto } from '@remote-harness/shared';

export type Block = Record<string, any>;

export type ToolResult = { text: string; isError: boolean };

export type ToolItem = {
  kind: 'tool';
  key: string;
  block: Block; // the tool_use block
  result?: ToolResult;
  sub: Block[]; // tool_use blocks a subagent ran on behalf of this call
};

export type DisplayItem =
  | { kind: 'user'; key: string; createdAt: string; blocks: Block[] }
  | { kind: 'text'; key: string; text: string }
  | { kind: 'thinking'; key: string; text: string }
  | ToolItem
  | { kind: 'group'; key: string; tools: ToolItem[] }
  | { kind: 'turn_end'; key: string; data: any }
  | { kind: 'system'; key: string; text: string }
  | { kind: 'permission_request'; key: string; createdAt: string; data: any }
  | { kind: 'error'; key: string; text: string };

// Tools the CLI folds into "Searched for 2 patterns, read 3 files".
const COLLAPSIBLE = new Set(['Read', 'Grep', 'Glob']);
// TodoWrite is shown as a pinned task list, never as a tool line.
export const HIDDEN_TOOLS = new Set(['TodoWrite', 'AskUserQuestion', 'ExitPlanMode']);

function normalizeBlocks(content: unknown): Block[] {
  if (Array.isArray(content)) return content;
  if (typeof content === 'string') return [{ type: 'text', text: content }];
  return [];
}

export function resultText(content: unknown): string {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content
      .map((c: Block) => (c?.type === 'text' ? c.text : c?.type === 'image' ? '[Image]' : JSON.stringify(c)))
      .join('\n');
  }
  return '';
}

export function groupMessages(rows: MessageDto[]): DisplayItem[] {
  // Pass 1: index every tool_result by the tool_use it answers.
  const results = new Map<string, ToolResult>();
  for (const row of rows) {
    const m = row.message as any;
    if (m?.type !== 'user' || m.local) continue;
    for (const b of normalizeBlocks(m.message?.content)) {
      if (b.type === 'tool_result' && b.tool_use_id) {
        results.set(b.tool_use_id, { text: resultText(b.content), isError: Boolean(b.is_error) });
      }
    }
  }

  // Pass 2: subagent tool uses hang off their parent Agent/Task call.
  const subByParent = new Map<string, Block[]>();
  for (const row of rows) {
    const m = row.message as any;
    if (m?.type !== 'assistant' || !m.parent_tool_use_id) continue;
    const list = subByParent.get(m.parent_tool_use_id) ?? [];
    for (const b of normalizeBlocks(m.message?.content)) if (b.type === 'tool_use') list.push(b);
    subByParent.set(m.parent_tool_use_id, list);
  }

  const items: DisplayItem[] = [];
  let sawInit = false;
  let pending: ToolItem[] = []; // open read/search group
  let deferred: DisplayItem[] = []; // thinking absorbed into the open group

  const flush = () => {
    if (pending.length === 1) items.push(pending[0]);
    else if (pending.length > 1) items.push({ kind: 'group', key: `g-${pending[0].key}`, tools: pending });
    items.push(...deferred);
    pending = [];
    deferred = [];
  };

  for (const row of rows) {
    const m = row.message as any;
    const key = `m${row.id}`;
    if (!m || typeof m !== 'object') continue;

    if (m.type === 'user' && m.local) {
      flush();
      items.push({ kind: 'user', key, createdAt: row.createdAt, blocks: normalizeBlocks(m.message?.content) });
      continue;
    }
    if (m.type === 'assistant') {
      if (m.parent_tool_use_id) continue;
      normalizeBlocks(m.message?.content).forEach((b, i) => {
        const bk = `${key}-${i}`;
        if (b.type === 'tool_use') {
          if (HIDDEN_TOOLS.has(b.name)) return;
          const tool: ToolItem = { kind: 'tool', key: b.id ?? bk, block: b, result: results.get(b.id), sub: subByParent.get(b.id) ?? [] };
          if (COLLAPSIBLE.has(b.name)) {
            pending.push(tool);
          } else {
            flush();
            items.push(tool);
          }
        } else if (b.type === 'thinking') {
          const text = String(b.thinking ?? '').trim();
          if (!text) return;
          const item: DisplayItem = { kind: 'thinking', key: bk, text };
          if (pending.length) deferred.push(item);
          else items.push(item);
        } else if (b.type === 'text') {
          if (!String(b.text ?? '').trim()) return;
          flush();
          items.push({ kind: 'text', key: bk, text: b.text });
        }
      });
      continue;
    }
    if (m.type === 'system') {
      if (m.subtype === 'init') {
        if (sawInit) continue;
        sawInit = true;
        flush();
        items.push({ kind: 'system', key, text: `Session started · ${m.model} · ${m.cwd}` });
      } else if (m.subtype === 'compact_boundary') {
        flush();
        items.push({ kind: 'system', key, text: 'Conversation compacted' });
      }
      continue;
    }
    if (m.type === 'result') {
      flush();
      items.push({ kind: 'turn_end', key, data: m });
      continue;
    }
    if (m.type === 'permission_request') {
      items.push({ kind: 'permission_request', key, createdAt: row.createdAt, data: m });
      continue;
    }
    if (m.type === 'error') {
      flush();
      items.push({ kind: 'error', key, text: m.message });
    }
    // user tool_result rows, stream_event, and other SDK chatter are consumed above or ignored.
  }
  flush();
  return items;
}

/**
 * When the in-flight turn started, or null if the session is idle. A turn ends with its result, with an error (the run failed
 * before it could report one), or with the session itself ending (stopped, crashed, or the machine closed it).
 */
export function busySince(rows: MessageDto[]): number | null {
  for (let i = rows.length - 1; i >= 0; i--) {
    const m = rows[i].message as any;
    if (m?.type === 'result' || m?.type === 'error' || m?.type === SESSION_ENDED) return null;
    if (m?.type === 'user' && m.local) return new Date(rows[i].createdAt).getTime() || Date.now();
  }
  return null;
}

/** The row the app adds (never stored) when the machine says a session ended, so a run without a result stops spinning. */
export const SESSION_ENDED = 'session_ended';

export type Todo = { content: string; status: 'pending' | 'in_progress' | 'completed'; activeForm?: string };

// The latest TodoWrite list issued after the most recent user prompt.
export function latestTodos(rows: MessageDto[]): Todo[] | null {
  let todos: Todo[] | null = null;
  for (const row of rows) {
    const m = row.message as any;
    if (m?.type === 'user' && m.local) todos = null;
    if (m?.type !== 'assistant' || m.parent_tool_use_id) continue;
    for (const b of normalizeBlocks(m.message?.content)) {
      if (b.type === 'tool_use' && b.name === 'TodoWrite' && Array.isArray(b.input?.todos)) todos = b.input.todos;
    }
  }
  return todos;
}
