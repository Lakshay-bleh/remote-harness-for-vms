import 'dart:convert';

import 'package:escanor/features/account/billing_page.dart';
import 'package:escanor/features/account/delete_account_page.dart';
import 'package:escanor/features/account/deletion_notice.dart';
import 'package:escanor/features/account/help_page.dart';
import 'package:escanor/features/account/policy_gate.dart';
import 'package:escanor/features/account/privacy_data_page.dart';
import 'package:escanor/features/account/security_page.dart';
import 'package:escanor/features/account/workspace_page.dart';
import 'package:escanor/features/settings/legal_content.dart' show policyVersion;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

import '../settings/harness.dart';

Map<String, dynamic> sub({String plan = 'pro', bool ending = false, Map<String, dynamic>? issue, bool payments = true}) => {
      'plan_id': plan,
      'plan_name': plan == 'free' ? 'Free' : 'Pro',
      'status': 'active',
      'usage': {'integrations_connected': 5, 'ai_runs_this_month': 10, 'team_members': 1, 'workspaces': 1},
      'limits': {'integrations': 6, 'ai_runs_per_month': 1000, 'team_members': 1, 'workspaces': 1},
      'billing_bypass': false,
      'current_period_end': '2026-11-03T12:00:00Z',
      'cancel_at_period_end': ending,
      'billing_cycle': 'monthly',
      'payment_issue': issue,
      'payments': {'enabled': payments, 'mode': 'live'},
    };

final plans = {
  'plans': [
    {'id': 'free', 'name': 'Free', 'price_monthly_inr': 0, 'description': 'Try it', 'features': ['1 workspace'], 'limits': {}},
    {'id': 'pro', 'name': 'Pro', 'price_monthly_inr': 249900, 'price_yearly_inr': 2499000, 'description': 'For one', 'features': ['More runs'], 'limits': {}},
    {'id': 'team', 'name': 'Team', 'price_monthly_inr': 799900, 'description': 'For teams', 'features': ['Seats'], 'limits': {}},
    {'id': 'enterprise', 'name': 'Enterprise', 'price_monthly_inr': null, 'description': 'Talk to us', 'features': [], 'limits': {}},
  ]
};

