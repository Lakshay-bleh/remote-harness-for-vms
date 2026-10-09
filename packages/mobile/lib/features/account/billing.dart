/// Plans and billing, as the app presents them. Pure: the screens only draw what these functions say, and the rules (what a button
/// does for a plan, how full a meter is, what a checkout answer means) are tested here without a phone.
library;

import 'package:intl/intl.dart';

import 'money.dart';

export 'money.dart';

enum Cycle { monthly, yearly }

Cycle? cycleFrom(Object? v) => v == 'yearly' ? Cycle.yearly : (v == 'monthly' ? Cycle.monthly : null);

int? _int(Object? v) => v is num ? v.toInt() : null;

Map<String, int?> _limits(Object? v) =>
    v is Map ? {for (final e in v.entries) '${e.key}': _int(e.value)} : <String, int?>{};

Map<String, int> _usage(Object? v) =>
    v is Map ? {for (final e in v.entries) if (e.value is num) '${e.key}': (e.value as num).toInt()} : <String, int>{};

class BillingPlan {
  const BillingPlan({
    required this.id,
    required this.name,
    this.priceMonthlyInr,
    this.priceYearlyInr,
    this.priceMonthlyUsd,
    this.description = '',
    this.features = const [],
    this.limits = const {},
  });
  final String id;
  final String name;

  /// In paise. Null: no online price (Enterprise).
  final int? priceMonthlyInr;

  /// In paise; a year costs ten months.
  final int? priceYearlyInr;
  final int? priceMonthlyUsd;
  final String description;
  final List<String> features;
  final Map<String, int?> limits;

  factory BillingPlan.fromJson(Map<String, dynamic> j) => BillingPlan(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        priceMonthlyInr: _int(j['price_monthly_inr']),
        priceYearlyInr: _int(j['price_yearly_inr']),
        priceMonthlyUsd: _int(j['price_monthly_usd']),
        description: '${j['description'] ?? ''}',
        features: j['features'] is List ? [for (final f in j['features'] as List) '$f'] : const [],
        limits: _limits(j['limits']),
      );
}

class PaymentIssue {
  const PaymentIssue({required this.kind, required this.message, this.until, this.manageUrl});
  final String kind; // past_due | halted
  final String message;
  final String? until;
  final String? manageUrl;

  static PaymentIssue? fromJson(Object? j) => j is Map
      ? PaymentIssue(kind: '${j['kind'] ?? ''}', message: '${j['message'] ?? ''}', until: j['until'] as String?, manageUrl: j['manage_url'] as String?)
      : null;
}

class BillingSub {
  const BillingSub({
    this.planId = 'free',
    this.planName = 'Free',
    this.status = 'active',
    this.usage = const {},
    this.limits = const {},
    this.billingBypass = false,
    this.currentPeriodEnd,
    this.cancelAtPeriodEnd = false,
    this.billingCycle,
    this.scheduledPlanId,
    this.scheduledPlanName,
    this.paymentIssue,
    this.paymentsEnabled,
  });
  final String planId;
  final String planName;
  final String status;
  final Map<String, int> usage;
  final Map<String, int?> limits;
  final bool billingBypass;
  final String? currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final Cycle? billingCycle;
  final String? scheduledPlanId;
  final String? scheduledPlanName;
  final PaymentIssue? paymentIssue;

  /// null when the server did not say.
  final bool? paymentsEnabled;

  factory BillingSub.fromJson(Map<String, dynamic> j) => BillingSub(
        planId: '${j['plan_id'] ?? 'free'}',
        planName: '${j['plan_name'] ?? 'Free'}',
        status: '${j['status'] ?? ''}',
        usage: _usage(j['usage']),
        limits: _limits(j['limits']),
        billingBypass: j['billing_bypass'] == true,
        currentPeriodEnd: j['current_period_end'] as String?,
        cancelAtPeriodEnd: j['cancel_at_period_end'] == true,
        billingCycle: cycleFrom(j['billing_cycle']),
        scheduledPlanId: j['scheduled_plan_id'] as String?,
        scheduledPlanName: j['scheduled_plan_name'] as String?,
        paymentIssue: PaymentIssue.fromJson(j['payment_issue']),
        paymentsEnabled: j['payments'] is Map ? (j['payments'] as Map)['enabled'] == true : null,
      );
}

class Invoice {
  const Invoice({required this.id, this.date, this.amount, this.currency = 'INR', this.status, this.description, this.url});
  final String id;
  final String? date;

  /// In paise.
  final int? amount;
  final String currency;
  final String? status;
  final String? description;
  final String? url;

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
        id: '${j['id'] ?? ''}',
        date: j['date'] as String?,
        amount: _int(j['amount']),
        currency: '${j['currency'] ?? 'INR'}',
        status: j['status'] as String?,
        description: j['description'] as String?,
        url: j['url'] as String?,
      );
}

const planOrder = ['free', 'pro', 'team', 'enterprise'];
int _rank(String id) => planOrder.contains(id) ? planOrder.indexOf(id) : 0;

