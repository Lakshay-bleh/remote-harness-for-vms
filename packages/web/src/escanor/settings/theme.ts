/**
 * The app's colours. Every colour in Tailwind is a CSS variable holding "R G B", so a theme is just a set of values on the
 * page root, and an opacity such as `bg-primary/15` still works. The palettes live in styles.css; this module chooses which
 * one is active and tints the accent.
 */

export type ThemeChoice = 'system' | 'dark' | 'light' | 'black';
export type ThemeName = Exclude<ThemeChoice, 'system'>;
export type AccentName = 'gold' | 'coral' | 'teal' | 'violet' | 'blue' | 'rose';

export const THEMES: ReadonlyArray<{ value: ThemeChoice; label: string; hint: string }> = [
  { value: 'system', label: 'Match my phone', hint: 'Light by day, dark by night, following your phone’s setting' },
  { value: 'dark', label: 'Dark', hint: 'Easy on the eyes' },
  { value: 'light', label: 'Light', hint: 'Bright and warm' },
  { value: 'black', label: 'Pure black', hint: 'Saves battery on OLED screens' },
];

/** Accent colours as RGB. `light` is the tone used on the light theme, where the same colour needs more depth to read. */
export const ACCENTS: Record<AccentName, { label: string; dark: [number, number, number]; light: [number, number, number] }> = {
  gold: { label: 'Gold', dark: [242, 167, 59], light: [217, 138, 18] },
  coral: { label: 'Coral', dark: [240, 112, 88], light: [214, 84, 58] },
  teal: { label: 'Teal', dark: [64, 188, 160], light: [24, 140, 118] },
  violet: { label: 'Violet', dark: [150, 132, 255], light: [104, 82, 224] },
  blue: { label: 'Blue', dark: [88, 156, 255], light: [36, 104, 224] },
  rose: { label: 'Rose', dark: [240, 108, 156], light: [208, 62, 118] },
};
export const ACCENT_NAMES = Object.keys(ACCENTS) as AccentName[];

/** The colour that sits behind the page chrome (the browser/status bar), per theme. */
export const THEME_COLOR: Record<ThemeName, string> = { dark: '#050505', light: '#faf8f4', black: '#000000' };

/** Which theme is actually shown, given the choice and whether the phone is in dark mode. */
export function resolveTheme(choice: ThemeChoice, systemDark: boolean): ThemeName {
  return choice === 'system' ? (systemDark ? 'dark' : 'light') : choice;
}

const channel = (v: number) => {
  const s = v / 255;
  return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
};
/** WCAG relative luminance, 0 (black) to 1 (white). */
export const luminance = ([r, g, b]: [number, number, number]) => 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);

/** Text on top of an accent: near-black on light accents, white on dark ones, whichever reads better. */
export function onAccent(rgb: [number, number, number]): [number, number, number] {
  const dark: [number, number, number] = [24, 14, 2];
  const white: [number, number, number] = [255, 255, 255];
  const contrast = (a: number, b: number) => (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
  const l = luminance(rgb);
  return contrast(l, luminance(dark)) >= contrast(l, luminance(white)) ? dark : white;
}

const darker = ([r, g, b]: [number, number, number], by = 0.07): [number, number, number] => [r, g, b].map((v) => Math.round(v * (1 - by))) as [number, number, number];
const triplet = (rgb: [number, number, number]) => rgb.join(' ');

/** The CSS variables for an accent on a theme. */
export function accentVars(accent: AccentName, theme: ThemeName): Record<string, string> {
  const rgb = ACCENTS[accent][theme === 'light' ? 'light' : 'dark'];
  return { '--c-primary': triplet(rgb), '--c-primary-active': triplet(darker(rgb)), '--c-on-primary': triplet(onAccent(rgb)) };
}

/** Put a theme on the page. Safe to call before the app mounts (and under test, where there is no page). */
export function applyTheme(choice: ThemeChoice, accent: AccentName, opts: { reduceMotion?: boolean } = {}): ThemeName {
  const systemDark = typeof matchMedia === 'function' ? matchMedia('(prefers-color-scheme: dark)').matches : true;
  const theme = resolveTheme(choice, systemDark);
  if (typeof document === 'undefined') return theme;
  const root = document.documentElement;
  root.dataset.theme = theme;
  root.style.colorScheme = theme === 'light' ? 'light' : 'dark';
  for (const [k, v] of Object.entries(accentVars(accent, theme))) root.style.setProperty(k, v);
  root.classList.toggle('reduce-motion', Boolean(opts.reduceMotion));
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', THEME_COLOR[theme]);
  return theme;
}