void main() {
  testWidgets('Billing shows the plan, meters, plans and invoices', (t) async {
    tallPhone(t);
    await setUpBackend({
      'GET /billing/subscription': (_) => sub(issue: {'kind': 'past_due', 'message': 'Your last payment failed.', 'manage_url': 'https://rzp.io/x'}),
      'GET /billing/plans': (_) => plans,
      'GET /billing/invoices': (_) => {
            'invoices': [
              {'id': 'i1', 'date': '2026-10-03T00:00:00Z', 'amount': 249900, 'currency': 'INR', 'status': 'paid', 'description': 'Pro plan', 'url': 'https://x/i1'}
            ]
          },
    });
    await t.pumpWidget(host(const BillingPage()));
    await settle(t);
    expect(find.text('Your last payment failed.'), findsOneWidget);
    expect(find.text('Update payment method'), findsOneWidget);
    expect(find.text('Renews on 3 November 2026.'), findsOneWidget);
    expect(find.text('5 of 6'), findsOneWidget);
    expect(find.text('Your plan'), findsOneWidget);
    expect(find.text('Upgrade to Team'), findsOneWidget);
    expect(find.text('Contact us'), findsOneWidget);
    expect(find.text('₹2,499 a month'), findsOneWidget);
    expect(find.text('Cancel my subscription'), findsOneWidget);
    expect(find.text('Pro plan · Paid'), findsOneWidget);
    await t.tap(find.text('Yearly'));
    await settle(t);
    expect(find.text('₹24,990 a year'), findsOneWidget);
    expect(find.text('Save ₹4,998 a year'), findsOneWidget);
    expect(find.text('A year costs ten months: two are free.'), findsOneWidget);
  });

  testWidgets('Upgrading between paid plans asks first, then says what happened', (t) async {
    tallPhone(t);
    final backend = await setUpBackend({
      'GET /billing/subscription': (_) => sub(),
      'GET /billing/plans': (_) => plans,
      'GET /billing/invoices': (_) => {'invoices': []},
      'POST /billing/change-plan': (_) => {'status': 'changed', 'plan_id': 'team', 'scheduled_plan_id': null, 'effective': 'now'},
    });
    await t.pumpWidget(host(const BillingPage()));
    await settle(t);
    await t.tap(find.text('Upgrade to Team'));
    await settle(t);
    expect(find.text('Starts now. Razorpay charges only the difference for the rest of this period.'), findsWidgets);
    await t.tap(find.text('Upgrade now'));
    await settle(t);
    expect(jsonDecode(backend.calls.firstWhere((r) => r.url.path.endsWith('change-plan')).body), {'plan_id': 'team'});
    expect(find.text('You are on the Team plan now.'), findsOneWidget);
  });

  testWidgets('With payments off, upgrading from Free is not offered as working', (t) async {
    tallPhone(t);
    await setUpBackend({
      'GET /billing/subscription': (_) => sub(plan: 'free', payments: false),
      'GET /billing/plans': (_) => plans,
      'GET /billing/invoices': (_) => {'invoices': []},
    });
    await t.pumpWidget(host(const BillingPage()));
    await settle(t);
    expect(find.textContaining('Online payments are not switched on yet'), findsOneWidget);
    expect(find.text('Upgrade to Pro'), findsOneWidget);
    expect(find.text('Cancel my subscription'), findsNothing);
  });

  testWidgets('Security turns on two-step verification with a QR code and a copyable key', (t) async {
    tallPhone(t);
    final backend = await setUpBackend({
      'GET /security/2fa': (_) => {'enabled': false, 'enrolled_at': null, 'backup_codes_left': 0},
      'POST /security/2fa/setup': (_) => {'secret': 'JBSWY3DPEHPK3PXP', 'otpauth_uri': 'otpauth://totp/Escanor:ada?secret=JBSWY3DPEHPK3PXP', 'issuer': 'Escanor'},
      'POST /security/2fa/enable': (_) => {'enabled': true, 'backup_codes': ['AAAA-BBBB', 'CCCC-DDDD']},
    });
    await t.pumpWidget(host(const SecurityPage()));
    await settle(t);
    await t.tap(find.text('Turn on'));
    await settle(t);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('JBSW Y3DP EHPK 3PXP'), findsOneWidget);
    await t.tap(find.text('I added it: enter the code'));
    await settle(t);
    await t.enterText(find.byType(TextField), '123 456');
    await settle(t, 2);
    await t.tap(find.text('Turn on').last);
    await settle(t);
    expect(jsonDecode(backend.calls.firstWhere((r) => r.url.path.endsWith('enable')).body), {'code': '123456'});
    expect(find.text('Your backup codes'), findsOneWidget);
    expect(find.text('AAAA-BBBB'), findsOneWidget);
  });

  testWidgets('A wrong-looking code is explained before anything is sent', (t) async {
    tallPhone(t);
    final backend = await setUpBackend({'GET /security/2fa': (_) => {'enabled': true, 'enrolled_at': '2026-09-01T00:00:00Z', 'backup_codes_left': 6}});
    await t.pumpWidget(host(const SecurityPage()));
    await settle(t);
    expect(find.text('6 left'), findsOneWidget);
    await t.tap(find.text('Turn off'));
    await settle(t);
    await t.enterText(find.byType(TextField), '12');
    await settle(t, 2);
    await t.tap(find.text('Turn off').last);
    await settle(t);
    expect(find.textContaining('Enter the 6 digits from your authenticator app'), findsOneWidget);
    expect(backend.count('POST /security/2fa/disable'), 0);
  });

  testWidgets('Delete account without two-step verification is confirmed with the email alone', (t) async {
    tallPhone(t);
    final backend = await setUpBackend({
      'POST /account/deletion': (_) => {'scheduled': true, 'scheduled_for': '2026-10-15T00:00:00Z', 'reference': 'DEL-1'},
    });
    await t.pumpWidget(host(const DeleteAccountPage()));
    await settle(t);
    expect(find.text('What happens'), findsOneWidget);
    expect(find.text('Turn on two-step verification'), findsNothing);
    expect(find.text('Code from your authenticator app (or a backup code)'), findsNothing);
    expect(find.textContaining('Any paid plan stops renewing now.'), findsOneWidget);
    final button = find.widgetWithText(InkWell, 'Delete my account');
    expect(t.widget<InkWell>(button).onTap, isNull);
    await t.enterText(find.byType(TextField), 'ada@example.com');
    await settle(t, 2);
    await t.tap(button);
    await settle(t);
    expect(jsonDecode(backend.calls.lastWhere((r) => r.method == 'POST').body), {'code': '', 'confirm_email': 'ada@example.com'});
    expect(find.text('Deletion scheduled'), findsOneWidget);
  });

  testWidgets('Delete account asks for the email and a code', (t) async {
    tallPhone(t);
    await setUpBackend({'GET /account/deletion': (_) => {'scheduled': false, 'two_factor_enabled': true}});
    await t.pumpWidget(host(const DeleteAccountPage()));
    await settle(t);
    final button = find.widgetWithText(InkWell, 'Delete my account');
    expect(t.widget<InkWell>(button).onTap, isNull);
    await t.enterText(find.byType(TextField).first, 'ADA@example.com ');
    await settle(t, 2);
    expect(t.widget<InkWell>(button).onTap, isNull, reason: 'two-step verification is on: the code is needed too');
    await t.enterText(find.byType(TextField).last, '123456');
    await settle(t, 2);
    expect(t.widget<InkWell>(button).onTap, isNotNull);
  });

  testWidgets('The Terms gate asks for agreement at the current version, then gets out of the way', (t) async {
    tallPhone(t);
    var states = <Map<String, Object?>>[];
    final backend = await setUpBackend({
      'GET /compliance/consents': (_) => states,
      'POST /compliance/consents': (r) {
        final b = jsonDecode(r.body) as Map<String, dynamic>;
        states = [
          ...states.where((s) => s['purpose'] != b['purpose']),
          {'purpose': b['purpose'], 'granted': true, 'notice_version': b['notice_version'], 'recorded_at': DateTime.now().toUtc().toIso8601String()},
        ];
        return states.last;
      },
    });
    await t.pumpWidget(host(const Scaffold(body: Stack(fit: StackFit.expand, children: [Text('the app'), DeletionNotice(otherwise: PolicyGate())]))));
    await settle(t);
    expect(find.text('Terms and privacy'), findsOneWidget);
    expect(find.textContaining('report offences to the authorities'), findsOneWidget);
    final agree = find.widgetWithText(InkWell, 'Agree and continue');
    expect(t.widget<InkWell>(agree).onTap, isNull, reason: 'not before the box is ticked');
    await t.tap(find.byType(Checkbox));
    await settle(t, 2);
    await t.tap(agree);
    await settle(t);
    final posted = [for (final r in backend.calls.where((r) => r.method == 'POST')) jsonDecode(r.body)];
    expect(posted.map((b) => b['purpose']), ['terms', 'privacy_notice', 'rules_notice']);
    expect(posted.every((b) => b['notice_version'] == policyVersion && b['action'] == 'grant'), true);
    expect(find.text('Terms and privacy'), findsNothing);
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('The rules come back every three months, and the gate fails open', (t) async {
    tallPhone(t);
    final old = DateTime.now().subtract(const Duration(days: 100)).toUtc().toIso8601String();
    var fail = false;
    await setUpBackend({
      'GET /compliance/consents': (_) => fail
          ? http.Response('{"detail":"down"}', 500)
          : [
              {'purpose': 'terms', 'granted': true, 'notice_version': policyVersion, 'recorded_at': old},
              {'purpose': 'privacy_notice', 'granted': true, 'notice_version': policyVersion, 'recorded_at': old},
              {'purpose': 'rules_notice', 'granted': true, 'notice_version': policyVersion, 'recorded_at': old},
            ],
      'POST /compliance/consents': (_) => {'ok': true},
    });
    await t.pumpWidget(host(const Scaffold(body: Stack(fit: StackFit.expand, children: [Text('the app'), PolicyGate()]))));
    await settle(t);
    expect(find.text('A reminder of our rules'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('Got it'), findsOneWidget);

    fail = true;
    await t.pumpWidget(host(const Scaffold(body: Stack(fit: StackFit.expand, children: [Text('the app'), PolicyGate(key: ValueKey(2))]))));
    await settle(t);
    expect(find.text('A reminder of our rules'), findsNothing);
  });

  testWidgets('A scheduled deletion is shown instead of the Terms gate', (t) async {
    await setUpBackend({
      'GET /account/deletion': (_) => {'scheduled': true, 'scheduled_for': DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String()},
      'GET /compliance/consents': (_) => [],
    });
    await t.pumpWidget(host(const Scaffold(body: Stack(fit: StackFit.expand, children: [Text('the app'), DeletionNotice(otherwise: PolicyGate())]))));
    await settle(t);
    expect(find.text('Keep my account'), findsOneWidget);
    expect(find.text('Terms and privacy'), findsNothing);
  });

  testWidgets('The deletion notice covers the app only while a deletion is scheduled, and keeps the account', (t) async {
    var scheduled = true;
    final backend = await setUpBackend({
      'GET /account/deletion': (_) => {'scheduled': scheduled, 'scheduled_for': DateTime.now().add(const Duration(days: 6, hours: 2)).toUtc().toIso8601String()},
      'POST /account/deletion/cancel': (_) {
        scheduled = false;
        return {'scheduled': false};
      },
    });
    await t.pumpWidget(host(const Scaffold(body: Stack(fit: StackFit.expand, children: [Text('the app'), DeletionNotice()]))));
    await settle(t);
    expect(find.text('Your account will be deleted in 6 days'), findsOneWidget);
    await t.tap(find.text('Keep my account'));
    await settle(t);
    expect(backend.count('POST /account/deletion/cancel'), 1);
    expect(find.text('Keep my account'), findsNothing);
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('Privacy saves a consent, lists requests and opens a complaint straight away when asked', (t) async {
    tallPhone(t);
    final backend = await setUpBackend({
      'GET /compliance/consents': (_) => [
            {'purpose': 'analytics', 'granted': true, 'notice_version': '2026-10-01', 'recorded_at': ''}
          ],
      'POST /compliance/consents': (r) => {'purpose': 'marketing', 'granted': true},
      'GET /compliance/requests': (_) => [
            {'id': 'r1', 'reference': 'PR-1', 'request_type': 'access', 'status': 'fulfilled', 'subject': 'My data'}
          ],
      'POST /compliance/requests': (r) => {
            'id': 'r2',
            'reference': 'PR-2',
            'request_type': 'grievance',
            'status': 'received',
            'subject': jsonDecode(r.body)['subject'],
            'acknowledge_by': DateTime.now().add(const Duration(hours: 47)).toUtc().toIso8601String(),
            'resolve_by': DateTime.now().add(const Duration(days: 30, hours: 1)).toUtc().toIso8601String(),
          },
    });
    await t.pumpWidget(host(const PrivacyDataPage(initialType: 'grievance')));
    await settle(t);
    expect(find.text('New request'), findsWidgets);
    expect(find.text('Make a complaint or report a problem'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, 'App crashes');
    await settle(t, 2);
    await t.tap(find.text('Send request'));
    await settle(t);
    expect(jsonDecode(backend.calls.lastWhere((r) => r.method == 'POST').body),
        {'request_type': 'grievance', 'subject': 'App crashes', 'details': ''});
    expect(find.textContaining('Your reference is PR-2'), findsOneWidget);
    await t.tap(find.text('Done'));
    await settle(t);
    expect(find.text('My data'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    await t.tap(find.text('Product news and offers'));
    await t.tap(find.byType(Switch).first);
    await settle(t);
    final consent = jsonDecode(backend.calls.lastWhere((r) => r.url.path.endsWith('consents') && r.method == 'POST').body);
    expect(consent, {'purpose': 'marketing', 'action': 'grant', 'notice_version': policyVersion, 'source': 'android'});
  });

  testWidgets('Workspace shows settings, the team and filters activity', (t) async {
    tallPhone(t);
    await setUpBackend({
      'GET /workspace/settings': (_) => {'workspace_name': 'Acme', 'default_region': 'ap-south', 'environment': 'staging', 'connected_devices': 3},
      'GET /admin/organization': (_) => {
            'your_role': 'owner',
            'members': [
              {'user_id': 'u1', 'email': 'ada@example.com', 'name': 'Ada', 'role': 'owner'},
              {'user_id': 'u2', 'email': 'bob@example.com', 'name': '', 'role': 'member'},
            ]
          },
      'GET /audit-logs': (_) => {
            'logs': [
              {'created_at': '2026-10-07T00:00:00Z', 'actor_email': 'ada@example.com', 'action': 'billing.plan_changed', 'target': 'pro', 'status': 'ok', 'detail': ''},
              {'created_at': '2026-10-07T00:00:00Z', 'actor_email': 'bob@example.com', 'action': 'integration.connected', 'target': 'github', 'status': 'ok', 'detail': ''},
            ]
          },
    });
    await t.pumpWidget(host(const WorkspacePage()));
    await settle(t);
    expect(find.text('Acme'), findsOneWidget);
    expect(find.text('India and South Asia'), findsOneWidget);
    expect(find.text('Staging'), findsOneWidget);
    expect(find.text('bob@example.com'), findsOneWidget);
    expect(find.text('Billing plan changed'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'github');
    await settle(t, 2);
    expect(find.text('Billing plan changed'), findsNothing);
    expect(find.text('Integration connected'), findsOneWidget);
  });

  testWidgets('A person who may not see the team is told so', (t) async {
    tallPhone(t);
    await setUpBackend({
      'GET /workspace/settings': (_) => {'workspace_name': 'Acme', 'default_region': 'auto', 'environment': 'production', 'connected_devices': 0},
      'GET /audit-logs': (_) => {'logs': []},
    });
    await t.pumpWidget(host(const WorkspacePage()));
    await settle(t);
    expect(find.text('Only owners and admins can see the team.'), findsOneWidget);
    expect(find.text('Nothing yet.'), findsOneWidget);
  });

  testWidgets('Help lists the documents and the way to report a problem', (t) async {
    tallPhone(t);
    await setUpBackend();
    await t.pumpWidget(host(const HelpPage()));
    await settle(t);
    expect(find.text('Report a problem or make a complaint'), findsOneWidget);
    expect(find.text('Refunds'), findsOneWidget);
    expect(find.text('Copy debug details'), findsOneWidget);
  });
}
