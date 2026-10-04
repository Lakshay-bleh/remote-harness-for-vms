import { ArrowUp, Camera, FileText, Image as ImageIcon, Microphone, Plus, Stop, Waveform, X } from '@phosphor-icons/react';
import { useRef, useState } from 'react';
import { Spinner } from '../ui';
import { useDictation } from '../voice/useDictation';
import { useVoiceMode } from '../voice/VoiceOrb';
import { ACCEPT_ALL, ACCEPT_TEXT, canAdd, humanSize, totalBytes, LIMITS, type Attachment } from './attachments';
import { readFile } from './readFile';

export interface ComposerProps {
  placeholder: string;
  running?: boolean;
  disabled?: boolean;
  /** `all`: photos, PDFs and text. `media`: photos and text, no PDFs. `text`: text and code files only. `none`: no attach button. */
  attach?: 'all' | 'media' | 'text' | 'none';
  /** Choices that belong to this chat (which machine, mode, model), in a row above the text. */
  chips?: React.ReactNode;
  onSend: (text: string, attachments: Attachment[]) => void;
  onStop?: () => void;
  /** Reported above the box, in the chat's own error style. */
  onProblem?: (message: string | null) => void;
}

/**
 * The message box every chat shares. On the left a plus opens a small menu (photos, camera, files) that stays on the left, so it
 * never covers the send button. On the right: speak instead of typing, voice mode (a conversation by voice), or send. Attached files
 * show as chips above the text, with a picture for photos and a button to take any of them off.
 */
