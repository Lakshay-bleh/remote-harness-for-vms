import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { ACCENT_NAMES, ACCENTS, accentVars, luminance, onAccent, resolveTheme, THEME_COLOR } from './theme';

const contrast = (a: [number, number, number], b: [number, number, number]) => {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
};

describe('resolveTheme', () => {
  it('follows the phone only when asked to', () => {
    assert.equal(resolveTheme('system', true), 'dark');
    assert.equal(resolveTheme('system', false), 'light');
    assert.equal(resolveTheme('light', true), 'light');
    assert.equal(resolveTheme('black', false), 'black');
  });
  it('has a status-bar colour for every theme', () => {
    for (const t of ['dark', 'light', 'black'] as const) assert.match(THEME_COLOR[t], /^#[0-9a-f]{6}$/);
  });
});

describe('accents', () => {
  it('keeps text on a button readable (WCAG AA, 4.5:1) for every accent on both themes', () => {
    for (const name of ACCENT_NAMES) {
      for (const tone of ['dark', 'light'] as const) {
        const bg = ACCENTS[name][tone];
        assert.ok(contrast(bg, onAccent(bg)) >= 4.5, `${name}/${tone} ${contrast(bg, onAccent(bg)).toFixed(2)}`);
      }
    }
  });
  it('writes the variables Tailwind reads, as "R G B"', () => {
    const v = accentVars('teal', 'dark');
    assert.deepEqual(Object.keys(v).sort(), ['--c-on-primary', '--c-primary', '--c-primary-active']);
    for (const value of Object.values(v)) assert.match(value, /^\d{1,3} \d{1,3} \d{1,3}$/);
  });
  it('uses the deeper tone on the light theme', () => {
    assert.notEqual(accentVars('gold', 'light')['--c-primary'], accentVars('gold', 'dark')['--c-primary']);
  });
});
