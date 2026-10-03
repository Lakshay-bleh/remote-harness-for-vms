import { DogState } from '../dog/DogState';
import { Button } from '../ui';
import type { ServerMsg } from './lib/protocol';

export type Approval = Extract<ServerMsg, { t: 'approval' }>;

/** Actions on the computer that are waiting for a person's OK. With none waiting, a dog keeps watch. */
export default function ApprovalsTab({ items, onAnswer, online }: { items: Approval[]; onAnswer: (a: Approval, ok: boolean) => void; online: boolean }) {
  if (items.length === 0) {
    return online
      ? <DogState scene="sit" title="All clear" text="Nothing is waiting for your OK. When your computer needs a yes before it does something, it will ask here." />
      : <DogState scene="sleep" title="Your computer is offline" text="Approvals will show up here once it is back." />;
  }
  return (
    <div className="space-y-3 px-4 pb-4 pt-3">
      {items.map((a) => (
        <div key={a.approvalId} className={`rounded-lg border p-4 ${a.risk === 'destructive' ? 'border-error/40 bg-error/5' : 'border-permission/30 bg-permission/5'}`}>
          <p className="text-[13px] font-medium uppercase tracking-wide text-muted">{a.risk === 'destructive' ? 'Needs your care' : 'Needs your OK'}</p>
          <p className="mt-1 text-[15px] font-medium text-ink">{a.describe}</p>
          <pre className="mt-2 max-h-32 overflow-auto whitespace-pre-wrap break-words rounded-md bg-surface-dark p-3 font-mono text-[12px] text-on-dark">{JSON.stringify(a.input, null, 2)}</pre>
          <div className="mt-3 flex gap-2"><Button onClick={() => onAnswer(a, true)}>Continue</Button><Button kind="quiet" onClick={() => onAnswer(a, false)}>Don’t do this</Button></div>
        </div>
      ))}
    </div>
  );
}
