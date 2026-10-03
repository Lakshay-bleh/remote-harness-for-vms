import { Directory, Encoding, Filesystem } from '@capacitor/filesystem';
import { Share } from '@capacitor/share';
import { isNative } from '../../api';

/** The export as text, as the person receives it. */
export const exportText = (data: unknown): string => JSON.stringify(data, null, 2);

export const exportFileName = (now: Date = new Date()): string => `escanor-my-data-${now.toISOString().slice(0, 10)}.json`;

/** Roughly how big it is, for "12 KB", before the person decides to copy or share it. */
export function sizeLabel(text: string): string {
  const bytes = new TextEncoder().encode(text).length;
  return bytes < 1024 ? `${bytes} bytes` : bytes < 1024 * 1024 ? `${(bytes / 1024).toFixed(bytes < 10 * 1024 ? 1 : 0)} KB` : `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

export async function copyExport(text: string): Promise<void> {
  await navigator.clipboard.writeText(text);
}

/**
 * Hand the export to the phone's share sheet as a file, so it can be saved to Files or Drive, mailed or sent to another app.
 * (A web view cannot save a downloaded file on its own.) In a browser it downloads the file instead.
 */
export async function shareExport(text: string, name = exportFileName()): Promise<'shared' | 'downloaded' | 'cancelled'> {
  if (isNative()) {
    const written = await Filesystem.writeFile({ path: name, data: text, directory: Directory.Cache, encoding: Encoding.UTF8 });
    try {
      await Share.share({ title: 'My Escanor data', url: written.uri, dialogTitle: 'Save or send my data' });
      return 'shared';
    } catch (e) {
      if (e instanceof Error && /cancel/i.test(e.message)) return 'cancelled';
      throw e;
    }
  }
  const url = URL.createObjectURL(new Blob([text], { type: 'application/json' }));
  const a = Object.assign(document.createElement('a'), { href: url, download: name });
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
  return 'downloaded';
}
