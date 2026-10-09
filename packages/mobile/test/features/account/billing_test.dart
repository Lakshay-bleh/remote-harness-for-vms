import 'package:escanor/features/account/billing.dart';
import 'package:escanor/features/account/razorpay_checkout.dart';
import 'package:flutter_test/flutter_test.dart';

// Port of packages/web/src/escanor/account/billing.test.ts.
BillingPlan plan(String id, [String? name]) => BillingPlan(id: id, name: name ?? id);

void main() {
  group('formatPrice', () {
    test('reads paise as rupees, in Indian grouping', () {
      expect(formatPrice(249900), '₹2,499 a month');
      expect(formatPrice(799900), '₹7,999 a month');
      expect(formatPrice(150), '₹1.5 a month');
      expect(formatPrice(0), 'Free');
      expect(formatPrice(null), 'Custom');
      expect(formatPrice(10000000), '₹1,00,000 a month');
    });
  });

  group('meters', () {
    test('shows how full each limit is, and calls a limitless one limitless', () {
      final m = meters(
        usage: {'integrations_connected': 5, 'ai_runs_this_month': 50, 'team_members': 1, 'workspaces': 1},
        limits: {'integrations': 6, 'ai_runs_per_month': 50, 'team_members': null, 'workspaces': 1},
      );
      expect(m.map((x) => [x.text, x.percent, x.tone]).toList(), [
        ['5 of 6', 83, MeterTone.warn],
        ['50 of 50', 100, MeterTone.full],
        ['1 · no limit', null, MeterTone.ok],
        ['1 of 1', 100, MeterTone.ok],
      ]);
    });
    test('does not call a seat or workspace limit of one "full": that is how the plan is, not running out', () {
      final m = meters(usage: {'team_members': 1, 'workspaces': 2}, limits: {'team_members': 1, 'workspaces': 1});
      expect([m[2].tone, m[3].tone], [MeterTone.ok, MeterTone.full]); // over the limit is still flagged
    });
    test('copes with missing numbers and a limit of zero', () {
      final m = meters(usage: {}, limits: {'integrations': 0});
      expect(m[0].percent, 100);
      expect(m[1].used, 0);
    });
  });

  group('planAction', () {
    PlanAction act(BillingPlan p, String planId, {bool ending = false, String? scheduled}) =>
        planAction(p, planId: planId, cancelAtPeriodEnd: ending, scheduledPlanId: scheduled);
    test('offers an upgrade from Free, and Enterprise is a conversation', () {
      expect(act(plan('pro', 'Pro'), 'free'), const PlanAction(PlanActionKind.upgrade, label: 'Upgrade to Pro'));
      expect(act(plan('team', 'Team'), 'free').kind, PlanActionKind.upgrade);
      expect(act(plan('enterprise'), 'free').kind, PlanActionKind.contact);
    });
    test('marks the current plan, and says so when it is ending', () {
      expect(act(plan('pro'), 'pro'), const PlanAction(PlanActionKind.current, label: 'Your plan'));
      expect(act(plan('pro'), 'pro', ending: true).label, contains('ends soon'));
    });
    test('moves between paid plans through the one subscription: up now, down at the period end', () {
      final up = act(plan('team', 'Team'), 'pro');
      expect(up.kind, PlanActionKind.switchPlan);
      expect(up.effect, SwitchEffect.now);
      final down = act(plan('pro', 'Pro'), 'team');
      expect(down.effect, SwitchEffect.periodEnd);
      expect(down.note, contains('until the period you paid for ends'));
    });
    test('starts a fresh subscription, not a change, when the old one is already ending', () {
      expect(act(plan('team', 'Team'), 'pro', ending: true), const PlanAction(PlanActionKind.upgrade, label: 'Subscribe to Team'));
    });
    test('shows a scheduled switch, and offers to keep the current plan instead', () {
      expect(act(plan('pro', 'Pro'), 'team', scheduled: 'pro').kind, PlanActionKind.scheduled);
      expect(act(plan('team', 'Team'), 'team', scheduled: 'pro'), const PlanAction(PlanActionKind.current, label: 'Keep this plan', undo: true));
    });
    test('offers nothing for Free on a paid plan (that is cancelling)', () {
      expect(act(plan('free'), 'pro').kind, PlanActionKind.none);
    });
  });

  group('status and renewal', () {
    test('says what is going on in plain words', () {
      expect(statusText(status: 'active', cancelAtPeriodEnd: false, planId: 'pro', billingBypass: false), 'Active');
      expect(statusText(status: 'active', cancelAtPeriodEnd: true, planId: 'pro', billingBypass: false), 'Cancelling');
      expect(statusText(status: 'past_due', cancelAtPeriodEnd: false, planId: 'pro', billingBypass: false), 'Past due');
      expect(statusText(status: 'active', cancelAtPeriodEnd: false, planId: 'free', billingBypass: true), 'Full access');
    });
    test('says when it renews or ends, and nothing for Free', () {
      expect(renewalText(planId: 'pro', currentPeriodEnd: '2026-11-03T12:00:00Z', cancelAtPeriodEnd: false), startsWith('Renews on 3 November 2026'));
      expect(renewalText(planId: 'pro', currentPeriodEnd: '2026-11-03T12:00:00Z', cancelAtPeriodEnd: true), startsWith('Ends on 3 November 2026. It will not renew'));
      expect(renewalText(planId: 'pro', currentPeriodEnd: '2026-11-03T12:00:00Z', cancelAtPeriodEnd: false, scheduledPlanName: 'Pro'), endsWith(', as Pro.'));
      expect(renewalText(planId: 'free', currentPeriodEnd: '2026-11-03T00:00:00Z', cancelAtPeriodEnd: false), null);
      expect(renewalText(planId: 'pro', currentPeriodEnd: null, cancelAtPeriodEnd: false), null);
      expect(renewalText(planId: 'pro', currentPeriodEnd: 'nonsense', cancelAtPeriodEnd: false), null);
    });
  });

  group('checkoutOutcome', () {
    test('opens the payment form when the server created a subscription to pay for', () {
      final o = checkoutOutcome({'status': 'created', 'razorpay_key_id': 'rzp_live_x', 'razorpay_subscription_id': 'sub_1'});
      expect([o.kind, o.key, o.subscriptionId], [CheckoutKind.pay, 'rzp_live_x', 'sub_1']);
    });
    test('shows the server’s own message when payments are not available, and never opens a form then', () {
      final o = checkoutOutcome({'status': 'unavailable', 'message': 'Online payments are not available yet.'});
      expect([o.kind, o.message], [CheckoutKind.message, 'Online payments are not available yet.']);
      expect(checkoutOutcome({'status': 'created'}).kind, CheckoutKind.message); // incomplete: no key to pay with
      expect(checkoutOutcome({}).kind, CheckoutKind.message);
      expect(checkoutOutcome({}).message, 'Checkout is not available right now. Nothing was charged.');
    });
    test('treats an already-active plan as done', () {
      final o = checkoutOutcome({'status': 'active', 'message': 'You are on the Free plan.'});
      expect([o.kind, o.message], [CheckoutKind.done, 'You are on the Free plan.']);
    });
  });

  group('yearly billing', () {
    const pro = BillingPlan(id: 'pro', name: 'Pro', priceMonthlyInr: 249900, priceYearlyInr: 2499000);
    test('prices a year as the server does, ten months', () {
      expect(planPrice(pro, Cycle.yearly), 2499000);
      expect(planPrice(const BillingPlan(id: 'pro', name: 'Pro', priceMonthlyInr: 249900), Cycle.yearly), 2499000);
      expect(planPrice(plan('enterprise'), Cycle.yearly), null);
      expect(formatPrice(2499000, Cycle.yearly), '₹24,990 a year');
    });
    test('says how much a year saves from the prices themselves', () {
      expect(yearlySaving(pro), 'Save ₹4,998 a year');
      expect(yearlySaving(plan('free')), null);
    });
    test('formats money for invoices', () {
      expect(formatMoney(249900), '₹2,499');
      expect(formatMoney(1050, 'USD'), r'$10.5');
      expect(formatMoney(1234, 'EUR'), 'EUR 12.34');
    });
  });

  group('plan changes and invoices in words', () {
    const names = {'pro': 'Pro', 'team': 'Team'};
    test('tells apart a change now from one at the period end', () {
      expect(changeOutcomeText({'status': 'changed', 'plan_id': 'team'}, names), contains('Team plan now'));
      expect(changeOutcomeText({'status': 'scheduled', 'plan_id': 'team', 'scheduled_plan_id': 'pro'}, names), contains('move to Pro when the period'));
    });
    test('words an invoice line, a failed charge included', () {
      expect(invoiceLine(status: 'paid', description: 'Pro plan'), 'Pro plan · Paid');
      expect(invoiceLine(status: 'failed', description: null), 'Failed');
      expect(invoiceLine(status: 'partially_refunded', description: 'Team plan'), 'Team plan · Partially refunded');
    });
    test('explains full access instead of leaving the page looking broken', () {
      expect(bypassText(billingBypass: true, planId: 'free'), contains('full access'));
      expect(bypassText(billingBypass: false, planId: 'free'), null);
    });
  });

  group('reading the server', () {
    test('a subscription with its cycle, schedule and payment problem', () {
      final s = BillingSub.fromJson({
        'plan_id': 'pro',
        'plan_name': 'Pro',
        'status': 'past_due',
        'usage': {'integrations_connected': 2},
        'limits': {'integrations': 6, 'team_members': null},
        'billing_cycle': 'yearly',
        'payment_issue': {'kind': 'past_due', 'message': 'Your last payment failed.', 'manage_url': 'https://rzp.io/x'},
        'payments': {'enabled': false},
      });
      expect(s.billingCycle, Cycle.yearly);
      expect(s.paymentIssue?.manageUrl, 'https://rzp.io/x');
      expect(s.paymentsEnabled, false);
      expect(s.limits.containsKey('team_members'), true);
      expect(statusTextFor(s), 'Past due');
    });
    test('a plan and an invoice', () {
      final p = BillingPlan.fromJson({'id': 'team', 'name': 'Team', 'price_monthly_inr': 799900, 'features': ['A', 'B'], 'limits': {}});
      expect(p.features, ['A', 'B']);
      expect(p.priceYearlyInr, null);
      final i = Invoice.fromJson({'id': 'inv_1', 'amount': 249900, 'currency': 'INR', 'status': 'paid'});
      expect(formatMoney(i.amount!, i.currency), '₹2,499');
    });
  });

  group('Razorpay answers', () {
    test('a payment hands back what Escanor needs to check it', () {
      final p = payResultFromSuccess({'razorpay_payment_id': 'pay_1', 'razorpay_subscription_id': 'sub_1', 'razorpay_signature': 'sig'}, 'sub_x');
      expect([p.paymentId, p.subscriptionId, p.signature], ['pay_1', 'sub_1', 'sig']);
      expect(payResultFromSuccess({'razorpay_payment_id': 'pay_1'}, 'sub_x').subscriptionId, 'sub_x');
    });
    test('closing the form is not a failure, and a raw error is worded for a person', () {
      expect(payResultFromError(2, 'Payment cancelled by user'), isA<PayClosed>());
      expect((payResultFromError(100, '{"error":{}}') as PayFailed).message, 'The payment did not go through. Nothing was charged.');
      expect((payResultFromError(100, 'Card declined') as PayFailed).message, 'Card declined');
      expect((payResultFromError(0, null) as PayFailed).message, contains('Check your connection'));
    });
    test('opens the subscription with the app’s name and colour', () {
      final o = checkoutOptions(key: 'rzp_x', subscriptionId: 'sub_1', planName: 'Pro', email: 'a@x.io');
      expect(o['subscription_id'], 'sub_1');
      expect(o['description'], 'Pro plan');
      expect((o['prefill'] as Map)['email'], 'a@x.io');
      expect((o['theme'] as Map)['color'], '#f2a73b');
    });
  });

  // Port of packages/web/src/escanor/account/razorpay.test.ts: payment apps keep working (a failed attempt keeps the form open).
  group('the payment form', () {
    const paid = Paid(paymentId: 'pay_1', subscriptionId: 'sub_1', signature: 'sig');

    test('a failed attempt keeps waiting, and a retry that succeeds is reported as paid', () async {
      final form = CheckoutSession();
      form.failed('Card declined');
      expect(form.settled, false);
      form.paid(paid);
      expect(await form.result, same(paid));
    });

    test('closing the form after a failure reports the failure', () async {
      final form = CheckoutSession();
      form.failed('Card declined');
      form.closed();
      final r = await form.result;
      expect(r, isA<PayFailed>());
      expect((r as PayFailed).message, 'Card declined');
    });

    test('closing it without trying is "closed", and a failure without words gets a plain one', () async {
      final a = CheckoutSession()..closed();
      expect(await a.result, isA<PayClosed>());
      final b = CheckoutSession()
        ..failed(null)
        ..closed();
      expect(((await b.result) as PayFailed).message, contains('did not go through'));
    });

    test('the phone’s error event is the form closing: cancelled, or the failure that ended it', () async {
      final cancelled = CheckoutSession()..onError(2, 'Payment cancelled by user');
      expect(await cancelled.result, isA<PayClosed>());
      final retriedThenClosed = CheckoutSession()
        ..failed('UPI app declined')
        ..onError(2, 'Payment cancelled by user');
      expect(((await retriedThenClosed.result) as PayFailed).message, 'UPI app declined');
      final failed = CheckoutSession()..onError(100, 'Card declined');
      expect(((await failed.result) as PayFailed).message, 'Card declined');
      // settled once: a late event changes nothing
      failed.paid(paid);
      expect(await failed.result, isA<PayFailed>());
    });
  });
}
