/**
 * The Escanor assistant, as both the web app and the mobile app see it: the API's shapes and the pure
 * chat-state functions. No I/O and no framework, so the behaviour that matters (merging polls, showing a
 * message at once, what to draw) is tested once and identical everywhere.
 */

// ---------------------------------------------------------------------------- API shapes

export type AssistantState = 'not_configured' | 'not_started' | 'setting_up' | 'ready' | 'reconnecting' | 'error';

/** Where the assistant is. Nothing here is a credential or a machine detail. */
export interface AssistantStatus {
  state: AssistantState;
  ready: boolean;
  message: string;
}

export interface AssistantConversation {
  id: string;
  title: string;
  created_at: string | null;
  updated_at: string | null;
}

export type AssistantApprovalStatus = 'pending' | 'allowed' | 'denied' | 'expired';

export type AssistantItem =
  | { id: number; kind: 'user'; text: string; at?: string | null }
  | { id: number; kind: 'assistant'; text: string; at?: string | null }
  | { id: number; kind: 'activity'; text: string; at?: string | null }
  | { id: number; kind: 'error'; text: string; at?: string | null }
  | { id: number; kind: 'done'; at?: string | null }
  | {
      id: number;
      kind: 'approval';
      request_id: string;
      status: AssistantApprovalStatus;
      title: string;
      detail: string;
      risk: 'normal' | 'high';
      raw: string;
      at?: string | null;
    };

export interface AssistantMessages {
  items: AssistantItem[];
  approvals: Array<{ request_id: string; status: AssistantApprovalStatus }>;
  running: boolean;
  pending: number;
  last_id: number;
}

export interface AssistantUsage {
  source: 'escanor-ai' | 'local';
  messages_today: number;
  message_limit: number | null;
  today: { requests: number; tokens: number; request_limit: number | null; token_limit: number | null };
  month: { requests: number; input_tokens: number; output_tokens: number; cost_usd: number | null };
  cost_is_estimate: boolean;
  unpriced_models: string[];
}

/** What the assistant can reach right now. The same answer on every device. */
export interface AssistantCapabilities {
  assistant: { state: string; ready: boolean };
  machine: { state: string; detail: string; source: string };
  mcp: { installed: boolean; checked: boolean };
  integrations: Array<{
    provider_id: string;
    name: string;
    connected: boolean;
    auth_method: string;
    /** true: the assistant will see it; false: connected but it has no tools for it yet; null: could not check. */
    available_to_assistant: boolean | null;
    needs_reconnect: boolean;
  }>;
  code: { hosts: Array<{ host: string; connected: boolean }>; can_change_code: boolean; protected_branches: string };
  summary: string;
}

export interface MachineView {
  state: string;
  detail: string;
  available: boolean;
  events: Array<{ at: number; kind: string; detail: string }>;
  logs?: string;
}

// ---------------------------------------------------------------------------- chat state

export type ChatItem = AssistantItem | { id: number; kind: 'user'; text: string; at?: string | null; optimistic: true };

export interface ChatState {
  items: ChatItem[];
  /** Highest server message id seen; the next poll asks for everything after it. */
  lastId: number;
  running: boolean;
  pending: number;
}

export const emptyChat: ChatState = { items: [], lastId: 0, running: false, pending: 0 };

let optimisticCounter = 0;

/** Show the person's message at once, before the server has heard of it. */
export function addOptimisticMessage(state: ChatState, text: string): ChatState {
  optimisticCounter += 1;
  return {
    ...state,
    items: [...state.items, { id: -optimisticCounter, kind: 'user', text, optimistic: true }],
    running: true,
  };
}

/** Take the optimistic message back, e.g. when sending failed. */
export function dropOptimisticMessages(state: ChatState): ChatState {
  return { ...state, items: state.items.filter((i) => !('optimistic' in i)), running: false };
}

/** Merge one poll into the state. Safe to apply the same response twice. */
export function applyMessages(state: ChatState, res: AssistantMessages): ChatState {
  const fresh = res.items.filter((i) => i.id > state.lastId);

  // Each real user message replaces one optimistic copy of it (matched by text, oldest first).
  let items = state.items;
  for (const incoming of fresh) {
    if (incoming.kind !== 'user') continue;
    const at = items.findIndex((i) => 'optimistic' in i && i.kind === 'user' && i.text === incoming.text);
    if (at >= 0) items = [...items.slice(0, at), ...items.slice(at + 1)];
  }
  items = [...items, ...fresh];

  const answers = new Map<string, AssistantApprovalStatus>(res.approvals.map((a) => [a.request_id, a.status]));
  items = items.map((i) => (i.kind === 'approval' && answers.has(i.request_id) ? { ...i, status: answers.get(i.request_id)! } : i));

  return { items, lastId: Math.max(state.lastId, res.last_id), running: res.running, pending: res.pending };
}

