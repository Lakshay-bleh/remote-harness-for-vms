import { CheckCircle, Microphone, Stop, WarningCircle, X } from '@phosphor-icons/react';
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { useHardwareBack } from '../back';
import { haptic } from '../settings/prefs';
import { Logo, Spinner, useKeyboardOpen } from '../ui';
import type { VoiceTab } from './commands';
import { loadOrb, movedFar, orbCss, ORB_SIZE, posFromPoint, saveOrb, type OrbPos, type View } from './orbPosition';
import { App as CapApp } from '@capacitor/app';
import { isNative } from '../../api';
import { deviceOrNull } from './device';
import PhoneControlSetup from './PhoneControlSetup';
import { useVoiceSession, type VoicePhase } from './useVoiceSession';
import { getVoicePrefs } from './voicePrefs';
import { wake } from './wakeWord';

export interface VoiceApi {
  /** Open voice mode and start listening. */
  open(): void;
  close(): void;
}

const VoiceContext = createContext<VoiceApi | null>(null);

/** Open Escanor's voice from anywhere (the message boxes have a button for it). Null outside the signed-in app. */
export const useVoiceMode = (): VoiceApi | null => useContext(VoiceContext);

const LABEL: Record<VoicePhase, string> = { idle: 'Tap the mic to talk', listening: 'Listening…', thinking: 'Working on it…', speaking: 'Speaking' };
const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/** What the system keeps for itself at the top and bottom of the screen, in pixels. */
function measureInsets(): { top: number; bottom: number } {
  const probe = document.createElement('div');
  probe.style.cssText = 'position:fixed;top:0;left:0;width:0;height:0;visibility:hidden;padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)';
  document.body.appendChild(probe);
  const cs = getComputedStyle(probe);
  const out = { top: parseFloat(cs.paddingTop) || 0, bottom: parseFloat(cs.paddingBottom) || 0 };
  probe.remove();
  return out;
}

const currentView = (): View => {
  const i = measureInsets();
  return { width: window.innerWidth, height: window.innerHeight, insetTop: i.top, insetBottom: i.bottom };
};

/**
 * Escanor's voice, on every screen. The Escanor mark floats where the person last put it: press and drag it anywhere, let go, and it
 * stays. A tap opens voice mode, a full screen of its own (so it never sits on top of the message box), where Escanor listens, does
 * what was said (on this phone, on a computer, or through the assistant), answers out loud, and listens again until the person
 * is done.
 */
