import { Gauge, ShieldCheck, Sparkle, Vibrate } from '@phosphor-icons/react';
import { useState } from 'react';
import { EFFORTS, MODELS, PERMISSION_MODES, setPrefs, TEXT_SIZE_PERCENT, usePrefs, type Prefs } from './prefs';
import { ChoiceSheet, Group, Page, Row, SwitchRow } from './parts';

const SIZES: Array<{ value: Prefs['textSize']; label: string }> = [
  { value: 'small', label: 'Small' },
  { value: 'default', label: 'Default' },
  { value: 'large', label: 'Large' },
];

/** How the app looks and feels on this phone. Stored on the phone, since a tablet may want something different. */
export function AppearancePage({ onBack }: { onBack: () => void }) {
  const p = usePrefs();
  return (
    <Page title="Appearance and feel" onBack={onBack}>
      <section>
        <h2 className="mb-1.5 px-1 text-[12px] font-medium uppercase tracking-wide text-muted">Text size</h2>
        <div role="radiogroup" aria-label="Text size" className="grid grid-cols-3 gap-1 rounded-xl border border-hairline bg-surface-card p-1">
          {SIZES.map((s) => (
            <button key={s.value} type="button" role="radio" aria-checked={p.textSize === s.value} onClick={() => setPrefs({ textSize: s.value })} className={`rounded-lg py-2.5 text-sm transition ${p.textSize === s.value ? 'bg-canvas font-medium text-ink shadow' : 'text-body'}`}>
              {s.label}
            </button>
          ))}
        </div>
        <div className="mt-3 rounded-xl border border-hairline bg-surface-card p-4">
          <p className="text-[15px] leading-relaxed text-body-strong">The assistant’s answers will look like this. Everything in the app scales with it, from {TEXT_SIZE_PERCENT.small}% to {TEXT_SIZE_PERCENT.large}%.</p>
        </div>
      </section>
      <Group title="Feel" footer="A short tap when you press a button, switch a setting or approve something. Needs a phone with a vibration motor.">
        <SwitchRow icon={<Vibrate size={18} />} label="Haptic feedback" on={p.haptics} onChange={(v) => setPrefs({ haptics: v })} />
      </Group>
    </Page>
  );
}

type Picker = 'mode' | 'model' | 'effort' | null;

/** What a new chat on one of your machines starts with. You can still change it inside the chat. */
export function ChatDefaultsPage({ onBack }: { onBack: () => void }) {
  const p = usePrefs();
  const [picker, setPicker] = useState<Picker>(null);
  const label = <T extends string>(list: ReadonlyArray<{ value: T; label: string }>, v: string) => list.find((o) => o.value === v)?.label ?? v;

  return (
    <Page title="New chats" onBack={onBack}>
      <Group title="Defaults for machine chats" footer="Applies to chats you start on your machines. The assistant on the Chat tab manages these itself.">
        <Row icon={<ShieldCheck size={18} />} label="Permissions" sub={PERMISSION_MODES.find((m) => m.value === p.defaultMode)?.hint} value={label(PERMISSION_MODES, p.defaultMode)} onClick={() => setPicker('mode')} />
        <Row icon={<Sparkle size={18} />} label="Model" value={label(MODELS, p.defaultModel)} onClick={() => setPicker('model')} />
        <Row icon={<Gauge size={18} />} label="Effort" value={label(EFFORTS, p.defaultEffort)} onClick={() => setPicker('effort')} />
      </Group>
      {picker === 'mode' && <ChoiceSheet title="Permissions" options={PERMISSION_MODES} value={p.defaultMode as (typeof PERMISSION_MODES)[number]['value']} onPick={(v) => setPrefs({ defaultMode: v })} onClose={() => setPicker(null)} />}
      {picker === 'model' && <ChoiceSheet title="Model" options={MODELS} value={p.defaultModel as (typeof MODELS)[number]['value']} onPick={(v) => setPrefs({ defaultModel: v })} onClose={() => setPicker(null)} />}
      {picker === 'effort' && <ChoiceSheet title="Effort" options={EFFORTS} value={p.defaultEffort as (typeof EFFORTS)[number]['value']} onPick={(v) => setPrefs({ defaultEffort: v })} onClose={() => setPicker(null)} />}
    </Page>
  );
}
