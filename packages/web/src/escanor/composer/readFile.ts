import { classify, clipText, fitWithin, LIMITS, UNSUPPORTED, type Attachment } from './attachments';

const id = () => Math.random().toString(36).slice(2, 10);

function toBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result).replace(/^data:[^,]*,/, ''));
    r.onerror = () => reject(new Error('Could not read that file.'));
    r.readAsDataURL(blob);
  });
}

const canvasBlob = (c: HTMLCanvasElement, type: string, quality: number): Promise<Blob> => new Promise((resolve, reject) => c.toBlob((b) => (b ? resolve(b) : reject(new Error('Could not prepare that photo.'))), type, quality));

/** A photo, shrunk to a size worth sending (and turned into JPEG, which every phone camera and the assistant understand). */
async function readImage(file: File): Promise<Attachment> {
  let bitmap: ImageBitmap;
  try {
    bitmap = await createImageBitmap(file);
  } catch {
    throw new Error(`Could not open ${file.name || 'that photo'}. Try a JPEG or PNG.`);
  }
  const { width, height } = fitWithin(bitmap.width, bitmap.height, LIMITS.imageEdge);
  const c = document.createElement('canvas');
  c.width = width;
  c.height = height;
  const ctx = c.getContext('2d')!;
  ctx.fillStyle = '#fff'; // a transparent PNG would turn black as a JPEG
  ctx.fillRect(0, 0, width, height);
  ctx.drawImage(bitmap, 0, 0, width, height);
  let blob = await canvasBlob(c, 'image/jpeg', 0.85);
  if (blob.size > LIMITS.bytesEach) blob = await canvasBlob(c, 'image/jpeg', 0.6);
  const t = document.createElement('canvas');
  const k = 96 / Math.max(width, height);
  t.width = Math.max(1, Math.round(width * k));
  t.height = Math.max(1, Math.round(height * k));
  t.getContext('2d')!.drawImage(c, 0, 0, t.width, t.height);
  bitmap.close?.();
  return { id: id(), name: (file.name || 'photo').replace(/\.[^.]+$/, '') + '.jpg', mime: 'image/jpeg', size: blob.size, kind: 'image', data: await toBase64(blob), preview: t.toDataURL('image/jpeg', 0.7) };
}

/** Read a picked file into something ready to send. Throws a sentence the person can read. */
export async function readFile(file: File): Promise<Attachment> {
  const kind = classify(file.name, file.type);
  if (!kind) throw new Error(UNSUPPORTED);
  if (kind === 'image') return readImage(file);
  if (kind === 'pdf') return { id: id(), name: file.name, mime: 'application/pdf', size: file.size, kind, data: await toBase64(file) };
  const { text, cut } = clipText(await file.text());
  return { id: id(), name: cut ? `${file.name} (first part)` : file.name, mime: file.type || 'text/plain', size: text.length, kind, text };
}
