/** Starts the app's own logging once a person is signed in, as the workspace's preferences allow. Renders nothing. */

import { useEffect } from 'react';

import { escanor } from './client';
import { startTelemetry } from './telemetry';

export default function TelemetryBoot() {
  useEffect(() => {
    let stop: (() => void) | undefined;
    let cancelled = false;
    (async () => {
      try {
        const config = await escanor.telemetryConfig();
        if (cancelled) return;
        const t = startTelemetry({
          source: 'app',
          release: (import.meta as { env?: Record<string, string | undefined> }).env?.VITE_APP_VERSION,
          config,
          env: window as unknown as Parameters<typeof startTelemetry>[0]['env'],
          send: (_source, entries, opts) => escanor.sendLogs(entries, opts.keepalive).then(() => undefined),
        });
        stop = () => { void t.flush().finally(() => t.stop()); };
      } catch {
        /* the app works the same without it */
      }
    })();
    return () => { cancelled = true; stop?.(); };
  }, []);
  return null;
}
