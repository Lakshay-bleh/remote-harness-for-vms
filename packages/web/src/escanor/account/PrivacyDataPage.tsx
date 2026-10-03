import { CopySimple, Export, FileText, Plus, ShieldCheck } from '@phosphor-icons/react';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { POLICY_VERSION } from '../../legal/content';
import { escanor, type PrivacyRequest } from '../client';
import { useLoad } from '../hooks';
import { ChoiceSheet, Group, Page, Row, SwitchRow } from '../settings/parts';
import { Button, Notice, Sheet, Spinner } from '../ui';
import { copyExport, exportText, shareExport, sizeLabel } from './dataExport';
import { describeDue, isFinished, OPTIONAL_CONSENTS, REQUEST_TYPES, requestProblem, statusLabel, type RequestType } from './privacy';

const FIELD = 'mt-1 w-full rounded-md border border-line-strong bg-surface-card px-3 py-3 text-[15px] text-ink outline-none transition placeholder:text-muted-soft focus:border-primary focus:ring-4 focus:ring-primary/15';

/** Your choices, a copy of your data, and requests about it, all inside the app. */
export default function PrivacyDataPage({ onBack, initialType }: { onBack: () => void; initialType?: RequestType }) {
  const consents = useLoad(() => escanor.consents(), 0);
  const requests = useLoad(() => escanor.privacyRequests(), 0);
  const [saving, setSaving] = useState<string | null>(null);
  const [notice, setNotice] = useState<{ tone: 'info' | 'error'; text: string } | null>(null);
  const [data, setData] = useState<{ text: string; scope?: string } | null>(null);
  const [exporting, setExporting] = useState(false);
  const [composing, setComposing] = useState<RequestType | null>(initialType ?? null);
  const [open, setOpen] = useState<PrivacyRequest | null>(null);

  const granted = new Map((consents.data ?? []).map((c) => [c.purpose, c.granted]));
  const toggle = async (purpose: string, grant: boolean) => {
    setSaving(purpose);
    setNotice(null);
    try {
      await escanor.recordConsent(purpose, grant, POLICY_VERSION);
      consents.reload();
    } catch (e) {
      setNotice({ tone: 'error', text: e instanceof Error ? e.message : 'Could not save that choice.' });
    } finally {
      setSaving(null);
    }
  };

  const prepare = async () => {
    setExporting(true);
    setNotice(null);
    try {
      const json = await escanor.exportMyData();
      setData({ text: exportText(json), scope: typeof json.scope === 'string' ? json.scope : undefined });
    } catch (e) {
      setNotice({ tone: 'error', text: e instanceof Error ? e.message : 'Could not get your data.' });
    } finally {
      setExporting(false);
    }
  };

  return (
    <Page title="Privacy and your data" onBack={onBack}>
      {notice && <Notice tone={notice.tone === 'error' ? 'error' : 'info'}>{notice.text}</Notice>}

      <Group title="Your choices" footer="None of these is needed to use Escanor, and each takes effect when you change it.">
        {consents.loading && !consents.data ? <div className="p-4 text-center"><Spinner /></div> : consents.error && !consents.data ? <p className="p-3.5 text-sm text-error">Could not load your choices.</p> : OPTIONAL_CONSENTS.map((c) => <SwitchRow key={c.purpose} label={c.label} sub={c.description} on={granted.get(c.purpose) === true} disabled={saving !== null} onChange={(v) => void toggle(c.purpose, v)} />)}
      </Group>

      <Group title="A copy of your data" footer="Your account records as a JSON file: profile, workspaces, your choices and requests. It never contains passwords or access tokens.">
        <Row icon={<FileText size={18} />} label={exporting ? 'Getting it…' : 'Get my data'} sub="Prepares the file so you can copy or save it" onClick={() => void prepare()} chevron={false} disabled={exporting} />
      </Group>

      <section>
        <div className="mb-1.5 flex items-center justify-between px-1">
          <h2 className="text-[12px] font-medium uppercase tracking-wide text-muted">Your requests</h2>
          <button type="button" onClick={() => setComposing('access')} className="flex items-center gap-1 text-[13px] text-primary"><Plus size={14} weight="bold" aria-hidden /> New request</button>
        </div>
        <div className="divide-y divide-hairline overflow-hidden rounded-xl border border-hairline bg-surface-card">
          {requests.loading && !requests.data ? <div className="p-4 text-center"><Spinner /></div> : (requests.data ?? []).length === 0 ? <p className="px-3.5 py-3 text-sm text-muted">No requests yet. Ask to correct your data, withdraw a consent, or make a complaint, and track it here.</p> : (requests.data ?? []).map((r) => (
            <Row key={r.id} icon={<ShieldCheck size={18} />} label={r.subject} sub={`${r.reference} · ${REQUEST_TYPES.find((t) => t.value === r.request_type)?.label ?? r.request_type}${isFinished(r.status) ? '' : ` · ${describeDue(r.status === 'received' ? r.acknowledge_by : r.resolve_by)}`}`} value={statusLabel(r.status)} onClick={() => void escanor.privacyRequest(r.id).then(setOpen).catch(() => setOpen(r))} />
          ))}
        </div>
      </section>

      {data && <DataSheet text={data.text} scope={data.scope} onClose={() => setData(null)} />}
      {composing && <NewRequest start={composing} onClose={() => setComposing(null)} onSent={() => { setComposing(null); requests.reload(); }} />}
      {open && <RequestSheet r={open} onClose={() => setOpen(null)} />}
    </Page>
  );
}

