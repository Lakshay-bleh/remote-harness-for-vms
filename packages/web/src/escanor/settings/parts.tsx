import { CaretRight } from '@phosphor-icons/react';
import type { ReactNode } from 'react';
import { haptic } from './prefs';
import { Button, ScreenHeader, Sheet } from '../ui';
import { useHardwareBack } from '../back';

/** One settings page: the shared header with a back arrow, then the scrolling body. The phone's back button steps out of it too. */
export function Page({ title, subtitle, onBack, children }: { title: string; subtitle?: string; onBack: () => void; children: ReactNode }) {
  useHardwareBack(true, onBack);
  return (
    <div className="flex h-full min-h-0 flex-col">
      <ScreenHeader title={title} subtitle={subtitle} onBack={onBack} />
      <div className="min-h-0 flex-1 space-y-6 overflow-y-auto px-4 pb-8 pt-4">{children}</div>
    </div>
  );
}

/** A titled card of rows, like the system settings: a small label above, a footnote below. */
export function Group({ title, footer, children }: { title?: string; footer?: ReactNode; children: ReactNode }) {
  return (
    <section>
      {title && <h2 className="mb-1.5 px-1 text-[12px] font-medium uppercase tracking-wide text-muted">{title}</h2>}
      <div className="divide-y divide-hairline overflow-hidden rounded-xl border border-hairline bg-surface-card">{children}</div>
      {footer && <p className="mt-1.5 px-1 text-[12px] leading-relaxed text-muted">{footer}</p>}
    </section>
  );
}

export interface RowProps {
  label: string;
  /** A small line under the label. */
  sub?: ReactNode;
  /** What is chosen now, shown on the right. */
  value?: ReactNode;
  icon?: ReactNode;
  onClick?: () => void;
  danger?: boolean;
  /** Draw the arrow that says "this opens something". On by default for tappable rows. */
  chevron?: boolean;
  right?: ReactNode;
  disabled?: boolean;
}

export function Row({ label, sub, value, icon, onClick, danger, chevron, right, disabled }: RowProps) {
  const body = (
    <>
      {icon && <span className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg ${danger ? 'bg-error/10 text-error' : 'bg-canvas text-body'}`}>{icon}</span>}
      <span className="min-w-0 flex-1 text-left">
        <span className={`block truncate text-[15px] ${danger ? 'text-error' : 'text-ink'}`}>{label}</span>
        {sub && <span className="mt-0.5 block text-[12px] leading-snug text-muted">{sub}</span>}
      </span>
      {value !== undefined && <span className="max-w-[45%] shrink-0 truncate text-right text-[14px] text-muted">{value}</span>}
      {right}
      {onClick && chevron !== false && <CaretRight size={16} className="shrink-0 text-muted-soft" aria-hidden />}
    </>
  );
  const cls = 'flex min-h-[52px] w-full items-center gap-3 px-3.5 py-2.5';
  return onClick ? (
    <button type="button" disabled={disabled} onClick={() => { haptic(); onClick(); }} className={`${cls} transition active:bg-surface-cream-strong disabled:opacity-50`}>{body}</button>
  ) : (
    <div className={cls}>{body}</div>
  );
}

export function Switch({ on, onChange, label, disabled }: { on: boolean; onChange: (v: boolean) => void; label: string; disabled?: boolean }) {
  return (
    <button type="button" role="switch" aria-checked={on} aria-label={label} disabled={disabled} onClick={() => { haptic(); onChange(!on); }} className={`relative h-7 w-12 shrink-0 rounded-full transition-colors duration-200 disabled:opacity-40 ${on ? 'bg-primary' : 'bg-line-strong'}`}>
      <span className={`absolute top-0.5 h-6 w-6 rounded-full bg-canvas shadow transition-all duration-200 ${on ? 'left-[22px]' : 'left-0.5'}`} />
    </button>
  );
}

export function SwitchRow({ label, sub, on, onChange, disabled, icon }: { label: string; sub?: ReactNode; on: boolean; onChange: (v: boolean) => void; disabled?: boolean; icon?: ReactNode }) {
  return <Row label={label} sub={sub} icon={icon} right={<Switch on={on} onChange={onChange} label={label} disabled={disabled} />} />;
}

/** Pick one of a few options from a bottom sheet. */
export function ChoiceSheet<T extends string>({ title, options, value, onPick, onClose }: { title: string; options: ReadonlyArray<{ value: T; label: string; hint?: string }>; value: T; onPick: (v: T) => void; onClose: () => void }) {
  return (
    <Sheet title={title} onClose={onClose}>
      <ul className="-mx-1 divide-y divide-hairline">
        {options.map((o) => (
          <li key={o.value}>
            <button type="button" onClick={() => { haptic(); onPick(o.value); onClose(); }} className="flex w-full items-center gap-3 rounded-md px-1 py-3 text-left transition active:bg-surface-card" aria-pressed={o.value === value}>
              <span className="min-w-0 flex-1"><span className="block text-[15px] text-ink">{o.label}</span>{o.hint && <span className="block text-[12px] text-muted">{o.hint}</span>}</span>
              <span aria-hidden className={`flex h-5 w-5 shrink-0 items-center justify-center rounded-full border ${o.value === value ? 'border-primary bg-primary' : 'border-line-strong'}`}>{o.value === value && <span className="h-2 w-2 rounded-full bg-on-primary" />}</span>
            </button>
          </li>
        ))}
      </ul>
    </Sheet>
  );
}

export function Avatar({ name, email, size = 56 }: { name?: string | null; email?: string | null; size?: number }) {
  return (
    <span className="flex shrink-0 items-center justify-center rounded-full border border-hairline bg-canvas font-display text-ink" style={{ width: size, height: size, fontSize: size * 0.42 }}>
      {(name || email || '?').slice(0, 1).toUpperCase()}
    </span>
  );
}

/** A confirm step for things that cannot be undone. */
export function ConfirmSheet({ title, body, action, onConfirm, onClose, busy }: { title: string; body: ReactNode; action: string; onConfirm: () => void; onClose: () => void; busy?: boolean }) {
  return (
    <Sheet title={title} onClose={onClose}>
      <div className="space-y-4">
        <p className="text-sm leading-relaxed text-body">{body}</p>
        <div className="flex gap-2">
          <Button kind="quiet" className="flex-1" onClick={onClose}>Cancel</Button>
          <Button kind="danger" className="flex-1" disabled={busy} onClick={onConfirm}>{busy ? 'Working…' : action}</Button>
        </div>
      </div>
    </Sheet>
  );
}
