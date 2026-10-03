/**
 * Plans and billing, as the app presents them. Pure: the screens only draw what these functions say, and the rules (what a button
 * does for a plan, how full a meter is, what a checkout answer means) are tested here without a phone.
 */

export interface BillingPlan {
  id: string;
  name: string;
  price_monthly_inr: number | null; // paise
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
}

export const PLAN_ORDER = ['free', 'pro', 'team', 'enterprise'] as const;
const rank = (id: string) => Math.max(0, PLAN_ORDER.indexOf(id as (typeof PLAN_ORDER)[number]));

/** Prices come in paise. "₹2,499 a month", "Free", or "Custom" for a plan without a price. */
export function formatPrice(paise: number | null): string {
  if (paise === null) return 'Custom';
  if (paise === 0) return 'Free';
  const rupees = paise / 100;
  return `₹${rupees.toLocaleString('en-IN', { maximumFractionDigits: rupees % 1 ? 2 : 0 })} a month`;
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
  | { kind: 'current'; label: string }
  | { kind: 'upgrade'; label: string }
  | { kind: 'contact'; label: string }
  | { kind: 'locked'; label: string; why: string }
  | { kind: 'none' };

/**
 * What the button on a plan card does. Moving between two paid plans is not offered here: a new subscription would start while the old
 * one kept renewing, so the person would pay for both. They cancel first (it runs to the end of what they paid for), then choose.
 */
export function planAction(plan: BillingPlan, sub: Pick<BillingSub, 'plan_id' | 'cancel_at_period_end'>): PlanAction {
  if (plan.id === sub.plan_id) return { kind: 'current', label: sub.cancel_at_period_end ? 'Current plan, ends soon' : 'Your plan' };
  if (plan.id === 'enterprise') return { kind: 'contact', label: 'Contact us' };
  if (plan.id === 'free') return { kind: 'none' }; // going back to Free is "cancel", which the page offers once, not on every card
  if (rank(plan.id) < rank(sub.plan_id)) return { kind: 'none' };
  if (sub.plan_id !== 'free') return { kind: 'locked', label: `Switch to ${plan.name}`, why: 'Cancel your current plan first. It stays active until the end of the period you paid for, then you can choose this one.' };
  return { kind: 'upgrade', label: `Upgrade to ${plan.name}` };
}

export function statusText(sub: Pick<BillingSub, 'status' | 'cancel_at_period_end' | 'plan_id' | 'billing_bypass'>): string {
  if (sub.billing_bypass) return 'Full access';
  if (sub.cancel_at_period_end) return 'Cancelling';
  if (sub.status === 'active') return 'Active';
  return sub.status ? sub.status.replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase()) : 'Active';
}

export function renewalText(sub: Pick<BillingSub, 'current_period_end' | 'cancel_at_period_end' | 'plan_id'>): string | null {
  if (sub.plan_id === 'free' || !sub.current_period_end) return null;
  const when = new Date(sub.current_period_end);
  if (Number.isNaN(when.getTime())) return null;
  const day = when.toLocaleDateString('en-IN', { day: 'numeric', month: 'long', year: 'numeric' });
  return sub.cancel_at_period_end ? `Ends on ${day}. It will not renew.` : `Renews on ${day}.`;
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
