import { randomUUID } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import type { AgentMcpStatus, ApiTokenDto, ClaudeAccount, ManagedMcpServer, MessageDto, SessionDto, VmDto } from '@remote-harness/shared';

export function openDb(dataDir: string) {
  mkdirSync(dataDir, { recursive: true });
  const db = new DatabaseSync(join(dataDir, 'hub.sqlite'));

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
    CREATE TABLE IF NOT EXISTS mcp_servers (
      name TEXT PRIMARY KEY,
      config_json TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS api_tokens (
      id TEXT PRIMARY KEY,
      token TEXT UNIQUE NOT NULL,
      label TEXT NOT NULL,
      created_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS vm_agent_version (
      vm_id TEXT PRIMARY KEY,
      version TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS vm_mcp_status (
      vm_id TEXT PRIMARY KEY,
      status_json TEXT NOT NULL,
      reported_at TEXT NOT NULL
    );
  `);

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
         ON CONFLICT(id) DO UPDATE SET status = excluded.status, last_message_at = excluded.last_message_at`,
      ).run(s.id, s.vmId, s.cwd, s.title, now, now, s.status, s.accountId);
    },

    touchSession(id: string, status?: string): void {
      if (status) {
        db.prepare('UPDATE sessions SET last_message_at = ?, status = ? WHERE id = ?').run(
          new Date().toISOString(),
          status,
          id,
        );
      } else {
        db.prepare('UPDATE sessions SET last_message_at = ? WHERE id = ?').run(new Date().toISOString(), id);
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
        .run(m.sessionId, m.vmId, JSON.stringify(m.message), createdAt);
      return {
        id: Number(result.lastInsertRowid),
        sessionId: m.sessionId,
        vmId: m.vmId,
        message: m.message,
        createdAt,
      };
    },

    rekeySession(oldId: string, newId: string): void {
      db.prepare('UPDATE messages SET session_id = ? WHERE session_id = ?').run(newId, oldId);
    },

    listMessages(sessionId: string): MessageDto[] {
      const rows = db
        .prepare(
          'SELECT id, session_id as sessionId, vm_id as vmId, payload, created_at as createdAt FROM messages WHERE session_id = ? ORDER BY id ASC',
        )
        .all(sessionId) as { id: number; sessionId: string; vmId: string; payload: string; createdAt: string }[];
      return rows.map((r) => ({ id: r.id, sessionId: r.sessionId, vmId: r.vmId, createdAt: r.createdAt, message: JSON.parse(r.payload) }));
    },

    listMcpServers(): ManagedMcpServer[] {
      const rows = db.prepare('SELECT config_json as configJson FROM mcp_servers ORDER BY name').all() as { configJson: string }[];
      return rows.map((r) => JSON.parse(r.configJson) as ManagedMcpServer);
    },

    putMcpServer(server: Omit<ManagedMcpServer, 'updatedAt'>): ManagedMcpServer {
      const stored: ManagedMcpServer = { ...server, updatedAt: new Date().toISOString() };
      db.prepare(
        `INSERT INTO mcp_servers (name, config_json, updated_at) VALUES (?, ?, ?)
         ON CONFLICT(name) DO UPDATE SET config_json = excluded.config_json, updated_at = excluded.updated_at`,
      ).run(stored.name, JSON.stringify(stored), stored.updatedAt);
      return stored;
    },

    deleteMcpServer(name: string): boolean {
      return Number(db.prepare('DELETE FROM mcp_servers WHERE name = ?').run(name).changes) > 0;
    },

    setVmMcpStatus(vmId: string, status: Pick<AgentMcpStatus, 'servers' | 'liveSessions'>): void {
      db.prepare(
        `INSERT INTO vm_mcp_status (vm_id, status_json, reported_at) VALUES (?, ?, ?)
         ON CONFLICT(vm_id) DO UPDATE SET status_json = excluded.status_json, reported_at = excluded.reported_at`,
      ).run(vmId, JSON.stringify(status), new Date().toISOString());
    },

    getVmMcpStatus(vmId: string): { servers: AgentMcpStatus['servers']; liveSessions: number; reportedAt: string } | null {
      const row = db.prepare('SELECT status_json as statusJson, reported_at as reportedAt FROM vm_mcp_status WHERE vm_id = ?').get(vmId) as
        | { statusJson: string; reportedAt: string }
        | undefined;
      if (!row) return null;
      return { ...JSON.parse(row.statusJson), reportedAt: row.reportedAt };
    },

    createAuthToken(): string {
      const token = randomUUID() + randomUUID();
      db.prepare('INSERT INTO auth_tokens (token, created_at) VALUES (?, ?)').run(token, new Date().toISOString());
      return token;
    },

    isValidToken(token: string): boolean {
      if (!token) return false;
      return (
        Boolean(db.prepare('SELECT 1 FROM auth_tokens WHERE token = ?').get(token)) ||
        Boolean(db.prepare('SELECT 1 FROM api_tokens WHERE token = ?').get(token))
      );
    },

    /** Sign out: the token stops working immediately, wherever it was copied to. */
    revokeToken(token: string): boolean {
      const a = Number(db.prepare('DELETE FROM auth_tokens WHERE token = ?').run(token).changes);
      const b = Number(db.prepare('DELETE FROM api_tokens WHERE token = ?').run(token).changes);
      return a + b > 0;
    },

    createApiToken(label: string): { id: string; token: string; label: string; createdAt: string } {
      const created = { id: randomUUID(), token: randomUUID() + randomUUID(), label, createdAt: new Date().toISOString() };
      db.prepare('INSERT INTO api_tokens (id, token, label, created_at) VALUES (?, ?, ?, ?)').run(
        created.id,
        created.token,
        created.label,
        created.createdAt,
      );
      return created;
    },

    listApiTokens(): ApiTokenDto[] {
      return db.prepare('SELECT id, label, created_at as createdAt FROM api_tokens ORDER BY created_at DESC').all() as never;
    },

    deleteApiToken(id: string): boolean {
      return Number(db.prepare('DELETE FROM api_tokens WHERE id = ?').run(id).changes) > 0;
    },

    setVmAgentVersion(vmId: string, version: string): void {
      db.prepare(
        `INSERT INTO vm_agent_version (vm_id, version) VALUES (?, ?)
         ON CONFLICT(vm_id) DO UPDATE SET version = excluded.version`,
      ).run(vmId, version);
    },

    getVmAgentVersion(vmId: string): string | null {
      const row = db.prepare('SELECT version FROM vm_agent_version WHERE vm_id = ?').get(vmId) as { version: string } | undefined;
      return row?.version ?? null;
    },
  };
}

export type Db = ReturnType<typeof openDb>;
