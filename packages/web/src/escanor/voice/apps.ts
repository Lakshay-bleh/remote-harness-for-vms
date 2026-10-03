export interface InstalledApp {
  label: string;
  package: string;
}

const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, '');

/** Other names people use for an app, mapped to a word that appears in its label or package. */
const NICKNAMES: Record<string, string[]> = {
  browser: ['chrome', 'browser', 'internet', 'firefox'],
  maps: ['maps'],
  googlemaps: ['maps'],
  mail: ['gmail', 'mail'],
  email: ['gmail', 'mail'],
  dialer: ['dialer', 'phone'],
  phone: ['phone', 'dialer'],
  messages: ['messages', 'messaging', 'sms'],
  text: ['messages', 'messaging', 'sms'],
  photos: ['photos', 'gallery'],
  gallery: ['gallery', 'photos'],
  music: ['music', 'spotify'],
  clock: ['clock'],
  calculator: ['calculator'],
  calendar: ['calendar'],
  files: ['files', 'myfiles'],
};

/**
 * The installed app a spoken name most likely means: an exact name first, then one that starts with it, then one that contains it,
 * then a nickname. Null when nothing fits: it must say so rather than open the wrong app.
 */
export function matchApp(spoken: string, apps: InstalledApp[]): InstalledApp | null {
  const want = norm(spoken);
  if (want.length < 2) return null;
  const labeled = apps.map((a) => ({ a, l: norm(a.label), p: a.package.toLowerCase() }));
  const shortest = (xs: typeof labeled) => xs.sort((x, y) => x.l.length - y.l.length)[0]?.a ?? null;

  const exact = labeled.filter((x) => x.l === want);
  if (exact.length) return shortest(exact);
  const starts = labeled.filter((x) => x.l.startsWith(want));
  if (starts.length) return shortest(starts);
  const contains = labeled.filter((x) => x.l.includes(want));
  if (contains.length) return shortest(contains);
  for (const word of NICKNAMES[want] ?? []) {
    const hit = labeled.filter((x) => x.l.includes(word) || x.p.includes(word));
    if (hit.length) return shortest(hit);
  }
  return null;
}
