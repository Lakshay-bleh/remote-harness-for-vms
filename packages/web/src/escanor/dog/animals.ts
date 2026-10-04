/**
 * The companions a person can choose in Settings. Pure data: names, a line about each, and the colours that differ from the dog's.
 * Drawing them is `sprites.ts`.
 */

export type Animal = 'dog' | 'unicorn' | 'pigeon' | 'hamster' | 'cat' | 'elephant';

export interface AnimalInfo {
  id: Animal;
  /** What it is called. */
  name: string;
  /** What it is. */
  kind: string;
  blurb: string;
  /** What it says when tapped. */
  says: string[];
}

export const ANIMALS: readonly AnimalInfo[] = [
  { id: 'dog', name: 'Shiro', kind: 'Dog', blurb: 'Chases balls and digs up bones.', says: ['Woof!', 'Woof woof!', 'Arf!', 'Bork!'] },
  { id: 'unicorn', name: 'Stacy', kind: 'Unicorn', blurb: 'Sparkly, with a rainbow mane.', says: ['Neigh!', '✨ Sparkle!', 'Hehe~', 'Neeeigh!'] },
  { id: 'pigeon', name: 'Riti', kind: 'Pigeon', blurb: 'Bobs along and pecks at crumbs.', says: ['Coo coo!', 'Prrr-coo!', 'Coo!', 'Flap flap!'] },
  { id: 'hamster', name: 'Bubbly', kind: 'Hamster', blurb: 'Runs on a wheel, cheeks full of seeds.', says: ['Squeak!', 'Squeak squeak!', 'Nom nom!', 'Eek!'] },
  { id: 'cat', name: 'Tom', kind: 'Cat', blurb: 'Curious, with whiskers and a long tail.', says: ['Meow!', 'Mrrow?', 'Purrr…', 'Mew!'] },
  { id: 'elephant', name: 'Jumbo', kind: 'Elephant', blurb: 'Big ears, a gentle trunk.', says: ['Toot!', 'Pawoo!', 'Brrrap!', 'Splash!'] },
];

export const DEFAULT_ANIMAL: Animal = 'dog';

export const isAnimal = (v: unknown): v is Animal => typeof v === 'string' && ANIMALS.some((a) => a.id === v);

export const animalInfo = (id: Animal): AnimalInfo => ANIMALS.find((a) => a.id === id) ?? ANIMALS[0];

/** The colours each animal changes from the dog's palette (see `PALETTE` in sprites.ts for what every letter is). */
export const PALETTE_OVERRIDES: Record<Animal, Record<string, string>> = {
  dog: {},
  cat: { f: '#8d99ae', d: '#5d6b85', c: '#ece8df', t: '#ff8fa8' },
  unicorn: { f: '#f7f3ff', d: '#cfc5ec', c: '#ffd9f3', M: '#ff7ad9', N: '#7ad7ff', H: '#ffd45a' },
  elephant: { f: '#a3aec2', d: '#7a869e', c: '#d3dae6', t: '#aeb8ca', T: '#7a869e' },
  hamster: { f: '#f0b866', d: '#d38c3a', c: '#fff2d6', t: '#ff9bb0', T: '#e0708c' },
  pigeon: { f: '#aab3c6', d: '#727c94', c: '#e6eaf2', M: '#4fcfa6', N: '#b57be0', y: '#f2a73b', p: '#ff7f9c', u: '#ff9d3c' },
};
