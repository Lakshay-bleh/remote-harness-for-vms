import { Browser } from '@capacitor/browser';
import { ArrowSquareOut, CheckCircle, WarningCircle } from '@phosphor-icons/react';
import { useState } from 'react';
import { isNative } from '../../api';
import { escanor } from '../client';
import { announcePlanChange, useLoad } from '../hooks';
import { useEscanorSession } from '../session';
import { ConfirmSheet, Page } from '../settings/parts';
import { Button, Notice, Spinner } from '../ui';
import { bypassText, changeOutcomeText, checkoutOutcome, formatMoney, formatPrice, invoiceLine, meters, planAction, planPrice, renewalText, statusText, yearlySaving, type BillingPlan, type Cycle } from './billing';
import { payWithRazorpay } from './razorpay';

const INVOICES_FIRST = 5;

const openLink = async (url: string) => {
  if (isNative()) await Browser.open({ url });
  else window.open(url, '_blank', 'noopener');
};

/** Your plan, what you have used, the plans you can move to, and your invoices: upgrade, change, or cancel without leaving the app. */
export default function BillingPage({ onBack, onContact }: { onBack: () => void; onContact: () => void }) {
  const { user } = useEscanorSession();
  const sub = useLoad(() => escanor.billingSubscription(), 0);
  const plans = useLoad(() => escanor.billingPlans(), 0);
  const invoices = useLoad(() => escanor.billingInvoices(), 0);
  const [busy, setBusy] = useState<string | null>(null);
  const [message, setMessage] = useState<{ tone: 'info' | 'error'; text: string } | null>(null);
  const [confirmCancel, setConfirmCancel] = useState(false);
  const [change, setChange] = useState<BillingPlan | null>(null);
  const [picked, setPicked] = useState<Cycle | null>(null);
  const [invoiceCount, setInvoiceCount] = useState(INVOICES_FIRST);

  const s = sub.data;
  const cycle: Cycle = picked ?? (s?.plan_id !== 'free' && s?.billing_cycle === 'yearly' ? 'yearly' : 'monthly');
  const say = (text: string, tone: 'info' | 'error' = 'info') => setMessage({ tone, text });
  const names = Object.fromEntries((plans.data ?? []).map((p) => [p.id, p.name]));
  const refresh = () => {
    sub.reload();
    invoices.reload();
    announcePlanChange(); // the usage screens and their limits, wherever they are open
  };

  const subscribe = async (plan: BillingPlan) => {
    setBusy(plan.id);
    setMessage(null);
    try {
      const outcome = checkoutOutcome(await escanor.billingCheckout(plan.id, cycle));
      if (outcome.kind === 'message') return say(outcome.message);
      if (outcome.kind === 'done') {
        say(outcome.message);
        return refresh();
      }
      const paid = await payWithRazorpay({ key: outcome.key, subscriptionId: outcome.subscriptionId, planName: plan.name, name: user?.name, email: user?.email });
      if (paid.kind === 'closed') return say('Payment cancelled. Nothing was charged.');
      if (paid.kind === 'failed') return say(paid.message, 'error');
      // The payment went through at Razorpay; tell Escanor, which checks the signature before it changes the plan.
      try {
        const done = await escanor.billingVerify(paid.response);
        say(`You are on the ${done.plan_name} plan. Thank you.`);
      } catch (e) {
        // Paid, but not yet confirmed here: Razorpay also tells Escanor directly, so the plan follows shortly. Never "nothing was charged".
        say(`Your payment went through, but Escanor could not confirm it yet (${e instanceof Error ? e.message : 'try again'}). Your plan will update shortly; if it does not, contact us.`, 'error');
      }
      refresh();
    } catch (e) {
      say(e instanceof Error ? e.message : 'Could not start checkout. Nothing was charged.', 'error');
    } finally {
      setBusy(null);
    }
  };

  const switchTo = async (plan: BillingPlan) => {
    setBusy(plan.id);
    setMessage(null);
    try {
      say(changeOutcomeText(await escanor.billingChangePlan(plan.id), names));
      refresh();
    } catch (e) {
      say(e instanceof Error ? e.message : 'Could not change the plan. Your plan is unchanged.', 'error');
    } finally {
      setBusy(null);
      setChange(null);
    }
  };

  const cancel = async () => {
    setBusy('cancel');
    try {
      await escanor.billingCancel();
      say('Cancelled. Your plan stays active until the end of the period you paid for, and will not renew.');
      refresh();
    } catch (e) {
      say(e instanceof Error ? e.message : 'Could not cancel. Your plan is unchanged.', 'error');
    } finally {
      setBusy(null);
      setConfirmCancel(false);
    }
  };

  const paid = Boolean(s && s.plan_id !== 'free');
  const bypass = s ? bypassText(s) : null;
  const issue = s?.payment_issue;
  const shown = invoices.data?.slice(0, invoiceCount) ?? [];

  return (
    <Page title="Plan and billing" onBack={onBack}>
      {message && <Notice tone={message.tone === 'error' ? 'error' : 'info'}>{message.text}</Notice>}
      {sub.error && !s && <Notice tone="error">{sub.error}</Notice>}
      {(sub.loading && !s) || (plans.loading && !plans.data) ? <div className="py-10 text-center"><Spinner /></div> : null}
      {s && s.payments && !s.payments.enabled && <Notice tone="warn">Online payments are not switched on yet, so upgrading is unavailable. Contact us and we will set you up.</Notice>}

      {issue && (
        <Notice tone={issue.kind === 'halted' ? 'error' : 'warn'}>
          <span className="flex items-start gap-2"><WarningCircle size={18} className="mt-0.5 shrink-0" aria-hidden /><span>{issue.message}{issue.manage_url && <> <button type="button" className="underline" onClick={() => void openLink(issue.manage_url!)}>Update payment method</button></>}</span></span>
        </Notice>
      )}

      {s && (
        <section className="space-y-3 rounded-xl border border-hairline bg-surface-card p-4">
          <div className="flex items-start justify-between gap-3">
            <div>
              <p className="text-[12px] font-medium uppercase tracking-wide text-muted">Your plan</p>
              <h2 className="font-display text-2xl text-ink">{s.plan_name}</h2>
              {paid && <p className="text-[12.5px] text-muted">Billed {s.billing_cycle === 'yearly' ? 'yearly' : 'monthly'}</p>}
            </div>
            <span className={`rounded-pill px-2.5 py-1 text-[12px] ${s.cancel_at_period_end || issue ? 'bg-warning/15 text-warning' : 'bg-success/15 text-success'}`}>{statusText(s)}</span>
          </div>
          {renewalText(s) && <p className="text-[13.5px] text-body">{renewalText(s)}</p>}
          {s.scheduled_plan_name && !s.cancel_at_period_end && <p className="text-[13.5px] text-body">You are moving to {s.scheduled_plan_name} when this period ends. Choose “Keep this plan” below to stay.</p>}
          {bypass && <p className="text-[13.5px] text-body">{bypass}</p>}
          <ul className="space-y-3 pt-1">
            {meters(s).map((m) => (
              <li key={m.key}>
                <div className="flex items-baseline justify-between text-[13.5px]"><span className="text-body-strong">{m.label}</span><span className="text-muted">{m.text}</span></div>
                {m.percent !== null && <div className="mt-1.5 h-2 overflow-hidden rounded-full bg-canvas" role="progressbar" aria-valuenow={m.percent} aria-valuemin={0} aria-valuemax={100} aria-label={m.label}><div className={`h-full rounded-full ${m.tone === 'full' ? 'bg-error' : m.tone === 'warn' ? 'bg-warning' : 'bg-primary'}`} style={{ width: `${m.percent}%` }} /></div>}
              </li>
            ))}
          </ul>
        </section>
      )}

      {s && plans.data && (
        <section className="space-y-3">
          <div className="flex items-center justify-between gap-3 px-1">
            <h2 className="text-[12px] font-medium uppercase tracking-wide text-muted">Plans</h2>
            <div className="flex rounded-pill border border-hairline bg-surface-card p-0.5 text-[13px]" role="group" aria-label="Billing cycle">
              {(['monthly', 'yearly'] as const).map((c) => (
                <button key={c} type="button" aria-pressed={cycle === c} onClick={() => setPicked(c)} className={`rounded-pill px-3 py-1 ${cycle === c ? 'bg-primary text-on-primary' : 'text-body'}`}>{c === 'monthly' ? 'Monthly' : 'Yearly'}</button>
              ))}
            </div>
          </div>
          {cycle === 'yearly' && <p className="px-1 text-[12.5px] text-muted">A year costs ten months: two are free.</p>}
          {paid && s.billing_cycle !== cycle && <p className="px-1 text-[12.5px] text-muted">A switch between plans keeps your current billing cycle ({s.billing_cycle === 'yearly' ? 'yearly' : 'monthly'}). To change the cycle, cancel and subscribe again after it ends.</p>}
          {plans.data.map((plan) => {
            const action = planAction(plan, s);
            const saving = cycle === 'yearly' ? yearlySaving(plan) : null;
            return (
              <article key={plan.id} className={`rounded-xl border bg-surface-card p-4 ${action.kind === 'current' ? 'border-primary/60' : 'border-hairline'}`}>
                <div className="flex items-baseline justify-between gap-3">
                  <h3 className="font-display text-xl text-ink">{plan.name}</h3>
                  <span className="text-[14px] text-body-strong">{formatPrice(planPrice(plan, cycle), cycle)}</span>
                </div>
                {saving && <p className="text-right text-[12px] text-success">{saving}</p>}
                <p className="mt-1 text-[13.5px] text-muted">{plan.description}</p>
                <ul className="mt-3 space-y-1.5">
                  {plan.features.map((f) => <li key={f} className="flex items-start gap-2 text-[13.5px] text-body"><CheckCircle size={16} weight="fill" className="mt-0.5 shrink-0 text-primary" aria-hidden />{f}</li>)}
                </ul>
                {action.kind === 'upgrade' && <Button className="mt-4 w-full" disabled={busy !== null || s.payments?.enabled === false} onClick={() => void subscribe(plan)}>{busy === plan.id ? 'Opening payment…' : action.label}</Button>}
                {action.kind === 'switch' && (
                  <>
                    <Button className="mt-4 w-full" kind={action.effect === 'now' ? 'primary' : 'quiet'} disabled={busy !== null} onClick={() => setChange(plan)}>{busy === plan.id ? 'Changing…' : action.label}</Button>
                    <p className="mt-1.5 text-[12.5px] leading-snug text-muted">{action.note}</p>
                  </>
                )}
                {action.kind === 'contact' && <Button kind="quiet" className="mt-4 w-full" onClick={onContact}>{action.label}</Button>}
                {action.kind === 'current' && !action.undo && <p className="mt-3 text-[13px] font-medium text-primary">{action.label}</p>}
                {action.kind === 'current' && action.undo && <Button kind="quiet" className="mt-4 w-full" disabled={busy !== null} onClick={() => void switchTo(plan)}>{busy === plan.id ? 'Updating…' : action.label}</Button>}
                {action.kind === 'scheduled' && <p className="mt-3 text-[13px] font-medium text-warning">{action.label}</p>}
              </article>
            );
          })}
        </section>
      )}

      {paid && !s?.cancel_at_period_end && (
        <section>
          <Button kind="danger" className="w-full" disabled={busy !== null} onClick={() => setConfirmCancel(true)}>Cancel my subscription</Button>
          <p className="mt-1.5 px-1 text-[12px] leading-relaxed text-muted">You keep your plan until the end of the period you paid for. Nothing is refunded automatically; see Refunds and cancellation in Privacy and legal.</p>
        </section>
      )}

      {paid && (
        <section className="space-y-2">
          <h2 className="px-1 text-[12px] font-medium uppercase tracking-wide text-muted">Invoices</h2>
          {invoices.loading && !invoices.data && <div className="py-3 text-center"><Spinner /></div>}
          {invoices.error && !invoices.data && <Notice tone="error">{invoices.error}</Notice>}
          {invoices.data && invoices.data.length === 0 && <p className="px-1 text-[13.5px] text-muted">No invoices yet. They appear here after your first payment.</p>}
          {shown.length > 0 && (
            <ul className="divide-y divide-hairline overflow-hidden rounded-xl border border-hairline bg-surface-card">
              {shown.map((i) => (
                <li key={i.id} className="flex items-center justify-between gap-3 px-4 py-3">
                  <div className="min-w-0">
                    <p className="truncate text-[14px] text-body-strong">{i.amount === null ? '' : formatMoney(i.amount, i.currency)} <span className="text-muted">{i.date ? new Date(i.date).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' }) : ''}</span></p>
                    <p className={`truncate text-[12.5px] ${i.status === 'failed' ? 'text-error' : 'text-muted'}`}>{invoiceLine(i)}</p>
                  </div>
                  {i.url && <button type="button" className="shrink-0 p-2 text-primary" aria-label="Open invoice" onClick={() => void openLink(i.url!)}><ArrowSquareOut size={20} aria-hidden /></button>}
                </li>
              ))}
            </ul>
          )}
          {invoices.data && invoices.data.length > invoiceCount && <Button kind="quiet" className="w-full" onClick={() => setInvoiceCount((n) => n + INVOICES_FIRST * 2)}>Show more</Button>}
        </section>
      )}

      <p className="px-1 text-[12px] leading-relaxed text-muted">Payments are handled by Razorpay in its own secure form. Your card, UPI or bank details are typed there and never reach Escanor.</p>

      {confirmCancel && <ConfirmSheet title="Cancel your subscription?" body="Your plan stays active until the end of the period you paid for, then it will not renew and your account moves to Free. You can subscribe again whenever you like." action="Cancel subscription" busy={busy === 'cancel'} onClose={() => setConfirmCancel(false)} onConfirm={() => void cancel()} />}
      {change && s && (() => { const a = planAction(change, s); return a.kind === 'switch' ? <ConfirmSheet title={a.label} body={a.note} action={a.effect === 'now' ? 'Upgrade now' : 'Switch at period end'} busy={busy === change.id} onClose={() => setChange(null)} onConfirm={() => void switchTo(change)} /> : null; })()}
    </Page>
  );
}
