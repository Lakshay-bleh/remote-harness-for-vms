/**
 * The chat's model picker, the same as the website's (lib/model-picker.ts): Auto, then only the models that can answer right now.
 * The person's pick is remembered on this phone; a pick that has stopped being able to answer falls back to Auto. The server stays
 * the authority: it refuses a model that cannot answer, with the reason.
 */
import { useSyncExternalStore } from 'react';
import type { AssistantModel, AssistantModels } from './client';

export const AUTO_ID = 'auto';

export interface PickerGroup {
  provider: string;
  label: string;
  models: AssistantModel[];
}

/** Older servers send neither `available` nor `reason`: treat those models as able to answer. */
export const canAnswer = (model: AssistantModel | undefined): boolean => !model || model.available !== false;

/** Only models that can answer now, grouped by provider. Proven ones lead each group; models on our own machine come last. */
export function pickerGroups(models: AssistantModel[]): PickerGroup[] {
  const groups = new Map<string, PickerGroup>();
  for (const model of models.filter(canAnswer)) {
    const g = groups.get(model.provider) ?? { provider: model.provider, label: (model.provider_label ?? model.provider).replace(/\s*\(on our server\)$/i, ''), models: [] };
    g.models.push(model);
    groups.set(model.provider, g);
  }
  return [...groups.values()]
    .map((g) => ({ ...g, models: [...g.models].sort((a, b) => Number(b.verified === true) - Number(a.verified === true)) }))
    .sort((a, b) => Number(a.models[0]?.local === true) - Number(b.models[0]?.local === true));
}

/** How many models are hidden because they cannot answer right now. */
export const hiddenCount = (models: AssistantModel[]): number => models.filter((m) => !canAnswer(m)).length;

/** What the person has selected: Auto unless they chose a model that can still answer. */
export function chosenId(models: AssistantModel[], picked: string | null): string {
  if (picked && picked !== AUTO_ID && models.some((m) => m.id === picked && canAnswer(m))) return picked;
  return AUTO_ID;
}

const short = (label: string) => label.replace(/\s*\([^)]*\)$/, '');

/** The short label for the picker button. */
export function chosenLabel(models: AssistantModel[], id: string, auto?: { resolves_to: string | null }): string {
  if (id === AUTO_ID) {
    const using = auto?.resolves_to ? models.find((m) => m.id === auto.resolves_to) : undefined;
    return using ? `Auto · ${short(using.label)}` : 'Auto';
  }
  const m = models.find((x) => x.id === id);
  return m ? short(m.label) : 'Model';
}

/**
 * The `model` to send with a message: the person's pick if it can answer, "auto" to a server that has Auto, and nothing when the
 * list has not loaded (the server then keeps the conversation's model).
 */
export function modelToSend(list: AssistantModels | null | undefined, picked: string | null): string | undefined {
  if (!list) return undefined;
  const id = chosenId(list.models ?? [], picked);
  if (id !== AUTO_ID) return id;
  return list.auto ? AUTO_ID : undefined;
}

// ---- the pick, remembered on this phone (the website's key, so it reads the same), and the last list seen (for voice)
const KEY = 'escanor-assistant-model';
const listeners = new Set<() => void>();
let lastList: AssistantModels | null = null;

export function getModelPick(): string | null {
  try {
    return localStorage.getItem(KEY);
  } catch {
    return null;
  }
}

export function setModelPick(id: string): void {
  try {
    localStorage.setItem(KEY, id);
  } catch {
    // not saved: it still holds until the app closes
  }
  memo = id;
  listeners.forEach((l) => l());
}

let memo: string | null | undefined;
const current = () => (memo === undefined ? (memo = getModelPick()) : memo);

export function useModelPick(): string | null {
  return useSyncExternalStore(
    (cb) => (listeners.add(cb), () => void listeners.delete(cb)),
    current,
    () => null,
  );
}

/** Remember the latest list from the server, so a message sent by voice uses the same model as one typed in the chat. */
export const rememberModels = (list: AssistantModels | null): void => void (lastList = list);

/** The `model` for a message sent from anywhere (voice included). */
export const currentModel = (): string | undefined => modelToSend(lastList, current());
