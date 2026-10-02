import { Envelope, SignOut, User } from '@phosphor-icons/react';
import { useState } from 'react';
import { describeUsage } from '@remote-harness/shared/escanor';
import { escanor } from '../client';
import { useLoad } from '../hooks';
import { LINKS, openExternal } from '../links';
import { useEscanorSession } from '../session';
import { Button, Notice, Sheet, Spinner } from '../ui';
import { Avatar, ConfirmSheet, Group, Page, Row } from './parts';

/** Name and sign-in. The name is edited here and shared with the website: it is the same account. */
export function AccountPage({ onBack }: { onBack: () => void }) {
  const { user, signOut, refreshUser } = useEscanorSession();
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(user?.name ?? '');
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [confirmOut, setConfirmOut] = useState(false);

  const save = async () => {
    const next = name.replace(/\s+/g, ' ').trim();
    if (!next) return setError('Please enter a name.');
    if (next.length > 80) return setError('A name can be up to 80 characters.');
    setSaving(true);
    setError(null);
    try {
      await escanor.updateProfile(next);
      await refreshUser();
      setEditing(false);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save your name.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Page title="Account" onBack={onBack}>
      <div className="flex flex-col items-center gap-2 pt-2 text-center">
        <Avatar name={user?.name} email={user?.email} size={72} />
        <p className="text-lg text-ink">{user?.name}</p>
        <p className="text-sm text-muted">{user?.email}</p>
      </div>

      <Group title="Profile">
        <Row icon={<User size={18} />} label="Name" value={user?.name} onClick={() => { setName(user?.name ?? ''); setError(null); setEditing(true); }} />
        <Row icon={<Envelope size={18} />} label="Email" value={user?.email} />
        <Row label="Sign-in" value="Google" />
      </Group>

      <Group title="On the web" footer="Billing, team members and data requests are managed on the Escanor website.">
        <Row label="Account settings" onClick={() => openExternal(LINKS.accountSettings)} />
        <Row label="Billing and plan" onClick={() => openExternal(LINKS.billing)} />
      </Group>

      <Group>
        <Row icon={<SignOut size={18} />} label="Sign out" danger onClick={() => setConfirmOut(true)} />
      </Group>

      {editing && (
        <Sheet title="Your name" onClose={() => setEditing(false)}>
          <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); void save(); }}>
            {error && <Notice tone="error">{error}</Notice>}
            <input value={name} onChange={(e) => setName(e.target.value)} autoFocus maxLength={80} autoComplete="name" aria-label="Name" className="w-full rounded-md border border-line-strong bg-surface-card px-3 py-3 text-base text-ink outline-none focus:border-primary focus:ring-4 focus:ring-primary/15" />
            <Button type="submit" className="w-full" disabled={saving}>{saving ? 'Saving…' : 'Save'}</Button>
          </form>
        </Sheet>
      )}
      {confirmOut && <ConfirmSheet title="Sign out?" body="You will need to sign in again. The computers paired with this phone are removed from it too (you can pair them again any time). Nothing on those computers is changed." action="Sign out" onConfirm={() => void signOut()} onClose={() => setConfirmOut(false)} />}
    </Page>
  );
}

/** What the plan is and what today's use looks like: the same numbers as the website. */
export function UsagePage({ onBack }: { onBack: () => void }) {
  const usage = useLoad(() => escanor.usage(), 60000);
  const plan = useLoad(() => escanor.subscription().catch(() => null), 0);
  const u = usage.data ? describeUsage(usage.data) : null;
  const month = usage.data?.month;
  const tone = u?.level === 'full' ? 'bg-error' : u?.level === 'warn' ? 'bg-warning' : 'bg-primary';

  return (
    <Page title="Plan and usage" onBack={onBack}>
      <Group title="Plan" footer="Change your plan on the website.">
        <Row label="Current plan" value={plan.loading && !plan.data ? <Spinner /> : String(plan.data?.plan_name ?? 'Free')} />
        {plan.data?.status ? <Row label="Status" value={<span className="capitalize">{String(plan.data.status).replace(/_/g, ' ')}</span>} /> : null}
        <Row label="Manage plan" onClick={() => openExternal(LINKS.billing)} />
      </Group>

      <section>
        <h2 className="mb-1.5 px-1 text-[12px] font-medium uppercase tracking-wide text-muted">Today</h2>
        {usage.loading && !u ? <div className="py-6 text-center"><Spinner /></div> : u ? (
          <div className="rounded-xl border border-hairline bg-surface-card p-4">
            <p className={`text-[15px] ${u.level === 'full' ? 'text-error' : u.level === 'warn' ? 'text-warning' : 'text-ink'}`}>{u.messages}</p>
            {u.tokens && <p className="mt-0.5 text-[12px] text-muted">{u.tokens}</p>}
            {u.ratio !== null && (
              <div className="mt-3 h-2 overflow-hidden rounded-full bg-canvas" role="progressbar" aria-valuenow={Math.round(u.ratio * 100)} aria-valuemin={0} aria-valuemax={100} aria-label="Daily messages used">
                <div className={`h-full rounded-full transition-all ${tone}`} style={{ width: `${Math.round(u.ratio * 100)}%` }} />
              </div>
            )}
          </div>
        ) : usage.error ? <Notice tone="error">{usage.error}</Notice> : null}
      </section>

      {month && (month.requests > 0 || month.input_tokens > 0) && (
        <Group title="This month" footer={usage.data?.cost_is_estimate ? 'Cost is an estimate.' : undefined}>
          <Row label="Requests" value={month.requests.toLocaleString()} />
          <Row label="Tokens in / out" value={`${month.input_tokens.toLocaleString()} / ${month.output_tokens.toLocaleString()}`} />
          {month.cost_usd !== null && <Row label="Cost" value={`$${month.cost_usd.toFixed(2)}`} />}
        </Group>
      )}
    </Page>
  );
}
