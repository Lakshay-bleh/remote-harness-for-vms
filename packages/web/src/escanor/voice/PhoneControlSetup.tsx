import { useCallback, useEffect, useState } from 'react';
import LegalSheet from '../../legal/LegalSheet';
import { Button, Spinner } from '../ui';
import type { ControlStatus, DevicePlugin } from './actions';
import { flushControlConsent, setControlConsent } from './controlConsent';
import { controlStep } from './phoneControl';
import { useVoicePrefs } from './voicePrefs';

/** What phone control can see and do, said in the app before Android is ever opened. Google Play calls this the prominent disclosure. */
const CAN_DO = [
  'Go home or back, open recent apps, notifications or quick settings, lock the screen and take a screenshot',
  'Scroll, tap a button by its name, and type into the box you are in',
  'Read the words on your screen, only when you ask “what is on my screen”',
];

/**
 * Switching on phone control, one step at a time and each one asked for: what it does and "I agree", then (for an app installed
 * from a file on Android 13+) allowing the restricted setting in App info, then switching Escanor on in Accessibility settings.
 * Android lets only the person do the last two; this says exactly where to tap and checks again when they come back.
 */
export default function PhoneControlSetup({ dev, onStatus, onDismiss }: { dev: DevicePlugin; onStatus?: (s: ControlStatus) => void; onDismiss?: () => void }) {
  const prefs = useVoicePrefs();
  const [status, setStatus] = useState<ControlStatus | null>(null);
  // Which of the restricted-setting steps the person has done (Android does not say when it has been allowed).
  const [done, setDone] = useState(0);
  const [policy, setPolicy] = useState(false);

  // A choice made while offline or signed out reaches the consent ledger the next time this opens.
  useEffect(() => void flushControlConsent(), []);

  const refresh = useCallback(async () => {
    const s = await dev.controlStatus().catch((): ControlStatus => ({ enabled: false, available: true, restricted: null }));
    setStatus(s);
    onStatus?.(s);
  }, [dev, onStatus]);

  // The person leaves for Android's settings to switch something on: look again when they come back.
  useEffect(() => {
    void refresh();
    const onVisible = () => document.visibilityState === 'visible' && void refresh();
    document.addEventListener('visibilitychange', onVisible);
    return () => document.removeEventListener('visibilitychange', onVisible);
  }, [refresh]);

  const step = controlStep(status, prefs.controlConsent);
  const text = 'text-[13px] leading-relaxed text-body';

  if (step === 'checking') return <div className="flex justify-center px-3.5 py-3"><Spinner /></div>;

  if (step === 'on') {
    return (
      <div className="px-3.5 py-3">
        <p className={`mb-2 ${text}`}>Phone control is on. To switch it off, turn off <b className="text-ink">Escanor</b> in Accessibility settings.</p>
        <Button kind="quiet" onClick={() => void dev.openControlSettings()} className="w-full">Open Accessibility settings</Button>
      </div>
    );
  }

  if (step === 'notInBuild') {
    return (
      <p className={`px-3.5 py-3 ${text}`}>
        This download of Escanor leaves phone control out, because Android’s Play Protect blocks downloaded apps that include it. To use it, install the <b className="text-ink">“with phone control”</b> APK from the Escanor release page.
      </p>
    );
  }

  if (step === 'disclosure') {
    return (
      <div className="space-y-2.5 px-3.5 py-3">
        <p className={`font-medium text-ink ${text}`}>Escanor uses Android’s Accessibility service to do these things for you:</p>
        <ul className={`list-disc space-y-1 pl-5 ${text}`}>{CAN_DO.map((c) => <li key={c}>{c}</li>)}</ul>
        <p className={text}>
          It acts only when you ask, by voice or in the app, and never on its own. To find a button or read the screen, it looks at the words on the screen at that moment. That text stays on this phone: it is shown and read aloud to you, and not stored or sent to Escanor’s servers. Escanor does not use it for ads or anything else.
        </p>
        <p className={text}>
          You can switch it off any time in Android’s Accessibility settings. Your choice is recorded in your account. More in the{' '}
          <button type="button" onClick={() => setPolicy(true)} className="text-ink underline">privacy policy</button>.
        </p>
        {policy && <LegalSheet start="privacy" onClose={() => setPolicy(false)} />}
        <div className="flex gap-2 pt-1">
          <Button onClick={() => void setControlConsent(true)} className="flex-1">I agree</Button>
          {onDismiss && <Button kind="quiet" onClick={onDismiss} className="flex-1">Not now</Button>}
        </div>
      </div>
    );
  }

  const withdraw = <button type="button" onClick={() => void setControlConsent(false)} className="w-full pt-1 text-center text-[12px] text-muted underline">I changed my mind</button>;

  if (step === 'restricted') {
    return (
      <div className="space-y-2.5 px-3.5 py-3">
        <p className={text}>Escanor was installed from a downloaded file, so Android greys its switch out (“Controlled by restricted setting”) until you allow it. Only you can do that:</p>
        <ol className={`list-decimal space-y-1 pl-5 ${text}`}>
          <li>Open Accessibility settings and tap <b className="text-ink">Escanor</b>. Android says “App was denied access”: tap <b className="text-ink">Close</b>. (Android shows the next option only after this.)</li>
          <li>Open Escanor’s App info, tap <b className="text-ink">⋮</b> at the top right, then <b className="text-ink">Allow restricted settings</b>, and confirm with your PIN or fingerprint.</li>
          <li>Open Accessibility settings again and switch Escanor on. (Allowed it before? Go straight to this step.)</li>
        </ol>
        <Button kind={done === 0 ? 'primary' : 'quiet'} onClick={() => { setDone(Math.max(done, 1)); void dev.openControlSettings(); }} className="w-full">1. Try it in Accessibility settings</Button>
        <Button kind={done === 1 ? 'primary' : 'quiet'} onClick={() => { setDone(Math.max(done, 2)); void dev.openAppInfo(); }} className="w-full">2. Allow restricted settings in App info</Button>
        <Button kind={done === 2 ? 'primary' : 'quiet'} onClick={() => void dev.openControlSettings()} className="w-full">3. Switch Escanor on</Button>
        {withdraw}
      </div>
    );
  }

  return (
    <div className="space-y-2.5 px-3.5 py-3">
      <p className={text}>In the next screen, find <b className="text-ink">Escanor</b>, tap it and switch it on. Android then shows its own warning, which it shows for every app that can press buttons for you.</p>
      <Button onClick={() => void dev.openControlSettings()} className="w-full">Open Accessibility settings</Button>
      <p className="text-[12px] leading-relaxed text-muted">
        Greyed out, “Controlled by restricted setting”? Open <button type="button" onClick={() => void dev.openAppInfo()} className="text-ink underline">Escanor’s App info</button>, tap ⋮ at the top right, then Allow restricted settings.
      </p>
      {withdraw}
    </div>
  );
}
