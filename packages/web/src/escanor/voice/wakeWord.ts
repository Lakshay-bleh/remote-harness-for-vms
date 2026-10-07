import { isAndroid } from '../../api';
import { Device } from './device';

export interface WakeStatus {
  running: boolean;
  modelReady: boolean;
  downloading: boolean;
  micAllowed: boolean;
  /** Phone control is on, and with it Android lets the app open itself from another app or the home screen. */
  opensDirectly?: boolean;
  /** This build can use full-screen notifications at all (the normal download leaves them out). */
  fullScreenDeclared?: boolean;
  /** "Full-screen notifications" (Android 14+): lets the notification take over a locked or idle screen. */
  fullScreenAllowed?: boolean;
}

/**
 * How "Hey Escanor" gets the app on screen when it is heard outside the app, in a sentence, and what could be switched on to improve
 * it. Escanor never draws over other apps (payment apps refuse to run next to one that can), so outside the app it is a notification
 * unless phone control is on.
 */
export function outsideApp(s: WakeStatus | null): { line: string; best: boolean; canAllowFullScreen: boolean } {
  const canAllowFullScreen = s?.fullScreenDeclared === true && s.fullScreenAllowed === false;
  if (s?.opensDirectly) return { line: 'Escanor opens straight away, from any app or the home screen.', best: true, canAllowFullScreen: false };
  return {
    line: canAllowFullScreen
      ? 'Escanor shows a “Hey! I’m listening” notification: tap it. Allow “Full-screen notifications” so it also shows on a locked screen.'
      : 'Escanor shows a “Hey! I’m listening” notification: tap it. With phone control on, it opens straight away.',
    best: false,
    canAllowFullScreen,
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
