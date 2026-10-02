import { useContext, useRef, useState, type ReactNode } from 'react';
import type { ImageAttachment } from '@remote-harness/shared';
import { EmbeddedContext } from '../escanor/ui';

function fileToImage(file: File): Promise<ImageAttachment> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = reader.result as string;
      resolve({ mediaType: file.type, dataBase64: result.split(',')[1] });
    };
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

export default function Composer({
  onSend,
  onInterrupt,
  busy,
  placeholder,
  topChips,
  footerExtra,
  onOpenSidebar,
}: {
  onSend: (text: string, images: ImageAttachment[]) => void;
  onInterrupt: () => void;
  busy: boolean;
  placeholder: string;
  topChips?: ReactNode;
  footerExtra?: ReactNode;
  onOpenSidebar?: () => void;
}) {
  const embedded = useContext(EmbeddedContext);
  const [text, setText] = useState('');
  const [images, setImages] = useState<ImageAttachment[]>([]);
  const taRef = useRef<HTMLTextAreaElement>(null);

  function autoGrow() {
    const el = taRef.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${Math.min(el.scrollHeight, 160)}px`;
  }

  async function addFiles(files: FileList | File[]) {
    const list = Array.from(files).filter((f) => f.type.startsWith('image/'));
    if (list.length === 0) return;
    const converted = await Promise.all(list.map(fileToImage));
    setImages((prev) => [...prev, ...converted]);
  }

  function submit() {
    if (!text.trim() && images.length === 0) return;
    onSend(text.trim(), images);
    setText('');
    setImages([]);
    requestAnimationFrame(autoGrow);
  }

  return (
    <div className={`${embedded ? 'pb-3' : 'safe-bottom'} border-t border-hairline bg-canvas px-3 pt-3`}>
      {images.length > 0 && (
        <div className="mb-2 flex flex-wrap gap-2">
          {images.map((img, i) => (
            <div key={i} className="relative">
              <img src={`data:${img.mediaType};base64,${img.dataBase64}`} className="h-14 w-14 rounded-md border border-hairline object-cover" />
              <button
                onClick={() => setImages(images.filter((_, j) => j !== i))}
                className="absolute -right-1.5 -top-1.5 flex h-4 w-4 items-center justify-center rounded-full border border-hairline bg-canvas text-[10px] text-muted"
              >
                ×
              </button>
            </div>
          ))}
        </div>
      )}
      <div className="rounded-xl border border-hairline bg-canvas px-3 pb-2 pt-2.5 transition focus-within:border-primary/60">
        {topChips && <div className="mb-2 flex flex-wrap items-center gap-1.5">{topChips}</div>}
        <textarea
          ref={taRef}
          rows={1}
          value={text}
          onChange={(e) => {
            setText(e.target.value);
            autoGrow();
          }}
          onPaste={(e) => e.clipboardData.files.length && addFiles(e.clipboardData.files)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault();
              submit();
            }
          }}
          placeholder={placeholder}
          className="max-h-40 w-full resize-none bg-transparent py-1 text-base text-ink outline-none placeholder:text-muted-soft md:text-[14px]"
        />
        <div className="mt-1.5 flex flex-wrap items-center justify-between gap-1.5">
          <div className="flex items-center gap-1">
            {onOpenSidebar && (
              <button
                onClick={onOpenSidebar}
                className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md text-muted transition hover:bg-surface-card hover:text-ink md:hidden"
              >
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
                  <rect x="3" y="4" width="18" height="16" rx="2" stroke="currentColor" strokeWidth="1.8" />
                  <path d="M9 4v16" stroke="currentColor" strokeWidth="1.8" />
                </svg>
              </button>
            )}
            <label className="flex h-8 w-8 shrink-0 cursor-pointer items-center justify-center rounded-md text-muted transition hover:bg-surface-card hover:text-ink">
              <input type="file" accept="image/*" multiple className="hidden" onChange={(e) => e.target.files && addFiles(e.target.files)} />
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none">
              <path
                d="M21 11.5V17a4 4 0 01-4 4H7a4 4 0 01-4-4V9a4 4 0 014-4h7.5M17 3l4 4-9.5 9.5H8v-3.5L17 3z"
                stroke="currentColor"
                strokeWidth="1.6"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
            </label>
          </div>
          <div className="flex flex-wrap items-center justify-end gap-1.5">
            {footerExtra}
            {busy ? (
              <button onClick={onInterrupt} className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md bg-surface-dark text-on-dark transition hover:bg-surface-dark-elevated">
                <svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor">
                  <rect x="5" y="5" width="14" height="14" rx="2" />
                </svg>
              </button>
            ) : (
              <button
                onClick={submit}
                disabled={!text.trim() && images.length === 0}
                className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md bg-primary text-on-primary transition hover:bg-primary-active disabled:opacity-30"
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
                  <path d="M4 12l16-8-6 8 6 8-16-8z" fill="currentColor" />
                </svg>
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
