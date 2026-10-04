import { useSyncExternalStore } from 'react';
import { DEFAULT_ANIMAL, isAnimal, type Animal } from './animals.ts';

/**
 * Which animal this device shows. Kept on the device (a companion is a taste, not an account setting) and shared by every screen
 * through one small store, so picking one in Settings changes all of them at once.
 */
export const COMPANION_KEY = 'escanor.companion.v1';

const listeners = new Set<() => void>();

/** Read a stored choice defensively: anything that is not one of the known animals is the default. */
export function parseCompanion(raw: string | null): Animal {
  return isAnimal(raw) ? raw : DEFAULT_ANIMAL;
}

const read = (): Animal => {
  try {
    return parseCompanion(localStorage.getItem(COMPANION_KEY));
  } catch {
    return DEFAULT_ANIMAL;
  }
};

let current: Animal = typeof localStorage === 'undefined' ? DEFAULT_ANIMAL : read();

export const getCompanion = (): Animal => current;

export function setCompanion(animal: Animal): void {
  current = isAnimal(animal) ? animal : DEFAULT_ANIMAL;
  try {
    localStorage.setItem(COMPANION_KEY, current);
  } catch {
    // not saved, but it still applies until the app is closed
  }
  listeners.forEach((l) => l());
}

export function useCompanion(): Animal {
  return useSyncExternalStore((cb) => (listeners.add(cb), () => void listeners.delete(cb)), () => current, () => DEFAULT_ANIMAL);
}
