import type { HubToBrowserMessage } from '@remote-harness/shared';
import { getToken } from './api';

type Handler = (msg: HubToBrowserMessage) => void;

const RECONNECT_DELAY_MS = 2000;

export class HubSocket {
  private ws: WebSocket | null = null;
  private handlers = new Set<Handler>();
  private stopped = false;

  connect(): void {
    if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) return;
    const token = getToken();
    if (!token) return;
    const proto = window.location.protocol === 'https:' ? 'wss' : 'ws';
    const ws = new WebSocket(`${proto}://${window.location.host}/ws?token=${encodeURIComponent(token)}`);
    this.ws = ws;

    ws.onmessage = (evt) => {
      try {
        const msg = JSON.parse(evt.data) as HubToBrowserMessage;
        for (const h of this.handlers) h(msg);
      } catch {
        // ignore malformed frames
      }
    };
    ws.onclose = () => {
      if (!this.stopped) setTimeout(() => this.connect(), RECONNECT_DELAY_MS);
    };
  }

  subscribe(handler: Handler): () => void {
    this.handlers.add(handler);
    return () => this.handlers.delete(handler);
  }

  stop(): void {
    this.stopped = true;
    this.ws?.close();
  }
}

export const hubSocket = new HubSocket();
