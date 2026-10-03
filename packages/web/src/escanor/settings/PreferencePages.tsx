import { Gauge, Moon, PlayCircle, ShieldCheck, Sparkle, Vibrate } from '@phosphor-icons/react';
import { useState } from 'react';
import { EFFORTS, MODELS, PERMISSION_MODES, setPrefs, START_TABS, TEXT_SIZE_PERCENT, usePrefs, type Prefs } from './prefs';
import { ACCENT_NAMES, ACCENTS, THEMES, type ThemeChoice } from './theme';
import { ChoiceSheet, Group, Page, Row, SwitchRow } from './parts';

const SIZES: Array<{ value: Prefs['textSize']; label: string }> = [
  { value: 'small', label: 'Small' },
  { value: 'default', label: 'Default' },
  { value: 'large', label: 'Large' },
];

/** Little previews of each theme: page, card and text colours, so the choice can be seen before it is made. */
const SWATCH: Record<Exclude<ThemeChoice, 'system'>, { page: string; card: string; ink: string; line: string }> = {
  dark: { page: '#050505', card: '#151513', ink: '#f3f1ec', line: '#3e3c37' },
  light: { page: '#faf8f4', card: '#ffffff', ink: '#1c1a16', line: '#cdc5b7' },
  black: { page: '#000000', card: '#0e0e0d', ink: '#f3f1ec', line: '#343432' },
};

function ThemeCard({ value, label, active, onPick }: { value: ThemeChoice; label: string; active: boolean; onPick: () => void }) {
  const s = value === 'system' ? null : SWATCH[value];
  return (
    <button type="button" role="radio" aria-checked={active} onClick={onPick} className={`overflow-hidden rounded-xl border text-left transition active:scale-[0.98] ${active ? 'border-primary ring-2 ring-primary/30' : 'border-hairline'}`}>
      <span aria-hidden className="flex h-16" style={s ? { background: s.page } : undefined}>
        {s ? (
          <span className="m-2.5 flex-1 rounded-md border p-1.5" style={{ background: s.card, borderColor: s.line }}>
            <span className="block h-1.5 w-8 rounded-full" style={{ background: s.ink }} />
            <span className="mt-1 block h-1.5 w-12 rounded-full opacity-40" style={{ background: s.ink }} />
          </span>
        ) : (
          <>
            <span className="flex-1" style={{ background: SWATCH.light.page }} />
            <span className="flex-1" style={{ background: SWATCH.dark.page }} />
          </>
        )}
      </span>
      <span className="block bg-surface-card px-3 py-2 text-[13px] text-ink">{label}</span>
    </button>
  );
}

/** How the app looks and feels on this phone. Stored on the phone, since a tablet may want something different. */
export function AppearancePage({ onBack }: { onBack: () => void }) {
  const p = usePrefs();
  const [picker, setPicker] = useState<'start' | null>(null);
  return (
    <Page title="Appearance and feel" onBack={onBack}>
      <section>
        <h2 className="mb-1.5 px-1 text-[12px] font-medium uppercase tracking-wide text-muted">Theme</h2>
        <div role="radiogroup" aria-label="Theme" className="grid grid-cols-2 gap-2">
          {THEMES.map((t) => <ThemeCard key={t.value} value={t.value} label={t.label} active={p.theme === t.value} onPick={() => setPrefs({ theme: t.value })} />)}
        </div>
        <p className="mt-1.5 px-1 text-[12px] leading-relaxed text-muted">{THEMES.find((t) => t.value === p.theme)?.hint}</p>
      </section>

      <section>
        <h2 className="mb-1.5 px-1 text-[12px] font-medium uppercase tracking-wide text-muted">Accent colour</h2>
        <div role="radiogroup" aria-label="Accent colour" className="flex flex-wrap gap-3 rounded-xl border border-hairline bg-surface-card p-3.5">
          {ACCENT_NAMES.map((name) => {
            const [r, g, b] = ACCENTS[name].dark;
            const on = p.accent === name;
            return (
              <button key={name} type="button" role="radio" aria-checked={on} aria-label={ACCENTS[name].label} onClick={() => setPrefs({ accent: name })} className={`flex h-11 w-11 items-center justify-center rounded-full transition active:scale-90 ${on ? 'ring-2 ring-ink ring-offset-2 ring-offset-surface-card' : ''}`} style={{ background: `rgb(${r} ${g} ${b})` }}>
                {on && <span className="h-2.5 w-2.5 rounded-full bg-white/90 shadow" />}
              </button>
            );
          })}
        </div>
      </section>

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

      <Group title="Feel" footer="Haptics give a short tap when you press a button, switch a setting or approve something (needs a vibration motor). Reduce motion turns off sliding and fading.">
        <SwitchRow icon={<Vibrate size={18} />} label="Haptic feedback" on={p.haptics} onChange={(v) => setPrefs({ haptics: v })} />
        <SwitchRow icon={<PlayCircle size={18} />} label="Reduce motion" on={p.reduceMotion} onChange={(v) => setPrefs({ reduceMotion: v })} />
        <Row icon={<Moon size={18} />} label="Open the app on" value={START_TABS.find((s) => s.value === p.startTab)?.label} onClick={() => setPicker('start')} />
      </Group>
      {picker === 'start' && <ChoiceSheet title="Open the app on" options={START_TABS} value={p.startTab} onPick={(v) => setPrefs({ startTab: v })} onClose={() => setPicker(null)} />}
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
