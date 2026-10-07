import { AppWindow, Download, HandPointing, Microphone, Phone, ShieldCheck, Waveform } from '@phosphor-icons/react';
import { useCallback, useEffect, useState } from 'react';
import { isAndroid, isIOS, isNative } from '../../api';
import { Button, Notice, Spinner } from '../ui';
import type { ControlStatus } from '../voice/actions';
import { deviceOrNull } from '../voice/device';
import PhoneControlSetup from '../voice/PhoneControlSetup';
import { outsideApp, wake, wakeStep, type WakeStatus } from '../voice/wakeWord';
import { setVoicePrefs, useVoicePrefs } from '../voice/voicePrefs';
import { Group, Page, Row, SwitchRow } from './parts';

/**
 * Everything about talking to Escanor and letting it use the phone: "Hey Escanor", calling, and controlling the phone (home, back,
 * scrolling, tapping). Each permission is explained here, in plain words, before Android asks for it, and each can be switched off.
 */
export default function VoicePage({ onBack }: { onBack: () => void }) {
  const dev = deviceOrNull();
  const prefs = useVoicePrefs();
  const [control, setControl] = useState<ControlStatus | null>(null);
  const [call, setCall] = useState<{ granted: boolean; available?: boolean } | null>(null);
  const [status, setStatus] = useState<WakeStatus | null>(null);
  const [progress, setProgress] = useState<number | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(async () => {
    if (!dev) return;
    setCall(await dev.callStatus().catch(() => ({ granted: false })));
    setStatus(await wake.status());
  }, [dev]);

  // The person leaves for Android's settings to switch something on: look again when they come back.
  useEffect(() => {
    void refresh();
    const onVisible = () => document.visibilityState === 'visible' && void refresh();
    document.addEventListener('visibilitychange', onVisible);
    return () => document.removeEventListener('visibilitychange', onVisible);
  }, [refresh]);

  const step = wakeStep(status);
  const outside = outsideApp(status);

  const turnWakeOn = async () => {
    setNote(null);
    setBusy(true);
    try {
      let s = status;
      if (wakeStep(s) === 'download') {
        setProgress(0);
        const r = await wake.download(setProgress);
        setProgress(null);
        if (!r.ok) return setNote(r.message ?? 'Could not download the voice model.');
        s = await wake.status();
        setStatus(s);
      }
      if (wakeStep(s) === 'microphone') {
        // Android asks the first time voice is used; if it was refused, only Android's settings can change it.
        return setNote('Escanor needs the microphone for this. Open Android Settings, then Apps, Escanor, Permissions, and allow Microphone. Then switch this on again.');
      }
      const r = await wake.start();
      if (!r.ok) return setNote(r.message ?? 'Could not start listening.');
      setVoicePrefs({ wakeWord: true });
      setStatus(await wake.status());
    } finally {
      setBusy(false);
    }
  };

  const turnWakeOff = async () => {
    await wake.stop();
    setVoicePrefs({ wakeWord: false });
    setStatus(await wake.status());
  };

  return (
    <Page title="Voice and phone control" subtitle="Talk to Escanor and let it use your phone" onBack={onBack}>
      {!isNative() && <Notice>These work in the Escanor phone app. You can look at what each one does here.</Notice>}
      {isIOS() && <Notice>iOS does not let an app listen for “Hey Escanor” in the background or press buttons in other apps, so those two are Android only. Talking to Escanor with the microphone button, calling, torch and opening websites work here.</Notice>}

      {!isIOS() && <Group title="Hey Escanor" footer="Escanor listens for the two words on this phone only, using a small voice model. Nothing is recorded or sent anywhere. A notification shows while it is listening, and it uses a little battery. Switch it off any time.">
        <SwitchRow
          icon={<Waveform size={18} />}
          label="Say “Hey Escanor”"
          on={prefs.wakeWord && step === 'listening'}
          disabled={!dev || busy}
          onChange={(v) => void (v ? turnWakeOn() : turnWakeOff())}
        />
        {step === 'download' && <Row icon={<Download size={18} />} label="One-time download" sub="About 40 MB of voice model, fetched over a secure connection when you switch this on." chevron={false} />}
        {progress !== null && <Row label={`Downloading… ${progress}%`} right={<Spinner />} chevron={false} />}
        {step === 'microphone' && <Row icon={<Microphone size={18} />} label="Microphone needed" sub="Allow it in Android Settings, Apps, Escanor, Permissions." chevron={false} />}
        {step === 'listening' && <Row label="Listening now" sub="Say “Hey Escanor” and then what you want." chevron={false} />}
      </Group>}

      {isAndroid() && (step === 'listening' || step === 'ready') && (
        <Group title="From other apps and the home screen" footer="Android does not let an app open itself from the background. Escanor never draws over other apps, so payment and banking apps keep working.">
          <Row icon={<AppWindow size={18} />} label="Open Escanor when it hears you" sub={outside.line} chevron={false} />
          {outside.canAllowFullScreen && <Row label="Full-screen notifications" value="Not allowed" sub="Lets the notification take over a locked or idle screen." onClick={() => void wake.openFullScreenSettings()} />}
          <Row label="Try it" sub="Tap, then press Home or open another app. In six seconds Escanor acts as though you had said it." onClick={() => void wake.test().then(() => setNote('Press Home now. Escanor will open in a few seconds.'))} />
        </Group>
      )}
      {note && <Notice tone="warn">{note}</Notice>}

      {!isIOS() && <Group
        title="Control your phone"
        footer="Escanor asks before each step. Android requires you to switch this on yourself, in its Accessibility settings. Payment and banking apps do not run while it is on, so Escanor switches it off by itself when you open one and leaves a notification to switch it back on."
      >
        <Row
          icon={<HandPointing size={18} />}
          label="Phone control"
          sub={control?.enabled ? 'Try: “go home”, “scroll down”, “tap Send”.' : 'Go home or back, scroll, tap and type when you ask.'}
          value={dev && !control ? <Spinner /> : control?.enabled ? 'On' : 'Off'}
          chevron={false}
        />
        {dev && <PhoneControlSetup dev={dev} onStatus={setControl} />}
      </Group>}

      {!isIOS() && call?.available === false && <Group title="Calling" footer="“Call Mom” opens the dialer with the number filled in, and you press call. Escanor does not ask for the Phone permission in this download, so it installs without warnings.">
        <Row icon={<Phone size={18} />} label="Calls open the dialer" chevron={false} />
      </Group>}
      {!isIOS() && call?.available !== false && <Group title="Calling" footer="With this on, “call Mom” rings straight away. Off, Escanor opens the dialer with the number filled in and you press call. Android asks for the Phone permission the first time.">
        <SwitchRow icon={<Phone size={18} />} label="Call directly" on={prefs.directCalls} onChange={(v) => setVoicePrefs({ directCalls: v })} />
        <Row
          icon={<ShieldCheck size={18} />}
          label="Phone permission"
          value={call === null ? <Spinner /> : call.granted ? 'Allowed' : 'Not allowed'}
          onClick={call && !call.granted && dev ? () => void dev.requestCallPermission().then(refresh) : undefined}
          sub={call && !call.granted ? 'Tap to allow Escanor to place calls.' : undefined}
          chevron={false}
        />
      </Group>}
    </Page>
  );
}