export default function ChatComposer({ placeholder, running = false, disabled = false, attach = 'all', chips, onSend, onStop, onProblem }: ComposerProps) {
  const [text, setText] = useState('');
  const [files, setFiles] = useState<Attachment[]>([]);
  const [menu, setMenu] = useState(false);
  const [reading, setReading] = useState(0);
  const [note, setNote] = useState<string | null>(null);
  const box = useRef<HTMLTextAreaElement>(null);
  const gallery = useRef<HTMLInputElement>(null);
  const camera = useRef<HTMLInputElement>(null);
  const picker = useRef<HTMLInputElement>(null);
  const voice = useVoiceMode();
  const dictation = useDictation((t) => { setText(t); grow(); });
  const problem = (m: string | null) => (setNote(m), onProblem?.(m));

  const grow = () => requestAnimationFrame(() => {
    const el = box.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${Math.min(el.scrollHeight, 160)}px`;
  });

  const add = async (list: FileList | null) => {
    setMenu(false);
    if (!list?.length) return;
    problem(null);
    let current = files;
    for (const f of Array.from(list)) {
      const why = canAdd(current, f, attach === 'text' ? 'text' : attach === 'media' ? 'media' : 'all');
      if (why) { problem(why); continue; }
      setReading((n) => n + 1);
      try {
        const a = await readFile(f);
        if (totalBytes([...current, a]) > LIMITS.bytesTotal) { problem('Those files are too big together. Attach fewer, or smaller ones.'); continue; }
        current = [...current, a];
        setFiles(current);
      } catch (e) {
        problem(e instanceof Error ? e.message : 'Could not attach that file.');
      } finally {
        setReading((n) => n - 1);
      }
    }
  };

  const content = text.trim().length > 0 || files.length > 0;
  const submit = () => {
    if (!content || disabled || running || reading > 0) return;
    dictation.stop();
    onSend(text.trim(), files);
    setText('');
    setFiles([]);
    problem(null);
    requestAnimationFrame(() => box.current && (box.current.style.height = 'auto'));
  };

  const iconBtn = 'flex h-10 w-10 shrink-0 items-center justify-center rounded-full transition active:scale-90 disabled:opacity-40';
  const err = note ?? dictation.error;

  return (
    <div className="relative mx-auto w-full max-w-3xl">
      {err && <p role="alert" className="mb-2 rounded-md border border-error/30 bg-error/10 px-3 py-2 text-[13px] text-error">{err}</p>}
      <form className="rounded-3xl border border-line-strong bg-surface-dark-soft transition focus-within:border-primary/60 focus-within:ring-4 focus-within:ring-primary/10" onSubmit={(e) => { e.preventDefault(); submit(); }}>
        {chips && <div className="flex flex-wrap items-center gap-1.5 px-3 pt-3">{chips}</div>}
        {(files.length > 0 || reading > 0) && (
          <ul className="flex gap-2 overflow-x-auto px-3 pt-3 [scrollbar-width:none]" aria-label="Attached files">
            {files.map((a) => (
              <li key={a.id} className="relative flex shrink-0 items-center gap-2 rounded-xl border border-hairline bg-surface-card p-1.5 pr-7">
                {a.preview ? <img src={a.preview} alt="" className="h-10 w-10 rounded-lg object-cover" /> : <span className="flex h-10 w-10 items-center justify-center rounded-lg bg-canvas text-muted"><FileText size={22} /></span>}
                <span className="max-w-[120px]"><span className="block truncate text-[13px] text-ink">{a.name}</span><span className="block text-[11px] text-muted">{a.kind === 'text' ? 'Text' : a.kind === 'pdf' ? 'PDF' : 'Photo'} · {humanSize(a.size)}</span></span>
                <button type="button" onClick={() => setFiles((f) => f.filter((x) => x.id !== a.id))} aria-label={`Remove ${a.name}`} className="absolute right-1 top-1 flex h-5 w-5 items-center justify-center rounded-full bg-canvas text-muted hover:text-ink"><X size={12} weight="bold" /></button>
              </li>
            ))}
            {reading > 0 && <li className="flex h-[52px] w-[52px] shrink-0 items-center justify-center rounded-xl border border-hairline bg-surface-card"><Spinner /></li>}
          </ul>
        )}

        <div className="flex items-end gap-1 py-1.5 pl-1.5 pr-1.5">
          {attach !== 'none' && (
            <button type="button" onClick={() => setMenu((m) => !m)} aria-label="Attach" aria-expanded={menu} disabled={disabled || running} className={`${iconBtn} text-body hover:bg-surface-card ${menu ? 'bg-surface-card text-ink' : ''}`}><Plus size={22} weight="bold" className={`transition-transform ${menu ? 'rotate-45' : ''}`} /></button>
          )}
          <textarea
            ref={box}
            value={text}
            onChange={(e) => { setText(e.target.value); grow(); }}
            onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey && !('ontouchstart' in window)) { e.preventDefault(); submit(); } }}
            rows={1}
            placeholder={dictation.listening ? 'Listening…' : placeholder}
            aria-label="Message"
            disabled={disabled}
            className={`max-h-40 min-h-[40px] flex-1 resize-none bg-transparent py-2 text-base text-ink outline-none placeholder:text-muted-soft ${attach === 'none' ? 'pl-3' : ''}`}
          />
          {dictation.supported && !running && (
            <button type="button" onClick={() => dictation.toggle(text)} aria-label={dictation.listening ? 'Stop dictating' : 'Speak your message'} aria-pressed={dictation.listening} disabled={disabled} className={`${iconBtn} ${dictation.listening ? 'animate-pulse bg-primary text-on-primary' : 'text-body hover:bg-surface-card'}`}><Microphone size={21} weight={dictation.listening ? 'fill' : 'regular'} /></button>
          )}
          {running ? (
            <button type="button" onClick={onStop} aria-label="Stop" className={`${iconBtn} bg-surface-card text-ink hover:bg-surface-cream-strong`}><Stop size={18} weight="fill" /></button>
          ) : content ? (
            <button type="submit" disabled={disabled || reading > 0} aria-label="Send" className={`${iconBtn} bg-primary text-on-primary hover:bg-primary-active`}><ArrowUp size={20} weight="bold" /></button>
          ) : voice ? (
            <button type="button" onClick={() => voice.open()} aria-label="Talk to Escanor" disabled={disabled} className={`${iconBtn} bg-primary text-on-primary hover:bg-primary-active`}><Waveform size={21} weight="bold" /></button>
          ) : (
            <button type="submit" disabled aria-label="Send" className={`${iconBtn} bg-surface-card text-muted-soft`}><ArrowUp size={20} weight="bold" /></button>
          )}
        </div>
      </form>

      {menu && (
        <>
          <div className="fixed inset-0 z-10" onClick={() => setMenu(false)} aria-hidden />
          <div role="menu" aria-label="Attach" className="absolute bottom-full left-0 z-20 mb-2 w-56 overflow-hidden rounded-2xl border border-line-strong bg-surface-card py-1 shadow-elevated">
            {(attach === 'all' || attach === 'media') && (
              <>
                <MenuItem icon={<ImageIcon size={20} />} label="Photos" onClick={() => gallery.current?.click()} />
                <MenuItem icon={<Camera size={20} />} label="Take a photo" onClick={() => camera.current?.click()} />
              </>
            )}
            <MenuItem icon={<FileText size={20} />} label={attach === 'text' ? 'Text or code file' : 'Files'} onClick={() => picker.current?.click()} />
          </div>
        </>
      )}
      <input ref={gallery} type="file" accept="image/*" multiple hidden onChange={(e) => { void add(e.target.files); e.target.value = ''; }} />
      <input ref={camera} type="file" accept="image/*" capture="environment" hidden onChange={(e) => { void add(e.target.files); e.target.value = ''; }} />
      <input ref={picker} type="file" accept={attach === 'text' ? ACCEPT_TEXT : ACCEPT_ALL} multiple hidden onChange={(e) => { void add(e.target.files); e.target.value = ''; }} />
    </div>
  );
}

function MenuItem({ icon, label, onClick }: { icon: React.ReactNode; label: string; onClick: () => void }) {
  return (
    <button type="button" role="menuitem" onClick={onClick} className="flex w-full items-center gap-3 px-4 py-3 text-left text-[15px] text-ink transition hover:bg-surface-strong active:bg-surface-strong">
      <span className="text-muted">{icon}</span>
      {label}
    </button>
  );
}
