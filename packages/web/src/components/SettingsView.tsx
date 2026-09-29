import { getHubUrl, isNative } from '../api';
import { useEscanor } from '../escanor/EscanorProvider';
import PageShell from './PageShell';

const Row = ({ label, value }: { label: string; value: string }) => (
  <div className="flex items-start justify-between gap-4 border-t border-hairline px-4 py-3 first:border-t-0">
    <span className="text-[13px] text-muted">{label}</span>
    <span className="min-w-0 break-all text-right text-[13px] text-ink">{value}</span>
  </div>
);

export default function SettingsView({ className, onMenu }: { className: string; onMenu: () => void }) {
  const { session, hubId, signOut } = useEscanor();
  return (
    <PageShell title="Settings" onMenu={onMenu} className={className}>
      <div className="mx-auto max-w-2xl px-4 py-5">
        <h3 className="mb-2 text-[11px] font-medium uppercase tracking-wide text-muted-soft">Account</h3>
        <div className="mb-6 overflow-hidden rounded-xl border border-hairline bg-canvas">
          <Row label="Name" value={session?.user.name ?? '—'} />
          <Row label="Email" value={session?.user.email ?? 'Signed in with hub password'} />
          <Row label="Hub ID" value={hubId ?? '—'} />
          <Row label="Hub" value={(isNative() ? getHubUrl() : window.location.origin) || '—'} />
        </div>
        <button onClick={signOut} className="rounded-md border border-hairline px-4 py-2.5 text-sm text-error hover:bg-surface-card">
          Sign out
        </button>
      </div>
    </PageShell>
  );
}
