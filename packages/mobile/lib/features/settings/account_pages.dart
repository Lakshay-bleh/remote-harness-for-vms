import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/load.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../ui/parts.dart';
import '../../ui/widgets.dart';
import '../account/account_api.dart' show fetchBillingSubscription;
import '../account/billing.dart' show BillingSub, statusTextFor;
import '../account/billing_page.dart';
import '../account/money.dart';
import '../account/plan_changes.dart';
import '../assistant/chat_state.dart' show AssistantUsage, describeAssistantUsage;
import 'settings_api.dart';
import 'settings_logic.dart';
import 'settings_screen.dart' show confirmSignOut, usageCache;
import 'settings_widgets.dart';

/// Name and sign-in. The name is edited here and shared with the website: it is the same account.
class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final user = ref.watch(sessionProvider).user;
    return SettingsPage(title: 'Account', children: [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(children: [
          Avatar(name: user?.name, email: user?.email, size: 72),
          const SizedBox(height: 8),
          Text(user?.name ?? '', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: c.ink)),
          const SizedBox(height: 2),
          Text(user?.email ?? '', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.muted)),
        ]),
      ),
      Group(title: 'Profile', children: [
        SRow(
          icon: Icons.person_outline_rounded,
          label: 'Name',
          value: user?.name,
          onTap: () => showESheet<void>(context, title: 'Your name', builder: (_) => _NameSheet(initial: user?.name ?? '')),
        ),
        SRow(icon: Icons.mail_outline_rounded, label: 'Email', value: user?.email),
        const SRow(label: 'Sign-in', value: 'Google'),
      ]),
      Group(children: [
        SRow(icon: Icons.logout_rounded, label: 'Sign out', danger: true, onTap: () => confirmSignOut(context, ref)),
      ]),
    ]);
  }
}

class _NameSheet extends ConsumerStatefulWidget {
  const _NameSheet({required this.initial});
  final String initial;
  @override
  ConsumerState<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends ConsumerState<_NameSheet> {
  late final _name = TextEditingController(text: widget.initial);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final r = checkProfileName(_name.text);
    if (r.name == null) return setState(() => _error = r.problem);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await updateProfile(r.name!);
      await ref.read(sessionProvider.notifier).refreshUser();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e, 'Could not save your name.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (_error != null) ...[Notice(_error!, tone: NoticeTone.error), const SizedBox(height: 12)],
      LabeledField(
        label: null,
        controller: _name,
        autofocus: true,
        maxLength: 80,
        capitalization: TextCapitalization.words,
        autofillHints: const [AutofillHints.name],
        onSubmitted: (_) => _save(),
      ),
      const SizedBox(height: 12),
      EButton(label: _saving ? 'Saving…' : 'Save', expand: true, onPressed: _saving ? null : _save),
    ]);
  }
}

/// What the plan is and what today's use looks like: the same numbers as the website.
class UsagePage extends StatefulWidget {
  const UsagePage({super.key});
  @override
  State<UsagePage> createState() => _UsagePageState();
}

class _UsagePageState extends State<UsagePage> {
  final _usage = Loader<Map<String, dynamic>>(fetchUsage, every: const Duration(minutes: 1), cache: usageCache);
  // The plan you paid for, from billing (the same answer as Plan and billing).
  final _plan = Loader<Map<String, dynamic>>(fetchBillingSubscription);

  @override
  void initState() {
    super.initState();
    planChanges.addListener(_planChanged);
  }

  void _planChanged() {
    _plan.reload();
    _usage.reload();
  }

  @override
  void dispose() {
    planChanges.removeListener(_planChanged);
    _usage.dispose();
    _plan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListenableBuilder(
      listenable: Listenable.merge([_usage, _plan]),
      builder: (context, _) {
        final data = _usage.data;
        final u = data == null ? null : describeAssistantUsage(AssistantUsage.fromJson(data));
        final month = data?['month'] is Map ? Map<String, dynamic>.from(data!['month'] as Map) : null;
        int n(String k) => (month?[k] as num?)?.toInt() ?? 0;
        final plan = _plan.data == null ? null : BillingSub.fromJson(_plan.data!);
        final tone = u?.level == 'full' ? c.error : (u?.level == 'warn' ? c.warning : c.primary);
        final cost = month?['cost_usd'];

        return SettingsPage(title: 'Plan and usage', children: [
          Group(title: 'Plan', footer: 'Change or cancel your plan under Plan and billing.', children: [
            SRow(
              label: 'Current plan',
              value: plan != null ? plan.planName : (_plan.loading ? null : 'Could not load'),
              right: _plan.loading && plan == null ? const Spinner(size: 22) : null,
            ),
            if (plan != null) SRow(label: 'Status', value: statusTextFor(plan)),
            SRow(label: 'Plan and billing', onTap: () => pushPage(context, const BillingPage())),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionTitle('Today'),
            if (_usage.loading && u == null)
              const BlockSpinner()
            else if (u != null)
              ECard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(u.messages,
                      style: TextStyle(fontSize: 15, color: u.level == 'full' ? c.error : (u.level == 'warn' ? c.warning : c.ink))),
                  if (u.tokens != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(u.tokens!, style: TextStyle(fontSize: 12, color: c.muted))),
                  if (u.ratio != null) ...[
                    const SizedBox(height: 12),
                    MeterBar(value: u.ratio!, color: tone, label: 'Daily messages used'),
                  ],
                ]),
              )
            else if (_usage.error != null)
              Notice(_usage.error!, tone: NoticeTone.error),
          ]),
          if (month != null && (n('requests') > 0 || n('input_tokens') > 0))
            Group(title: 'This month', footer: data?['cost_is_estimate'] == true ? 'Cost is an estimate.' : null, children: [
              SRow(label: 'Requests', value: groupThousands(n('requests'))),
              SRow(label: 'Tokens in / out', value: '${groupThousands(n('input_tokens'))} / ${groupThousands(n('output_tokens'))}'),
              if (cost is num) SRow(label: 'Cost', value: '\$${cost.toStringAsFixed(2)}'),
            ]),
        ]);
      },
    );
  }
}
