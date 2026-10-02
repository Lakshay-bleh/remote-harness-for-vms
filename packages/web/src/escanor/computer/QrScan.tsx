import { Image as ImageIcon } from '@phosphor-icons/react';
import { useEffect, useRef, useState } from 'react';
import { Notice } from '../ui';
import { decodeQr } from './qr';

const MAX_SIDE = 720; // frames are shrunk before decoding: faster, and a QR this size is still crisp

function readPixels(source: CanvasImageSource, w: number, h: number, canvas: HTMLCanvasElement) {
  const scale = Math.min(1, MAX_SIDE / Math.max(w, h));
  canvas.width = Math.max(1, Math.round(w * scale));
  canvas.height = Math.max(1, Math.round(h * scale));
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  if (!ctx) return null;
  ctx.drawImage(source, 0, 0, canvas.width, canvas.height);
  return ctx.getImageData(0, 0, canvas.width, canvas.height);
}

/**
 * Scans a QR code with the camera, and also from a photo of it. Frames are decoded in JavaScript, so it works in the Android app's
 * WebView. If the camera cannot start (permission refused, none present) the caller is told, and the photo option still works.
 */
export default function QrScan({ onCode }: { onCode: (text: string) => void }) {
  const video = useRef<HTMLVideoElement>(null);
  const canvas = useRef<HTMLCanvasElement | null>(null);
  const [starting, setStarting] = useState(true);
  const [note, setNote] = useState<string | null>(null);
  /** Why the camera is not running, if it is not. The photo option below still works, so the scanner stays open and says so. */
  const [cameraProblem, setCameraProblem] = useState<string | null>(null);
  const onCodeRef = useRef(onCode);
  onCodeRef.current = onCode;

  useEffect(() => {
    let stop = false;
    let stream: MediaStream | null = null;
    let timer: ReturnType<typeof setTimeout> | undefined;
    (async () => {
      if (!navigator.mediaDevices?.getUserMedia) return setCameraProblem('This phone cannot use the camera here.');
      try {
        stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: 'environment' } }, audio: false });
      } catch (e) {
        const denied = e instanceof DOMException && (e.name === 'NotAllowedError' || e.name === 'SecurityError');
        return setCameraProblem(denied ? 'Camera access was not allowed. You can allow it in the phone’s settings for Escanor.' : 'The camera could not start.');
      }
      const el = video.current;
      if (stop || !el) return stream.getTracks().forEach((t) => t.stop());
      el.srcObject = stream;
      await el.play().catch(() => undefined);
      setStarting(false);
      canvas.current ??= document.createElement('canvas');
      const tick = () => {
        if (stop) return;
        if (el.readyState >= 2 && el.videoWidth > 0) {
          const img = readPixels(el, el.videoWidth, el.videoHeight, canvas.current!);
          const text = img ? decodeQr(img.data, img.width, img.height) : null;
          if (text) return onCodeRef.current(text);
        }
        timer = setTimeout(tick, 120);
      };
      tick();
    })();
    return () => {
      stop = true;
      if (timer) clearTimeout(timer);
      stream?.getTracks().forEach((t) => t.stop());
    };
  }, []);

  const fromPhoto = async (file: File | undefined) => {
    if (!file) return;
    setNote(null);
    try {
      const bitmap = await createImageBitmap(file);
      canvas.current ??= document.createElement('canvas');
      const img = readPixels(bitmap, bitmap.width, bitmap.height, canvas.current);
      const text = img ? decodeQr(img.data, img.width, img.height) : null;
      bitmap.close();
      text ? onCodeRef.current(text) : setNote('No QR code found in that photo. Try a sharper, closer one.');
    } catch {
      setNote('That photo could not be read.');
    }
  };

  return (
    <div className="space-y-3">
      {cameraProblem ? (
        <Notice tone="warn">{cameraProblem} You can still scan from a photo of the code, or type the code.</Notice>
      ) : (
        <div className="relative overflow-hidden rounded-lg border border-hairline bg-black">
          <video ref={video} playsInline muted className="aspect-square w-full object-cover" />
          {/* a frame to aim with */}
          <div aria-hidden className="pointer-events-none absolute inset-[18%] rounded-2xl border-2 border-primary/80 shadow-[0_0_0_999px_rgba(0,0,0,0.35)]" />
          {starting && <div className="absolute inset-0 flex items-center justify-center bg-black/70 p-3"><Notice>Starting the camera…</Notice></div>}
        </div>
      )}
      {note && <Notice tone="warn">{note}</Notice>}
      <label className="block">
        <input type="file" accept="image/*" className="sr-only" onChange={(e) => { void fromPhoto(e.target.files?.[0]); e.target.value = ''; }} />
        <span className="inline-flex w-full cursor-pointer items-center justify-center gap-2 rounded-pill border border-line-strong px-5 py-2.5 text-sm font-medium text-ink transition hover:bg-surface-card active:scale-[0.98]"><ImageIcon size={18} /> Choose a photo of the code</span>
      </label>
    </div>
  );
}
