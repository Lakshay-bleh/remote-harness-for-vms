const KNOWN: Record<string, string> = {
  'os.open_url': 'Opened a website',
  'os.open_app': 'Opened an app',
  'os.volume': 'Changed the volume',
  'os.media': 'Controlled media',
  'system.stats': 'Checked how busy it is',
  'system.processes': 'Looked at running programs',
  'shell.exec': 'Ran a command',
  'shell.open': 'Opened a terminal',
  'fs.read': 'Read a file',
  'fs.write': 'Changed a file',
};

const words = (s: string) => s.replace(/[_-]+/g, ' ').trim();
const cap = (s: string) => (s ? s[0].toUpperCase() + s.slice(1) : s);

/** The nicest words for a capability id such as `os.open_url`: a plain sentence for the common ones, readable words for the rest. */
export function activityLabel(id: string): string {
  if (KNOWN[id]) return KNOWN[id];
  const [group = '', action = ''] = id.split('.');
  if (!group) return 'Something';
  return action ? `${cap(words(group))}: ${words(action)}` : cap(words(group));
}
