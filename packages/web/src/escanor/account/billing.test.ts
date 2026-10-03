import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { checkoutOutcome, formatPrice, meters, planAction, renewalText, statusText, type BillingPlan } from './billing';

const plan = (id: string, name = id): BillingPlan => ({ id, name, price_monthly_inr: null, price_monthly_usd: null, description: '', features: [], limits: {} });

describe('formatPrice', () => {
  it('reads paise as rupees, in Indian grouping', () => {
    assert.equal(formatPrice(249900), '₹2,499 a month');
    assert.equal(formatPrice(799900), '₹7,999 a month');
    assert.equal(formatPrice(150), '₹1.5 a month');
    assert.equal(formatPrice(0), 'Free');
    assert.equal(formatPrice(null), 'Custom');
  });
});

describe('meters', () => {
  it('shows how full each limit is, and calls a limitless one limitless', () => {
    const m = meters({ usage: { integrations_connected: 5, ai_runs_this_month: 50, team_members: 1, workspaces: 1 }, limits: { integrations: 6, ai_runs_per_month: 50, team_members: null, workspaces: 1 } });
    assert.deepEqual(m.map((x) => [x.text, x.percent, x.tone]), [['5 of 6', 83, 'warn'], ['50 of 50', 100, 'full'], ['1 · no limit', null, 'ok'], ['1 of 1', 100, 'ok']]);
  });
  it('does not call a seat or workspace limit of one "full": that is how the plan is, not running out', () => {
    const m = meters({ usage: { team_members: 1, workspaces: 2 }, limits: { team_members: 1, workspaces: 1 } });
    assert.deepEqual([m[2].tone, m[3].tone], ['ok', 'full']); // over the limit is still flagged
  });
  it('copes with missing numbers and a limit of zero', () => {
    const m = meters({ usage: {}, limits: { integrations: 0 } });
    assert.equal(m[0].percent, 100);
    assert.equal(m[1].used, 0);
  });
});

describe('planAction', () => {
  const free = { plan_id: 'free', cancel_at_period_end: false };
  const pro = { plan_id: 'pro', cancel_at_period_end: false };
  it('offers an upgrade from Free, and Enterprise is a conversation', () => {
    assert.deepEqual(planAction(plan('pro', 'Pro'), free), { kind: 'upgrade', label: 'Upgrade to Pro' });
    assert.equal(planAction(plan('team', 'Team'), free).kind, 'upgrade');
    assert.equal(planAction(plan('enterprise'), free).kind, 'contact');
  });
  it('marks the current plan, and says so when it is ending', () => {
    assert.deepEqual(planAction(plan('pro'), pro), { kind: 'current', label: 'Your plan' });
    assert.match((planAction(plan('pro'), { ...pro, cancel_at_period_end: true }) as { label: string }).label, /ends soon/);
  });
  it('never starts a second paid subscription on top of the first (the person would pay for both)', () => {
    const a = planAction(plan('team', 'Team'), pro);
    assert.equal(a.kind, 'locked');
    assert.match((a as { why: string }).why, /Cancel your current plan first/);
  });
  it('offers nothing for a plan below the current one, or for Free (that is cancelling)', () => {
    assert.equal(planAction(plan('free'), pro).kind, 'none');
    assert.equal(planAction(plan('pro'), { plan_id: 'team', cancel_at_period_end: false }).kind, 'none');
  });
});

describe('status and renewal', () => {
  it('says what is going on in plain words', () => {
    assert.equal(statusText({ status: 'active', cancel_at_period_end: false, plan_id: 'pro', billing_bypass: false }), 'Active');
    assert.equal(statusText({ status: 'active', cancel_at_period_end: true, plan_id: 'pro', billing_bypass: false }), 'Cancelling');
    assert.equal(statusText({ status: 'past_due', cancel_at_period_end: false, plan_id: 'pro', billing_bypass: false }), 'Past due');
    assert.equal(statusText({ status: 'active', cancel_at_period_end: false, plan_id: 'free', billing_bypass: true }), 'Full access');
  });
  it('says when it renews or ends, and nothing for Free', () => {
    assert.match(renewalText({ plan_id: 'pro', current_period_end: '2026-11-03T00:00:00Z', cancel_at_period_end: false })!, /^Renews on 3 November 2026/);
    assert.match(renewalText({ plan_id: 'pro', current_period_end: '2026-11-03T00:00:00Z', cancel_at_period_end: true })!, /^Ends on 3 November 2026\. It will not renew/);
    assert.equal(renewalText({ plan_id: 'free', current_period_end: '2026-11-03T00:00:00Z', cancel_at_period_end: false }), null);
    assert.equal(renewalText({ plan_id: 'pro', current_period_end: null, cancel_at_period_end: false }), null);
    assert.equal(renewalText({ plan_id: 'pro', current_period_end: 'nonsense', cancel_at_period_end: false }), null);
  });
});

describe('checkoutOutcome', () => {
  it('opens the payment form when the server created a subscription to pay for', () => {
    assert.deepEqual(checkoutOutcome({ status: 'created', razorpay_key_id: 'rzp_live_x', razorpay_subscription_id: 'sub_1' }), { kind: 'pay', key: 'rzp_live_x', subscriptionId: 'sub_1' });
  });
  it('shows the server’s own message when payments are not available, and never opens a form then', () => {
    assert.deepEqual(checkoutOutcome({ status: 'unavailable', message: 'Online payments are not available yet.' }), { kind: 'message', message: 'Online payments are not available yet.' });
    assert.equal(checkoutOutcome({ status: 'created' }).kind, 'message'); // incomplete: no key to pay with
    assert.equal(checkoutOutcome({}).kind, 'message');
  });
  it('treats an already-active plan as done', () => {
    assert.deepEqual(checkoutOutcome({ status: 'active', message: 'You are on the Free plan.' }), { kind: 'done', message: 'You are on the Free plan.' });
  });
});