export default function VoiceHost({ go, onAssistant, children }: { go: (tab: VoiceTab) => void; onAssistant: (text: string, signal: AbortSignal) => Promise<string | void>; children?: ReactNode }) {
  const [open, setOpen] = useState(false);
  const live = useRef(false); // a conversation is running: keep listening after each answer
  const [pos, setPos] = useState<OrbPos>(loadOrb);
  const posRef = useRef(pos);
  posRef.current = pos;
  const drag = useRef<{ sx: number; sy: number; moved: boolean } | null>(null);
  const [dragging, setDragging] = useState(false);
  const keyboard = useKeyboardOpen();

  const v = useVoiceSession({ go: (t) => { go(t); close(); }, onAssistant });
  const dev = deviceOrNull();
  // The phone-control steps open under an answer that needs them; "Not now" hides them until the next answer.
  const [setupClosed, setSetupClosed] = useState(false);
  useEffect(() => setSetupClosed(false), [v.reply]);

  const talk = useCallback(async () => {
    live.current = true;
    let quiet = 0;
    while (live.current) {
      const outcome = await v.start();
      if (!live.current) break;
      if (outcome === 'stop') return void closeRef.current(); // "stop" or "that's all": leave voice mode
      if (outcome === 'error' || outcome === 'cancelled') break;
      quiet = outcome === 'silent' ? quiet + 1 : 0;
      if (quiet >= 2) break; // nobody is talking: stop listening instead of listening forever
      await sleep(250);
    }
    live.current = false;
  }, [v.start]);
  const closeRef = useRef<() => void>(() => undefined);

  const close = useCallback(() => {
    live.current = false;
    v.cancel();
    setOpen(false);
  }, [v.cancel]);
  closeRef.current = close;

  const show = useCallback(() => {
    haptic(15);
    setOpen(true);
    void talk();
  }, [talk]);

  useHardwareBack(open, close, 3);

  // "Hey Escanor": while voice mode has the microphone the background listener steps aside, and comes back when it is closed.
  useEffect(() => {
    void wake.pause(open);
  }, [open]);
  // Heard while the app is open, or the "Hey! I'm listening" notification was tapped (escanor://voice): open voice mode.
  const showRef = useRef<() => void>(() => undefined);
  showRef.current = show;
  useEffect(() => {
    const off = wake.onHeard(() => showRef.current());
    let sub: Promise<{ remove: () => Promise<void> }> | null = null;
    if (isNative()) sub = CapApp.addListener('appUrlOpen', ({ url }) => /^escanor:\/\/voice/.test(url) && showRef.current());
    // The service ends with the phone's own housekeeping now and then: bring it back if the person left it switched on.
    if (isNative() && getVoicePrefs().wakeWord) void wake.status().then((s) => { if (s?.modelReady && !s.running && s.micAllowed) void wake.start().catch(() => undefined); });
    return () => {
      off();
      void sub?.then((x) => x.remove());
    };
  }, []);
  useEffect(() => () => void (live.current = false), []);

  const api = useMemo<VoiceApi>(() => ({ open: show, close }), [show, close]);

  // ---- the movable button
  const onDown = (e: React.PointerEvent<HTMLButtonElement>) => {
    e.currentTarget.setPointerCapture(e.pointerId);
    drag.current = { sx: e.clientX, sy: e.clientY, moved: false };
  };
  const onMove = (e: React.PointerEvent<HTMLButtonElement>) => {
    const d = drag.current;
    if (!d) return;
    if (!d.moved && movedFar(e.clientX - d.sx, e.clientY - d.sy)) {
      d.moved = true;
      setDragging(true);
      haptic(10);
    }
    if (d.moved) setPos(posFromPoint(e.clientX, e.clientY, currentView()));
  };
  const onUp = (e: React.PointerEvent<HTMLButtonElement>) => {
    const d = drag.current;
    drag.current = null;
    setDragging(false);
    if (e.currentTarget.hasPointerCapture(e.pointerId)) e.currentTarget.releasePointerCapture(e.pointerId);
    if (!d) return;
    if (d.moved) saveOrb(posRef.current);
    else show();
  };
  const onCancel = () => {
    if (drag.current?.moved) saveOrb(posRef.current);
    drag.current = null;
    setDragging(false);
  };
  const onKey = (e: React.KeyboardEvent) => {
    // Keyboard and switch users cannot drag: the arrow keys nudge it, Enter opens it.
    const step = 0.04;
    const move: Record<string, [number, number]> = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] };
    const m = move[e.key];
    if (!m) return;
    e.preventDefault();
    const next = { x: Math.min(1, Math.max(0, posRef.current.x + m[0])), y: Math.min(1, Math.max(0, posRef.current.y + m[1])) };
    setPos(next);
    saveOrb(next);
  };

  const busy = v.phase !== 'idle';
  const css = orbCss(pos);

  return (
    <VoiceContext.Provider value={api}>
      {children}

      {!keyboard && !open && (
        <button
          type="button"
          aria-label="Talk to Escanor. Drag to move this button."
          onPointerDown={onDown}
          onPointerMove={onMove}
          onPointerUp={onUp}
          onPointerCancel={onCancel}
          onKeyDown={onKey}
          onContextMenu={(e) => e.preventDefault()}
          style={{ ...css, width: ORB_SIZE, height: ORB_SIZE, touchAction: 'none' }}
          className={`fixed z-30 flex items-center justify-center rounded-full border border-line-strong bg-[#050505] shadow-elevated outline-none transition-[transform,box-shadow] duration-150 focus-visible:ring-4 focus-visible:ring-primary/40 ${dragging ? 'scale-110 shadow-[0_18px_40px_-8px_rgba(0,0,0,0.7)]' : 'active:scale-95'}`}
        >
          <Logo size={38} className="pointer-events-none" />
        </button>
      )}

      {open && (
        <div role="dialog" aria-label="Escanor voice" className="fixed inset-0 z-[55] flex flex-col bg-canvas text-ink">
          <div className="safe-top flex items-center justify-between px-4 pb-2 pt-3">
            <span className="flex items-center gap-2 text-[15px] font-medium text-ink"><Logo size={22} />Escanor</span>
            <button type="button" onClick={close} aria-label="Close voice" className="flex h-10 w-10 items-center justify-center rounded-full text-muted transition hover:bg-surface-card hover:text-ink active:scale-90"><X size={22} /></button>
          </div>

          <div className="flex min-h-0 flex-1 flex-col items-center justify-center gap-5 overflow-y-auto px-6 text-center" aria-live="polite">
            <span className="relative flex h-40 w-40 items-center justify-center">
              {v.phase === 'listening' && (
                <>
                  <span aria-hidden className="absolute inset-0 animate-ping rounded-full border-2 border-primary/30" />
                  <span aria-hidden className="absolute inset-3 animate-pulse rounded-full border border-primary/40" />
                </>
              )}
              {v.phase === 'thinking' && <span aria-hidden className="absolute inset-0 animate-spin rounded-full border-2 border-transparent border-t-primary" />}
              {v.phase === 'speaking' && <span aria-hidden className="absolute inset-2 animate-pulse rounded-full bg-primary/10" />}
              <span className={`relative flex h-28 w-28 items-center justify-center rounded-full border bg-[#050505] ${v.phase === 'listening' ? 'border-primary/60 shadow-[0_0_40px_-6px_rgb(var(--c-primary)/0.5)]' : 'border-line-strong'}`}><Logo size={76} /></span>
            </span>

            <p className="flex items-center gap-2 text-sm text-muted">{v.phase === 'thinking' && <Spinner />}{LABEL[v.phase]}</p>
            {v.heard && <p className="max-w-full text-balance text-[22px] leading-snug text-ink">“{v.heard}”</p>}
            {v.reply && (
              <div className={`flex max-h-[34svh] w-full max-w-md items-start gap-2.5 overflow-y-auto rounded-xl border p-3.5 text-left ${v.reply.ok ? 'border-hairline bg-surface-card' : 'border-warning/30 bg-warning/5'}`}>
                {v.reply.ok ? <CheckCircle size={20} weight="fill" className="mt-0.5 shrink-0 text-success" aria-hidden /> : <WarningCircle size={20} weight="fill" className="mt-0.5 shrink-0 text-warning" aria-hidden />}
                <p className="whitespace-pre-wrap text-[14px] leading-snug text-body-strong">{v.reply.say}</p>
              </div>
            )}
            {v.reply?.needs === 'accessibility' && !setupClosed && dev && (
              <div className="w-full max-w-md overflow-y-auto rounded-xl border border-hairline bg-surface-card text-left">
                <PhoneControlSetup dev={dev} onDismiss={() => setSetupClosed(true)} />
              </div>
            )}
            {!v.heard && !v.reply && <p className="max-w-xs text-[13px] leading-relaxed text-muted">Try “open YouTube”, “set a timer for 5 minutes”, “call Mom”, “on my computer, show my containers”, or ask anything.</p>}
          </div>

          <div className="safe-bottom flex flex-col items-center gap-2 pb-6 pt-3">
            <button
              type="button"
              onClick={busy || live.current ? () => { live.current = false; v.cancel(); } : () => void talk()}
              aria-label={busy ? 'Stop' : 'Talk'}
              className={`flex h-[72px] w-[72px] items-center justify-center rounded-full text-on-primary transition active:scale-90 ${busy ? 'bg-surface-card text-ink' : 'bg-primary'}`}
            >
              {busy ? <Stop size={28} weight="fill" /> : <Microphone size={30} weight="fill" />}
            </button>
            <span className="text-[12px] text-muted">{busy ? 'Tap to stop' : 'Tap to talk'}</span>
          </div>
        </div>
      )}
    </VoiceContext.Provider>
  );
}
