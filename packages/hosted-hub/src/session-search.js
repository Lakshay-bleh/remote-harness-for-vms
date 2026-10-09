// Searching a machine's chats by what was said in them, not only by title: GET /api/vms/:vmId/sessions/search?q=&limit=.
// The matching and ranking are the self-hosted hub's (packages/hub/src/search.ts), so both hubs answer the same way.
// This hub keeps each message as its JSON payload, so a cheap LIKE on the payload narrows the candidates and the readable
// text (what the person typed and what the assistant wrote) is taken out of the matches only.
import { likePattern, parseQuery, rankSessions, readableText } from '../../hub/src/search.ts';

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 100;
// Enough to rank a busy machine well without reading all of it: the newest matching messages, a few per chat.
const MAX_ROWS = 4000;
const PER_SESSION = 40;

/** `exec(sql, ...params)` returns the rows as plain objects (a Durable Object's `sql.exec(...).toArray()`). */
export function searchSessions(exec, vmId, rawQuery, rawLimit) {
  const q = parseQuery(String(rawQuery ?? ''));
  if (!q) return [];
  const asked = Number.parseInt(String(rawLimit ?? ''), 10);
  const limit = Number.isFinite(asked) && asked > 0 ? Math.min(asked, MAX_LIMIT) : DEFAULT_LIMIT;

  const sessions = exec('SELECT id, title, last_message_at FROM sessions WHERE vm_id = ?', vmId);
  if (sessions.length === 0) return [];
  // Any query word may be in the messages (the rest in the title), so a message is a candidate when it has any of them.
  const likes = q.stems.map(() => 'payload LIKE ?').join(' OR ');
  const rows = exec(
    `SELECT session_id, payload FROM messages WHERE vm_id = ? AND (${likes}) ORDER BY id DESC LIMIT ${MAX_ROWS}`,
    vmId,
    ...q.stems.map(likePattern),
  );
  const texts = new Map();
  for (const r of rows) {
    const list = texts.get(r.session_id) ?? [];
    if (list.length >= PER_SESSION) continue;
    let text = '';
    try {
      text = readableText(JSON.parse(r.payload));
    } catch {
      text = '';
    }
    if (text) list.push(text);
    texts.set(r.session_id, list);
  }
  return rankSessions(
    q,
    sessions.map((s) => ({
      sessionId: s.id,
      title: s.title ?? '',
      lastMessageAt: s.last_message_at ?? '',
      texts: (texts.get(s.id) ?? []).reverse(), // oldest first
    })),
    limit,
  );
}
