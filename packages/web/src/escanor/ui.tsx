import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { List } from '@phosphor-icons/react';
import { createContext, useContext, type ReactNode } from 'react';

/**
 * The Escanor mark: the eclipse, the same artwork as the app icon and the website. It carries its own black-and-gold
 * palette on a transparent background, so it sits on any surface. Use this everywhere; do not draw another mark.
 */
export const Logo = ({ size = 44, className = '' }: { size?: number; className?: string }) => (
  <img src="/brand-mark.png" alt="" aria-hidden="true" width={size} height={size} draggable={false} className={`shrink-0 select-none object-contain ${className}`} style={{ width: size, height: size }} />
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
  const look = kind === 'primary' ? 'btn-sheen bg-primary text-on-primary hover:-translate-y-px hover:shadow-[0_12px_28px_-12px_rgb(242_167_59/0.65)]' : kind === 'danger' ? 'border border-error/40 text-error hover:bg-error/10' : 'border border-line-strong text-ink hover:bg-surface-card';
  return (
    <button type={type} onClick={onClick} disabled={disabled} className={`rounded-pill px-5 py-2.5 text-sm font-medium transition duration-150 active:scale-[0.98] focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-primary/25 disabled:opacity-40 disabled:active:scale-100 ${look} ${className}`}>
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
    <div className="fixed inset-0 z-40 flex flex-col justify-end bg-black/60 md:items-center md:justify-center" onClick={onClose}>
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

/** Lets any screen header open the navigation drawer on phones. Null where the sidebar is always visible. */
export const NavContext = createContext<{ open: () => void } | null>(null);

export function MenuButton() {
  const nav = useContext(NavContext);
  if (!nav) return null;
  return (
    <button onClick={nav.open} aria-label="Open menu" className="-ml-2 flex h-9 w-9 shrink-0 items-center justify-center rounded-pill text-body transition hover:bg-surface-card hover:text-ink active:scale-90 md:hidden">
      <List size={22} />
    </button>
  );
}

/** The title bar every main screen shares, so moving between screens never changes the ground under you. */
export function ScreenHeader({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <header className="flex min-h-[52px] items-center gap-2 border-b border-hairline px-4 py-2.5">
      <MenuButton />
      <h1 className="min-w-0 flex-1 truncate font-display text-2xl leading-tight text-ink">{title}</h1>
      {children}
    </header>
  );
}

export const GoogleIcon = ({ size = 17 }: { size?: number }) => (
  <svg viewBox="0 0 24 24" width={size} height={size} aria-hidden>
    <path fill="#4285F4" d="M21.6 12.23c0-.71-.06-1.4-.18-2.05H12v3.88h5.38a4.6 4.6 0 0 1-2 3.02v2.5h3.24c1.89-1.74 2.98-4.3 2.98-7.35Z" />
    <path fill="#34A853" d="M12 22c2.7 0 4.96-.9 6.62-2.42l-3.24-2.5c-.9.6-2.04.96-3.38.96-2.6 0-4.8-1.76-5.59-4.11H3.06v2.58A10 10 0 0 0 12 22Z" />
    <path fill="#FBBC05" d="M6.41 13.93a5.99 5.99 0 0 1 0-3.85V7.5H3.06a10 10 0 0 0 0 9l3.35-2.57Z" />
    <path fill="#EA4335" d="M12 5.98c1.47 0 2.79.5 3.83 1.5l2.87-2.87C16.95 2.99 14.7 2 12 2a10 10 0 0 0-8.94 5.5l3.35 2.58C7.2 7.74 9.4 5.98 12 5.98Z" />
  </svg>
);

/** Both sign-in screens (Escanor and your own hub) share this frame: the form on the left, the eclipse on wide screens. */
export function AuthShell({ title, subtitle, children, footer }: { title: string; subtitle: string; children: ReactNode; footer?: ReactNode }) {
  return (
    <main className="grid min-h-[100dvh] bg-canvas text-ink lg:grid-cols-[minmax(0,1fr)_minmax(0,1.05fr)]">
      <div className="safe-top relative flex min-h-[100dvh] flex-col px-6 pb-8 pt-8">
        <Logo size={36} />
        <div className="mx-auto flex w-full max-w-[400px] flex-1 flex-col justify-center pb-10">
          <h1 className="text-2xl font-semibold tracking-tight text-ink">{title}</h1>
          <p className="mt-1.5 text-sm leading-relaxed text-body">{subtitle}</p>
          <div className="mt-6 space-y-3">{children}</div>
        </div>
        {footer && <div className="text-center">{footer}</div>}
      </div>
      <aside className="relative hidden p-4 lg:block" aria-hidden="true">
        <div className="relative h-full overflow-hidden rounded-2xl border border-hairline bg-canvas">
          <img src="/login-eclipse.webp" alt="" className="absolute inset-0 h-full w-full object-cover object-[50%_18%]" />
          <div className="absolute inset-0 bg-gradient-to-t from-canvas via-canvas/30 to-transparent" />
          <div className="absolute inset-x-0 bottom-0 p-10">
            <p className="max-w-sm text-balance text-3xl font-semibold leading-tight tracking-tight text-ink">When production breaks, Escanor goes to work.</p>
            <p className="mt-3 max-w-sm text-sm text-body">Connect your stack and your agents. Escanor watches, fixes and verifies, even when you are not looking.</p>
          </div>
        </div>
      </aside>
    </main>
  );
}
