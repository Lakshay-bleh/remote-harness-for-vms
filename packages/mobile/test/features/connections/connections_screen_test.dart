import 'dart:convert';

import 'package:escanor/core/api.dart';
import 'package:escanor/core/storage.dart';
import 'package:escanor/core/theme.dart';
import 'package:escanor/features/connections/connections_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Widget app(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: buildTheme(EscanorColors.of(ThemeName.dark, AccentName.gold), reduceMotion: true),
        home: Scaffold(body: child),
      ),
    );

void main() {
  final sent = <http.Request>[];
  var connected = <Map<String, dynamic>>[
    {'provider_id': 'sentry', 'name': 'Sentry', 'available_to_assistant': true, 'needs_reconnect': false},
  ];

  setUp(() async {
    await Storage.initForTest();
    sent.clear();
    connected = [{'provider_id': 'sentry', 'name': 'Sentry', 'available_to_assistant': true, 'needs_reconnect': false}];
    api = Api(
      base: 'https://api.test',
      client: MockClient((req) async {
        sent.add(req);
        final p = req.url.path;
        if (p == '/ai/capabilities') return http.Response(jsonEncode({'summary': 'Your assistant can use 1 service.', 'integrations': connected}), 200);
        if (p == '/integrations/catalog') {
          return http.Response(jsonEncode({'providers': [
            {'id': 'github', 'name': 'GitHub', 'description': 'Code hosting', 'category_label': 'Source control', 'connect_via': 'api_key', 'oauth_available': false,
              'credential_fields': ['org_name'], 'token_label': 'Personal access token', 'help_url': 'https://github.com/settings/tokens'},
            {'id': 'vercel', 'name': 'Vercel', 'description': 'Hosting', 'category_label': 'Hosting', 'connect_via': 'oauth', 'oauth_available': true, 'credential_fields': []},
            {'id': 'sentry', 'name': 'Sentry', 'category_label': 'Observability', 'connect_via': 'oauth', 'oauth_available': true, 'credential_fields': []},
            {'id': 'local', 'name': 'Local DB', 'category_label': 'Databases', 'connect_via': 'local_agent', 'credential_fields': []},
          ]}), 200);
        }
        if (p == '/auth/integrations/github/connect') {
          connected = [...connected, {'provider_id': 'github', 'name': 'GitHub', 'available_to_assistant': true}];
          return http.Response('{"synced":true}', 200);
        }
        if (p == '/auth/integrations/sentry' && req.method == 'DELETE') {
          connected = [];
          return http.Response('{"disconnected":true}', 200);
        }
        return http.Response('{}', 404);
      }),
    );
    api.tokens.set('access', 'refresh', 900);
  });

  testWidgets('connected services, the catalog, search, connecting with a key and disconnecting', (tester) async {
    await tester.pumpWidget(app(const ConnectionsScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your assistant can use 1 service. Connect a service once'), findsOneWidget);
    expect(find.text('Your assistant can use this'), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('Vercel'), findsOneWidget);
    expect(find.text('Observability'), findsNothing, reason: 'already connected services are not offered again');

    await tester.enterText(find.byType(TextField), 'host');
    await tester.pumpAndSettle();
    expect(find.text('GitHub'), findsNothing);
    expect(find.text('Vercel'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Nothing matches.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub'));
    await tester.pumpAndSettle();
    expect(find.text('Connect GitHub'), findsOneWidget);
    expect(find.text('Personal access token'), findsOneWidget);
    expect(find.text('Org name'), findsOneWidget);
    expect(find.text('Where do I find this?'), findsNothing, reason: 'no link out of the app');
    final sheetFields = find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField));
    await tester.enterText(sheetFields.first, ' ghp_secret ');
    await tester.pump();
    await tester.tap(find.text('Connect').last);
    await tester.pumpAndSettle();
    final connect = sent.lastWhere((r) => r.url.path.endsWith('/connect'));
    expect(jsonDecode(connect.body), {'access_token': 'ghp_secret'});
    expect(find.text('GitHub connected.'), findsOneWidget);

    await tester.tap(find.text('Disconnect').first);
    await tester.pumpAndSettle();
    expect(find.text('Disconnect Sentry?'), findsOneWidget);
    await tester.tap(find.text('Disconnect').last);
    await tester.pumpAndSettle();
    expect(find.text('Sentry disconnected.'), findsOneWidget);
  });

  testWidgets('a service that connects through a paired machine says so', (tester) async {
    await tester.pumpWidget(app(const ConnectionsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Local DB'));
    await tester.pumpAndSettle();
    expect(find.textContaining('connects through a machine you pair'), findsOneWidget);
  });
}
