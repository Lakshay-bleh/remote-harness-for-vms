var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

// src/hub.ts
import { DurableObject } from "cloudflare:workers";
import { searchSessions } from "./session-search.js";

// src/protocol.ts
var MIN_MCP_AGENT_VERSION = "0.3.0";
function agentSupportsMcp(version) {
  if (!version) return false;
  const parse = /* @__PURE__ */ __name((v) => v.split(".").map((n) => parseInt(n, 10) || 0), "parse");
  const have = parse(version);
  const need = parse(MIN_MCP_AGENT_VERSION);
  for (let i = 0; i < Math.max(have.length, need.length); i++) {
    const d = (have[i] ?? 0) - (need[i] ?? 0);
    if (d !== 0) return d > 0;
  }
  return true;
}
__name(agentSupportsMcp, "agentSupportsMcp");
var MCP_SERVER_NAME_RE = /^[a-z0-9][a-z0-9_-]{0,31}$/;
var HEADER_NAME_RE = /^[A-Za-z0-9!#$%&'*+.^_`|~-]{1,64}$/;
var MAX_HEADERS = 16;
var MAX_HEADER_VALUE = 4096;
function parseMcpServerInput(name, body) {
  if (!MCP_SERVER_NAME_RE.test(name)) {
    return { ok: false, error: 'Server name must be 1-32 chars of a-z, 0-9, "_" or "-", starting with a letter or digit' };
  }
  const b = body && typeof body === "object" ? body : {};
  if (typeof b.url !== "string") return { ok: false, error: "url is required" };
  let url;
  try {
    url = new URL(b.url.trim());
  } catch {
    return { ok: false, error: "url is not a valid URL" };
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") return { ok: false, error: "url must be http(s)" };
  if (url.username || url.password) return { ok: false, error: "url must not embed credentials; use headers" };
  let headers;
  if (b.headers !== void 0 && b.headers !== null) {
    if (typeof b.headers !== "object" || Array.isArray(b.headers)) return { ok: false, error: "headers must be an object" };
    const entries = Object.entries(b.headers);
    if (entries.length > MAX_HEADERS) return { ok: false, error: `at most ${MAX_HEADERS} headers` };
    headers = {};
    for (const [k, v] of entries) {
      if (!HEADER_NAME_RE.test(k)) return { ok: false, error: `invalid header name "${k}"` };
      if (typeof v !== "string" || v.length > MAX_HEADER_VALUE || /[\r\n]/.test(v)) {
        return { ok: false, error: `invalid value for header "${k}"` };
      }
      headers[k] = v;
    }
  }
  return {
    ok: true,
    server: {
      name,
      url: url.toString(),
      headers,
      autoAllow: b.autoAllow === void 0 ? true : Boolean(b.autoAllow),
      autoAllowReads: b.autoAllowReads === void 0 ? false : Boolean(b.autoAllowReads),
      alwaysLoad: b.alwaysLoad === void 0 ? true : Boolean(b.alwaysLoad),
      managedBy: typeof b.managedBy === "string" ? b.managedBy.slice(0, 32) : void 0
    }
  };
}
__name(parseMcpServerInput, "parseMcpServerInput");
function toMcpServerDto(s) {
  const { headers, ...rest } = s;
  return { ...rest, headerNames: Object.keys(headers ?? {}) };
}
__name(toMcpServerDto, "toMcpServerDto");

// src/tokens.ts
var PREFIX = { agent: "esa", app: "esb" };
var KIND_OF_PREFIX = { esa: "agent", esb: "app" };
var TENANT_RE = /^[A-Za-z0-9-]{1,64}$/;
var MAX_GEN = 1e9;
var encoder = new TextEncoder();
async function hmacKey(secret) {
  return crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}
__name(hmacKey, "hmacKey");
function b64url(bytes) {
  let s = "";
  for (const b of new Uint8Array(bytes)) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
__name(b64url, "b64url");
function fromB64url(s) {
  if (!/^[A-Za-z0-9_-]+$/.test(s)) return null;
  const padded = s.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - s.length % 4) % 4);
  try {
    return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
  } catch {
    return null;
  }
}
__name(fromB64url, "fromB64url");
var isValidTenantId = /* @__PURE__ */ __name((id) => TENANT_RE.test(id), "isValidTenantId");
async function mintToken(secret, kind, tenant, gen) {
  if (!isValidTenantId(tenant)) throw new Error("Invalid tenant id");
  if (!Number.isInteger(gen) || gen < 0 || gen > MAX_GEN) throw new Error("Invalid generation");
  const sig = await crypto.subtle.sign("HMAC", await hmacKey(secret), encoder.encode(`${PREFIX[kind]}.${tenant}.${gen}`));
  return `${PREFIX[kind]}.${tenant}.${gen}.${b64url(sig)}`;
}
__name(mintToken, "mintToken");
async function verifyToken(secret, token) {
  if (!secret || token.length > 200) return null;
  const parts = token.split(".");
  if (parts.length !== 4) return null;
  const [prefix, tenant, genText, sig] = parts;
  const kind = KIND_OF_PREFIX[prefix];
  if (!kind || !isValidTenantId(tenant) || !/^\d{1,10}$/.test(genText)) return null;
  const gen = Number(genText);
  if (gen > MAX_GEN) return null;
  const given = fromB64url(sig);
  if (!given) return null;
  const ok = await crypto.subtle.verify("HMAC", await hmacKey(secret), given, encoder.encode(`${prefix}.${tenant}.${gen}`));
  return ok ? { kind, tenant, gen } : null;
}
__name(verifyToken, "verifyToken");
function bearer(header) {
  return header?.startsWith("Bearer ") ? header.slice(7).trim() : "";
}
__name(bearer, "bearer");

// src/hub.ts
var PROJECTS_REQUEST_TIMEOUT_MS = 5e3;
var CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS"
};
function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...CORS } });
}
__name(json, "json");
function contentBlocks(text, images) {
  const blocks = [];
  if (text) blocks.push({ type: "text", text });
  for (const img of images ?? []) {
    blocks.push({ type: "image", source: { type: "base64", media_type: img.mediaType, data: img.dataBase64 } });
  }
  return blocks;
}
__name(contentBlocks, "contentBlocks");
var Hub = class extends DurableObject {
  static {
    __name(this, "Hub");
  }
  sql;
  pendingProjects = /* @__PURE__ */ new Map();
  constructor(ctx, env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.migrate();
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
  }
  // ---------- database ----------
  migrate() {
    this.sql.exec(`
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
      CREATE TABLE IF NOT EXISTS mcp_servers (
        name TEXT PRIMARY KEY,
        config_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS tenant_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
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
  }
  now = /* @__PURE__ */ __name(() => (/* @__PURE__ */ new Date()).toISOString(), "now");
  upsertVm(name) {
    const existing = this.sql.exec("SELECT id FROM vms WHERE name = ?", name).toArray()[0];
    const id = existing?.id ?? crypto.randomUUID();
    this.sql.exec(
      `INSERT INTO vms (id, name, last_seen_at) VALUES (?, ?, ?)
       ON CONFLICT(name) DO UPDATE SET last_seen_at = excluded.last_seen_at`,
      id,
      name,
      this.now()
    );
    return id;
  }
  touchVmSeen(id) {
    this.sql.exec("UPDATE vms SET last_seen_at = ? WHERE id = ?", this.now(), id);
  }
  setVmAccounts(id, accounts) {
    this.sql.exec("UPDATE vms SET accounts_json = ? WHERE id = ?", JSON.stringify(accounts), id);
  }
  getVmAccounts(id) {
    const row = this.sql.exec("SELECT accounts_json FROM vms WHERE id = ?", id).toArray()[0];
    return row ? JSON.parse(row.accounts_json) : [];
  }
  upsertSession(s) {
    const now = this.now();
    this.sql.exec(
      `INSERT INTO sessions (id, vm_id, cwd, title, created_at, last_message_at, status, account_id)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET status = excluded.status, last_message_at = excluded.last_message_at`,
      s.id,
      s.vmId,
      s.cwd,
      s.title,
      now,
      now,
      s.status,
      s.accountId
    );
  }
  touchSession(id, status) {
    if (status) this.sql.exec("UPDATE sessions SET last_message_at = ?, status = ? WHERE id = ?", this.now(), status, id);
    else this.sql.exec("UPDATE sessions SET last_message_at = ? WHERE id = ?", this.now(), id);
  }
  insertMessage(m) {
    this.sql.exec(
      "INSERT INTO messages (session_id, vm_id, payload, created_at) VALUES (?, ?, ?, ?)",
      m.sessionId,
      m.vmId,
      JSON.stringify(m.message),
      this.now()
    );
  }
  listMessages(sessionId) {
    const rows = this.sql.exec("SELECT id, session_id, vm_id, payload, created_at FROM messages WHERE session_id = ? ORDER BY id ASC", sessionId).toArray();
    return rows.map((r) => ({
      id: r.id,
      sessionId: r.session_id,
      vmId: r.vm_id,
      createdAt: r.created_at,
      message: JSON.parse(r.payload)
    }));
  }
  listMcpServers() {
    const rows = this.sql.exec("SELECT config_json FROM mcp_servers ORDER BY name").toArray();
    return rows.map((r) => JSON.parse(r.config_json));
  }
  putMcpServer(server) {
    const stored = { ...server, updatedAt: this.now() };
    this.sql.exec(
      `INSERT INTO mcp_servers (name, config_json, updated_at) VALUES (?, ?, ?)
       ON CONFLICT(name) DO UPDATE SET config_json = excluded.config_json, updated_at = excluded.updated_at`,
      stored.name,
      JSON.stringify(stored),
      stored.updatedAt
    );
    return stored;
  }
  deleteMcpServer(name) {
    const exists = this.sql.exec("SELECT 1 FROM mcp_servers WHERE name = ?", name).toArray().length > 0;
    if (exists) this.sql.exec("DELETE FROM mcp_servers WHERE name = ?", name);
    return exists;
  }
  setVmMcpStatus(vmId, status) {
    this.sql.exec(
      `INSERT INTO vm_mcp_status (vm_id, status_json, reported_at) VALUES (?, ?, ?)
       ON CONFLICT(vm_id) DO UPDATE SET status_json = excluded.status_json, reported_at = excluded.reported_at`,
      vmId,
      JSON.stringify(status),
      this.now()
    );
  }
  getVmMcpStatus(vmId) {
    const row = this.sql.exec("SELECT status_json, reported_at FROM vm_mcp_status WHERE vm_id = ?", vmId).toArray()[0];
    return row ? { ...JSON.parse(row.status_json), reportedAt: row.reported_at } : null;
  }
  // Push the complete set to every connected agent; a VM that is offline converges on its next hello.
  pushMcpServers() {
    const servers = this.listMcpServers();
    for (const { att } of this.agentSockets()) {
      if (att.vmId) this.sendToVm(att.vmId, { type: "set_mcp_servers", servers });
    }
  }
  getVmAgentVersion(vmId) {
    const row = this.sql.exec("SELECT version FROM vm_agent_version WHERE vm_id = ?", vmId).toArray()[0];
    return row?.version ?? null;
  }
  // ---------- sockets ----------
  agentSockets() {
    return this.ctx.getWebSockets("agent").map((ws) => ({ ws, att: ws.deserializeAttachment() ?? {} }));
  }
  agentFor(vmId) {
    return this.agentSockets().find((a) => a.att.vmId === vmId)?.ws;
  }
  sendToVm(vmId, msg) {
    const ws = this.agentFor(vmId);
    if (!ws) return false;
    try {
      ws.send(JSON.stringify(msg));
      return true;
    } catch {
      return false;
    }
  }
  broadcast(msg) {
    const payload = JSON.stringify(msg);
    for (const ws of this.ctx.getWebSockets("browser")) {
      try {
        ws.send(payload);
      } catch {
      }
    }
  }
  requestProjects(vmId) {
    const ws = this.agentFor(vmId);
    if (!ws) return Promise.resolve([]);
    const requestId = crypto.randomUUID();
    ws.send(JSON.stringify({ type: "list_projects", requestId }));
    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        this.pendingProjects.delete(requestId);
        resolve([]);
      }, PROJECTS_REQUEST_TIMEOUT_MS);
      this.pendingProjects.set(requestId, (projects) => {
        clearTimeout(timer);
        resolve(projects);
      });
    });
  }
  // ---------- HTTP / upgrade entry ----------
  // The Worker in front of this object has already verified the caller's signed token and says what it
  // proved in x-hub-role / x-hub-gen. This object is only reachable through that Worker, so those
  // headers are trusted; what only this object knows is whether the token has since been revoked.
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname.startsWith("/_admin/")) return this.handleAdmin(request, url);
    const role = request.headers.get("x-hub-role");
    const gen = Number(request.headers.get("x-hub-gen"));
    if (role !== "agent" && role !== "app" || !Number.isInteger(gen) || gen < this.minGen(role)) {
      return new Response("Unauthorized", { status: 401 });
    }
    if (url.pathname === "/agent") {
      if (role !== "agent") return new Response("Unauthorized", { status: 401 });
      return this.acceptSocket("agent", gen);
    }
    if (url.pathname === "/ws") {
      if (role !== "app") return new Response("Unauthorized", { status: 401 });
      return this.acceptSocket("browser", gen);
    }
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
    if (role !== "app") return json({ error: "Unauthorized" }, 401);
    return this.handleApi(request, url);
  }
  acceptSocket(tag, gen) {
    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1], [tag, `gen:${gen}`]);
    return new Response(null, { status: 101, webSocket: pair[0] });
  }
  // ---------- revocation ----------
  minGen(role) {
    const row = this.sql.exec("SELECT value FROM tenant_meta WHERE key = ?", `min_${role}_gen`).toArray()[0];
    return row ? Number(row.value) : 0;
  }
  setMinGen(role, gen) {
    if (gen <= this.minGen(role)) return;
    this.sql.exec(
      `INSERT INTO tenant_meta (key, value) VALUES (?, ?)
       ON CONFLICT(key) DO UPDATE SET value = excluded.value`,
      `min_${role}_gen`,
      String(gen)
    );
    const tag = role === "agent" ? "agent" : "browser";
    for (const ws of this.ctx.getWebSockets(tag)) {
      const socketGen = Number(this.ctx.getTags(ws).find((t) => t.startsWith("gen:"))?.slice(4) ?? 0);
      if (socketGen < gen) ws.close(1008, "token revoked");
    }
  }
  /** The generation of the token currently issued for a role: 1 until it has been rotated. */
  currentGen(role) {
    return Math.max(1, this.minGen(role));
  }
  async handleAdmin(request, url) {
    if (request.headers.get("x-hub-admin") !== "1") return new Response("Not found", { status: 404 });
    if (request.method === "GET" && url.pathname === "/_admin/gens") {
      return json({ agent: this.currentGen("agent"), app: this.currentGen("app") });
    }
    if (request.method === "POST" && url.pathname === "/_admin/rotate") {
      const body = await request.json().catch(() => ({}));
      if (body.role !== "agent" && body.role !== "app") return json({ error: "role must be agent or app" }, 400);
      const next = this.currentGen(body.role) + 1;
      this.setMinGen(body.role, next);
      return json({ gen: next });
    }
    if (request.method === "GET" && url.pathname === "/_admin/status") {
      const vms = this.sql.exec("SELECT id FROM vms").toArray();
      return json({
        vms: vms.length,
        connectedVms: new Set(this.agentSockets().map((a) => a.att.vmId).filter(Boolean)).size,
        browsers: this.ctx.getWebSockets("browser").length
      });
    }
    if (request.method === "DELETE" && url.pathname === "/_admin/data") {
      for (const ws of this.ctx.getWebSockets()) ws.close(1008, "tenant removed");
      await this.ctx.storage.deleteAll();
      this.migrate();
      this.setMinGen("agent", MAX_GEN + 1);
      this.setMinGen("app", MAX_GEN + 1);
      return json({ ok: true });
    }
    return new Response("Not found", { status: 404 });
  }
  // ---------- agent -> hub ----------
  async webSocketMessage(ws, data) {
    if (!this.ctx.getTags(ws).includes("agent")) return;
    let msg;
    try {
      msg = JSON.parse(typeof data === "string" ? data : new TextDecoder().decode(data));
    } catch {
      return;
    }
    const att = ws.deserializeAttachment() ?? {};
    if (msg.type === "hello") {
      const vmId2 = this.upsertVm(msg.vmName);
      for (const other of this.agentSockets()) {
        if (other.ws !== ws && other.att.vmId === vmId2) other.ws.close(1e3, "replaced by newer connection");
      }
      ws.serializeAttachment({ vmId: vmId2, vmName: msg.vmName });
      this.setVmAccounts(vmId2, msg.accounts);
      this.sql.exec(
        `INSERT INTO vm_agent_version (vm_id, version) VALUES (?, ?)
         ON CONFLICT(vm_id) DO UPDATE SET version = excluded.version`,
        vmId2,
        String(msg.agentVersion ?? "")
      );
      for (const s of msg.sessions) {
        this.upsertSession({ id: s.sessionId, vmId: vmId2, cwd: s.cwd, title: s.title, status: s.status, accountId: s.accountId });
      }
      this.touchVmSeen(vmId2);
      this.broadcast({ type: "vm_status", vmId: vmId2, name: msg.vmName, connected: true, accounts: this.getVmAccounts(vmId2) });
      this.sendToVm(vmId2, { type: "set_mcp_servers", servers: this.listMcpServers() });
      return;
    }
    const vmId = att.vmId;
    if (!vmId) return;
    if (msg.type === "projects_list") {
      const resolve = this.pendingProjects.get(msg.requestId);
      if (resolve) {
        this.pendingProjects.delete(msg.requestId);
        resolve(msg.projects);
      }
      return;
    }
    const now = this.now();
    switch (msg.type) {
      case "mcp_status":
        this.setVmMcpStatus(vmId, { servers: msg.servers, liveSessions: msg.liveSessions });
        break;
      case "sdk_message":
        this.insertMessage({ sessionId: msg.sessionId, vmId, message: msg.message });
        this.touchSession(msg.sessionId, "active");
        this.broadcast({ type: "sdk_message", vmId, sessionId: msg.sessionId, tempId: msg.tempId, message: msg.message, createdAt: now });
        break;
      case "session_created":
        this.sql.exec("UPDATE messages SET session_id = ? WHERE session_id = ?", msg.sessionId, msg.tempId);
        this.upsertSession({ id: msg.sessionId, vmId, cwd: msg.cwd, title: msg.title, status: "active", accountId: msg.accountId });
        this.broadcast({
          type: "session_created",
          vmId,
          tempId: msg.tempId,
          sessionId: msg.sessionId,
          cwd: msg.cwd,
          title: msg.title,
          accountId: msg.accountId
        });
        break;
      case "session_ended":
        this.touchSession(msg.sessionId, "idle");
        this.broadcast({ type: "session_ended", vmId, sessionId: msg.sessionId });
        break;
      case "permission_request":
        this.insertMessage({
          sessionId: msg.sessionId,
          vmId,
          message: {
            type: "permission_request",
            requestId: msg.requestId,
            toolName: msg.toolName,
            input: msg.input,
            blockedPath: msg.blockedPath
          }
        });
        this.broadcast({
          type: "permission_request",
          vmId,
          sessionId: msg.sessionId,
          requestId: msg.requestId,
          toolName: msg.toolName,
          input: msg.input,
          blockedPath: msg.blockedPath
        });
        break;
      case "error": {
        const sessionId = msg.sessionId ?? msg.tempId ?? "unknown";
        console.error(`[agent ${vmId}]`, msg.message);
        this.insertMessage({ sessionId, vmId, message: { type: "error", message: msg.message } });
        this.broadcast({
          type: "sdk_message",
          vmId,
          sessionId,
          tempId: msg.tempId,
          message: { type: "error", message: msg.message },
          createdAt: now
        });
        break;
      }
    }
  }
  async webSocketClose(ws, code, reason) {
    await this.onSocketGone(ws);
    try {
      ws.close(code, reason);
    } catch {
    }
  }
  async webSocketError(ws) {
    await this.onSocketGone(ws);
  }
  async onSocketGone(ws) {
    if (!this.ctx.getTags(ws).includes("agent")) return;
    const att = ws.deserializeAttachment() ?? {};
    if (!att.vmId || !att.vmName) return;
    const stillConnected = this.agentSockets().some((a) => a.ws !== ws && a.att.vmId === att.vmId);
    if (stillConnected) return;
    this.touchVmSeen(att.vmId);
    this.broadcast({ type: "vm_status", vmId: att.vmId, name: att.vmName, connected: false, accounts: this.getVmAccounts(att.vmId) });
  }
  // ---------- REST API ----------
  async handleApi(request, url) {
    const path = url.pathname.replace(/^\/api/, "");
    const method = request.method;
    const body = method === "POST" || method === "PUT" ? await request.json().catch(() => ({})) : {};
    if (method === "GET" && path === "/mcp-servers") {
      const overview = {
        servers: this.listMcpServers().map(toMcpServerDto),
        vms: this.sql.exec("SELECT id, name FROM vms ORDER BY name").toArray().map((v) => {
          const status = this.getVmMcpStatus(v.id);
          return {
            vmId: v.id,
            name: v.name,
            connected: Boolean(this.agentFor(v.id)),
            agentVersion: this.getVmAgentVersion(v.id),
            mcpSupported: agentSupportsMcp(this.getVmAgentVersion(v.id)),
            reportedAt: status?.reportedAt ?? null,
            servers: status?.servers ?? [],
            liveSessions: status?.liveSessions ?? 0
          };
        })
      };
      return json(overview);
    }
    let mcp;
    if (mcp = path.match(/^\/mcp-servers\/([^/]+)$/)) {
      const name = decodeURIComponent(mcp[1]);
      if (method === "PUT") {
        const parsed = parseMcpServerInput(name, body);
        if (!parsed.ok) return json({ error: parsed.error }, 400);
        const server = this.putMcpServer(parsed.server);
        this.pushMcpServers();
        const vmsTotal = this.sql.exec("SELECT COUNT(*) AS n FROM vms").toArray()[0].n;
        const result = { server: toMcpServerDto(server), vmsConnected: new Set(this.agentSockets().map((a) => a.att.vmId).filter(Boolean)).size, vmsTotal };
        return json(result);
      }
      if (method === "DELETE") {
        const removed = this.deleteMcpServer(name);
        if (removed) this.pushMcpServers();
        return json({ ok: removed }, removed ? 200 : 404);
      }
    }
    if (method === "GET" && path === "/vms") {
      const rows = this.sql.exec("SELECT id, name, last_seen_at, accounts_json FROM vms ORDER BY name").toArray();
      return json(
        rows.map((r) => ({
          id: r.id,
          name: r.name,
          lastSeenAt: r.last_seen_at,
          accounts: JSON.parse(r.accounts_json),
          connected: Boolean(this.agentFor(r.id))
        }))
      );
    }
    let m;
    if (method === "GET" && (m = path.match(/^\/vms\/([^/]+)\/sessions$/))) {
      const rows = this.sql.exec(
        `SELECT id, vm_id, cwd, title, created_at, last_message_at, status, account_id
           FROM sessions WHERE vm_id = ? ORDER BY last_message_at DESC`,
        m[1]
      ).toArray();
      const sessions = rows.map((r) => ({
        id: r.id,
        vmId: r.vm_id,
        cwd: r.cwd,
        title: r.title,
        createdAt: r.created_at,
        lastMessageAt: r.last_message_at,
        status: r.status,
        accountId: r.account_id
      }));
      return json(sessions);
    }
    if (method === "GET" && (m = path.match(/^\/vms\/([^/]+)\/projects$/))) {
      return json(await this.requestProjects(m[1]));
    }
    if (method === "GET" && (m = path.match(/^\/vms\/([^/]+)\/sessions\/search$/))) {
      const exec = (query, ...params) => this.sql.exec(query, ...params).toArray();
      return json(searchSessions(exec, m[1], url.searchParams.get("q"), url.searchParams.get("limit")));
    }
    if (method === "GET" && (m = path.match(/^\/vms\/([^/]+)\/sessions\/([^/]+)\/messages$/))) {
      return json(this.listMessages(m[2]));
    }
    if (method === "POST" && (m = path.match(/^\/vms\/([^/]+)\/sessions$/))) {
      const vmId = m[1];
      const { cwd, text, images, accountId } = body;
      if (!text && !(images?.length > 0)) return json({ error: "text or images required" }, 400);
      const tempId = crypto.randomUUID();
      const localMessage = { type: "user", local: true, message: { role: "user", content: contentBlocks(text ?? "", images) } };
      this.insertMessage({ sessionId: tempId, vmId, message: localMessage });
      this.broadcast({ type: "sdk_message", vmId, sessionId: tempId, message: localMessage, createdAt: this.now() });
      const delivered = this.sendToVm(vmId, { type: "user_input", sessionId: tempId, tempId, cwd, accountId, text: text ?? "", images });
      if (!delivered) return json({ error: "VM not connected" }, 503);
      return json({ tempId }, 202);
    }
    if ((m = path.match(/^\/vms\/([^/]+)\/sessions\/([^/]+)\/([a-z-]+)$/)) && method === "POST") {
      const [, vmId, sessionId, action] = m;
      const b = body;
      switch (action) {
        case "messages": {
          if (!b.text && !(b.images?.length > 0)) return json({ error: "text or images required" }, 400);
          const localMessage = { type: "user", local: true, message: { role: "user", content: contentBlocks(b.text ?? "", b.images) } };
          this.insertMessage({ sessionId, vmId, message: localMessage });
          this.touchSession(sessionId, "active");
          this.broadcast({ type: "sdk_message", vmId, sessionId, message: localMessage, createdAt: this.now() });
          const delivered = this.sendToVm(vmId, { type: "user_input", sessionId, text: b.text ?? "", images: b.images });
          return delivered ? json({ ok: true }, 202) : json({ error: "VM not connected" }, 503);
        }
        case "interrupt":
          return this.deliver(this.sendToVm(vmId, { type: "interrupt", sessionId }));
        case "model":
          return this.deliver(this.sendToVm(vmId, { type: "set_model", sessionId, model: b.model || void 0 }));
        case "effort":
          return this.deliver(this.sendToVm(vmId, { type: "set_effort", sessionId, effort: b.effort || null }));
        case "permission-mode":
          return this.deliver(this.sendToVm(vmId, { type: "set_permission_mode", sessionId, mode: b.mode }));
        case "permission-response": {
          const delivered = this.sendToVm(vmId, {
            type: "permission_response",
            requestId: b.requestId,
            behavior: b.behavior,
            message: b.message
          });
          this.broadcast({ type: "permission_resolved", vmId, sessionId, requestId: b.requestId });
          return this.deliver(delivered);
        }
      }
    }
    return json({ error: "Not found" }, 404);
  }
  deliver(delivered) {
    return json({ ok: delivered }, delivered ? 202 : 503);
  }
};

// src/index.ts
var CORS2 = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS"
};
var json2 = /* @__PURE__ */ __name((body, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...CORS2 } }), "json");
var unauthorized = /* @__PURE__ */ __name(() => new Response("Unauthorized", { status: 401, headers: CORS2 }), "unauthorized");
var tenantStub = /* @__PURE__ */ __name((env, tenant) => env.HUB.get(env.HUB.idFromName(`t:${tenant}`)), "tenantStub");
async function routeToTenant(request, env, kind, token) {
  const verified = await verifyToken(env.HUB_SIGNING_SECRET, token);
  if (!verified || verified.kind !== kind) return unauthorized();
  const headers = new Headers(request.headers);
  for (const name of [...headers.keys()]) if (name.startsWith("x-hub-")) headers.delete(name);
  headers.set("x-hub-role", kind);
  headers.set("x-hub-gen", String(verified.gen));
  return tenantStub(env, verified.tenant).fetch(new Request(request, { headers }));
}
__name(routeToTenant, "routeToTenant");
async function isAdmin(request, env) {
  const given = bearer(request.headers.get("authorization"));
  if (!env.HUB_ADMIN_TOKEN || !given) return false;
  const digest = /* @__PURE__ */ __name(async (s) => crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)), "digest");
  const [a, b] = await Promise.all([digest(given), digest(env.HUB_ADMIN_TOKEN)]);
  const [x, y] = [new Uint8Array(a), new Uint8Array(b)];
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}
__name(isAdmin, "isAdmin");
async function handleAdmin(request, env, path) {
  if (!await isAdmin(request, env)) return unauthorized();
  if (path === "/admin/tenants" && request.method === "POST") {
    const body = await request.json().catch(() => ({}));
    const id2 = crypto.randomUUID();
    return json2({ id: id2, label: String(body.label ?? "").trim().slice(0, 100) || "tenant", createdAt: (/* @__PURE__ */ new Date()).toISOString(), ...await credentials(env, id2, 1, 1) }, 201);
  }
  const m = path.match(/^\/admin\/tenants\/([^/]+)(?:\/([a-z-]+))?$/);
  if (!m || !isValidTenantId(m[1])) return json2({ error: "Not found" }, 404);
  const [, id, action] = m;
  const stub = tenantStub(env, id);
  const internal = /* @__PURE__ */ __name((p, init = {}) => stub.fetch(`https://hub.internal${p}`, { ...init, headers: { "x-hub-admin": "1", "content-type": "application/json" } }), "internal");
  const gens = /* @__PURE__ */ __name(async () => await (await internal("/_admin/gens")).json(), "gens");
  const rotate = /* @__PURE__ */ __name(async (role) => (await (await internal("/_admin/rotate", { method: "POST", body: JSON.stringify({ role }) })).json()).gen, "rotate");
  if (!action && request.method === "GET") return internal("/_admin/status");
  if (!action && request.method === "DELETE") return internal("/_admin/data", { method: "DELETE" });
  const deleted = action && ["credentials", "rotate-agent-token", "rotate-app-token"].includes(action) && (await gens()).agent > MAX_GEN;
  if (deleted) return json2({ error: "Tenant was deleted" }, 410);
  if (action === "credentials" && request.method === "GET") {
    const g = await gens();
    return json2(await credentials(env, id, g.agent, g.app));
  }
  if (action === "rotate-agent-token" && request.method === "POST") {
    return json2({ agentToken: await mintToken(env.HUB_SIGNING_SECRET, "agent", id, await rotate("agent")) });
  }
  if (action === "rotate-app-token" && request.method === "POST") {
    return json2({ apiToken: await mintToken(env.HUB_SIGNING_SECRET, "app", id, await rotate("app")) });
  }
  return json2({ error: "Not found" }, 404);
}
__name(handleAdmin, "handleAdmin");
async function credentials(env, tenant, agentGen, appGen) {
  return {
    agentToken: await mintToken(env.HUB_SIGNING_SECRET, "agent", tenant, agentGen),
    apiToken: await mintToken(env.HUB_SIGNING_SECRET, "app", tenant, appGen)
  };
}
__name(credentials, "credentials");
var index_default = {
  async fetch(request, env) {
    const { pathname, searchParams } = new URL(request.url);
    if (pathname === "/" || pathname === "/healthz") return json2({ ok: true, service: "escanor-hub" });
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS2 });
    if (pathname === "/agent") return routeToTenant(request, env, "agent", bearer(request.headers.get("authorization")));
    if (pathname === "/ws") return routeToTenant(request, env, "app", searchParams.get("token") ?? "");
    if (pathname.startsWith("/api/")) return routeToTenant(request, env, "app", bearer(request.headers.get("authorization")));
    if (pathname.startsWith("/admin/")) return handleAdmin(request, env, pathname);
    return json2({ error: "Not found" }, 404);
  }
};
export {
  Hub,
  index_default as default
};
//# sourceMappingURL=index.js.map