import { useState } from 'react';
import LegalSheet from '../legal/LegalSheet';

/** Escanor service notices, read inside the app; independent hub operators must supply their own notices. */
export default function LegalLinks() {
  const [open, setOpen] = useState<string | null>(null);
  return (
    <div className="mt-4 text-xs leading-relaxed text-muted">
      <nav aria-label="Legal and support" className="flex flex-wrap gap-x-3 gap-y-1">
        <button type="button" onClick={() => setOpen('privacy')} className="underline">Escanor privacy</button>
        <button type="button" onClick={() => setOpen('terms')} className="underline">Terms</button>
        <button type="button" onClick={() => setOpen('support')} className="underline">Support</button>
      </nav>
      <p className="mt-2">For a self-hosted hub, ask its operator about access, storage and deletion of your session data.</p>
      {open && <LegalSheet start={open} onClose={() => setOpen(null)} />}
    </div>
  );
}
