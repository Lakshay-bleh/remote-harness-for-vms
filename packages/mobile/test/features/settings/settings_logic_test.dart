import 'package:escanor/features/settings/legal_content.dart';
import 'package:escanor/features/settings/settings_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('developer page', () {
    test('shows only the host of the server', () {
      expect(hostOf('https://api.escanor.in/api/v1'), 'api.escanor.in');
      expect(hostOf('http://10.0.2.2:8100/api/v1'), '10.0.2.2:8100');
      expect(hostOf('not a url'), 'not a url');
    });
    test('checks the health address beside the API', () {
      expect(healthUri('https://api.escanor.in/api/v1').toString(), 'https://api.escanor.in/health');
      expect(healthUri('http://10.0.2.2:8100/api/v1/').toString(), 'http://10.0.2.2:8100/health');
    });
    test('words the connection check', () {
      expect(checkText(ok: true, ms: 120, status: 200), 'Reachable · 120 ms');
      expect(checkText(ok: false, ms: 50, status: 503), 'Error 503');
      expect(checkText(ok: false, ms: 9000, status: 0), 'Cannot reach it');
    });
    test('debug info names the build and never a token', () {
      final text = debugInfo(
          version: '1.0.0 (1)',
          platform: 'Android app',
          server: 'https://api.escanor.in/api/v1',
          signedIn: true,
          computers: 2,
          screen: '412x915 @3x',
          os: 'Android 15',
          now: DateTime.utc(2026, 10, 7, 9));
      expect(text.split('\n').first, 'Escanor app 1.0.0 (1)');
      expect(text, contains('Paired computers: 2'));
      expect(text, contains('Signed in: yes'));
      expect(text, contains('Time: 2026-10-07T09:00:00.000Z'));
      expect(text.toLowerCase().contains('token'), false);
    });
    test('lists only live keys the person made', () {
      final keys = appKeys([
        McpConnection.fromJson({'id': 'a', 'name': 'Claude', 'total_calls': 3}),
        McpConnection.fromJson({'id': 'b', 'name': 'Old', 'revoked_at': '2026-01-01T00:00:00Z'}),
        McpConnection.fromJson({'id': 'c', 'name': 'Desktop', 'managed_by': 'escanor-desktop'}),
      ]);
      expect(keys.map((k) => k.id), ['a']);
      expect(keys.single.totalCalls, 3);
    });
  });

  group('profile name', () {
    test('tidies spaces and refuses empty or long names', () {
      expect(checkProfileName('  Ada   Lovelace ').name, 'Ada Lovelace');
      expect(checkProfileName('   ').problem, 'Please enter a name.');
      expect(checkProfileName('x' * 81).problem, 'A name can be up to 80 characters.');
      expect(checkProfileName('x' * 80).name?.length, 80);
    });
  });

  group('notification choices', () {
    test('reads the account switches, on unless the server says off', () {
      final p = NotificationPrefs.fromJson({'push_enabled': true, 'server_down': false});
      expect(p.pushEnabled, true);
      expect(p['server_down'], false);
      expect(p['team_pings'], true);
    });
    test('a change touches only that switch', () {
      final p = const NotificationPrefs().merge({'team_pings': false});
      expect(p.teamPings, false);
      expect(p.emergencyAlerts, true);
      expect(p.toJson().length, 6);
    });
    test('lists the five kinds in the website order', () {
      expect(notificationKinds.map((k) => k.key), ['emergency_alerts', 'server_down', 'deployment_approvals', 'team_pings', 'checks']);
    });
  });

  group('legal documents', () {
    test('lists every document the website links, except its own index and its About page', () {
      final keys = legalList.map((d) => d.key).toList();
      expect(keys, [
        'privacy', 'terms', 'acceptable-use', 'refunds', 'cookies', 'privacy/requests', 'delete-account', //
        'grievances', 'support', 'security', 'accessibility', 'privacy/notice', 'dpa', 'dark-patterns-audit', 'privacy/us',
      ]);
      expect(keys.contains('legal'), false);
      expect(keys.contains('about'), false); // a website page, opened on the web
      for (final k in keys) {
        expect(legalDocuments[k]!.sections, isNotEmpty, reason: k);
      }
    });
    test('names a document for its page, and falls back for an unknown one', () {
      expect(legalLabel('privacy/requests'), 'Privacy requests');
      expect(legalLabel('privacy/us'), 'US privacy');
      expect(legalLabel('privacy/notice'), 'Consent notice');
      expect(legalLabel('dpa'), 'Data processing');
      expect(legalLabel('about'), 'Legal'); // a website page, not stored in the app
      expect(legalLabel('nope'), 'Legal');
      expect(policyVersion, '2026-10-08');
      expect(policyDate, '8 October 2026');
    });
  });
}
