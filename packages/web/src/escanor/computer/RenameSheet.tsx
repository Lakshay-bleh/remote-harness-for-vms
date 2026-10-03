import { useState } from 'react';
import { Button, Sheet } from '../ui';
import { cleanName } from './computerPrefs';

/** Give a computer a name you will recognise. Blank goes back to the name the computer gave itself. */
export default function RenameSheet({ current, original, onSave, onClose }: { current: string; original: string; onSave: (name: string) => void; onClose: () => void }) {
  const [text, setText] = useState(current);
  const clean = cleanName(text);
  return (
    <Sheet title="Rename this computer" onClose={onClose}>
      <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); onSave(clean === original ? '' : clean); onClose(); }}>
        <input value={text} onChange={(e) => setText(e.target.value)} placeholder={original} maxLength={60} autoFocus aria-label="Computer name" className="w-full rounded-md border border-line-strong bg-surface-card px-3 py-3 text-base text-ink outline-none focus:border-primary focus:ring-4 focus:ring-primary/15" />
        <p className="text-[12px] leading-relaxed text-muted">This name is only on this phone. The computer is still called “{original}” on the computer itself. Leave it blank to use that name.</p>
        <Button type="submit" className="w-full">Save</Button>
      </form>
    </Sheet>
  );
}