/// Prices come in paise. "₹2,499 a month", "₹24,990 a year", "Free", or "Custom" for a plan without a price.
String formatPrice(int? paise, [Cycle cycle = Cycle.monthly]) {
  if (paise == null) return 'Custom';
  if (paise == 0) return 'Free';
  return '${formatMoney(paise)} a ${cycle == Cycle.yearly ? 'year' : 'month'}';
}

/// What a plan costs for the chosen cycle, in paise; null where there is no online price.
int? planPrice(BillingPlan plan, Cycle cycle) {
  final monthly = plan.priceMonthlyInr;
  if (monthly == null) return null;
  if (cycle == Cycle.yearly) return plan.priceYearlyInr ?? monthly * 10;
  return monthly;
}

/// "Save ₹4,998 a year", for the yearly toggle, from the actual prices rather than a promise written into the screen.
String? yearlySaving(BillingPlan plan) {
  final monthly = plan.priceMonthlyInr;
  if (monthly == null || monthly == 0) return null;
  final saved = monthly * 12 - planPrice(plan, Cycle.yearly)!;
  return saved > 0 ? 'Save ${formatMoney(saved)} a year' : null;
}

const meterKinds = [
  (limit: 'integrations', used: 'integrations_connected', label: 'Integrations', consumable: true),
  (limit: 'ai_runs_per_month', used: 'ai_runs_this_month', label: 'AI runs this month', consumable: true),
  (limit: 'team_members', used: 'team_members', label: 'Seats', consumable: false),
  (limit: 'workspaces', used: 'workspaces', label: 'Workspaces', consumable: false),
];

enum MeterTone { ok, warn, full }

class Meter {
  const Meter({required this.key, required this.label, required this.used, required this.limit, required this.text, required this.percent, required this.tone});
  final String key;
  final String label;
  final int used;
  final int? limit;

  /// "3 of 6", or "3 · no limit".
  final String text;

  /// 0 to 100, or null when there is no limit to be a fraction of.
  final int? percent;
  final MeterTone tone;
}

List<Meter> meters({required Map<String, int> usage, required Map<String, int?> limits}) {
  return [
    for (final m in meterKinds)
      () {
        final used = (usage[m.used] ?? 0) < 0 ? 0 : (usage[m.used] ?? 0);
        final limit = limits[m.limit];
        final percent = limit == null ? null : (limit == 0 ? 100 : ((used / limit) * 100).round().clamp(0, 100));
        final MeterTone tone;
        if (percent == null || !m.consumable) {
          tone = used > (limit ?? double.infinity) ? MeterTone.full : MeterTone.ok;
        } else {
          tone = percent >= 100 ? MeterTone.full : (percent >= 80 ? MeterTone.warn : MeterTone.ok);
        }
        return Meter(
          key: m.limit,
          label: m.label,
          used: used,
          limit: limit,
          text: limit == null ? '${groupIndian(used)} · no limit' : '${groupIndian(used)} of ${groupIndian(limit)}',
          percent: percent,
          tone: tone,
        );
      }(),
  ];
}

enum PlanActionKind { current, upgrade, switchPlan, scheduled, contact, none }

enum SwitchEffect { now, periodEnd }

class PlanAction {
  const PlanAction(this.kind, {this.label = '', this.undo = false, this.effect, this.note});
  final PlanActionKind kind;
  final String label;

  /// current: offering to undo a scheduled switch.
  final bool undo;
  final SwitchEffect? effect;
  final String? note;

  @override
  bool operator ==(Object other) =>
      other is PlanAction && other.kind == kind && other.label == label && other.undo == undo && other.effect == effect && other.note == note;
  @override
  int get hashCode => Object.hash(kind, label, undo, effect, note);
  @override
  String toString() => 'PlanAction($kind, $label, undo: $undo, $effect)';
}

/// What the button on a plan card does. Between two paid plans the server changes the one subscription (up now, the difference
/// charged; down when the period ends), so nobody pays twice. A subscription that is already set to end is not changed, it is
/// started again: the old one just runs out.
PlanAction planAction(BillingPlan plan, {required String planId, required bool cancelAtPeriodEnd, String? scheduledPlanId}) {
  if (plan.id == 'enterprise') return const PlanAction(PlanActionKind.contact, label: 'Contact us');
  if (plan.id == planId) {
    if (scheduledPlanId != null && scheduledPlanId.isNotEmpty) return const PlanAction(PlanActionKind.current, label: 'Keep this plan', undo: true);
    return PlanAction(PlanActionKind.current, label: cancelAtPeriodEnd ? 'Current plan, ends soon' : 'Your plan');
  }
  if (plan.id == 'free') return const PlanAction(PlanActionKind.none); // going back to Free is "cancel", offered once on the page
  if (scheduledPlanId == plan.id) return PlanAction(PlanActionKind.scheduled, label: 'Switching to ${plan.name} at the end of the period');
  if (planId == 'free' || planId == 'enterprise' || cancelAtPeriodEnd) {
    return PlanAction(PlanActionKind.upgrade, label: planId == 'free' ? 'Upgrade to ${plan.name}' : 'Subscribe to ${plan.name}');
  }
  if (_rank(plan.id) > _rank(planId)) {
    return PlanAction(PlanActionKind.switchPlan,
        label: 'Upgrade to ${plan.name}', effect: SwitchEffect.now, note: 'Starts now. Razorpay charges only the difference for the rest of this period.');
  }
  return PlanAction(PlanActionKind.switchPlan,
      label: 'Switch to ${plan.name}',
      effect: SwitchEffect.periodEnd,
      note: 'You keep your current plan until the period you paid for ends, then move to this one.');
}

