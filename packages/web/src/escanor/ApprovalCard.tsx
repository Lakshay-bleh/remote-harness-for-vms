import { useState } from 'react';
import type { AssistantItem } from '@remote-harness/shared/escanor';
import { Button } from './ui';

type Approval = Extract<AssistantItem, { kind: 'approval' }>;

/** "Should I go ahead?" in plain words. The only thing the assistant asks a person for. */
export default function ApprovalCard({ item, onAnswer }: { item: Approval; onAnswer: (allow: boolean) => void }) {
  const [details, setDetails] = useState(false);
  const high = item.risk === 'high';
  const answered = item.status !== 'pending';

  return (
    <div className={`rounded-lg border p-4 ${high ? 'border-error/40 bg-error/5' : 'border-permission/30 bg-permission/5'}`} role="group" aria-label="Permission needed">
      <p className="text-[13px] font-medium uppercase tracking-wide text-muted">{high ? 'Needs your care' : 'Needs your OK'}</p>
      <p className="mt-1 text-[15px] font-medium text-ink">{item.title}</p>
      {item.detail && <p className="mt-0.5 break-words text-sm text-body">{item.detail}</p>}
      {item.raw && (
        <>
          <button onClick={() => setDetails((d) => !d)} className="mt-2 text-[12px] text-muted underline underline-offset-2">
            {details ? 'Hide details' : 'Show details'}
          </button>
          {details && <pre className="on-dark-scroll mt-2 max-h-48 overflow-auto whitespace-pre-wrap break-words rounded-md bg-surface-dark p-3 font-mono text-[12px] text-on-dark">{item.raw}</pre>}
        </>
      )}
      {answered ? (
        <p className="mt-3 text-sm text-muted">{item.status === 'allowed' ? 'You said continue.' : item.status === 'denied' ? 'You said no.' : ''}</p>
      ) : (
        <div className="mt-3 flex gap-2">
          <Button onClick={() => onAnswer(true)}>Continue</Button>
          <Button kind="quiet" onClick={() => onAnswer(false)}>Don’t do this</Button>
        </div>
      )}
    </div>
  );
}
