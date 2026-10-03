import { CheckCircle, Lock } from '@phosphor-icons/react';
import { useState } from 'react';
import { escanor } from '../client';
import { useLoad } from '../hooks';
import { useEscanorSession } from '../session';
import { ConfirmSheet, Page } from '../settings/parts';
import { Button, Notice, Spinner } from '../ui';
import { checkoutOutcome, formatPrice, meters, planAction, renewalText, statusText, type BillingPlan } from './billing';
import { payWithRazorpay } from './razorpay';

/** Your plan, what you have used, and the plans you can move to, with payment inside the app. */
export default function BillingPage({ onBack, onContact }: { onBack: () => void; onContact: () => void }) {
  const { user } = useEscanorSession();
  const sub = useLoad(() => escanor.billingSubscription(), 0);
  const plans = useLoad(() => escanor.billingPlans(), 0);
  const [busy, setBusy] = useState<string | null>(null);
  const [message, setMessage] = useState<{ tone: 'info' | 'error'; text: string } | null>(null);
  const [confirmCancel, setConfirmCancel] = useState(false);

  const s = sub.data;
  const say = (text: string, tone: 'info' | 'error' = 'info') => setMessage({ tone, text });

  const upgrade = async (plan: BillingPlan) => {
    setBusy(plan.id);
    setMessage(null);
    try {
      const outcome = checkoutOutcome(await escanor.billingCheckout(plan.id));
      if (outcome.kind === 'message') return say(outcome.message);
      if (outcome.kind === 'done') {
        say(outcome.message);
        return sub.reload();
      }
      const paid = await payWithRazorpay({ key: outcome.key, subscriptionId: outcome.subscriptionId, planName: plan.name, name: user?.name, email: user?.email });
      if (paid.kind === 'closed') return say('Payment cancelled. Nothing was charged.');
      if (paid.kind === 'failed') return say(paid.message, 'error');
      // The payment went through at Razorpay; tell Escanor, which checks the signature before it changes the plan.
      const done = await escanor.billingVerify(paid.response);
      say(`You are on the ${done.plan_name} plan. Thank you.`);
      sub.reload();
    } catch (e) {
      say(e instanceof Error ? e.message : 'Could not start checkout. Nothing was charged.', 'error');
    } finally {
      setBusy(null);
    }
  };

  const cancel = async () => {
    setBusy('cancel');
    try {
      await escanor.billingCancel();
      say('Cancelled. Your plan stays active until the end of the period you paid for, and will not renew.');
      sub.reload();
    } catch (e) {
      say(e instanceof Error ? e.message : 'Could not cancel. Your plan is unchanged.', 'error');
    } finally {
      setBusy(null);
      setConfirmCancel(false);
    }
  };

  const paid = s && s.plan_id !== 'free';

  return (
    <Page title="Plan and billing" onBack={onBack}>
      {message && <Notice tone={message.tone === 'error' ? 'error' : 'info'}>{message.text}</Notice>}
      {sub.error && !s && <Notice tone="error">{sub.error}</Notice>}
      {(sub.loading && !s) || (plans.loading && !plans.data) ? <div className="py-10 text-center"><Spinner /></div> : null}

      {s && (
        <section className="space-y-3 rounded-xl border border-hairline bg-surface-card p-4">
          <div className="flex items-start justify-between gap-3">
            <div>
              <p className="text-[12px] font-medium uppercase tracking-wide text-muted">Your plan</p>
              <h2 className="font-display text-2xl text-ink">{s.plan_name}</h2>
            </div>
            <span className={`rounded-pill px-2.5 py-1 text-[12px] ${s.cancel_at_period_end ? 'bg-warning/15 text-warning' : 'bg-success/15 text-success'}`}>{statusText(s)}</span>
          </div>
          {renewalText(s) && <p className="text-[13.5px] text-body">{renewalText(s)}</p>}
          {s.billing_bypass && <p className="text-[13.5px] text-body">Your account has full access, with no plan limits.</p>}
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
          <h2 className="px-1 text-[12px] font-medium uppercase tracking-wide text-muted">Plans</h2>
          {plans.data.map((plan) => {
            const action = planAction(plan, s);
            return (
              <article key={plan.id} className={`rounded-xl border bg-surface-card p-4 ${action.kind === 'current' ? 'border-primary/60' : 'border-hairline'}`}>
                <div className="flex items-baseline justify-between gap-3">
                  <h3 className="font-display text-xl text-ink">{plan.name}</h3>
                  <span className="text-[14px] text-body-strong">{formatPrice(plan.price_monthly_inr)}</span>
                </div>
                <p className="mt-1 text-[13.5px] text-muted">{plan.description}</p>
                <ul className="mt-3 space-y-1.5">
                  {plan.features.map((f) => <li key={f} className="flex items-start gap-2 text-[13.5px] text-body"><CheckCircle size={16} weight="fill" className="mt-0.5 shrink-0 text-primary" aria-hidden />{f}</li>)}
                </ul>
                {action.kind === 'upgrade' && <Button className="mt-4 w-full" disabled={busy !== null} onClick={() => void upgrade(plan)}>{busy === plan.id ? 'Opening payment…' : action.label}</Button>}
                {action.kind === 'contact' && <Button kind="quiet" className="mt-4 w-full" onClick={onContact}>{action.label}</Button>}
                {action.kind === 'current' && <p className="mt-3 text-[13px] font-medium text-primary">{action.label}</p>}
                {action.kind === 'locked' && <p className="mt-3 flex items-start gap-2 text-[12.5px] leading-snug text-muted"><Lock size={14} className="mt-0.5 shrink-0" aria-hidden />{action.why}</p>}
              </article>
            );
          })}
        </section>
      )}

      {paid && !s.cancel_at_period_end && !s.billing_bypass && (
        <section>
          <Button kind="danger" className="w-full" disabled={busy !== null} onClick={() => setConfirmCancel(true)}>Cancel my subscription</Button>
          <p className="mt-1.5 px-1 text-[12px] leading-relaxed text-muted">You keep your plan until the end of the period you paid for. Nothing is refunded automatically; see Refunds and cancellation in Privacy and legal.</p>
        </section>
      )}

      <p className="px-1 text-[12px] leading-relaxed text-muted">Payments are handled by Razorpay in its own secure form. Your card, UPI or bank details are typed there and never reach Escanor.</p>

      {confirmCancel && <ConfirmSheet title="Cancel your subscription?" body="Your plan stays active until the end of the period you paid for, then it will not renew and your account moves to Free. You can subscribe again whenever you like." action="Cancel subscription" busy={busy === 'cancel'} onClose={() => setConfirmCancel(false)} onConfirm={() => void cancel()} />}
    </Page>
  );
}