/** Reflect the person's answer immediately, before the next poll confirms it. */
export function markAnswered(state: ChatState, requestId: string, allow: boolean): ChatState {
  const status: AssistantApprovalStatus = allow ? 'allowed' : 'denied';
  return {
    ...state,
    items: state.items.map((i) => (i.kind === 'approval' && i.request_id === requestId && i.status === 'pending' ? { ...i, status } : i)),
    pending: Math.max(0, state.pending - 1),
  };
}

export type DisplayBlock =
  | { key: string; type: 'user' | 'assistant' | 'error'; text: string; optimistic?: boolean }
  | { key: string; type: 'activity'; text: string; live: boolean }
  | { key: string; type: 'approval'; item: Extract<AssistantItem, { kind: 'approval' }> };

/**
 * What to actually draw. A run of "Checking which services are available" x9 is one quiet line, the
 * turn-finished marker is not drawn, and only the latest activity line pulses while work is happening.
 */
export function toDisplay(state: ChatState): DisplayBlock[] {
  const blocks: DisplayBlock[] = [];
  state.items.forEach((item, index) => {
    const key = `${item.id}:${index}`;
    switch (item.kind) {
      case 'user':
        blocks.push({ key, type: 'user', text: item.text, ...('optimistic' in item ? { optimistic: true } : {}) });
        break;
      case 'assistant':
        blocks.push({ key, type: 'assistant', text: item.text });
        break;
      case 'error':
        blocks.push({ key, type: 'error', text: item.text });
        break;
      case 'approval':
        // A question nobody needs to answer any more (the turn ended) is noise.
        if (item.status !== 'expired') blocks.push({ key, type: 'approval', item });
        break;
      case 'activity': {
        const previous = blocks[blocks.length - 1];
        if (previous?.type === 'activity' && previous.text === item.text) break; // the same thing again
        blocks.push({ key, type: 'activity', text: item.text, live: false });
        break;
      }
      case 'done':
        break;
    }
  });

  if (state.running && state.pending === 0) {
    const last = blocks[blocks.length - 1];
    if (last?.type === 'activity') last.live = true;
  }
  return blocks;
}

/** Are we waiting on the assistant (as opposed to on the person)? Drives the "thinking" indicator. */
export function isThinking(state: ChatState): boolean {
  if (!state.running || state.pending > 0) return false;
  const last = toDisplay(state).at(-1);
  return !last || last.type === 'user' || last.type === 'activity';
}

/** How long to wait before asking again. Quick while something is happening, patient otherwise. */
export function pollDelayMs(state: ChatState): number {
  if (state.running) return 700;
  if (state.pending > 0) return 1500;
  return 8000;
}

/** Usage, in words a person can act on. Cost is the operator's business and is deliberately not shown. */
export type UsageSummary = {
  messages: string;
  tokens: string | null;
  /** 0..1 of the daily message allowance used, or null when there is no limit. */
  ratio: number | null;
  level: 'ok' | 'warn' | 'full';
};

function compact(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1).replace(/\.0$/, '')}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1).replace(/\.0$/, '')}k`;
  return String(n);
}

export function describeUsage(usage: {
  messages_today: number;
  message_limit: number | null;
  today: { tokens: number };
}): UsageSummary {
  const used = Math.max(0, usage.messages_today);
  const limit = usage.message_limit && usage.message_limit > 0 ? usage.message_limit : null;
  const ratio = limit ? Math.min(1, used / limit) : null;
  return {
    messages: limit ? `${used} of ${limit} messages today` : `${used} message${used === 1 ? '' : 's'} today`,
    tokens: usage.today.tokens > 0 ? `${compact(usage.today.tokens)} tokens` : null,
    ratio,
    level: ratio === null ? 'ok' : ratio >= 1 ? 'full' : ratio >= 0.8 ? 'warn' : 'ok',
  };
}
