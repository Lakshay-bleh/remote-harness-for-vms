// What the hub tells Escanor's backend so the person's phone gets a push: Claude on a machine is waiting for their OK, or
// finished (or failed) what it was asked. Pure functions; the Durable Object sends them (see Hub.notify).

const oneLine = (s, max) => {
  const line = String(s ?? "").split("\n").map((l) => l.trim()).find(Boolean) ?? "";
  return line.length > max ? `${line.slice(0, max - 1)}…` : line;
};

const lastPart = (p) => String(p ?? "").split("/").filter(Boolean).pop() ?? "";

/** A few words for what Claude wants to do, e.g. "Run: npm test" or "Edit: app.ts". */
export function describeTool(toolName, input) {
  const i = input && typeof input === "object" ? input : {};
  switch (toolName) {
    case "Bash":
      return `Run: ${oneLine(i.command, 100)}`;
    case "Edit":
    case "MultiEdit":
    case "Write":
    case "NotebookEdit":
      return `Edit: ${lastPart(i.file_path ?? i.notebook_path) || "a file"}`;
    case "WebFetch":
      return `Open: ${oneLine(i.url, 100)}`;
    case "WebSearch":
      return `Search the web: ${oneLine(i.query, 80)}`;
    default: {
      const mcp = /^mcp__([^_]+(?:_[^_]+)*)__(.+)$/.exec(String(toolName ?? ""));
      if (mcp) return `Use ${mcp[2].replace(/_/g, " ")} (${mcp[1]})`;
      return `Use ${toolName}`;
    }
  }
}

/** The event for a permission prompt. */
export function approvalEvent({ vmId, vmName, sessionId, title, requestId, toolName, input }) {
  return { kind: "approval", vmId, vmName, sessionId, title: oneLine(title, 120), text: describeTool(toolName, input), requestId };
}

/** The event for the end of a turn (an SDK 'result' message), or null for anything else. */
export function resultEvent({ vmId, vmName, sessionId, title, message }) {
  if (!message || typeof message !== "object" || message.type !== "result") return null;
  const failed = message.is_error === true || (typeof message.subtype === "string" && message.subtype !== "success");
  const text = failed ? oneLine(message.result ?? (Array.isArray(message.errors) ? message.errors[0] : "") ?? message.subtype, 160) : oneLine(message.result, 160);
  return { kind: failed ? "failed" : "done", vmId, vmName, sessionId, title: oneLine(title, 120), text };
}

/** What identifies a stored agent message, so a copy resent after a dropped connection is skipped (as in the self-hosted hub). */
export function agentMessageUid(msg) {
  if (msg?.type === "permission_request" && msg.requestId) return `perm:${msg.requestId}`;
  const uuid = msg?.type === "sdk_message" ? msg.message?.uuid : undefined;
  return typeof uuid === "string" && uuid ? `sdk:${uuid}` : undefined;
}
