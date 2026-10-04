/**
 * Plans and billing, as the app presents them. Pure: the screens only draw what these functions say, and the rules (what a button
 * does for a plan, how full a meter is, what a checkout answer means) are tested here without a phone.
 */

export interface BillingPlan {
  id: string;
  name: string;
  price_monthly_inr: number | null; // paise
  price_yearly_inr?: number | null; // paise, a year costs ten months
  price_monthly_usd: number | null;
  description: string;
  features: string[];
  limits: Record<string, number | null>;
}

export interface BillingSub {
  plan_id: string;
  plan_name: string;
  status: string;
  usage: Record<string, number>;
  limits: Record<string, number | null>;
  billing_bypass: boolean;
  current_period_end: string | null;
  cancel_at_period_end: boolean;
  billing_cycle?: Cycle;
  scheduled_plan_id?: string | null;
  scheduled_plan_name?: string | null;
  payment_issue?: PaymentIssue | null;
  payments?: { enabled: boolean; mode: string | null };
}

export type Cycle = 'monthly' | 'yearly';

export interface PaymentIssue {
  kind: 'past_due' | 'halted';
  message: string;
  until: string | null;
  manage_url: string | null;
}

export interface Invoice {
  id: string;
  date: string | null;
  amount: number | null; // paise
  currency: string;
  status: string | null;
  description: string | null;
  url: string | null;
}

export const PLAN_ORDER = ['free', 'pro', 'team', 'enterprise'] as const;
const rank = (id: string) => Math.max(0, PLAN_ORDER.indexOf(id as (typeof PLAN_ORDER)[number]));

/** Prices come in paise. "₹2,499 a month", "₹24,990 a year", "Free", or "Custom" for a plan without a price. */
export function formatPrice(paise: number | null, cycle: Cycle = 'monthly'): string {
  if (paise === null) return 'Custom';
  if (paise === 0) return 'Free';
  return `${formatMoney(paise)} a ${cycle === 'yearly' ? 'year' : 'month'}`;
}

/** An amount in paise as rupees ("₹2,499", "₹1.5"), for prices and invoices. */
export function formatMoney(paise: number, currency = 'INR'): string {
  const value = paise / 100;
  const symbol = currency === 'INR' ? '₹' : currency === 'USD' ? '$' : `${currency} `;
  return `${symbol}${value.toLocaleString('en-IN', { maximumFractionDigits: value % 1 ? 2 : 0 })}`;
}

/** What a plan costs for the chosen cycle, in paise; null where there is no online price. */
export function planPrice(plan: BillingPlan, cycle: Cycle): number | null {
  if (plan.price_monthly_inr === null) return null;
  if (cycle === 'yearly') return plan.price_yearly_inr ?? plan.price_monthly_inr * 10;
  return plan.price_monthly_inr;
}

/** "Two months free", for the yearly toggle, from the actual prices rather than a promise written into the screen. */
export function yearlySaving(plan: BillingPlan): string | null {
  if (!plan.price_monthly_inr) return null;
  const saved = plan.price_monthly_inr * 12 - planPrice(plan, 'yearly')!;
  return saved > 0 ? `Save ${formatMoney(saved)} a year` : null;
}

export const METERS = [
  { limit: 'integrations', used: 'integrations_connected', label: 'Integrations', consumable: true },
  { limit: 'ai_runs_per_month', used: 'ai_runs_this_month', label: 'AI runs this month', consumable: true },
  { limit: 'team_members', used: 'team_members', label: 'Seats', consumable: false },
  { limit: 'workspaces', used: 'workspaces', label: 'Workspaces', consumable: false },
] as const;

export interface Meter {
  key: string;
  label: string;
  used: number;
  limit: number | null;
  /** "3 of 6", or "3 · no limit". */
  text: string;
  /** 0 to 100, or null when there is no limit to be a fraction of. */
  percent: number | null;
  tone: 'ok' | 'warn' | 'full';
}

export function meters(sub: Pick<BillingSub, 'usage' | 'limits'>): Meter[] {
  return METERS.map((m) => {
    const used = Math.max(0, Number(sub.usage[m.used] ?? 0));
    const limit = sub.limits[m.limit] ?? null;
    const percent = limit === null ? null : limit === 0 ? 100 : Math.min(100, Math.round((used / limit) * 100));
    return { key: m.limit, label: m.label, used, limit, text: limit === null ? `${used.toLocaleString('en-IN')} · no limit` : `${used.toLocaleString('en-IN')} of ${limit.toLocaleString('en-IN')}`, percent, tone: percent === null || !m.consumable ? (used > (limit ?? Infinity) ? 'full' : 'ok') : percent >= 100 ? 'full' : percent >= 80 ? 'warn' : 'ok' };
  });
}

export type PlanAction =
  | { kind: 'current'; label: string; undo?: boolean }
  | { kind: 'upgrade'; label: string } // a new subscription, paid in the app
  | { kind: 'switch'; label: string; effect: 'now' | 'period_end'; note: string } // between two paid plans, through change-plan
  | { kind: 'scheduled'; label: string }
  | { kind: 'contact'; label: string }
  | { kind: 'none' };

