import { Download, HandPointing, Microphone, Phone, ShieldCheck, Waveform } from '@phosphor-icons/react';
import { useCallback, useEffect, useState } from 'react';
import { isNative } from '../../api';
import { Button, Notice, Spinner } from '../ui';
import { deviceOrNull } from '../voice/device';
import { wake, wakeStep, type WakeStatus } from '../voice/wakeWord';
import { setVoicePrefs, useVoicePrefs } from '../voice/voicePrefs';
import { Group, Page, Row, SwitchRow } from './parts';

/**
 * Everything about talking to Escanor and letting it use the phone: "Hey Escanor", calling, and controlling the phone (home, back,
 * scrolling, tapping). Each permission is explained here, in plain words, before Android asks for it, and each can be switched off.
 */
export default function VoicePage({ onBack }: { onBack: () => void }) {
  const dev = deviceOrNull();
  const prefs = useVoicePrefs();
  const [control, setControl] = useState<boolean | null>(null);
  const [controlBuilt, setControlBuilt] = useState(true);
  const [call, setCall] = useState<boolean | null>(null);
  const [status, setStatus] = useState<WakeStatus | null>(null);
  const [progress, setProgress] = useState<number | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(async () => {
    if (!dev) return;
    const c = await dev.controlStatus().catch(() => ({ enabled: false, available: true }));
    setControl(c.enabled);
    setControlBuilt(c.available !== false);
    setCall((await dev.callStatus().catch(() => ({ granted: false }))).granted);
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
      {!isNative() && <Notice>These work in the Escanor Android app. You can look at what each one does here.</Notice>}

      <Group title="Hey Escanor" footer="Escanor listens for the two words on this phone only, using a small voice model. Nothing is recorded or sent anywhere. A notification shows while it is listening, and it uses a little battery. Switch it off any time.">
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
      </Group>
      {note && <Notice tone="warn">{note}</Notice>}

      <Group
        title="Control your phone"
        footer="Escanor can then go home or back, open your notifications, scroll, tap a button by its name and type, but only when you ask. It never does anything on its own, and it reads what is on your screen only when you ask “what is on my screen”. Android requires you to switch this on yourself, in its Accessibility settings."
      >
        <Row
          icon={<HandPointing size={18} />}
          label="Phone control"
          sub={!controlBuilt ? 'Not in this download. See below.' : control ? 'On. Try: “go home”, “scroll down”, “tap Send”.' : 'Off. Turn it on in Android’s Accessibility settings.'}
          value={control === null ? <Spinner /> : control ? 'On' : 'Off'}
          chevron={false}
        />
        {!controlBuilt && dev && (
          <div className="px-3.5 py-3 text-[13px] leading-relaxed text-body">
            Android’s Play Protect blocks apps installed from outside the Play Store when they ask to control the phone, so the normal Escanor download leaves this out. If you want it, install the <b className="text-ink">“with phone control”</b> APK from the Escanor release page (Play Protect may warn: choose “Install anyway”).
          </div>
        )}
        {controlBuilt && !control && dev && (
          <div className="px-3.5 py-3">
            <p className="mb-2 text-[13px] leading-relaxed text-body">In the next screen, find <b className="text-ink">Escanor</b>, tap it and switch it on. Android shows a warning that is normal for any app that can press buttons for you.</p>
            <Button onClick={() => void dev.openControlSettings()} className="w-full">Open Accessibility settings</Button>
          </div>
        )}
      </Group>

      <Group title="Calling" footer="With this on, “call Mom” rings straight away. Off, Escanor opens the dialer with the number filled in and you press call. Android asks for the Phone permission the first time.">
        <SwitchRow icon={<Phone size={18} />} label="Call directly" on={prefs.directCalls} onChange={(v) => setVoicePrefs({ directCalls: v })} />
        <Row
          icon={<ShieldCheck size={18} />}
          label="Phone permission"
          value={call === null ? <Spinner /> : call ? 'Allowed' : 'Not allowed'}
          onClick={!call && dev ? () => void dev.requestCallPermission().then(refresh) : undefined}
          sub={!call ? 'Tap to allow Escanor to place calls.' : undefined}
          chevron={false}
        />
      </Group>
    </Page>
  );
}
