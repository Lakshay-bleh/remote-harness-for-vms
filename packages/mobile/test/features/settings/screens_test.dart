import 'dart:convert';

import 'package:escanor/features/settings/legal_content.dart' show policyDate;
import 'package:escanor/core/cache.dart';
import 'package:escanor/core/prefs.dart';
import 'package:escanor/core/theme.dart';
import 'package:escanor/features/account/plan_changes.dart';
import 'package:escanor/features/settings/account_pages.dart';
import 'package:escanor/features/settings/developer_page.dart';
import 'package:escanor/features/settings/info_pages.dart';
import 'package:escanor/features/settings/notifications_page.dart';
import 'package:escanor/features/settings/preference_pages.dart';
import 'package:escanor/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'harness.dart';

void main() {
  testWidgets('Settings shows who is signed in, the day’s use and every group', (t) async {
    tallPhone(t);
    await setUpBackend();
    await t.pumpWidget(host(const SettingsScreen()));
    await settle(t);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('ada@example.com'), findsOneWidget);
    expect(find.text('12 of 50 messages today'), findsOneWidget);
    for (final g in ['PLAN', 'ACCOUNT', 'PREFERENCES', 'CONNECTED', 'MORE']) {
      expect(find.text(g), findsOneWidget, reason: g);
    }
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('Sign out asks first', (t) async {
    tallPhone(t);
    await setUpBackend();
    await t.pumpWidget(host(const SettingsScreen()));
    await settle(t);
    await t.tap(find.text('Sign out'));
    await settle(t);
    expect(find.text('Sign out?'), findsOneWidget);
    expect(find.textContaining('The computers paired with this phone are removed from it too'), findsOneWidget);
  });

  testWidgets('Usage shows the plan, today and this month', (t) async {
    tallPhone(t);
    await setUpBackend();
    await t.pumpWidget(host(const UsagePage()));
    await settle(t);
    expect(find.text('Pro'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('12 of 50 messages today'), findsOneWidget);
    expect(find.text('4.2k tokens'), findsOneWidget);
    expect(find.text('120,000 / 9,000'), findsOneWidget);
    expect(find.text(r'$1.23'), findsOneWidget);
    expect(find.text('Cost is an estimate.'), findsOneWidget);
  });

  testWidgets('Usage shows the plan you paid for, follows a plan change, and says when it cannot load', (t) async {
    tallPhone(t);
    var plan = 'pro';
    var down = false;
    final backend = await setUpBackend({
      'GET /billing/subscription': (_) => down
          ? http.Response('{"detail":"down"}', 500)
          : {'plan_id': plan, 'plan_name': plan == 'team' ? 'Team' : 'Pro', 'status': 'active', 'cancel_at_period_end': plan == 'team'},
    });
    await t.pumpWidget(host(const UsagePage()));
    await settle(t);
    expect(find.text('Pro'), findsOneWidget);
    expect(backend.count('GET /subscription'), 0, reason: 'the plan comes from billing');
    plan = 'team';
    final usageBefore = backend.count('GET /ai/usage');
    announcePlanChange();
    await settle(t);
    expect(find.text('Team'), findsOneWidget);
    expect(find.text('Cancelling'), findsOneWidget);
    expect(backend.count('GET /ai/usage'), greaterThan(usageBefore));

    down = true;
    clearCache();
    await t.pumpWidget(host(const UsagePage(key: ValueKey(2))));
    await settle(t);
    expect(find.text('Could not load'), findsOneWidget);
  });

  testWidgets('Account edits the name and refuses an empty one', (t) async {
    final backend = await setUpBackend({'PATCH /users/me': (r) => jsonDecode(r.body)});
    await t.pumpWidget(host(const AccountPage()));
    await settle(t);
    await t.tap(find.text('Name'));
    await settle(t);
    await t.enterText(find.byType(TextField), '   ');
    await t.tap(find.text('Save'));
    await settle(t);
    expect(find.text('Please enter a name.'), findsOneWidget);
    await t.enterText(find.byType(TextField), '  Ada   King ');
    await t.tap(find.text('Save'));
    await settle(t);
    final patch = backend.calls.firstWhere((r) => r.method == 'PATCH');
    expect(jsonDecode(patch.body), {'name': 'Ada King'});
  });

  testWidgets('Appearance changes the theme, accent and text size on this phone', (t) async {
    tallPhone(t);
    await setUpBackend();
    late WidgetRef ref;
    await t.pumpWidget(host(Consumer(builder: (context, r, _) {
      ref = r;
      return const AppearancePage();
    })));
    await settle(t);
    await t.tap(find.text('Light'));
    await t.tap(find.bySemanticsLabel('Violet'));
    await t.tap(find.text('Large'));
    await settle(t);
    final p = ref.read(prefsProvider);
    expect([p.theme, p.accent, p.textSize], [ThemeChoice.light, AccentName.violet, 'large']);
    expect(find.textContaining('from 93.75% to 112.5%'), findsOneWidget);
  });

  testWidgets('New chats picks a default model from a sheet', (t) async {
    await setUpBackend();
    late WidgetRef ref;
    await t.pumpWidget(host(Consumer(builder: (context, r, _) {
      ref = r;
      return const ChatDefaultsPage();
    })));
    await settle(t);
    await t.tap(find.text('Model'));
    await settle(t);
    await t.tap(find.text('Opus 5.5'));
    await settle(t);
    expect(ref.read(prefsProvider).defaultModel, 'claude-opus-5-5');
  });

  testWidgets('Notifications saves each switch to the account and goes back when that fails', (t) async {
    tallPhone(t);
    var fail = false;
    final backend = await setUpBackend({
      'GET /users/me/notification-preferences': (_) =>
          {'push_enabled': true, 'emergency_alerts': true, 'server_down': true, 'deployment_approvals': true, 'team_pings': true, 'checks': true},
      'GET /users/me/push-status': (_) => {'configured': true, 'devices': 1},
      'PATCH /users/me/notification-preferences': (r) => fail
          ? null
          : {'push_enabled': true, 'emergency_alerts': true, 'server_down': true, 'deployment_approvals': true, 'team_pings': true, 'checks': false},
    });
    await t.pumpWidget(host(const NotificationsPage()));
    await settle(t);
    // Not a phone in this test: the page says alerts need the app, and the account switches still work.
    expect(find.textContaining('Alerts on a phone need the Escanor Android app'), findsOneWidget);
    expect(find.text('Team messages'), findsOneWidget);
    expect(find.text('Automatic checks'), findsOneWidget);
    await t.tap(find.byType(Switch).last);
    await settle(t);
    expect(jsonDecode(backend.calls.lastWhere((r) => r.method == 'PATCH').body), {'checks': false});
    expect(t.widget<Switch>(find.byType(Switch).last).value, false);
    fail = true;
    await t.tap(find.byType(Switch).first);
    await settle(t);
    expect(t.widget<Switch>(find.byType(Switch).first).value, true); // back as it was
  });

  testWidgets('Developer lists keys, creates one shown once, and tests the connection', (t) async {
    tallPhone(t);
    final backend = await setUpBackend({
      'GET /agent/mcp/connections': (_) => [
            {'id': 'k1', 'name': 'Claude Desktop', 'token_prefix': 'esc_ab', 'created_at': '2026-10-01T00:00:00Z', 'total_calls': 1234},
            {'id': 'k2', 'name': 'Revoked', 'revoked_at': '2026-10-02T00:00:00Z', 'total_calls': 0},
          ],
      'POST /agent/mcp/install': (_) => {'endpoint': 'https://mcp.escanor.in/mcp', 'token': 'esc_secret_token', 'cli_command': ''},
    });
    await t.pumpWidget(host(const DeveloperPage()));
    await settle(t);
    expect(find.text('Claude Desktop'), findsOneWidget);
    expect(find.text('Revoked'), findsNothing);
    expect(find.text('esc_ab… · 1,234 calls'), findsOneWidget);
    expect(find.text('test.escanor'), findsOneWidget);
    await t.tap(find.text('Create a key'));
    await settle(t);
    expect(find.text('Your new key'), findsOneWidget);
    expect(find.text('esc_secret_token'), findsOneWidget);
    expect(find.text('Copy it now. It is shown only once.'), findsOneWidget);
    expect(backend.count('POST /agent/mcp/install'), 1);
  });

  testWidgets('A key can be renamed', (t) async {
    tallPhone(t);
    final backend = await setUpBackend({
      'GET /agent/mcp/connections': (_) => [
            {'id': 'k1', 'name': 'Claude Desktop', 'token_prefix': 'esc_ab', 'created_at': '2026-10-01T00:00:00Z', 'total_calls': 2},
          ],
      'PATCH /agent/mcp/connections/k1': (r) => {'id': 'k1', 'name': jsonDecode(r.body)['name']},
    });
    await t.pumpWidget(host(const DeveloperPage()));
    await settle(t);
    await t.tap(find.text('Claude Desktop'));
    await settle(t);
    expect(find.text('Replace with a new key'), findsOneWidget);
    expect(find.text('Delete this key'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Cursor');
    await settle(t);
    await t.tap(find.text('Save name'));
    await settle(t);
    expect(jsonDecode(backend.calls.lastWhere((r) => r.method == 'PATCH').body), {'name': 'Cursor'});
  });

  testWidgets('Legal documents read inside the app', (t) async {
    tallPhone(t);
    await setUpBackend();
    await t.pumpWidget(host(const PrivacyPage()));
    await settle(t);
    await t.tap(find.text('Terms'));
    await settle(t);
    expect(find.text('Terms of service'), findsOneWidget);
    expect(find.text('This agreement'), findsOneWidget);
    expect(find.text('Last updated $policyDate'), findsOneWidget);
  });

  testWidgets('About shows the version and the documents', (t) async {
    await setUpBackend();
    await t.pumpWidget(host(const AboutPage()));
    await settle(t);
    expect(find.text('Escanor'), findsOneWidget);
    expect(find.textContaining('Version '), findsOneWidget);
    expect(find.text('Terms of service'), findsOneWidget);
  });
}