/**
 * What the button on a plan card does. Between two paid plans the server changes the one subscription (up now, the difference
 * charged; down when the period ends), so nobody pays twice. A subscription that is already set to end is not changed, it is
 * started again: the old one just runs out.
 */
export function planAction(plan: BillingPlan, sub: Pick<BillingSub, 'plan_id' | 'cancel_at_period_end'> & { scheduled_plan_id?: string | null }): PlanAction {
  if (plan.id === 'enterprise') return { kind: 'contact', label: 'Contact us' };
  if (plan.id === sub.plan_id) {
    if (sub.scheduled_plan_id) return { kind: 'current', label: 'Keep this plan', undo: true };
    return { kind: 'current', label: sub.cancel_at_period_end ? 'Current plan, ends soon' : 'Your plan' };
  }
  if (plan.id === 'free') return { kind: 'none' }; // going back to Free is "cancel", which the page offers once, not on every card
  if (sub.scheduled_plan_id === plan.id) return { kind: 'scheduled', label: `Switching to ${plan.name} at the end of the period` };
  if (sub.plan_id === 'free' || sub.plan_id === 'enterprise' || sub.cancel_at_period_end) return { kind: 'upgrade', label: sub.plan_id === 'free' ? `Upgrade to ${plan.name}` : `Subscribe to ${plan.name}` };
  if (rank(plan.id) > rank(sub.plan_id)) return { kind: 'switch', label: `Upgrade to ${plan.name}`, effect: 'now', note: 'Starts now. Razorpay charges only the difference for the rest of this period.' };
  return { kind: 'switch', label: `Switch to ${plan.name}`, effect: 'period_end', note: 'You keep your current plan until the period you paid for ends, then move to this one.' };
}

export function statusText(sub: Pick<BillingSub, 'status' | 'cancel_at_period_end' | 'plan_id' | 'billing_bypass'>): string {
  if (sub.billing_bypass && sub.plan_id === 'free') return 'Full access';
  if (sub.cancel_at_period_end) return 'Cancelling';
  if (sub.status === 'active') return 'Active';
  return sub.status ? sub.status.replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase()) : 'Active';
}

export function renewalText(sub: Pick<BillingSub, 'current_period_end' | 'cancel_at_period_end' | 'plan_id'> & { scheduled_plan_name?: string | null }): string | null {
  if (sub.plan_id === 'free' || !sub.current_period_end) return null;
  const when = new Date(sub.current_period_end);
  if (Number.isNaN(when.getTime())) return null;
  const day = when.toLocaleDateString('en-IN', { day: 'numeric', month: 'long', year: 'numeric' });
  if (sub.cancel_at_period_end) return `Ends on ${day}. It will not renew.`;
  return sub.scheduled_plan_name ? `Renews on ${day}, as ${sub.scheduled_plan_name}.` : `Renews on ${day}.`;
}

export type CheckoutOutcome =
  | { kind: 'pay'; key: string; subscriptionId: string }
  | { kind: 'done'; message: string }
  | { kind: 'message'; message: string };

/** What the server's answer to "start checkout" means for the screen. */
export function checkoutOutcome(r: { status?: string; message?: string | null; razorpay_key_id?: string; razorpay_subscription_id?: string; plan_id?: string }): CheckoutOutcome {
  if (r.status === 'created' && r.razorpay_key_id && r.razorpay_subscription_id) return { kind: 'pay', key: r.razorpay_key_id, subscriptionId: r.razorpay_subscription_id };
  if (r.status === 'active') return { kind: 'done', message: r.message || 'Your plan is updated.' };
  return { kind: 'message', message: r.message || 'Checkout is not available right now. Nothing was charged.' };
}

/** What a plan change did, in words. The server answers "changed" (now) or "scheduled" (when the period ends). */
export function changeOutcomeText(r: { status?: string; plan_id?: string; scheduled_plan_id?: string | null }, names: Record<string, string>): string {
  if (r.status === 'scheduled' && r.scheduled_plan_id) return `Done. You move to ${names[r.scheduled_plan_id] ?? 'the new plan'} when the period you paid for ends.`;
  if (r.status === 'changed') return `You are on the ${names[r.plan_id ?? ''] ?? 'new'} plan now.`;
  return 'Your plan is updated.';
}

/** One line for an invoice row: "Pro plan · paid", with a failed charge worded as what it is. */
export function invoiceLine(i: Pick<Invoice, 'status' | 'description'>): string {
  const status = i.status === 'paid' ? 'Paid' : i.status === 'failed' ? 'Failed' : i.status ? i.status.replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase()) : '';
  return [i.description, status].filter(Boolean).join(' · ');
}

/** Why the page shows no upgrade/cancel for an account that has full access, in plain words. */
export function bypassText(sub: Pick<BillingSub, 'billing_bypass' | 'plan_id'>): string | null {
  if (!sub.billing_bypass) return null;
  return sub.plan_id === 'free'
    ? 'Your account has full access with no plan limits, so you never need to pay. The plans below are optional.'
    : 'Your account also has full access with no plan limits, whatever the plan below says.';
}
