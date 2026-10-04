import { isNative } from '../../api';
import { Device } from './device';

export interface WakeStatus {
  running: boolean;
  modelReady: boolean;
  downloading: boolean;
  micAllowed: boolean;
}

/** What the person sees while turning "Hey Escanor" on, in order: a sentence for each thing that can be in the way. */
export type WakeStep = 'unsupported' | 'download' | 'microphone' | 'ready' | 'listening';

export function wakeStep(s: WakeStatus | null, native = isNative()): WakeStep {
  if (!native || !s) return 'unsupported';
  if (s.running) return 'listening';
  if (!s.modelReady) return 'download';
  if (!s.micAllowed) return 'microphone';
  return 'ready';
}

export const wake = {
  status: (): Promise<WakeStatus | null> => (isNative() ? Device.wakeStatus().catch(() => null) : Promise.resolve(null)),
  download: (onProgress: (percent: number) => void): Promise<{ ok: boolean; message?: string }> => {
    const sub = Device.addListener('wakeModelProgress', (e: { percent: number }) => onProgress(e.percent));
    return Device.wakeDownloadModel().finally(() => void sub.then((s) => s.remove()));
  },
  start: () => Device.wakeStart(),
  stop: () => Device.wakeStop(),
  /** Voice mode has the microphone while it is open. */
  pause: (paused: boolean) => (isNative() ? Device.wakePause({ paused }).catch(() => undefined) : Promise.resolve(undefined)),
  deleteModel: () => Device.wakeDeleteModel(),
  /** Called when "Hey Escanor" is heard while the app is open. Returns how to stop listening for it. */
  onHeard: (cb: () => void): (() => void) => {
    if (!isNative()) return () => undefined;
    const sub = Device.addListener('wake', cb);
    return () => void sub.then((s) => s.remove());
  },
};
