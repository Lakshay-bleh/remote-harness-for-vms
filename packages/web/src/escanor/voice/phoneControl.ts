import type { ControlStatus } from './actions';

/**
 * Where the person is in switching on phone control, one step at a time, each asked for and none skipped:
 * - notInBuild: this download leaves phone control out (see the "with phone control" APK)
 * - disclosure: say in the app what it can see and do, and wait for "I agree" (Google Play requires this before Accessibility)
 * - restricted: Android 13+ greys the switch out for apps installed from a file until the person allows it in App info
 * - turnOn: send them to Accessibility settings to switch Escanor on themselves
 * - on: done
 */
export type ControlStep = 'checking' | 'notInBuild' | 'disclosure' | 'restricted' | 'turnOn' | 'on';

export function controlStep(status: ControlStatus | null, consented: boolean): ControlStep {
  if (!status) return 'checking';
  if (status.enabled) return 'on';
  if (status.available === false) return 'notInBuild';
  if (!consented) return 'disclosure';
  if (status.restricted === true) return 'restricted';
  return 'turnOn';
}
