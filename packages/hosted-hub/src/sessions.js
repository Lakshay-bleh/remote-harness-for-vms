// Chats on the hosted hub: listing (with the id each started under), their messages a page at a time, rename and delete,
// and the mode/model/effort that may come with a message. Pure SQL over `exec(sql, ...params) => rows`, so it is tested
// against real SQLite (test/sessions.test.ts) and runs unchanged on a Durable Object's storage.

export const DEFAULT_MESSAGE_LIMIT = 2000;
export const MAX_MESSAGE_LIMIT = 5000;

export const SESSIONS_SCHEMA = `
  CREATE TABLE IF NOT EXISTS session_aliases (
    old_id TEXT PRIMARY KEY,
    new_id TEXT NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_session_aliases_new ON session_aliases(new_id);
`;

/** A new chat runs under a temporary id until Claude names it. Remember which, so an app that missed the news can catch up. */
export function recordAlias(exec, tempId, sessionId) {
  if (!tempId || !sessionId || tempId === sessionId) return;
  exec("INSERT INTO session_aliases (old_id, new_id) VALUES (?, ?) ON CONFLICT(old_id) DO UPDATE SET new_id = excluded.new_id", tempId, sessionId);
}

/** The real id for a temporary one (or the id itself). */
export function resolveSession(exec, id) {
  return exec("SELECT new_id FROM session_aliases WHERE old_id = ?", id)[0]?.new_id ?? id;
}

export function listSessions(exec, vmId) {
  return exec(
    `SELECT id, vm_id, cwd, title, created_at, last_message_at, status, account_id,
            (SELECT a.old_id FROM session_aliases a WHERE a.new_id = sessions.id LIMIT 1) AS temp_id
       FROM sessions WHERE vm_id = ? ORDER BY last_message_at DESC`,
    vmId
  ).map((r) => ({
    id: r.id,
    vmId: r.vm_id,
    cwd: r.cwd,
    title: r.title,
    createdAt: r.created_at,
    lastMessageAt: r.last_message_at,
    status: r.status,
    accountId: r.account_id,
    ...(r.temp_id ? { tempId: r.temp_id } : {}),
  }));
}

const whole = (v) => (typeof v === "string" && /^\d{1,15}$/.test(v) ? Number(v) : undefined);

/** `?limit=&after=&before=` as numbers (anything else is ignored). */
export function messageQuery(params) {
  const limit = whole(params.get("limit"));
  return {
    limit: limit === undefined ? DEFAULT_MESSAGE_LIMIT : Math.max(1, Math.min(MAX_MESSAGE_LIMIT, limit)),
    after: whole(params.get("after")),
    before: whole(params.get("before")),
  };
}

/** The newest `limit` messages of a chat, oldest first. `after`: only newer than that id. `before`: only older (a page further back). */
export function listMessages(exec, sessionId, { limit = DEFAULT_MESSAGE_LIMIT, after, before } = {}) {
  const where = ["session_id = ?"];
  const params = [sessionId];
  if (after !== undefined) {
    where.push("id > ?");
    params.push(after);
  }
  if (before !== undefined) {
    where.push("id < ?");
    params.push(before);
  }
  const rows = exec(
    `SELECT id, session_id, vm_id, payload, created_at FROM (
       SELECT * FROM messages WHERE ${where.join(" AND ")} ORDER BY id DESC LIMIT ?
     ) ORDER BY id ASC`,
    ...params,
    limit
  );
  return rows.map((r) => ({ id: r.id, sessionId: r.session_id, vmId: r.vm_id, createdAt: r.created_at, message: JSON.parse(r.payload) }));
}

const exists = (exec, vmId, id) => exec("SELECT 1 AS one FROM sessions WHERE id = ? AND vm_id = ?", id, vmId).length > 0;

export function renameSession(exec, vmId, id, title) {
  if (!exists(exec, vmId, id)) return false;
  exec("UPDATE sessions SET title = ? WHERE id = ? AND vm_id = ?", title, id, vmId);
  return true;
}

/** The chat and everything said in it. (The machine keeps its own transcript; that is the machine's to delete.) */
export function deleteSession(exec, vmId, id) {
  if (!exists(exec, vmId, id)) return false;
  exec("DELETE FROM messages WHERE session_id = ? AND vm_id = ?", id, vmId);
  exec("DELETE FROM sessions WHERE id = ? AND vm_id = ?", id, vmId);
  exec("DELETE FROM session_aliases WHERE new_id = ? OR old_id = ?", id, id);
  return true;
}

const PERMISSION_MODES = ["default", "acceptEdits", "bypassPermissions", "plan", "dontAsk", "auto"];
const EFFORT_LEVELS = ["low", "medium", "high", "xhigh", "max"];

/** The mode, model and effort that may come with a message (packages/shared parseRunChoices). Unknown values are left out. */
export function runChoices(body) {
  const out = {};
  if (typeof body !== "object" || body === null) return out;
  const { permissionMode, model, effort } = body;
  if (PERMISSION_MODES.includes(permissionMode)) out.permissionMode = permissionMode;
  if (typeof model === "string" && model.length <= 200) out.model = model;
  if (effort === null || effort === "") out.effort = null;
  else if (EFFORT_LEVELS.includes(effort)) out.effort = effort;
  return out;
}
