import { createHash, randomUUID } from 'node:crypto';
import { chmodSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import type { ClaudeAccount, MessageDto, SessionDto, VmDto } from '@remote-harness/shared';
import { redactSecrets } from '@remote-harness/shared/validate';
import { deriveKey, isSealed, open as unseal, seal } from './secretbox.js';

const sessionDigest = (token: string) => `sha256:${createHash('sha256').update(token).digest('hex')}`;
const SESSION_MAX_AGE_MS = 30 * 24 * 60 * 60 * 1000;
const DEFAULT_MESSAGE_LIMIT = 2000;

export type DbOptions = {
  // When set, MCP bearer tokens are stored AES-GCM encrypted under a key derived from this secret.
  encryptionKey?: string;
};

export function openDb(dataDir: string, opts: DbOptions = {}) {
  mkdirSync(dataDir, { recursive: true, mode: 0o700 });
  chmodSync(dataDir, 0o700);
  const dbPath = join(dataDir, 'hub.sqlite');
  const db = new DatabaseSync(dbPath);
  chmodSync(dbPath, 0o600); // transcripts, permission inputs and tokens live here: owner-only
  // WAL + synchronous=NORMAL commits without an fsync per write, which keeps the (synchronous) inserts
  // for every streamed agent message from stalling the event loop.
  db.exec('PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA busy_timeout = 5000;');
  const key = opts.encryptionKey ? deriveKey(opts.encryptionKey) : null;

  db.exec(`
    CREATE TABLE IF NOT EXISTS vms (
      id TEXT PRIMARY KEY,
      name TEXT UNIQUE NOT NULL,
      last_seen_at TEXT,
      accounts_json TEXT NOT NULL DEFAULT '[]'
    );
    CREATE TABLE IF NOT EXISTS sessions (
      id TEXT PRIMARY KEY,
      vm_id TEXT NOT NULL,
      cwd TEXT NOT NULL,
      title TEXT NOT NULL,
      created_at TEXT NOT NULL,
      last_message_at TEXT NOT NULL,
      status TEXT NOT NULL,
      account_id TEXT NOT NULL DEFAULT 'default'
    );
    CREATE TABLE IF NOT EXISTS messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL,
      vm_id TEXT NOT NULL,
      payload TEXT NOT NULL,
      created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id, id);
    CREATE TABLE IF NOT EXISTS auth_tokens (
      token TEXT PRIMARY KEY,
      created_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS hub_users (
      escanor_user_id TEXT PRIMARY KEY,
      hub_id TEXT NOT NULL UNIQUE,
      email TEXT NOT NULL,
      name TEXT,
      created_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS mcp_servers (
      name TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      token TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
  `);

  // Idempotent migration: preserve existing sessions but stop storing usable
  // bearer credentials in the auth table. No message/history rows are removed.
  for (const row of db.prepare('SELECT token FROM auth_tokens').all() as { token: string }[]) {
    if (!row.token.startsWith('sha256:')) {
      db.prepare('UPDATE auth_tokens SET token = ? WHERE token = ?').run(sessionDigest(row.token), row.token);
    }
  }

  if (key) {
    for (const row of db.prepare('SELECT name, token FROM mcp_servers').all() as { name: string; token: string }[]) {
      if (!isSealed(row.token)) db.prepare('UPDATE mcp_servers SET token = ? WHERE name = ?').run(seal(key, row.token), row.name);
    }
  }

  return {
    upsertVm(name: string): string {
      const existing = db.prepare('SELECT id FROM vms WHERE name = ?').get(name) as { id: string } | undefined;
      const id = existing?.id ?? randomUUID();
      db.prepare(
        `INSERT INTO vms (id, name, last_seen_at) VALUES (?, ?, ?)
         ON CONFLICT(name) DO UPDATE SET last_seen_at = excluded.last_seen_at`,
      ).run(id, name, new Date().toISOString());
      return id;
    },

    touchVmSeen(id: string): void {
      db.prepare('UPDATE vms SET last_seen_at = ? WHERE id = ?').run(new Date().toISOString(), id);
    },

    setVmAccounts(id: string, accounts: ClaudeAccount[]): void {
      db.prepare('UPDATE vms SET accounts_json = ? WHERE id = ?').run(JSON.stringify(accounts), id);
    },

    listVms(): Omit<VmDto, 'connected'>[] {
      const rows = db
        .prepare('SELECT id, name, last_seen_at as lastSeenAt, accounts_json as accountsJson FROM vms ORDER BY name')
        .all() as { id: string; name: string; lastSeenAt: string | null; accountsJson: string }[];
      return rows.map((r) => ({ id: r.id, name: r.name, lastSeenAt: r.lastSeenAt, accounts: JSON.parse(r.accountsJson) }));
    },

    getVmName(id: string): string | undefined {
      const row = db.prepare('SELECT name FROM vms WHERE id = ?').get(id) as { name: string } | undefined;
      return row?.name;
    },

    getVmAccounts(id: string): ClaudeAccount[] {
      const row = db.prepare('SELECT accounts_json as accountsJson FROM vms WHERE id = ?').get(id) as
        | { accountsJson: string }
        | undefined;
      return row ? JSON.parse(row.accountsJson) : [];
    },

    upsertSession(s: { id: string; vmId: string; cwd: string; title: string; status: string; accountId: string }): void {
      const now = new Date().toISOString();
      db.prepare(
        `INSERT INTO sessions (id, vm_id, cwd, title, created_at, last_message_at, status, account_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET status = excluded.status, last_message_at = excluded.last_message_at
         WHERE sessions.vm_id = excluded.vm_id`,
      ).run(s.id, s.vmId, s.cwd, s.title, now, now, s.status, s.accountId);
    },

    // vmId scopes the update to the owning VM, so one agent can't touch another VM's session.
    touchSession(id: string, status?: string, vmId?: string): void {
      const now = new Date().toISOString();
      const scope = vmId ? ' AND vm_id = ?' : '';
      const extra = vmId ? [vmId] : [];
      if (status) {
        db.prepare(`UPDATE sessions SET last_message_at = ?, status = ? WHERE id = ?${scope}`).run(now, status, id, ...extra);
      } else {
        db.prepare(`UPDATE sessions SET last_message_at = ? WHERE id = ?${scope}`).run(now, id, ...extra);
      }
    },

    listSessionsByVm(vmId: string): SessionDto[] {
      return db
        .prepare(
          `SELECT id, vm_id as vmId, cwd, title, created_at as createdAt, last_message_at as lastMessageAt, status, account_id as accountId
           FROM sessions WHERE vm_id = ? ORDER BY last_message_at DESC`,
        )
        .all(vmId) as never;
    },

    insertMessage(m: { sessionId: string; vmId: string; message: unknown }): MessageDto {
      const createdAt = new Date().toISOString();
      const result = db
        .prepare('INSERT INTO messages (session_id, vm_id, payload, created_at) VALUES (?, ?, ?, ?)')
        .run(m.sessionId, m.vmId, JSON.stringify(redactSecrets(m.message)), createdAt);
      return {
        id: Number(result.lastInsertRowid),
        sessionId: m.sessionId,
        vmId: m.vmId,
        message: m.message,
        createdAt,
      };
    },

    rekeySession(oldId: string, newId: string, vmId: string): void {
      db.prepare('UPDATE messages SET session_id = ? WHERE session_id = ? AND vm_id = ?').run(newId, oldId, vmId);
    },

    // Most recent `limit` messages, oldest first. Scoped to the VM so a session id from another VM yields nothing.
    listMessages(sessionId: string, vmId: string, limit = DEFAULT_MESSAGE_LIMIT): MessageDto[] {
      const rows = db
        .prepare(
          `SELECT id, session_id as sessionId, vm_id as vmId, payload, created_at as createdAt FROM (
             SELECT * FROM messages WHERE session_id = ? AND vm_id = ? ORDER BY id DESC LIMIT ?
           ) ORDER BY id ASC`,
        )
        .all(sessionId, vmId, limit) as { id: number; sessionId: string; vmId: string; payload: string; createdAt: string }[];
      return rows.map((r) => ({ id: r.id, sessionId: r.sessionId, vmId: r.vmId, createdAt: r.createdAt, message: JSON.parse(r.payload) }));
    },

    createAuthToken(): string {
      const token = randomUUID() + randomUUID();
      db.prepare('INSERT INTO auth_tokens (token, created_at) VALUES (?, ?)').run(sessionDigest(token), new Date().toISOString());
      return token;
    },

    // The hub is single-tenant: the first Escanor user to sign in owns it, and only they
    // (or emails in allowedEmails) may sign in afterwards. Returns null when refused.
    upsertHubUser(user: { id: string; email: string; name: string | null }, allowedEmails: string[]): { hubId: string } | null {
      const existing = db.prepare('SELECT hub_id FROM hub_users WHERE escanor_user_id = ?').get(user.id) as { hub_id: string } | undefined;
      if (existing) return { hubId: existing.hub_id };
      const count = (db.prepare('SELECT COUNT(*) AS n FROM hub_users').get() as { n: number }).n;
      if (count > 0 && !allowedEmails.includes(user.email.toLowerCase())) return null;
      const hubId = `hub_${randomUUID()}`;
      db.prepare('INSERT INTO hub_users (escanor_user_id, hub_id, email, name, created_at) VALUES (?, ?, ?, ?, ?)').run(
        user.id, hubId, user.email, user.name, new Date().toISOString(),
      );
      return { hubId };
    },

    setMcpServer(name: string, url: string, token: string): void {
      db.prepare(
        'INSERT INTO mcp_servers (name, url, token, updated_at) VALUES (?, ?, ?, ?) ON CONFLICT(name) DO UPDATE SET url = excluded.url, token = excluded.token, updated_at = excluded.updated_at',
      ).run(name, url, key ? seal(key, token) : token, new Date().toISOString());
    },

    removeMcpServer(name: string): void {
      db.prepare('DELETE FROM mcp_servers WHERE name = ?').run(name);
    },

    listMcpServers(): { name: string; url: string; token: string }[] {
      const rows = db.prepare('SELECT name, url, token FROM mcp_servers ORDER BY name').all() as { name: string; url: string; token: string }[];
      const out: { name: string; url: string; token: string }[] = [];
      for (const r of rows) {
        if (!isSealed(r.token)) {
          out.push(r);
          continue;
        }
        try {
          if (!key) throw new Error('no encryption key configured');
          out.push({ ...r, token: unseal(key, r.token) });
        } catch (err) {
          // e.g. HUB_ENCRYPTION_KEY / HUB_AGENT_TOKEN was rotated: skip rather than break every send. Re-save the MCP server.
          console.error(`[db] cannot decrypt MCP server "${r.name}" (${err instanceof Error ? err.message : err}); skipping it`);
        }
      }
      return out;
    },

    isValidToken(token: string): boolean {
      if (!token || token.length > 512) return false;
      const row = db.prepare('SELECT created_at FROM auth_tokens WHERE token = ?').get(sessionDigest(token)) as { created_at: string } | undefined;
      const age = row ? Date.now() - Date.parse(row.created_at) : NaN;
      return Number.isFinite(age) && age >= 0 && age < SESSION_MAX_AGE_MS;
    },

    revokeAuthToken(token: string): void {
      db.prepare('DELETE FROM auth_tokens WHERE token = ?').run(sessionDigest(token));
    },
  };
}

export type Db = ReturnType<typeof openDb>;
