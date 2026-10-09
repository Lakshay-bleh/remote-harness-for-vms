import WebSocket from 'ws';
import type { AgentToHubMessage, HubToAgentMessage } from '@remote-harness/shared';

const DEFAULT_RECONNECT_DELAY_MS = 3000;
const DEFAULT_MAX_BUFFERED = 1000;
// Cloudflare closes WebSockets that are idle for ~100s, so keep traffic flowing.
const DEFAULT_PING_INTERVAL_MS = 25_000;
// After sleep or a network change the old TCP socket is half-open: writes just queue and 'close' never fires,
// so the agent would stay "connected" to nothing. No pong within this window means the socket is dead.
const DEFAULT_PONG_TIMEOUT_MS = 60_000;
const HANDSHAKE_TIMEOUT_MS = 15_000;

export class HubConnection {
  private ws: WebSocket | null = null;
  private closedByUser = false;
  private pingTimer: NodeJS.Timeout | null = null;
  private buffer: AgentToHubMessage[] = [];
  private reconnectDelayMs: number;
  private maxBuffered: number;
  private pingIntervalMs: number;
  private pongTimeoutMs: number;

  constructor(
    private url: string,
    private token: string,
    private onMessage: (msg: HubToAgentMessage) => void,
    private onOpen: () => void,
    opts: { reconnectDelayMs?: number; maxBuffered?: number; pingIntervalMs?: number; pongTimeoutMs?: number } = {},
  ) {
    this.reconnectDelayMs = opts.reconnectDelayMs ?? DEFAULT_RECONNECT_DELAY_MS;
    this.maxBuffered = opts.maxBuffered ?? DEFAULT_MAX_BUFFERED;
    this.pingIntervalMs = opts.pingIntervalMs ?? DEFAULT_PING_INTERVAL_MS;
    this.pongTimeoutMs = opts.pongTimeoutMs ?? DEFAULT_PONG_TIMEOUT_MS;
  }

  connect(): void {
    this.closedByUser = false;
    const ws = new WebSocket(this.url, {
      headers: { authorization: `Bearer ${this.token}` },
      handshakeTimeout: HANDSHAKE_TIMEOUT_MS,
    });
    this.ws = ws;
    let lastHeard = Date.now();
    const heard = () => { lastHeard = Date.now(); };
    ws.on('pong', heard);

    ws.on('open', () => {
      heard();
      this.pingTimer = setInterval(() => {
        if (ws.readyState !== WebSocket.OPEN) return;
        if (Date.now() - lastHeard > this.pongTimeoutMs) {
          console.error(`Hub connection silent for ${Math.round((Date.now() - lastHeard) / 1000)}s, reconnecting`);
          ws.terminate(); // emits 'close', which schedules the reconnect
          return;
        }
        ws.ping();
      }, this.pingIntervalMs);
      this.onOpen(); // sends the hello first, so the hub knows who we are before the replay
      this.flush();
    });
    ws.on('message', (data) => {
      heard();
      try {
        this.onMessage(JSON.parse(data.toString()) as HubToAgentMessage);
      } catch (err) {
        console.error('Failed to parse hub message', err);
      }
    });
    ws.on('close', () => {
      if (this.pingTimer) clearInterval(this.pingTimer);
      this.pingTimer = null;
      if (!this.closedByUser) setTimeout(() => this.connect(), this.reconnectDelayMs);
    });
    ws.on('error', (err) => console.error('Hub connection error', err.message));
  }

  // Messages produced while the hub is unreachable (a permission request, session_created, session_ended,
  // streamed output) are kept and replayed after reconnect instead of being dropped. The buffer is
  // bounded; when full it sheds streamed sdk_messages first because the critical events can't be re-derived.
  send(msg: AgentToHubMessage): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(msg));
      return;
    }
    if (this.buffer.length >= this.maxBuffered) {
      const i = this.buffer.findIndex((m) => m.type === 'sdk_message');
      this.buffer.splice(i === -1 ? 0 : i, 1);
    }
    this.buffer.push(msg);
  }

  private flush(): void {
    const pending = this.buffer;
    this.buffer = [];
    for (const m of pending) this.send(m);
  }

  bufferedForTest(): AgentToHubMessage[] {
    return [...this.buffer];
  }

  close(): void {
    this.closedByUser = true;
    this.ws?.close();
  }
}