PlanAction planActionFor(BillingPlan plan, BillingSub sub) =>
    planAction(plan, planId: sub.planId, cancelAtPeriodEnd: sub.cancelAtPeriodEnd, scheduledPlanId: sub.scheduledPlanId);

String _capitalise(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String statusText({required String status, required bool cancelAtPeriodEnd, required String planId, required bool billingBypass}) {
  if (billingBypass && planId == 'free') return 'Full access';
  if (cancelAtPeriodEnd) return 'Cancelling';
  if (status == 'active') return 'Active';
  return status.isNotEmpty ? _capitalise(status.replaceAll('_', ' ')) : 'Active';
}

String statusTextFor(BillingSub s) => statusText(status: s.status, cancelAtPeriodEnd: s.cancelAtPeriodEnd, planId: s.planId, billingBypass: s.billingBypass);

/// "3 November 2026".
String longDate(DateTime d) => DateFormat('d MMMM y').format(d);

String? renewalText({required String planId, required String? currentPeriodEnd, required bool cancelAtPeriodEnd, String? scheduledPlanName}) {
  if (planId == 'free' || currentPeriodEnd == null) return null;
  final when = DateTime.tryParse(currentPeriodEnd);
  if (when == null) return null;
  final day = longDate(when.toLocal());
  if (cancelAtPeriodEnd) return 'Ends on $day. It will not renew.';
  return (scheduledPlanName != null && scheduledPlanName.isNotEmpty) ? 'Renews on $day, as $scheduledPlanName.' : 'Renews on $day.';
}

String? renewalTextFor(BillingSub s) => renewalText(
    planId: s.planId, currentPeriodEnd: s.currentPeriodEnd, cancelAtPeriodEnd: s.cancelAtPeriodEnd, scheduledPlanName: s.scheduledPlanName);

enum CheckoutKind { pay, done, message }

class CheckoutOutcome {
  const CheckoutOutcome(this.kind, {this.key, this.subscriptionId, this.message});
  final CheckoutKind kind;
  final String? key;
  final String? subscriptionId;
  final String? message;
}

/// What the server's answer to "start checkout" means for the screen.
CheckoutOutcome checkoutOutcome(Map<String, dynamic> r) {
  final status = r['status'];
  final key = r['razorpay_key_id'];
  final sub = r['razorpay_subscription_id'];
  final message = r['message'] is String && (r['message'] as String).isNotEmpty ? r['message'] as String : null;
  if (status == 'created' && key is String && key.isNotEmpty && sub is String && sub.isNotEmpty) {
    return CheckoutOutcome(CheckoutKind.pay, key: key, subscriptionId: sub);
  }
  if (status == 'active') return CheckoutOutcome(CheckoutKind.done, message: message ?? 'Your plan is updated.');
  return CheckoutOutcome(CheckoutKind.message, message: message ?? 'Checkout is not available right now. Nothing was charged.');
}

/// What a plan change did, in words. The server answers "changed" (now) or "scheduled" (when the period ends).
String changeOutcomeText(Map<String, dynamic> r, Map<String, String> names) {
  final scheduled = r['scheduled_plan_id'];
  if (r['status'] == 'scheduled' && scheduled is String && scheduled.isNotEmpty) {
    return 'Done. You move to ${names[scheduled] ?? 'the new plan'} when the period you paid for ends.';
  }
  if (r['status'] == 'changed') return 'You are on the ${names['${r['plan_id'] ?? ''}'] ?? 'new'} plan now.';
  return 'Your plan is updated.';
}

/// One line for an invoice row: "Pro plan · Paid", with a failed charge worded as what it is.
String invoiceLine({String? status, String? description}) {
  final s = status == 'paid'
      ? 'Paid'
      : status == 'failed'
          ? 'Failed'
          : (status != null && status.isNotEmpty ? _capitalise(status.replaceAll('_', ' ')) : '');
  return [description, s].where((x) => x != null && x.isNotEmpty).join(' · ');
}

/// Why the page shows no upgrade/cancel for an account that has full access, in plain words.
String? bypassText({required bool billingBypass, required String planId}) {
  if (!billingBypass) return null;
  return planId == 'free'
      ? 'Your account has full access with no plan limits, so you never need to pay. The plans below are optional.'
      : 'Your account also has full access with no plan limits, whatever the plan below says.';
}
