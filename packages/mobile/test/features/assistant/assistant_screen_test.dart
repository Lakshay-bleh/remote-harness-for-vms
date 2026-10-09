import 'dart:convert';

import 'package:escanor/core/api.dart';
import 'package:escanor/core/nav.dart';
import 'package:escanor/core/storage.dart';
import 'package:escanor/features/assistant/assistant_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'harness.dart';

void main() {
  late Map<String, dynamic> status;
  late List<Map<String, dynamic>> chatBodies;
  late List<Map<String, dynamic>> answers;
  late List<Map<String, dynamic>> items;
  late List<String> stops;
  late bool n2Running;
  late List<Map<String, dynamic>> connected;

  setUp(() async {
    connected = [
      {'provider_id': 'github', 'name': 'GitHub', 'connected': true, 'available_to_assistant': true},
    ];
    status = {'state': 'ready', 'ready': true, 'message': 'Ready'};
    chatBodies = [];
    answers = [];
    items = [];
    stops = [];
    n2Running = true;
    // This test is about answering an approval by hand, so this phone is set to ask first.
    await Storage.initForTest(prefs: {'escanor.prefs.v1': '{"defaultMode":"default"}', 'escanor.migrated.autonomy.v1': '1'}, secrets: {
      'escanor_access': 'a',
      'escanor_refresh': 'r',
      'escanor_access_expires': '${DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch}',
    });
    api = Api(
      base: 'https://api.test',
      client: MockClient((req) async {
        final p = req.url.path;
        http.Response ok(Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json; charset=utf-8'});
        if (p == '/auth/session') return ok({'user': {'id': 'u1', 'email': 'a@b.co', 'name': 'Ada'}});
        if (p == '/ai/status') return ok(status);
        if (p == '/ai/capabilities') {
          return ok({
            'machine': {'state': 'sleeping', 'detail': '', 'source': ''},
            'integrations': connected,
          });
        }
        if (p == '/ai/conversations') return ok({'conversations': []});
        if (p == '/ai/chat') {
          chatBodies.add(jsonDecode(req.body) as Map<String, dynamic>);
          items = [
            {'id': 1, 'kind': 'user', 'text': chatBodies.last['text']},
            {'id': 2, 'kind': 'approval', 'request_id': 'r1', 'status': 'pending', 'title': 'Read the build log', 'detail': '', 'risk': 'normal', 'raw': ''},
          ];
          return ok({'conversation_id': 'n1'});
        }
        if (p == '/ai/conversations/n1/messages') {
          final after = int.parse(req.url.queryParameters['after'] ?? '0');
          return ok({'items': items.where((i) => (i['id'] as int) > after).toList(), 'approvals': [], 'running': true, 'pending': 1, 'last_id': items.length});
        }
        if (p == '/ai/conversations/n2/messages') {
          return ok({
            'items': [
              {'id': 1, 'kind': 'user', 'text': 'deploy it'},
              {'id': 2, 'kind': 'notice', 'text': 'Model A wasn’t available, so Model B is answering.'},
              if (!n2Running) {'id': 3, 'kind': 'notice', 'text': 'Stopped.'},
            ],
            'approvals': [],
            'running': n2Running,
            'pending': 0,
            'last_id': n2Running ? 2 : 3,
            if (n2Running)
              'progress': {
                'text': 'Asking GPT OSS 120b · step 2',
                'since': DateTime.now().toUtc().subtract(const Duration(seconds: 14)).toIso8601String(),
                'step': 2,
              },
          });
        }
        if (p == '/ai/conversations/n2/stop') {
          stops.add('n2');
          return ok({'ok': true, 'stopped': true});
        }
        if (p == '/ai/conversations/n1/permissions/r1') {
          answers.add(jsonDecode(req.body) as Map<String, dynamic>);
          return ok({'status': 'ok'});
        }
        return http.Response('{}', 404);
      }),
    );
  });

  Future<ProviderContainer> pumpScreen(WidgetTester tester) async {
    final container = ProviderContainer();
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: themed(const AssistantScreen())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return container;
  }

  Future<void> finish(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump();
  }

  testWidgets('while the assistant is being set up, says so', (tester) async {
    status = {'state': 'setting_up', 'ready': false, 'message': 'Starting your machine…'};
    final container = await pumpScreen(tester);
    expect(find.text('Getting your assistant ready'), findsOneWidget);
    expect(find.text('Starting your machine…'), findsOneWidget);
    expect(find.text('This happens once, and takes a few seconds.'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('a stuck assistant says it is not available', (tester) async {
    status = {'state': 'not_configured', 'ready': false, 'message': 'Escanor AI is not configured.'};
    final container = await pumpScreen(tester);
    expect(find.text('Your assistant isn’t available yet'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('connected services whose reach could not be checked count as connected, not as nothing', (tester) async {
    connected = [
      for (var i = 0; i < 25; i++) {'provider_id': 'p$i', 'name': 'Service $i', 'connected': true, 'available_to_assistant': null},
    ];
    final container = await pumpScreen(tester);
    expect(find.text('Connected:'), findsOneWidget);
    expect(find.text('+20'), findsOneWidget);
    expect(find.text('Connect a service so I can work on it'), findsNothing);
    await finish(tester, container);
  });

  testWidgets('services connected without assistant tools are not called nothing connected', (tester) async {
    connected = [
      {'provider_id': 'airtable', 'name': 'Airtable', 'connected': true, 'available_to_assistant': false},
      {'provider_id': 'vercel', 'name': 'Vercel', 'connected': true, 'available_to_assistant': null, 'needs_reconnect': true},
    ];
    final container = await pumpScreen(tester);
    expect(find.text('Connected:'), findsNothing);
    expect(find.text('Connect a service so I can work on it'), findsNothing);
    await finish(tester, container);
  });

  testWidgets('with nothing connected, invites connecting a service', (tester) async {
    connected = [];
    final container = await pumpScreen(tester);
    expect(find.text('Connect a service so I can work on it'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('a new chat offers suggestions; one starts the conversation and its question can be answered', (tester) async {
    final container = await pumpScreen(tester);
    expect(find.text('New chat'), findsOneWidget);
    expect(find.text('What should we work on?'), findsOneWidget);
    expect(find.text('Asleep'), findsOneWidget, reason: 'the machine chip');
    expect(find.text('Connected:'), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);

    await tester.tap(find.text('Fix the failing build in my repository'));
    await tester.pump();
    expect(find.text('Fix the failing build in my repository'), findsOneWidget, reason: 'shown at once');
    await tester.pump(const Duration(milliseconds: 50));
    expect(chatBodies.single, {'text': 'Fix the failing build in my repository', 'conversation_id': null});
    expect(container.read(navProvider).conversationId, 'n1');

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Read the build log'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(answers.single, {'allow': true});
    expect(find.text('You said continue.'), findsOneWidget);

    // a new chat from the header starts empty again
    await tester.tap(find.byTooltip('New chat'));
    await tester.pump();
    expect(find.text('What should we work on?'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('a running turn says what it is doing and for how long, quiet notices show, and Stop stops it', (tester) async {
    final container = ProviderContainer();
    container.read(navProvider.notifier).openChat('n2');
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: themed(const AssistantScreen())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Model A wasn’t available, so Model B is answering.'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^Asking GPT OSS 120b · step 2 · 1[45]s$')), findsOneWidget);

    await tester.tap(find.byTooltip('Stop'));
    await tester.pump();
    expect(find.text('Stopping…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 50));
    expect(stops, ['n2']);
    expect(find.byTooltip('Stopping'), findsOneWidget, reason: 'the stop button shows it is working');

    n2Running = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Stopped.'), findsOneWidget);
    expect(find.text('Stopping…'), findsNothing);
    expect(find.byTooltip('Stop'), findsNothing);
    await finish(tester, container);
  });
}
