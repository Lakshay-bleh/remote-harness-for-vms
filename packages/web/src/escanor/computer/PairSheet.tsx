import { Camera, WifiHigh } from '@phosphor-icons/react';
import { useCallback, useState } from 'react';
import { escanor } from '../client';
import { haptic } from '../settings/prefs';
import { Button, Notice, Sheet, Spinner } from '../ui';
import QrScan from './QrScan';
import type { CloudDirectory, PairedComputer } from './lib/client';
import { pairComputer, parseEntry, type PairEntry } from './pairing';

/** The signed-in app's own backend is how a phone finds the person's computers and reaches them from anywhere. */
const cloud: CloudDirectory = { computers: () => escanor.desktops(), pair: (id, body) => escanor.pairWithDesktop(id, body) };

const FIELD = 'mt-1 w-full rounded-md border border-line-strong bg-surface-card px-3 py-3 font-mono text-[15px] text-ink outline-none transition placeholder:text-muted-soft focus:border-primary focus:ring-4 focus:ring-primary/15';

type Way = 'code' | 'scan' | 'wifi';

/**
 * Pair with a computer. By default with just the code it shows: that works from anywhere there is internet, with no address and no
 * shared Wi-Fi. Scanning its QR is the same thing without typing. Pairing over the local network is the quiet alternative.
 */
export default function PairSheet({ onPaired, onClose }: { onPaired: (c: PairedComputer) => void; onClose: () => void }) {
  const [way, setWay] = useState<Way>('code');
  const [code, setCode] = useState('');
  const [address, setAddress] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const deviceName = /Android/i.test(navigator.userAgent) ? 'Android phone' : /iPhone|iPad/i.test(navigator.userAgent) ? 'iPhone' : 'Phone';

  const pair = useCallback(
    async (entry: PairEntry, mode: 'cloud' | 'lan', lanAddress?: string) => {
      setBusy(true);
      setError(null);
      try {
        const paired = await pairComputer(entry, deviceName, { mode, cloud, lanAddress });
        haptic(20);
        onPaired(paired);
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Pairing did not work.');
        setBusy(false);
        setWay((w) => (w === 'scan' ? 'code' : w)); // after a failed scan, land on the typing form with the error visible
      }
    },
    [deviceName, onPaired],
  );

  const scanned = useCallback(
    (text: string) => {
      const entry = parseEntry(text);
      entry ? void pair(entry, 'cloud') : (setError('That is not an Escanor pairing code.'), setWay('code'));
    },
    [pair],
  );

  const submit = (mode: 'cloud' | 'lan') => {
    const entry = parseEntry(code);
    if (!entry) return setError('That is not a valid pairing code. It looks like ABCD-EFGH-IJKL-… (letters and the digits 2 to 7).');
    void pair(entry, mode, mode === 'lan' ? address : undefined);
  };

  return (
    <Sheet title="Add your computer" onClose={onClose}>
      <p className="text-sm text-body">On your computer, open <b>Escanor Desktop</b>, go to <b>Phone</b> and choose <b>Pair a phone</b>. Then enter the code it shows. Both devices need to be signed in to the same Escanor account.</p>
      <div className="mt-4 space-y-3">
        {error && <Notice tone="error">{error}</Notice>}

        {busy ? (
          <div className="flex items-center gap-3 py-8 text-sm text-muted"><Spinner /> {way === 'wifi' ? 'Connecting over your Wi-Fi…' : 'Finding your computer and pairing…'}</div>
        ) : way === 'scan' ? (
          <>
            <QrScan onCode={scanned} />
            <Button kind="quiet" className="w-full" onClick={() => setWay('code')}>Type the code instead</Button>
          </>
        ) : (
          <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); submit(way === 'wifi' ? 'lan' : 'cloud'); }}>
            <label className="block text-sm text-body">Pairing code
              <input value={code} onChange={(e) => setCode(e.target.value)} placeholder="ABCD-EFGH-IJKL-…" autoCapitalize="characters" autoCorrect="off" spellCheck={false} autoComplete="off" autoFocus className={FIELD} />
            </label>
            {way === 'wifi' && (
              <label className="block text-sm text-body">Computer address (shown on the Phone screen)
                <input value={address} onChange={(e) => setAddress(e.target.value)} placeholder="192.168.1.20:47625" inputMode="url" autoCapitalize="none" autoCorrect="off" spellCheck={false} className={FIELD} />
                <span className="mt-1 block text-[12px] text-muted">Your phone must be on the same Wi-Fi as the computer.</span>
              </label>
            )}
            <Button type="submit" className="w-full" disabled={!code.trim() || (way === 'wifi' && !address.trim())}>{way === 'wifi' ? 'Pair over Wi-Fi' : 'Pair'}</Button>
            <div className="flex flex-col gap-2 pt-1">
              {way === 'code' && <Button kind="quiet" className="flex w-full items-center justify-center gap-2" onClick={() => { setError(null); setWay('scan'); }}><Camera size={18} /> Scan the QR code instead</Button>}
              {way === 'code' ? (
                <button type="button" onClick={() => { setError(null); setWay('wifi'); }} className="mx-auto flex items-center gap-1.5 py-1.5 text-[13px] text-muted transition hover:text-ink"><WifiHigh size={16} /> Computer on the same Wi-Fi? Pair locally</button>
              ) : (
                <button type="button" onClick={() => { setError(null); setWay('code'); }} className="mx-auto py-1.5 text-[13px] text-muted transition hover:text-ink">Back to pairing from anywhere</button>
              )}
            </div>
          </form>
        )}
      </div>
    </Sheet>
  );
}
