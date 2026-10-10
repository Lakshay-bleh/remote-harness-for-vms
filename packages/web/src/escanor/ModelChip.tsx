import { CaretDown, Check, Sparkle } from '@phosphor-icons/react';
import { useState } from 'react';
import type { AssistantModels } from './client';
import { AUTO_ID, chosenId, chosenLabel, hiddenCount, pickerGroups, setModelPick } from './modelPicker';
import { Sheet } from './ui';

/** The model chip above the message box, and the list it opens: Auto, then the models that can answer right now. */
export default function ModelChip({ list, picked }: { list: AssistantModels; picked: string | null }) {
  const [open, setOpen] = useState(false);
  const models = list.models ?? [];
  const selected = chosenId(models, picked);
  const label = chosenLabel(models, selected, list.auto);
  const hidden = hiddenCount(models);
  const choose = (id: string) => {
    setModelPick(id);
    setOpen(false);
  };
  const row = (id: string, name: string, hint?: string) => (
    <li key={id}>
      <button type="button" onClick={() => choose(id)} aria-pressed={selected === id} className="flex w-full items-center gap-3 rounded-md px-2 py-2.5 text-left transition hover:bg-surface-card active:scale-[0.99]">
        <span className="min-w-0 flex-1">
          <span className="block truncate text-[15px] text-ink">{name}</span>
          {hint && <span className="block text-[12px] text-muted">{hint}</span>}
        </span>
        {selected === id && <Check size={18} weight="bold" className="shrink-0 text-primary" aria-hidden />}
      </button>
    </li>
  );

  return (
    <>
      <button type="button" onClick={() => setOpen(true)} aria-label={`Model: ${label}. Choose another`} className="flex max-w-full items-center gap-1 rounded-pill border border-hairline px-2.5 py-1 text-[12px] text-body transition hover:bg-surface-card hover:text-ink active:scale-95">
        <Sparkle size={13} aria-hidden />
        <span className="truncate">{label}</span>
        <CaretDown size={11} aria-hidden />
      </button>
      {open && (
        <Sheet title="Model" onClose={() => setOpen(false)}>
          <ul className="space-y-0.5">{row(AUTO_ID, 'Auto', list.auto?.available === false ? 'Nothing can answer right now' : 'The best model that can answer')}</ul>
          {pickerGroups(models).map((g) => (
            <section key={g.provider} className="mt-3">
              <h3 className="px-2 pb-1 text-[12px] font-medium uppercase tracking-wide text-muted">{g.label}</h3>
              <ul className="space-y-0.5">{g.models.map((m) => row(m.id, m.label.replace(/\s*\([^)]*\)$/, ''), m.local ? 'Slower' : undefined))}</ul>
            </section>
          ))}
          <p className="mt-4 px-2 pb-2 text-[12px] leading-relaxed text-muted">
            {selected === AUTO_ID ? list.auto?.detail || 'Auto picks the best model that can answer, and the next one when it cannot.' : 'Only models that can answer right now are listed.'}
            {hidden > 0 ? ' Models that can’t answer at the moment are hidden.' : ''}
          </p>
        </Sheet>
      )}
    </>
  );
}
