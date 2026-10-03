import { CaretRight } from '@phosphor-icons/react';
import { useState } from 'react';
import { Sheet } from '../escanor/ui';
import { LEGAL_LIST, LegalBody } from './LegalBody';

/** The legal documents as a bottom sheet: a list, then the one you pick. For screens that have no Settings around them (sign-in). */
export default function LegalSheet({ start, onClose }: { start?: string; onClose: () => void }) {
  const [open, setOpen] = useState<string | null>(start ?? null);
  return (
    <Sheet title={open ? (LEGAL_LIST.find((d) => d.key === open)?.label ?? 'Legal') : 'Legal and privacy'} onClose={open && !start ? () => setOpen(null) : onClose}>
      {open ? (
        <LegalBody docKey={open} />
      ) : (
        <ul className="-mx-1 divide-y divide-hairline">
          {LEGAL_LIST.map((d) => (
            <li key={d.key}><button type="button" onClick={() => setOpen(d.key)} className="flex w-full items-center justify-between px-1 py-3.5 text-left text-[15px] text-ink transition active:bg-surface-card">{d.label}<CaretRight size={16} className="text-muted-soft" aria-hidden /></button></li>
          ))}
        </ul>
      )}
    </Sheet>
  );
}
