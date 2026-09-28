import type { MessageDto } from '@remote-harness/shared';

export type Block = Record<string, any>;

export type DisplayItem =
  | { kind: 'user'; key: string; createdAt: string; blocks: Block[] }
  | { kind: 'assistant'; key: string; createdAt: string; blocks: Block[]; model?: string }
  | { kind: 'tool_result'; key: string; createdAt: string; blocks: Block[] }
  | { kind: 'system_init'; key: string; createdAt: string; data: any }
  | { kind: 'result'; key: string; createdAt: string; data: any }
  | { kind: 'permission_request'; key: string; createdAt: string; data: any }
  | { kind: 'error'; key: string; createdAt: string; text: string }
  | { kind: 'raw'; key: string; createdAt: string; data: any };

const SKIPPED_TYPES = new Set(['stream_event']);

function normalizeBlocks(content: unknown): Block[] {
  if (Array.isArray(content)) return content;
  if (typeof content === 'string') return [{ type: 'text', text: content }];
  return [];
}

export function groupMessages(rows: MessageDto[]): DisplayItem[] {
  const items: DisplayItem[] = [];
  const assistantIndexByTurn = new Map<string, number>();
  let sawInit = false;

  for (const row of rows) {
    const m = row.message as any;
    const key = `m${row.id}`;
    if (!m || typeof m !== 'object') continue;

    if (m.type === 'user' && m.local) {
      items.push({ kind: 'user', key, createdAt: row.createdAt, blocks: normalizeBlocks(m.message?.content) });
      continue;
    }
    if (m.type === 'user') {
      items.push({ kind: 'tool_result', key, createdAt: row.createdAt, blocks: normalizeBlocks(m.message?.content) });
      continue;
    }
    if (m.type === 'assistant') {
      const turnId: string = m.message?.id ?? key;
      const idx = assistantIndexByTurn.get(turnId);
      const newBlocks = normalizeBlocks(m.message?.content);
      const existing = idx !== undefined ? items[idx] : undefined;
      if (existing && existing.kind === 'assistant') {
        existing.blocks = [...existing.blocks, ...newBlocks];
      } else {
        assistantIndexByTurn.set(turnId, items.length);
        items.push({ kind: 'assistant', key: `t-${turnId}`, createdAt: row.createdAt, blocks: newBlocks, model: m.message?.model });
      }
      continue;
    }
    if (m.type === 'system' && m.subtype === 'init') {
      if (sawInit) continue;
      sawInit = true;
      items.push({ kind: 'system_init', key, createdAt: row.createdAt, data: m });
      continue;
    }
    if (m.type === 'result') {
      items.push({ kind: 'result', key, createdAt: row.createdAt, data: m });
      continue;
    }
    if (m.type === 'permission_request') {
      items.push({ kind: 'permission_request', key, createdAt: row.createdAt, data: m });
      continue;
    }
    if (m.type === 'error') {
      items.push({ kind: 'error', key, createdAt: row.createdAt, text: m.message });
      continue;
    }
    if (SKIPPED_TYPES.has(m.type)) continue;
    items.push({ kind: 'raw', key, createdAt: row.createdAt, data: m });
  }
  return items;
}
