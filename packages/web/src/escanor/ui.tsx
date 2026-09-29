import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import type { ReactNode } from 'react';

export const Logo = ({ size = 44 }: { size?: number }) => (
  <div className="flex items-center justify-center rounded-lg bg-surface-dark text-primary" style={{ width: size, height: size }}>
    <svg width={size * 0.42} height={size * 0.42} viewBox="0 0 100 100" fill="none" aria-hidden>
      <path d="M35 22 L60 50 L35 78" stroke="currentColor" strokeWidth="12" strokeLinecap="round" strokeLinejoin="round" />
      <rect x="60" y="66" width="10" height="20" rx="5" fill="currentColor" />
    </svg>
  </div>
);

/** An assistant answer. Markdown only: raw HTML is never rendered, and links must be http(s). */
export function Md({ text }: { text: string }) {
  return (
    <div className="markdown text-[15px] leading-relaxed text-body-strong">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{ a: ({ href, children }) => (href && /^https?:\/\//i.test(href) ? <a href={href} target="_blank" rel="noreferrer noopener" className="text-primary underline">{children}</a> : <span>{children}</span>) }}
      >
        {text}
      </ReactMarkdown>
    </div>
  );
}

export function Button({ children, onClick, kind = 'primary', disabled, type = 'button', className = '' }: { children: ReactNode; onClick?: () => void; kind?: 'primary' | 'quiet' | 'danger'; disabled?: boolean; type?: 'button' | 'submit'; className?: string }) {
  const look = kind === 'primary' ? 'bg-primary text-on-primary hover:bg-primary-active' : kind === 'danger' ? 'border border-error/40 text-error hover:bg-error/10' : 'border border-hairline text-body hover:bg-surface-card';
  return (
    <button type={type} onClick={onClick} disabled={disabled} className={`rounded-md px-4 py-2.5 text-sm font-medium transition disabled:opacity-40 ${look} ${className}`}>
      {children}
    </button>
  );
}

export function Notice({ tone = 'info', children }: { tone?: 'info' | 'error' | 'warn'; children: ReactNode }) {
  const look = tone === 'error' ? 'border-error/30 bg-error/10 text-error' : tone === 'warn' ? 'border-warning/30 bg-warning/10 text-body-strong' : 'border-hairline bg-surface-soft text-body';
  return <div role={tone === 'error' ? 'alert' : undefined} className={`rounded-md border px-3 py-2 text-[13px] ${look}`}>{children}</div>;
}

export const Spinner = () => <span className="inline-block h-4 w-4 animate-spin rounded-full border-2 border-hairline border-t-primary" role="status" aria-label="Loading" />;

export function Sheet({ title, onClose, children }: { title: string; onClose: () => void; children: ReactNode }) {
  return (
    <div className="fixed inset-0 z-40 flex flex-col justify-end bg-black/30 md:items-center md:justify-center" onClick={onClose}>
      <div role="dialog" aria-label={title} className="safe-bottom flex max-h-[85svh] w-full flex-col rounded-t-xl bg-canvas md:max-w-lg md:rounded-xl" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between border-b border-hairline px-4 py-3">
          <h2 className="font-display text-xl text-ink">{title}</h2>
          <button onClick={onClose} className="rounded-md px-2 py-1 text-sm text-muted hover:bg-surface-card" aria-label="Close">Close</button>
        </div>
        <div className="overflow-y-auto px-4 py-3">{children}</div>
      </div>
    </div>
  );
}

export function ago(iso: string | number | null | undefined): string {
  if (iso == null) return '';
  const t = typeof iso === 'number' ? iso * 1000 : new Date(iso).getTime();
  const m = Math.floor((Date.now() - t) / 60000);
  if (m < 1) return 'just now';
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  return h < 24 ? `${h}h ago` : `${Math.floor(h / 24)}d ago`;
}
