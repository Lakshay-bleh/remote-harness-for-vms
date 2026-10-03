import { Microphone, Stop, WarningCircle, CheckCircle } from '@phosphor-icons/react';
import { useState } from 'react';
import { haptic } from '../settings/prefs';
import { Logo, Sheet, Spinner, useKeyboardOpen } from '../ui';
import type { VoiceTab } from './commands';
import { useVoiceSession, type VoicePhase } from './useVoiceSession';

const LABEL: Record<VoicePhase, string> = { idle: 'Tap the mic and speak', listening: 'Listening…', thinking: 'Working on it…', speaking: 'Speaking' };

/**
 * Escanor's voice, on every screen: the Escanor mark floats above the tab bar; tapping it listens, does what you said (on this
 * phone, on your computer, or through the assistant) and tells you what happened.
 */
export default function VoiceOrb({ go, onAssistant }: { go: (tab: VoiceTab) => void; onAssistant: (text: string) => Promise<void> }) {
  const [open, setOpen] = useState(false);
  const keyboard = useKeyboardOpen();
  const v = useVoiceSession({ go: (t) => { go(t); setOpen(false); }, onAssistant: async (text) => { await onAssistant(text); setOpen(false); } });

  const show = () => {
    haptic(15);
    setOpen(true);
    void v.start();
  };
  const hide = () => {
    v.cancel();
    setOpen(false);
  };
  const busy = v.phase !== 'idle';

  return (
    <>
      {!keyboard && !open && (
        <button type="button" onClick={show} aria-label="Talk to Escanor" className="fixed bottom-[calc(76px+env(safe-area-inset-bottom))] right-4 z-30 flex h-14 w-14 items-center justify-center rounded-full border border-line-strong bg-[#050505] shadow-elevated transition active:scale-90 md:bottom-6">
          <Logo size={38} />
        </button>
      )}

      {open && (
        <Sheet title="Escanor" onClose={hide}>
          <div className="flex flex-col items-center gap-4 pb-2 pt-1 text-center" aria-live="polite">
            <span className={`relative flex h-20 w-20 items-center justify-center rounded-full border border-line-strong bg-[#050505] ${v.phase === 'listening' ? 'ring-4 ring-primary/40' : ''}`}>
              {v.phase === 'listening' && <span aria-hidden className="absolute inset-[-8px] animate-ping rounded-full border-2 border-primary/30" />}
              <Logo size={52} />
            </span>
            <p className="flex items-center gap-2 text-sm text-muted">{v.phase === 'thinking' && <Spinner />}{LABEL[v.phase]}</p>
            {v.heard && <p className="max-w-full text-[17px] leading-snug text-ink">“{v.heard}”</p>}
            {v.reply && (
              <div className={`flex w-full items-start gap-2.5 rounded-xl border p-3.5 text-left ${v.reply.ok ? 'border-hairline bg-surface-card' : 'border-warning/30 bg-warning/5'}`}>
                {v.reply.ok ? <CheckCircle size={20} weight="fill" className="mt-0.5 shrink-0 text-success" aria-hidden /> : <WarningCircle size={20} weight="fill" className="mt-0.5 shrink-0 text-warning" aria-hidden />}
                <p className="text-[14px] leading-snug text-body-strong">{v.reply.say}</p>
              </div>
            )}
            <button type="button" onClick={busy ? v.cancel : () => void v.start()} className="flex h-14 w-14 items-center justify-center rounded-full bg-primary text-on-primary transition active:scale-90" aria-label={busy ? 'Stop' : 'Speak again'}>
              {busy ? <Stop size={24} weight="fill" /> : <Microphone size={24} weight="fill" />}
            </button>
            <p className="text-[12px] leading-relaxed text-muted">Try: “open YouTube”, “set a timer for 5 minutes”, “call 98765 43210”, “on my computer, open YouTube”, or ask anything.</p>
          </div>
        </Sheet>
      )}
    </>
  );
}
