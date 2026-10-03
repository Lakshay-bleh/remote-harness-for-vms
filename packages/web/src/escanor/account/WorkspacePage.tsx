import { ClockCounterClockwise, Globe, PencilSimple, Users } from '@phosphor-icons/react';
import { useState } from 'react';
import { ApiError, escanor, type OrgMember } from '../client';
import { useLoad } from '../hooks';
import { ChoiceSheet, Group, Page, Row } from '../settings/parts';
import { ago, Button, Notice, Sheet, Spinner } from '../ui';
import { cleanWorkspaceName, describeAction, ENVIRONMENTS, environmentLabel, REGIONS, regionLabel, roleLabel } from './workspace';

const FIELD = 'mt-1 w-full rounded-md border border-line-strong bg-surface-card px-3 py-3 text-[15px] text-ink outline-none transition placeholder:text-muted-soft focus:border-primary focus:ring-4 focus:ring-primary/15';

/** Your workspace: its name and defaults, the people in it, and what happened lately. */
export default function WorkspacePage({ onBack }: { onBack: () => void }) {
  const ws = useLoad(() => escanor.workspaceSettings(), 0);
  const org = useLoad(() => escanor.organization().catch((e) => (e instanceof ApiError && e.status === 404 ? null : Promise.reject(e))), 0);
  const log = useLoad(() => escanor.auditLogs(50).catch(() => []), 0);
  const [editName, setEditName] = useState(false);
  const [name, setName] = useState('');
  const [picker, setPicker] = useState<null | 'region' | 'environment'>(null);
  const [role, setRole] = useState<OrgMember | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const w = ws.data;

  const save = async (patch: { workspace_name?: string; default_region?: string; environment?: string }) => {
    setSaving(true);
    setError(null);
    try {
      await escanor.updateWorkspaceSettings(patch);
      ws.reload();
      return true;
    } catch (e) {
      setError(e instanceof ApiError && e.status === 404 ? 'Only owners and admins can change workspace settings.' : e instanceof Error ? e.message : 'Could not save.');
      return false;
    } finally {
      setSaving(false);
    }
  };

  return (
    <Page title="Workspace and team" onBack={onBack}>
      {error && <Notice tone="error">{error}</Notice>}
      {ws.loading && !w && <div className="py-8 text-center"><Spinner /></div>}
      {w && (
        <Group title="Workspace" footer="Only owners and admins can change these.">
          <Row icon={<PencilSimple size={18} />} label="Name" value={w.workspace_name} onClick={() => { setName(w.workspace_name); setEditName(true); }} />
          <Row icon={<Globe size={18} />} label="Region" value={regionLabel(w.default_region)} onClick={() => setPicker('region')} disabled={saving} />
          <Row icon={<Globe size={18} />} label="Environment" value={environmentLabel(w.environment)} onClick={() => setPicker('environment')} disabled={saving} />
          <Row label="Connected machines" value={w.connected_devices} />
        </Group>
      )}

      <section>
        <h2 className="mb-1.5 px-1 text-[12px] font-medium uppercase tracking-wide text-muted">Team</h2>
        <div className="divide-y divide-hairline overflow-hidden rounded-xl border border-hairline bg-surface-card">
          {org.loading && !org.data ? <div className="p-4 text-center"><Spinner /></div> : !org.data ? <p className="px-3.5 py-3 text-sm text-muted">Only owners and admins can see the team.</p> : org.data.members.map((m) => (
            <Row key={m.user_id} icon={<Users size={18} />} label={m.name || m.email} sub={m.name ? m.email : undefined} value={roleLabel(m.role)} onClick={org.data!.your_role === 'owner' && m.role !== 'owner' ? () => setRole(m) : undefined} />
          ))}
        </div>
      </section>

      <section>
        <h2 className="mb-1.5 px-1 text-[12px] font-medium uppercase tracking-wide text-muted">Recent activity</h2>
        <div className="divide-y divide-hairline overflow-hidden rounded-xl border border-hairline bg-surface-card">
          {log.loading && !log.data ? <div className="p-4 text-center"><Spinner /></div> : (log.data ?? []).length === 0 ? <p className="px-3.5 py-3 text-sm text-muted">Nothing yet.</p> : (log.data ?? []).map((l, i) => (
            <Row key={l.id ?? i} icon={<ClockCounterClockwise size={18} />} label={describeAction(l.action)} sub={[l.actor_email, l.target, l.detail].filter(Boolean).join(' · ')} value={ago(l.created_at)} />
          ))}
        </div>
      </section>

      {editName && (
        <Sheet title="Workspace name" onClose={() => setEditName(false)}>
          <form className="space-y-3" onSubmit={async (e) => { e.preventDefault(); const n = cleanWorkspaceName(name); if (n && (await save({ workspace_name: n }))) setEditName(false); }}>
            <input value={name} onChange={(e) => setName(e.target.value)} maxLength={80} autoFocus aria-label="Workspace name" className={FIELD} />
            <Button type="submit" className="w-full" disabled={saving || !cleanWorkspaceName(name)}>{saving ? 'Saving…' : 'Save'}</Button>
          </form>
        </Sheet>
      )}
      {picker === 'region' && w && <ChoiceSheet title="Region" options={REGIONS} value={w.default_region as (typeof REGIONS)[number]['value']} onPick={(v) => void save({ default_region: v })} onClose={() => setPicker(null)} />}
      {picker === 'environment' && w && <ChoiceSheet title="Environment" options={ENVIRONMENTS} value={w.environment as (typeof ENVIRONMENTS)[number]['value']} onPick={(v) => void save({ environment: v })} onClose={() => setPicker(null)} />}
      {role && (
        <ChoiceSheet title={`Role for ${role.name || role.email}`} options={[{ value: 'member', label: 'Member', hint: 'Uses the workspace' }, { value: 'admin', label: 'Admin', hint: 'Manages members and settings' }]} value={role.role === 'admin' ? 'admin' : 'member'} onPick={(v) => void escanor.setMemberRole(role.user_id, v).then(() => org.reload()).catch((e) => setError(e instanceof Error ? e.message : 'Could not change the role.'))} onClose={() => setRole(null)} />
      )}
    </Page>
  );
}
