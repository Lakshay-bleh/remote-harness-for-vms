import { useCallback } from 'react';
import { DogState } from '../dog/DogState';
import ErrorCard from './ErrorCard';
import type { ClientMsg, ServerMsg } from './lib/protocol';
import { useRemote } from './useRemote';

type Request = (msg: ClientMsg) => Promise<ServerMsg[]>;

interface Stats { cpu: { load: number; model: string; cores: number }; mem: { used: number; total: number }; disks: Array<{ mount: string; used: number; size: number; usePercent: number }>; os: { hostname: string; uptimeSec: number }; battery: { percent: number; charging: boolean } | null; tempC: number | null }
interface Reading { stats: Stats; procs: Array<{ pid: number; name: string; cpu: number; memBytes: number }> }

const gb = (n: number) => `${(n / 1024 ** 3).toFixed(1)} GB`;
const uid = () => Math.random().toString(36).slice(2, 10);

function Meter({ value }: { value: number }) {
  const v = Math.min(100, Math.max(0, value));
  return <div className="h-2 overflow-hidden rounded-full bg-surface-card"><div className={`h-full rounded-full transition-[width] duration-500 ${v > 90 ? 'bg-error' : v > 75 ? 'bg-permission' : 'bg-primary'}`} style={{ width: `${v}%` }} /></div>;
}

/** CPU, memory, storage and the busiest programs. Shows the last reading at once, then keeps it fresh: quickly over Wi-Fi, gently over the cloud. */
export default function ResourcesTab({ computerId, request, online, route }: { computerId: string; request: Request; online: boolean; route: 'lan' | 'cloud' | null }) {
  const read = useCallback(async (): Promise<Reading> => {
    // Both are asked at the same moment, so over the cloud they travel together.
    const [s, p] = await Promise.all([request({ t: 'call', id: uid(), capability: 'system.stats' }), request({ t: 'call', id: uid(), capability: 'system.processes', input: { limit: 6 } })]);
    const sr = s.find((m) => m.t === 'result');
    const pr = p.find((m) => m.t === 'result');
    if (!sr || sr.t !== 'result' || !sr.ok) throw new Error(sr && sr.t === 'result' ? (sr.error?.message ?? 'The computer could not read itself.') : 'No answer.');
    return { stats: sr.result as Stats, procs: pr && pr.t === 'result' && pr.ok ? (pr.result as Reading['procs']) : [] };
  }, [request]);

  const r = useRemote<Reading>({ computerId, what: 'stats', online, run: read, ttlMs: 3000, everyMs: route === 'lan' ? 3000 : 9000, deadlineMs: 25_000 });

  if (!r.data) {
    if (r.error && !r.refreshing) return <div className="px-4 py-4"><ErrorCard error={r.error} onRetry={r.reload} /></div>;
    if (!online) return <DogState scene="sleep" title="Your computer is offline" text="Its numbers will show here when it is back." />;
    return <DogState scene="run" live title="Reading your computer…" text="Fetching its CPU, memory and storage." />;
  }
  const { stats, procs } = r.data;
  const memPct = (stats.mem.used / stats.mem.total) * 100;
  return (
    <div className="space-y-4 px-4 pb-4 pt-3">
      <div className="rounded-lg border border-hairline bg-surface-card p-4"><div className="flex justify-between text-sm"><span className="text-body">CPU</span><span className="font-medium text-ink">{stats.cpu.load.toFixed(0)}%</span></div><div className="mt-2"><Meter value={stats.cpu.load} /></div><p className="mt-2 truncate text-[12px] text-muted">{stats.cpu.model} · {stats.cpu.cores} threads{stats.tempC ? ` · ${stats.tempC.toFixed(0)}°C` : ''}</p></div>
      <div className="rounded-lg border border-hairline bg-surface-card p-4"><div className="flex justify-between text-sm"><span className="text-body">Memory</span><span className="font-medium text-ink">{gb(stats.mem.used)} of {gb(stats.mem.total)}</span></div><div className="mt-2"><Meter value={memPct} /></div></div>
      {stats.disks[0] && <div className="rounded-lg border border-hairline bg-surface-card p-4"><div className="flex justify-between text-sm"><span className="text-body">Storage</span><span className="font-medium text-ink">{gb(stats.disks[0].used)} of {gb(stats.disks[0].size)}</span></div><div className="mt-2"><Meter value={stats.disks[0].usePercent} /></div></div>}
      {stats.battery && <p className="text-sm text-body">Battery {Math.round(stats.battery.percent)}%{stats.battery.charging ? ', charging' : ''}</p>}
      {procs.length > 0 && (
        <div className="rounded-lg border border-hairline bg-surface-card"><p className="px-4 pt-3 text-[12px] font-medium uppercase tracking-wide text-muted">Busiest programs</p><ul className="divide-y divide-hairline">{procs.map((p) => <li key={p.pid} className="flex justify-between gap-3 px-4 py-2.5 text-sm"><span className="truncate text-ink">{p.name}</span><span className="shrink-0 text-muted">{p.cpu.toFixed(1)}% · {(p.memBytes / 1024 ** 2).toFixed(0)} MB</span></li>)}</ul></div>
      )}
      {r.stale && <p className="text-center text-[11px] text-muted-soft">Showing the last reading while it updates…</p>}
    </div>
  );
}
