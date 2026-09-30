/**
 * The website's (and the app's) own logs, sent to the workspace's monitoring.
 *
 * What is captured is decided by the workspace's preferences (`GET /observability/client-config`): uncaught errors and
 * unhandled promise rejections, `console.error`/`console.warn`, failed or slow requests to the API, and (when switched on)
 * page performance. Entries are batched, bounded and de-duplicated in memory, and sent with the person's own session; nothing
 * is sent for what the workspace turned off. It never logs its own traffic, and never throws.
 *
 * Kept free of React so it can be tested in isolation: the environment (window, fetch, performance) is passed in.
 *
 * This is the same module as the website's (escanor/lib/telemetry.ts, which has the tests); the two repositories share no package,
 * so it is kept identical by hand.
 */

export interface ClientConfig {
  enabled: boolean;
  website: boolean;
  app: boolean;
  console_errors: boolean;
  network_errors: boolean;
  performance: boolean;
  sample_rate: number;
}

export interface ClientEntry {
  ts?: string;
  level: 'debug' | 'info' | 'warn' | 'error' | 'fatal';
  message: string;
  stack?: string;
  url?: string;
  release?: string;
  session?: string;
  status?: number;
  duration_ms?: number;
  resource?: string;
  method?: string;
  kind?: 'log' | 'event' | 'request';
  attrs?: Record<string, string | number | boolean>;
}

export interface TelemetryEnv {
  addEventListener(type: string, listener: (e: any) => void): void; // eslint-disable-line @typescript-eslint/no-explicit-any
  removeEventListener(type: string, listener: (e: any) => void): void; // eslint-disable-line @typescript-eslint/no-explicit-any
  location: { href: string };
  fetch?: typeof fetch;
  console?: Pick<Console, 'error' | 'warn'>;
  PerformanceObserver?: typeof PerformanceObserver;
  document?: { visibilityState?: string };
}

export interface TelemetryOptions {
  source: 'website' | 'app';
  release?: string;
  config: ClientConfig;
  send: (source: 'website' | 'app', entries: ClientEntry[], opts: { keepalive?: boolean }) => Promise<void>;
  env: TelemetryEnv;
  /** Requests whose URL contains one of these are never logged (the monitoring routes themselves, and anything noisy). */
  ignoreUrls?: string[];
  flushMs?: number;
  maxBatch?: number;
  slowMs?: number;
  now?: () => number;
  session?: string;
  random?: () => number;
}

const MAX_QUEUE = 200;
const MAX_MESSAGE = 1500;

const clip = (v: unknown, n: number): string => {
  const s = typeof v === 'string' ? v : v instanceof Error ? `${v.name}: ${v.message}` : (() => { try { return JSON.stringify(v); } catch { return String(v); } })();
  return (s ?? '').length > n ? `${(s ?? '').slice(0, n - 1)}…` : (s ?? '');
};

/** What a request to the API looked like, without its query string (which may hold tokens or ids). */
export function routeOf(url: string): string {
  try {
    const u = new URL(url, 'http://local');
    return u.pathname.replace(/\/[0-9a-f]{8}-[0-9a-f-]{27,}|\/\d{3,}|\/[0-9a-f]{24}/g, '/:id').slice(0, 160);
  } catch {
    return url.split('?')[0]!.slice(0, 160);
  }
}

