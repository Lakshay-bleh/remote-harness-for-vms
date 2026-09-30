import { escanor } from './client';
import { useLoad } from './hooks';
import { ago, Notice, Sheet, Spinner } from './ui';

const LABEL: Record<string, string> = { running: 'Running', starting: 'Starting', sleeping: 'Asleep, wakes when you chat', stopped: 'Stopped', unavailable: 'Unavailable', unknown: 'Not started yet' };
const EVENT: Record<string, string> = {
  'machine.started': 'Machine started', 'machine.woke': 'Machine woke up', 'machine.slept': 'Machine went to sleep',
  'git.push': 'Pushed a branch', 'git.push_blocked': 'A push to a protected branch was blocked',
};

export const machineTone = (state: string) => (state === 'running' ? 'bg-success' : state === 'unavailable' ? 'bg-error' : state === 'sleeping' ? 'bg-muted-soft' : 'bg-accent-amber');
export const machineLabel = (state: string) => LABEL[state] ?? state;

/** What the assistant's machine is doing, and what it has done: the cloud side of "make this change". */
export default function MachineSheet({ onClose }: { onClose: () => void }) {
  const machine = useLoad(() => escanor.machine(true), 3000);
  const m = machine.data;

  return (
    <Sheet title="Your assistant’s machine" onClose={onClose}>
      {machine.loading && !m ? <Spinner /> : null}
      {machine.error && <Notice tone="error">{machine.error}</Notice>}
      {m && (
        <div className="space-y-4">
          <div className="flex items-center gap-2">
            <span className={`h-2.5 w-2.5 rounded-full ${machineTone(m.state)}`} />
            <span className="text-[15px] font-medium text-ink">{machineLabel(m.state)}</span>
          </div>
          {m.detail && <p className="text-sm text-body">{m.detail}</p>}
          {!m.available && <Notice>Live details appear once your assistant’s machine service is connected.</Notice>}

          {m.events.length > 0 && (
            <section>
              <h3 className="mb-1.5 text-[12px] font-medium uppercase tracking-wide text-muted">Recent activity</h3>
              <ul className="space-y-1.5">
                {m.events.slice(0, 12).map((e, i) => (
                  <li key={i} className="flex justify-between gap-3 text-sm">
                    <span className="min-w-0 text-body"><span className="text-ink">{EVENT[e.kind] ?? e.kind}</span>{e.detail ? ` · ${e.detail}` : ''}</span>
                    <span className="shrink-0 text-[12px] text-muted-soft">{ago(e.at)}</span>
                  </li>
                ))}
              </ul>
            </section>
          )}

          {m.logs ? (
            <section>
              <h3 className="mb-1.5 text-[12px] font-medium uppercase tracking-wide text-muted">Live output</h3>
              <pre className="on-dark-scroll max-h-64 overflow-auto whitespace-pre-wrap break-words rounded-md bg-surface-dark p-3 font-mono text-[11px] leading-relaxed text-on-dark">{m.logs}</pre>
            </section>
          ) : null}
        </div>
      )}
    </Sheet>
  );
}
