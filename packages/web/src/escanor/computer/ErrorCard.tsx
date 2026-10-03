import { Desktop, DeviceMobile, ArrowsLeftRight } from '@phosphor-icons/react';
import { useState } from 'react';
import { Button, Spinner } from '../ui';
import { explainFailure, type FixWhere } from './errors';

const WHERE: Record<FixWhere, { label: string; Icon: typeof Desktop }> = {
  computer: { label: 'Fix it on your computer', Icon: Desktop },
  phone: { label: 'Fix it in this app', Icon: DeviceMobile },
  both: { label: 'Check both devices', Icon: ArrowsLeftRight },
};

/**
 * An error, explained: what happened, which device the fix is on, and the steps. When the cause is a permission switched off for
 * phones it also offers to ask the computer to allow it (the computer's owner then says yes there; the phone cannot grant itself).
 */
export default function ErrorCard({ error, onRetry, onAsk }: { error: unknown; onRetry?: () => void; onAsk?: (groupLabel: string) => Promise<string> }) {
  const e = explainFailure(error);
  const { label, Icon } = WHERE[e.where];
  const [asking, setAsking] = useState(false);
  const [answer, setAnswer] = useState<string | null>(null);

  const ask = async () => {
    if (!e.ask || !onAsk) return;
    setAsking(true);
    setAnswer(null);
    try {
      setAnswer(await onAsk(e.ask.groupLabel));
    } catch (err) {
      setAnswer(explainFailure(err).title);
    } finally {
      setAsking(false);
    }
  };

  return (
    <div role="alert" className="rounded-xl border border-warning/30 bg-warning/5 p-4 text-left">
      <p className="text-[15px] font-medium text-ink">{e.title}</p>
      <p className="mt-2 flex items-center gap-1.5 text-[11px] font-medium uppercase tracking-wide text-muted"><Icon size={14} aria-hidden /> {label}</p>
      <ol className="mt-1.5 list-decimal space-y-1 pl-5 text-[14px] leading-snug text-body">
        {e.steps.map((s) => <li key={s}>{s}</li>)}
      </ol>
      {(e.ask && onAsk) || onRetry ? (
        <div className="mt-3 flex flex-wrap gap-2">
          {e.ask && onAsk && <Button onClick={() => void ask()} disabled={asking}>{asking ? 'Asking…' : 'Ask my computer to allow it'}</Button>}
          {onRetry && <Button kind="quiet" onClick={onRetry}>Try again</Button>}
        </div>
      ) : null}
      {asking && <p className="mt-2 flex items-center gap-2 text-[13px] text-muted"><Spinner /> Sending the request…</p>}
      {answer && <p className="mt-2 text-[13px] leading-snug text-body">{answer}</p>}
    </div>
  );
}
