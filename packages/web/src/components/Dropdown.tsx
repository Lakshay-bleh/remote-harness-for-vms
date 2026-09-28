import { useEffect, useRef, useState, type ReactNode } from 'react';

export function Chip({ icon, label }: { icon?: ReactNode; label: string }) {
  return (
    <span className="flex items-center gap-1.5 rounded-pill border border-hairline bg-surface-card px-2.5 py-1 text-[12px] text-muted">
      {icon}
      <span className="max-w-[140px] truncate">{label}</span>
    </span>
  );
}

export default function Dropdown<T extends string>({
  icon,
  value,
  options,
  onChange,
  disabled,
}: {
  icon?: ReactNode;
  value: T;
  options: { value: T; label: string }[];
  onChange: (value: T) => void;
  disabled?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function onDocClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener('mousedown', onDocClick);
    return () => document.removeEventListener('mousedown', onDocClick);
  }, []);

  const current = options.find((o) => o.value === value);

  return (
    <div ref={ref} className="relative">
      <button
        disabled={disabled}
        onClick={() => setOpen((o) => !o)}
        className="flex items-center gap-1.5 rounded-pill border border-hairline bg-surface-card px-2.5 py-1 text-[12px] text-body transition hover:bg-surface-cream-strong disabled:opacity-40"
      >
        {icon}
        <span className="max-w-[120px] truncate">{current?.label ?? value}</span>
        <svg width="9" height="9" viewBox="0 0 24 24" fill="none" className={`shrink-0 transition-transform ${open ? 'rotate-180' : ''}`}>
          <path d="M6 9l6 6 6-6" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>
      {open && (
        <div className="absolute bottom-full left-0 z-20 mb-1.5 min-w-[170px] overflow-hidden rounded-lg border border-hairline bg-canvas py-1 shadow-elevated">
          {options.map((o) => (
            <button
              key={o.value}
              onClick={() => {
                onChange(o.value);
                setOpen(false);
              }}
              className={`flex w-full items-center px-3 py-2 text-left text-[13px] transition hover:bg-surface-card ${
                o.value === value ? 'font-medium text-primary' : 'text-body'
              }`}
            >
              {o.label}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
