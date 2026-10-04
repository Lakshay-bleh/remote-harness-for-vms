import { CheckCircle } from '@phosphor-icons/react';
import { useState } from 'react';
import { ANIMALS, animalInfo, type Animal } from '../dog/animals';
import { setCompanion, useCompanion } from '../dog/companion';
import PixelDog from '../dog/PixelDog';
import { SCENES, type Scene } from '../dog/sprites';
import { Page } from './parts';

const SCENE_LABEL: Record<Scene, string> = { run: 'Loading', sniff: 'Looking up', dig: 'Digging', sit: 'All clear', sleep: 'Waiting', lick: 'Say something' };

/** Pick the animal that keeps you company on every empty and loading screen. */
export default function CompanionPage({ onBack }: { onBack: () => void }) {
  const chosen = useCompanion();
  const [scene, setScene] = useState<Scene>('sit');
  const info = animalInfo(chosen);

  return (
    <Page title="Companion" subtitle="Who keeps you company" onBack={onBack}>
      <section className="rounded-xl border border-hairline bg-surface-card p-4 text-center" aria-label="Preview">
        <div className="flex justify-center"><PixelDog animal={chosen} scene={scene} scale={7} /></div>
        <h2 className="mt-2 font-display text-2xl text-ink">{info.name} the {info.kind.toLowerCase()}</h2>
        <p className="text-[13.5px] text-muted">{info.blurb}</p>
        <div className="mt-3 flex flex-wrap justify-center gap-1.5" role="group" aria-label="Scene to preview">
          {SCENES.map((s) => (
            <button key={s} type="button" aria-pressed={scene === s} onClick={() => setScene(s)} className={`rounded-pill border px-3 py-1 text-[12.5px] ${scene === s ? 'border-primary bg-primary/10 text-primary' : 'border-hairline text-body'}`}>{SCENE_LABEL[s]}</button>
          ))}
        </div>
      </section>

      <ul className="grid grid-cols-2 gap-3" aria-label="Choose a companion">
        {ANIMALS.map((a) => {
          const on = a.id === chosen;
          return (
            <li key={a.id}>
              <button type="button" aria-pressed={on} onClick={() => setCompanion(a.id as Animal)} className={`relative flex w-full flex-col items-center rounded-xl border bg-surface-card p-3 text-center transition active:scale-[0.98] ${on ? 'border-primary ring-2 ring-primary/30' : 'border-hairline'}`}>
                {on && <CheckCircle size={20} weight="fill" className="absolute right-2 top-2 text-primary" aria-label="Chosen" />}
                <PixelDog animal={a.id} scene="sit" scale={3} />
                <span className="mt-1 text-[15px] font-medium text-ink">{a.name}</span>
                <span className="text-[12.5px] text-muted">{a.kind}</span>
              </button>
            </li>
          );
        })}
      </ul>
      <p className="px-1 text-[12px] leading-relaxed text-muted">Your companion shows on loading and empty screens on this phone. It does not change how anything works.</p>
    </Page>
  );
}