function DataSheet({ text, scope, onClose }: { text: string; scope?: string; onClose: () => void }) {
  const [state, setState] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const run = async (what: () => Promise<string>) => {
    setBusy(true);
    try {
      setState(await what());
    } catch (e) {
      setState(e instanceof Error ? e.message : 'That did not work.');
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet title="Your data" onClose={onClose}>
      <div className="space-y-3">
        <p className="text-sm text-body">Ready: {sizeLabel(text)}. Save it as a file, or copy it.</p>
        <Button className="flex w-full items-center justify-center gap-2" disabled={busy} onClick={() => void run(async () => ((await shareExport(text)) === 'cancelled' ? '' : 'Done.'))}><Export size={18} aria-hidden /> Save or send as a file</Button>
        <Button kind="quiet" className="flex w-full items-center justify-center gap-2" disabled={busy} onClick={() => void run(async () => (await copyExport(text), 'Copied to the clipboard.'))}><CopySimple size={18} aria-hidden /> Copy to the clipboard</Button>
        {state && <Notice>{state}</Notice>}
        {scope && <p className="text-[12px] leading-relaxed text-muted">{scope}</p>}
      </div>
    </Sheet>
  );
}

function NewRequest({ start, onClose, onSent }: { start: RequestType; onClose: () => void; onSent: () => void }) {
  const [type, setType] = useState<RequestType>(start);
  const [subject, setSubject] = useState('');
  const [details, setDetails] = useState('');
  const [picker, setPicker] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState<PrivacyRequest | null>(null);
  const meta = REQUEST_TYPES.find((t) => t.value === type)!;
  const problem = useMemo(() => requestProblem({ request_type: type, subject, details }), [type, subject, details]);

  const send = useCallback(async () => {
    if (problem) return setError(problem);
    setBusy(true);
    setError(null);
    try {
      setSent(await escanor.openPrivacyRequest({ request_type: type, subject: subject.trim(), details: details.trim() }));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not send that. Try again.');
    } finally {
      setBusy(false);
    }
  }, [problem, type, subject, details]);

  if (sent) {
    return (
      <Sheet title="Request received" onClose={onSent}>
        <div className="space-y-3">
          <p className="text-sm text-body">Your reference is <b className="font-mono text-ink">{sent.reference}</b>. A person looks at it; it is acknowledged {describeDue(sent.acknowledge_by)} and answered {describeDue(sent.resolve_by)}. You can follow it under Your requests.</p>
          <Button className="w-full" onClick={onSent}>Done</Button>
        </div>
      </Sheet>
    );
  }
  return (
    <>
      <Sheet title="New request" onClose={onClose}>
        <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); void send(); }}>
          {error && <Notice tone="error">{error}</Notice>}
          <button type="button" onClick={() => setPicker(true)} className="w-full rounded-md border border-line-strong bg-surface-card px-3 py-3 text-left"><span className="block text-[12px] text-muted">What is this about?</span><span className="block text-[15px] text-ink">{meta.label}</span></button>
          <p className="text-[12px] text-muted">{meta.hint}</p>
          <label className="block text-sm text-body">Title<input value={subject} onChange={(e) => setSubject(e.target.value)} maxLength={200} placeholder="A few words" className={FIELD} /></label>
          <label className="block text-sm text-body">Details (optional)<textarea value={details} onChange={(e) => setDetails(e.target.value)} rows={4} maxLength={5000} className={FIELD} /></label>
          <p className="text-[12px] text-muted">Do not include passwords, card numbers or access tokens.</p>
          <Button type="submit" className="w-full" disabled={busy || Boolean(problem)}>{busy ? 'Sending…' : 'Send request'}</Button>
        </form>
      </Sheet>
      {picker && <ChoiceSheet title="What is this about?" options={REQUEST_TYPES} value={type} onPick={setType} onClose={() => setPicker(false)} />}
    </>
  );
}

function RequestSheet({ r, onClose }: { r: PrivacyRequest; onClose: () => void }) {
  const [full, setFull] = useState(r);
  useEffect(() => setFull(r), [r]);
  return (
    <Sheet title={r.reference} onClose={onClose}>
      <div className="space-y-3 text-sm">
        <p className="text-ink">{full.subject}</p>
        <p className="text-muted">{REQUEST_TYPES.find((t) => t.value === full.request_type)?.label ?? full.request_type} · {statusLabel(full.status)}{isFinished(full.status) ? '' : `, ${describeDue(full.status === 'received' ? full.acknowledge_by : full.resolve_by)}`}</p>
        {full.resolution_note && <Notice>{full.resolution_note}</Notice>}
        {(full.events ?? []).length > 0 && (
          <ol className="space-y-2 border-l border-hairline pl-3">
            {full.events!.map((e, i) => <li key={i} className="text-[13px]"><span className="text-ink">{statusLabel(e.to_status)}</span><span className="text-muted"> · {new Date(e.created_at).toLocaleString()}</span>{e.note && <span className="block text-body">{e.note}</span>}</li>)}
          </ol>
        )}
      </div>
    </Sheet>
  );
}