export function startTelemetry(opts: TelemetryOptions): { stop(): void; flush(): Promise<void>; log(entry: ClientEntry): void; pending(): number } {
  const { env, config, source } = opts;
  const now = opts.now ?? (() => Date.now());
  const random = opts.random ?? Math.random;
  const slowMs = opts.slowMs ?? 3000;
  const maxBatch = opts.maxBatch ?? 20;
  const session = opts.session ?? Math.random().toString(36).slice(2, 12);
  const ignore = [...(opts.ignoreUrls ?? []), '/observability/'];
  const queue: ClientEntry[] = [];
  const recent = new Map<string, number>();
  const cleanups: Array<() => void> = [];
  let timer: ReturnType<typeof setInterval> | null = null;
  let stopped = false;

  const enabled = config.enabled && (source === 'website' ? config.website : config.app);
  if (!enabled) return { stop() {}, flush: async () => undefined, log() {}, pending: () => 0 };

  function push(entry: ClientEntry): void {
    if (stopped) return;
    // Sampling thins the routine; an error or a warning is never dropped.
    if ((entry.level === 'info' || entry.level === 'debug') && config.sample_rate < 1 && random() >= config.sample_rate) return;
    // The same message again within a minute is counted, not repeated.
    const key = `${entry.level}|${entry.message}`;
    const t = now();
    const last = recent.get(key);
    if (last !== undefined && t - last < 60_000) return;
    recent.set(key, t);
    if (recent.size > 500) recent.clear();
    if (queue.length >= MAX_QUEUE) queue.shift();
    queue.push({ ts: new Date(t).toISOString(), url: env.location.href.split('?')[0], release: opts.release, session, ...entry, message: clip(entry.message, MAX_MESSAGE) });
    if (queue.length >= maxBatch) void flush();
  }

  async function flush(keepalive = false): Promise<void> {
    if (!queue.length) return;
    const batch = queue.splice(0, 50);
    try {
      await opts.send(source, batch, { keepalive });
    } catch {
      // Put them back once (and only once: a service that is down must not make the page hold on to everything).
      if (queue.length < MAX_QUEUE / 2) queue.unshift(...batch.slice(0, 20));
    }
  }

  const on = (type: string, handler: (e: any) => void) => { // eslint-disable-line @typescript-eslint/no-explicit-any
    env.addEventListener(type, handler);
    cleanups.push(() => env.removeEventListener(type, handler));
  };

  if (config.console_errors) {
    on('error', (e) => {
      if (e?.target && e.target !== env && e.target.tagName) return; // a failed image or script tag is not a JavaScript error
      push({ level: 'error', message: e?.message || clip(e?.error, 400) || 'Uncaught error', stack: e?.error?.stack ? clip(e.error.stack, 1500) : undefined, attrs: e?.filename ? { file: String(e.filename).split('?')[0]!, line: Number(e.lineno) || 0 } : undefined });
    });
    on('unhandledrejection', (e) => push({ level: 'error', message: `Unhandled rejection: ${clip(e?.reason instanceof Error ? e.reason.message : e?.reason, 400)}`, stack: e?.reason?.stack ? clip(e.reason.stack, 1500) : undefined }));
    const c = env.console;
    if (c) {
      const originals = { error: c.error, warn: c.warn };
      for (const level of ['error', 'warn'] as const) {
        c[level] = (...args: unknown[]) => {
          try {
            push({ level: level === 'error' ? 'error' : 'warn', message: args.map((a) => clip(a, 300)).join(' '), attrs: { console: true } });
          } catch {
            /* never break the page's own logging */
          }
          return originals[level].apply(c, args as []);
        };
      }
      cleanups.push(() => { c.error = originals.error; c.warn = originals.warn; });
    }
  }

  if (config.network_errors && env.fetch) {
    const original = env.fetch;
    const wrapped = async function (this: unknown, input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.href : (input as Request).url;
      const method = (init?.method ?? (typeof input === 'object' && 'method' in input ? (input as Request).method : 'GET')).toUpperCase();
      const watched = !ignore.some((p) => url.includes(p));
      const started = now();
      try {
        const res = await original.call(this, input, init);
        if (watched) {
          const ms = now() - started;
          if (res.status >= 500) push({ level: 'error', message: `${method} ${routeOf(url)} failed (${res.status})`, status: res.status, duration_ms: ms, resource: routeOf(url), method, kind: 'request' });
          else if (res.status >= 400 && res.status !== 401 && res.status !== 404) push({ level: 'warn', message: `${method} ${routeOf(url)} was refused (${res.status})`, status: res.status, duration_ms: ms, resource: routeOf(url), method, kind: 'request' });
          else if (ms >= slowMs) push({ level: 'warn', message: `${method} ${routeOf(url)} was slow (${Math.round(ms)} ms)`, status: res.status, duration_ms: ms, resource: routeOf(url), method, kind: 'request' });
        }
        return res;
      } catch (err) {
        if (watched && (err as Error)?.name !== 'AbortError') push({ level: 'error', message: `${method} ${routeOf(url)} could not be reached: ${clip((err as Error)?.message, 160)}`, duration_ms: now() - started, resource: routeOf(url), method, kind: 'request' });
        throw err;
      }
    } as typeof fetch;
    (env as { fetch?: typeof fetch }).fetch = wrapped;
    cleanups.push(() => { (env as { fetch?: typeof fetch }).fetch = original; });
  }

  if (config.performance && env.PerformanceObserver) {
    try {
      const observe = (type: string, read: (entry: any) => ClientEntry | null) => { // eslint-disable-line @typescript-eslint/no-explicit-any
        const po = new env.PerformanceObserver!((list) => {
          for (const entry of list.getEntries()) {
            const e = read(entry);
            if (e) push(e);
          }
        });
        po.observe({ type, buffered: true } as PerformanceObserverInit);
        cleanups.push(() => po.disconnect());
      };
      observe('largest-contentful-paint', (e) => (e.startTime > 4000 ? { level: 'warn', message: `Slow page: largest paint at ${Math.round(e.startTime)} ms`, duration_ms: e.startTime, kind: 'event', attrs: { metric: 'LCP' } } : null));
      observe('layout-shift', (e) => (!e.hadRecentInput && e.value > 0.25 ? { level: 'warn', message: `Layout jumped (shift ${e.value.toFixed(2)})`, kind: 'event', attrs: { metric: 'CLS' } } : null));
      observe('longtask', (e) => (e.duration > 500 ? { level: 'warn', message: `The page froze for ${Math.round(e.duration)} ms`, duration_ms: e.duration, kind: 'event', attrs: { metric: 'longtask' } } : null));
    } catch {
      /* a browser without these entry types simply reports none */
    }
  }

  const leaving = () => void flush(true);
  on('pagehide', leaving);
  on('visibilitychange', () => { if (env.document?.visibilityState === 'hidden') leaving(); });
  timer = setInterval(() => void flush(), opts.flushMs ?? 10_000);
  (timer as unknown as { unref?: () => void }).unref?.(); // in Node (tests, SSR) a forgotten timer must not keep the process alive

  return {
    stop() {
      stopped = true;
      if (timer) clearInterval(timer);
      for (const c of cleanups.splice(0)) c();
    },
    flush: () => flush(),
    log: push,
    pending: () => queue.length,
  };
}
