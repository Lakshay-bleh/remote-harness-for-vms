import WebSocket from 'ws';
import type { AgentToHubMessage, HubToAgentMessage } from '@remote-harness/shared';

const RECONNECT_DELAY_MS = 3000;
// Cloudflare closes WebSockets that are idle for ~100s, so keep traffic flowing.
const PING_INTERVAL_MS = 25_000;

export class HubConnection {
  private ws: WebSocket | null = null;
  private closedByUser = false;
  private pingTimer: NodeJS.Timeout | null = null;

  constructor(
    private url: string,
    private token: string,
    private onMessage: (msg: HubToAgentMessage) => void,
    private onOpen: () => void,
  ) {}

  connect(): void {
    this.closedByUser = false;
    const ws = new WebSocket(this.url, { headers: { authorization: `Bearer ${this.token}` } });
    this.ws = ws;

    ws.on('open', () => {
      this.pingTimer = setInterval(() => ws.readyState === WebSocket.OPEN && ws.ping(), PING_INTERVAL_MS);
      this.onOpen();
    });
    ws.on('message', (data) => {
      try {
        this.onMessage(JSON.parse(data.toString()) as HubToAgentMessage);
      } catch (err) {
        console.error('Failed to parse hub message', err);
      }
    });
    ws.on('close', () => {
      if (this.pingTimer) clearInterval(this.pingTimer);
      if (!this.closedByUser) setTimeout(() => this.connect(), RECONNECT_DELAY_MS);
    });
    ws.on('error', (err) => console.error('Hub connection error', err.message));
  }

  send(msg: AgentToHubMessage): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(msg));
    }
  }

  close(): void {
    this.closedByUser = true;
    this.ws?.close();
  }
}
