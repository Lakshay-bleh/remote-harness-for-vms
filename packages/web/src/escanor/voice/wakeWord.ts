import { isAndroid } from '../../api';
import { Device } from './device';

export interface WakeStatus {
  running: boolean;
  modelReady: boolean;
  downloading: boolean;
  micAllowed: boolean;
  /** "Display over other apps": lets the app open itself from another app or the home screen. */
  overlayAllowed?: boolean;
  /** "Full-screen notifications" (Android 14+): lets the notification take over a locked or idle screen. */
  fullScreenAllowed?: boolean;
}

/** How "Hey Escanor" gets the app on screen when it is heard outside the app, in a sentence, and what could be switched on to improve it. */
export function outsideApp(s: WakeStatus | null): { line: string; best: boolean; canAllowOverlay: boolean; canAllowFullScreen: boolean } {
  const overlay = s?.overlayAllowed === true;
  const full = s?.fullScreenAllowed !== false;
  if (overlay) return { line: 'Escanor opens straight away, from any app or the home screen.', best: true, canAllowOverlay: false, canAllowFullScreen: !full };
  return {
    line: full ? 'Escanor shows a “Hey! I’m listening” notification: tap it. Allow “Display over other apps” to open straight away.' : 'Escanor shows a “Hey! I’m listening” notification: tap it. Allow “Display over other apps” and “Full-screen notifications” to open straight away.',
    best: false,
    canAllowOverlay: true,
    canAllowFullScreen: !full,
  };
}

/** What the person sees while turning "Hey Escanor" on, in order: a sentence for each thing that can be in the way. */
export type WakeStep = 'unsupported' | 'download' | 'microphone' | 'ready' | 'listening';

export function wakeStep(s: WakeStatus | null, native = isAndroid()): WakeStep {
  if (!native || !s) return 'unsupported';
  if (s.running) return 'listening';
  if (!s.modelReady) return 'download';
  if (!s.micAllowed) return 'microphone';
  return 'ready';
}

export const wake = {
  status: (): Promise<WakeStatus | null> => (isAndroid() ? Device.wakeStatus().catch(() => null) : Promise.resolve(null)),
  download: (onProgress: (percent: number) => void): Promise<{ ok: boolean; message?: string }> => {
    const sub = Device.addListener('wakeModelProgress', (e: { percent: number }) => onProgress(e.percent));
    return Device.wakeDownloadModel().finally(() => void sub.then((s) => s.remove()));
  },
  start: () => Device.wakeStart(),
  stop: () => Device.wakeStop(),
  /** Voice mode has the microphone while it is open. */
  pause: (paused: boolean) => (isAndroid() ? Device.wakePause({ paused }).catch(() => undefined) : Promise.resolve(undefined)),
  deleteModel: () => Device.wakeDeleteModel(),
  openOverlaySettings: () => Device.wakeOpenOverlaySettings(),
  openFullScreenSettings: () => Device.wakeOpenFullScreenSettings(),
  /** Act as though the phrase was heard in six seconds, so it can be tried from another app. */
  test: () => Device.wakeTest(),
  /** Called when "Hey Escanor" is heard while the app is open. Returns how to stop listening for it. */
  onHeard: (cb: () => void): (() => void) => {
    if (!isAndroid()) return () => undefined;
    const sub = Device.addListener('wake', cb);
    return () => void sub.then((s) => s.remove());
  },
};
