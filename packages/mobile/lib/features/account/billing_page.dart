import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/cache.dart';
import '../../core/load.dart';
import '../../core/prefs.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../ui/parts.dart';
import '../../ui/widgets.dart';
import '../settings/settings_widgets.dart';
import 'account_api.dart';
import 'billing.dart';
import 'plan_changes.dart';
import 'privacy_data_page.dart';
import 'razorpay_checkout.dart';

const _invoicesFirst = 5;
const _plansCache = CachePolicy('billing-plans', ttl: Duration(hours: 1), maxAge: Duration(days: 30));
const _subCache = CachePolicy('billing-subscription', ttl: Duration(minutes: 1), maxAge: Duration(days: 7));
const _invoiceCache = CachePolicy('billing-invoices', ttl: Duration(minutes: 5), maxAge: Duration(days: 30));

/// Your plan, what you have used, the plans you can move to, and your invoices: upgrade, change, or cancel without leaving the app.
class BillingPage extends ConsumerStatefulWidget {
  const BillingPage({super.key});
  @override
  ConsumerState<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends ConsumerState<BillingPage> {
  final _sub = Loader<Map<String, dynamic>>(fetchBillingSubscription, cache: _subCache);
  final _plans = Loader<List<dynamic>>(fetchBillingPlans, cache: _plansCache);
  final _invoices = Loader<List<dynamic>>(fetchInvoices, cache: _invoiceCache);
  String? _busy;
  ({bool error, String text})? _message;
  Cycle? _picked;
  int _invoiceCount = _invoicesFirst;

  @override
  void dispose() {
    _sub.dispose();
    _plans.dispose();
    _invoices.dispose();
    super.dispose();
  }

  void _say(String text, {bool error = false}) {
    if (mounted) setState(() => _message = (error: error, text: text));
  }

  void _refresh() {
    _sub.reload();
    _invoices.reload();
    announcePlanChange(); // the usage screens and their limits, wherever they are open
  }

  void _contact() => pushPage(context, const PrivacyDataPage(initialType: 'grievance'));

  Future<void> _subscribe(BillingPlan plan, Cycle cycle) async {
    setState(() {
      _busy = plan.id;
      _message = null;
    });
    final user = ref.read(sessionProvider).user;
    try {
      final outcome = checkoutOutcome(await billingCheckout(plan.id, cycle));
      if (outcome.kind == CheckoutKind.message) return _say(outcome.message!);
      if (outcome.kind == CheckoutKind.done) {
        _say(outcome.message!);
        return _refresh();
      }
      final paid = await payWithRazorpay(
          key: outcome.key!, subscriptionId: outcome.subscriptionId!, planName: plan.name, name: user?.name, email: user?.email);
      switch (paid) {
        case PayClosed():
          return _say('Payment cancelled. Nothing was charged.');
        case PayFailed(:final message):
          return _say(message, error: true);
        case Paid():
          // The payment went through at Razorpay; tell Escanor, which checks the signature before it changes the plan.
          try {
            final done = await billingVerify(paymentId: paid.paymentId, subscriptionId: paid.subscriptionId, signature: paid.signature);
            _say('You are on the ${done['plan_name'] ?? plan.name} plan. Thank you.');
          } catch (e) {
            // Paid, but not yet confirmed here: Razorpay also tells Escanor directly, so the plan follows shortly. Never "nothing was
            // charged".
            _say('Your payment went through, but Escanor could not confirm it yet (${errorText(e, 'try again')}). Your plan will update '
                'shortly; if it does not, contact us.', error: true);
          }
          _refresh();
      }
    } catch (e) {
      _say(errorText(e, 'Could not start checkout. Nothing was charged.'), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _switchTo(BillingPlan plan, Map<String, String> names) async {
    setState(() {
      _busy = plan.id;
      _message = null;
    });
    try {
      _say(changeOutcomeText(await billingChangePlan(plan.id), names));
      _refresh();
    } catch (e) {
      _say(errorText(e, 'Could not change the plan. Your plan is unchanged.'), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _confirmSwitch(BillingPlan plan, PlanAction a, Map<String, String> names) => showConfirmSheet(
        context,
        title: a.label,
        body: a.note ?? '',
        action: a.effect == SwitchEffect.now ? 'Upgrade now' : 'Switch at period end',
        onConfirm: () => _switchTo(plan, names),
      );

  Future<void> _cancel() => showConfirmSheet(
        context,
        title: 'Cancel your subscription?',
        body: 'Your plan stays active until the end of the period you paid for, then it will not renew and your account moves to Free. You '
            'can subscribe again whenever you like.',
        action: 'Cancel subscription',
        onConfirm: () async {
          setState(() => _busy = 'cancel');
          try {
            await billingCancel();
            _say('Cancelled. Your plan stays active until the end of the period you paid for, and will not renew.');
            _refresh();
          } catch (e) {
            _say(errorText(e, 'Could not cancel. Your plan is unchanged.'), error: true);
          } finally {
            if (mounted) setState(() => _busy = null);
          }
        },
      );

  Future<void> _open(String url) async {
    try {
      await openLink(url);
    } catch (e) {
      _say(errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_sub, _plans, _invoices]),
      builder: (context, _) {
        final c = context.c;
        final s = _sub.data == null ? null : BillingSub.fromJson(_sub.data!);
        final plans = _plans.data == null
            ? null
            : [for (final p in _plans.data!) if (p is Map) BillingPlan.fromJson(Map<String, dynamic>.from(p))];
        final invoices = _invoices.data == null
            ? null
            : [for (final i in _invoices.data!) if (i is Map) Invoice.fromJson(Map<String, dynamic>.from(i))];
        final cycle = _picked ?? (s != null && s.planId != 'free' && s.billingCycle == Cycle.yearly ? Cycle.yearly : Cycle.monthly);
        final names = {for (final p in plans ?? const <BillingPlan>[]) p.id: p.name};
        final paid = s != null && s.planId != 'free';
        final bypass = s == null ? null : bypassText(billingBypass: s.billingBypass, planId: s.planId);
        final issue = s?.paymentIssue;
        final shown = (invoices ?? const <Invoice>[]).take(_invoiceCount).toList();

        return SettingsPage(title: 'Plan and billing', children: [
          if (_message != null) Notice(_message!.text, tone: _message!.error ? NoticeTone.error : NoticeTone.info),
          if (_sub.error != null && s == null) Notice(_sub.error!, tone: NoticeTone.error),
          if ((_sub.loading && s == null) || (_plans.loading && plans == null)) const BlockSpinner(padding: 40),
          if (s != null && s.paymentsEnabled == false)
            const Notice('Online payments are not switched on yet, so upgrading is unavailable. Contact us and we will set you up.', tone: NoticeTone.warn),
          if (issue != null)
            Notice(
              '',
              tone: issue.kind == 'halted' ? NoticeTone.error : NoticeTone.warn,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                    padding: const EdgeInsets.only(top: 1, right: 8),
                    child: Icon(Icons.error_outline_rounded, size: 18, color: issue.kind == 'halted' ? c.error : c.warning)),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(issue.message, style: TextStyle(fontSize: 13, color: issue.kind == 'halted' ? c.error : c.bodyStrong)),
                    if (issue.manageUrl != null && issue.manageUrl!.isNotEmpty)
                      GestureDetector(
                        onTap: () => _open(issue.manageUrl!),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Update payment method',
                              style: TextStyle(fontSize: 13, color: c.ink, decoration: TextDecoration.underline, decorationColor: c.ink)),
                        ),
                      ),
                  ]),
                ),
              ]),
            ),
          if (s != null) _currentPlan(context, s, paid, bypass, issue != null),
          if (s != null && plans != null) _plansSection(context, s, plans, cycle, paid, names),
          if (paid && !s.cancelAtPeriodEnd)
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              EButton(label: 'Cancel my subscription', kind: ButtonKind.danger, expand: true, onPressed: _busy == null ? _cancel : null),
              const SizedBox(height: 6),
              const Footnote('You keep your plan until the end of the period you paid for. Nothing is refunded automatically; see Refunds and '
                  'cancellation in Privacy and legal.'),
            ]),
          if (paid)
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SectionTitle('Invoices'),
              if (_invoices.loading && invoices == null) const BlockSpinner(padding: 12),
              if (_invoices.error != null && invoices == null) Notice(_invoices.error!, tone: NoticeTone.error),
              if (invoices != null && invoices.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('No invoices yet. They appear here after your first payment.', style: TextStyle(fontSize: 13.5, color: c.muted)),
                ),
              if (shown.isNotEmpty)
                RowsCard(children: [
                  for (final i in shown)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text.rich(
                              TextSpan(children: [
                                TextSpan(text: i.amount == null ? '' : formatMoney(i.amount!, i.currency)),
                                TextSpan(text: ' ${shortDate(i.date)}', style: TextStyle(color: c.muted)),
                              ]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, color: c.bodyStrong),
                            ),
                            Text(invoiceLine(status: i.status, description: i.description),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.5, color: i.status == 'failed' ? c.error : c.muted)),
                          ]),
                        ),
                        if (i.url != null && i.url!.isNotEmpty)
                          IconButton(
                            tooltip: 'Open invoice',
                            onPressed: () => _open(i.url!),
                            icon: Icon(Icons.open_in_new_rounded, size: 20, color: c.primary),
                          ),
                      ]),
                    ),
                ]),
              if (invoices != null && invoices.length > _invoiceCount) ...[
                const SizedBox(height: 8),
                EButton(
                  label: 'Show more',
                  kind: ButtonKind.quiet,
                  expand: true,
                  onPressed: () => setState(() => _invoiceCount += _invoicesFirst * 2),
                ),
              ],
            ]),
          const Footnote('Payments are handled by Razorpay in its own secure form. Your card, UPI or bank details are typed there and never reach '
              'Escanor.'),
        ]);
      },
    );
  }

  Widget _currentPlan(BuildContext context, BillingSub s, bool paid, String? bypass, bool hasIssue) {
    final c = context.c;
    final renewal = renewalTextFor(s);
    return ECard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('YOUR PLAN', style: TextStyle(fontSize: 12, letterSpacing: 0.6, fontWeight: FontWeight.w500, color: c.muted)),
              Text(s.planName, style: TextStyle(fontSize: 24, color: c.ink, fontWeight: FontWeight.w500)),
              if (paid) Text('Billed ${s.billingCycle == Cycle.yearly ? 'yearly' : 'monthly'}', style: TextStyle(fontSize: 12.5, color: c.muted)),
            ]),
          ),
          StatusPill(statusTextFor(s), color: s.cancelAtPeriodEnd || hasIssue ? c.warning : c.success),
        ]),
        if (renewal != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(renewal, style: TextStyle(fontSize: 13.5, color: c.body))),
        if (s.scheduledPlanName != null && s.scheduledPlanName!.isNotEmpty && !s.cancelAtPeriodEnd)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('You are moving to ${s.scheduledPlanName} when this period ends. Choose “Keep this plan” below to stay.',
                style: TextStyle(fontSize: 13.5, color: c.body)),
          ),
        if (bypass != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(bypass, style: TextStyle(fontSize: 13.5, color: c.body))),
        for (final m in meters(usage: s.usage, limits: s.limits))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(m.label, style: TextStyle(fontSize: 13.5, color: c.bodyStrong))),
                Text(m.text, style: TextStyle(fontSize: 13.5, color: c.muted)),
              ]),
              if (m.percent != null) ...[
                const SizedBox(height: 6),
                MeterBar(
                  value: m.percent! / 100,
                  label: m.label,
                  color: m.tone == MeterTone.full ? c.error : (m.tone == MeterTone.warn ? c.warning : c.primary),
                ),
              ],
            ]),
          ),
      ]),
    );
  }

  Widget _plansSection(BuildContext context, BillingSub s, List<BillingPlan> plans, Cycle cycle, bool paid, Map<String, String> names) {
    final c = context.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(children: [
          Expanded(child: Text('PLANS', style: TextStyle(fontSize: 12, letterSpacing: 0.6, fontWeight: FontWeight.w500, color: c.muted))),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
                color: c.surfaceCard, border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.pill)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final cy in Cycle.values)
                Semantics(
                  button: true,
                  selected: cycle == cy,
                  child: GestureDetector(
                    onTap: () {
                      haptic();
                      setState(() => _picked = cy);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(color: cycle == cy ? c.primary : Colors.transparent, borderRadius: BorderRadius.circular(Radii.pill)),
                      child: Text(cy == Cycle.monthly ? 'Monthly' : 'Yearly', style: TextStyle(fontSize: 13, color: cycle == cy ? c.onPrimary : c.body)),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      ),
      if (cycle == Cycle.yearly) ...[const SizedBox(height: 8), Footnote('A year costs ten months: two are free.')],
      if (paid && (s.billingCycle ?? Cycle.monthly) != cycle) ...[
        const SizedBox(height: 8),
        Footnote('A switch between plans keeps your current billing cycle (${s.billingCycle == Cycle.yearly ? 'yearly' : 'monthly'}). To change '
            'the cycle, cancel and subscribe again after it ends.'),
      ],
      for (final plan in plans) ...[const SizedBox(height: 12), _planCard(context, s, plan, cycle, names)],
    ]);
  }

  Widget _planCard(BuildContext context, BillingSub s, BillingPlan plan, Cycle cycle, Map<String, String> names) {
    final c = context.c;
    final a = planActionFor(plan, s);
    final saving = cycle == Cycle.yearly ? yearlySaving(plan) : null;
    final busy = _busy != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surfaceCard,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: a.kind == PlanActionKind.current ? c.primary.withValues(alpha: 0.6) : c.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Expanded(child: Text(plan.name, style: TextStyle(fontSize: 20, color: c.ink, fontWeight: FontWeight.w500))),
          Text(formatPrice(planPrice(plan, cycle), cycle), style: TextStyle(fontSize: 14, color: c.bodyStrong)),
        ]),
        if (saving != null) Text(saving, textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: c.success)),
        if (plan.description.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(plan.description, style: TextStyle(fontSize: 13.5, color: c.muted))),
        if (plan.features.isNotEmpty) const SizedBox(height: 8),
        for (final f in plan.features)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 1, right: 8), child: Icon(Icons.check_circle_rounded, size: 16, color: c.primary)),
              Expanded(child: Text(f, style: TextStyle(fontSize: 13.5, color: c.body))),
            ]),
          ),
        switch (a.kind) {
          PlanActionKind.upgrade => Padding(
              padding: const EdgeInsets.only(top: 16),
              child: EButton(
                label: _busy == plan.id ? 'Opening payment…' : a.label,
                expand: true,
                onPressed: busy || s.paymentsEnabled == false ? null : () => _subscribe(plan, cycle),
              ),
            ),
          PlanActionKind.switchPlan => Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                EButton(
                  label: _busy == plan.id ? 'Changing…' : a.label,
                  kind: a.effect == SwitchEffect.now ? ButtonKind.primary : ButtonKind.quiet,
                  expand: true,
                  onPressed: busy ? null : () => _confirmSwitch(plan, a, names),
                ),
                const SizedBox(height: 6),
                Text(a.note ?? '', style: TextStyle(fontSize: 12.5, height: 1.35, color: c.muted)),
              ]),
            ),
          PlanActionKind.contact => Padding(
              padding: const EdgeInsets.only(top: 16),
              child: EButton(label: a.label, kind: ButtonKind.quiet, expand: true, onPressed: _contact),
            ),
          PlanActionKind.current when !a.undo => Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(a.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.primary)),
            ),
          PlanActionKind.current => Padding(
              padding: const EdgeInsets.only(top: 16),
              child: EButton(
                label: _busy == plan.id ? 'Updating…' : a.label,
                kind: ButtonKind.quiet,
                expand: true,
                onPressed: busy ? null : () => _switchTo(plan, names),
              ),
            ),
          PlanActionKind.scheduled => Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(a.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.warning)),
            ),
          PlanActionKind.none => const SizedBox.shrink(),
        },
      ]),
    );
  }
}
