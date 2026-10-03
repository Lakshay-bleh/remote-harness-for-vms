import { DotsThreeVertical } from '@phosphor-icons/react';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import { useHardwareBack } from './back';
import { haptic } from './settings/prefs';

export interface MenuItem {
  label: string;
  icon?: ReactNode;
  onClick: () => void;
  danger?: boolean;
  disabled?: boolean;
  /** A thin line above this item, to group the ones that follow. */
  divider?: boolean;
}

/**
 * The three-dots button and its menu. Closes on a tap outside, Escape, or the phone's back button, and puts the dangerous item at the
 * bottom behind a divider so it is never the one under a thumb by accident.
 */
export function OverflowMenu({ items, label = 'More options' }: { items: MenuItem[]; label?: string }) {
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  useHardwareBack(open, () => setOpen(false), 3);

  useEffect(() => {
    if (!open) return;
    const away = (e: PointerEvent) => root.current && !root.current.contains(e.target as Node) && setOpen(false);
    const esc = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false);
    document.addEventListener('pointerdown', away);
    document.addEventListener('keydown', esc);
    return () => {
      document.removeEventListener('pointerdown', away);
      document.removeEventListener('keydown', esc);
    };
  }, [open]);

  return (
    <div ref={root} className="relative">
      <button type="button" aria-label={label} aria-haspopup="menu" aria-expanded={open} onClick={() => { haptic(); setOpen((o) => !o); }} className="flex h-10 w-10 items-center justify-center rounded-pill text-body transition hover:bg-surface-card hover:text-ink active:scale-90">
        <DotsThreeVertical size={24} weight="bold" />
      </button>
      {open && (
        <ul role="menu" className="absolute right-0 top-full z-40 mt-1 min-w-[230px] overflow-hidden rounded-xl border border-line-strong bg-surface-card py-1 shadow-elevated">
          {items.map((it) => (
            <li key={it.label} role="none" className={it.divider ? 'mt-1 border-t border-hairline pt-1' : ''}>
              <button type="button" role="menuitem" disabled={it.disabled} onClick={() => { setOpen(false); haptic(); it.onClick(); }} className={`flex w-full items-center gap-3 px-4 py-3 text-left text-[15px] transition active:bg-surface-cream-strong disabled:opacity-40 ${it.danger ? 'text-error' : 'text-ink'}`}>
                {it.icon && <span className="flex h-5 w-5 shrink-0 items-center justify-center text-muted">{it.icon}</span>}
                {it.label}
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
