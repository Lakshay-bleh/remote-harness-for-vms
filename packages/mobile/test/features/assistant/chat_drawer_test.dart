import 'dart:convert';

import 'package:escanor/core/api.dart';
import 'package:escanor/core/nav.dart';
import 'package:escanor/core/storage.dart';
import 'package:escanor/features/assistant/chat_drawer.dart';
import 'package:escanor/features/assistant/chat_meta_store.dart';
import 'package:escanor/features/assistant/conversations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'harness.dart';

void main() {
  late List<Map<String, dynamic>> server;
  late List<String> deleted;
  late List<String> calls;
  late bool deleteFails;

  setUp(() async {
    final soon = DateTime.now().toUtc().toIso8601String();
    server = [
      {'id': 'c1', 'title': 'Fix the failing build', 'created_at': soon, 'updated_at': soon},
      {'id': 'c2', 'title': 'Deploy to Vercel', 'created_at': soon, 'updated_at': soon},
    ];
    deleted = [];
    calls = [];
    deleteFails = false;
    await Storage.initForTest(secrets: {
      'escanor_access': 'a',
      'escanor_refresh': 'r',
      'escanor_access_expires': '${DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch}',
    });
    api = Api(
      base: 'https://api.test',
      client: MockClient((req) async {
        final p = req.url.path;
        if (p == '/auth/session') return http.Response(jsonEncode({'user': {'id': 'u1', 'email': 'a@b.co', 'name': 'Ada'}}), 200);
        if (p == '/ai/conversations' && req.method == 'GET') return http.Response(jsonEncode({'conversations': server}), 200);
        if (p.endsWith('/stop') && req.method == 'POST') {
          calls.add('stop ${p.split('/')[3]}');
          return http.Response(jsonEncode({'ok': true, 'stopped': true}), 200);
        }
        if (p.startsWith('/ai/conversations/') && req.method == 'DELETE') {
          final id = Uri.decodeComponent(p.split('/').last);
          calls.add('delete $id');
          if (deleteFails) return http.Response(jsonEncode({'detail': 'Server is busy'}), 500);
          deleted.add(id);
          server = server.where((c) => c['id'] != id).toList();
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        return http.Response('{}', 404);
      }),
    );
  });

  Future<ProviderContainer> pumpDrawer(WidgetTester tester) async {
    final container = ProviderContainer();
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: themed(const ChatDrawer())));
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> finish(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump();
  }

  testWidgets('lists the chats by recency, opens one, and starts a new one', (tester) async {
    final container = await pumpDrawer(tester);
    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Fix the failing build'), findsOneWidget);
    expect(find.text('Deploy to Vercel'), findsOneWidget);

    await tester.tap(find.text('Deploy to Vercel'));
    await tester.pump();
    expect(container.read(navProvider).conversationId, 'c2');
    expect(container.read(navProvider).tab, AppTab.assistant);

    await tester.tap(find.text('New chat'));
    await tester.pump();
    expect(container.read(navProvider).conversationId, isNull);
    await finish(tester, container);
  });

  testWidgets('a chat can be pinned and renamed on this phone, and the name wins over the server’s', (tester) async {
    final container = await pumpDrawer(tester);
    await tester.tap(find.byTooltip('Options for Deploy to Vercel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin to the top'));
    await tester.pumpAndSettle();
    expect(find.text('Pinned'), findsOneWidget);
    expect(container.read(chatMetaProvider).pinned, ['c2']);

    await tester.tap(find.byTooltip('Options for Deploy to Vercel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Ship it');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Ship it'), findsOneWidget);
    expect(chatName('c2', container.read(chatMetaProvider), container.read(conversationsProvider).list), 'Ship it');
    expect(Storage.instance.getString('escanor.chats.v1'), contains('Ship it'));
    await finish(tester, container);
  });

  testWidgets('deleting asks first, then removes the chat everywhere', (tester) async {
    final container = await pumpDrawer(tester);
    container.read(navProvider.notifier).openChat('c1');
    await tester.tap(find.byTooltip('Options for Fix the failing build'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete “Fix the failing build”?'), findsOneWidget);
    expect(find.text('This cannot be undone.'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(deleted, ['c1']);
    expect(calls, ['stop c1', 'delete c1'], reason: 'a chat still working is stopped before it is deleted');
    expect(find.text('Fix the failing build'), findsNothing);
    expect(container.read(navProvider).conversationId, isNull, reason: 'the open chat was the one deleted');
    await finish(tester, container);
  });

  testWidgets('a delete that fails says which chat and keeps it', (tester) async {
    deleteFails = true;
    final container = await pumpDrawer(tester);
    container.read(navProvider.notifier).openChat('c1');
    await tester.tap(find.byTooltip('Options for Fix the failing build'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(calls, ['stop c1', 'delete c1']);
    expect(find.textContaining('Could not delete “Fix the failing build”.'), findsOneWidget);
    expect(find.text('Fix the failing build'), findsOneWidget);
    expect(container.read(navProvider).conversationId, 'c1');
    await tester.pump(const Duration(seconds: 10));
    await finish(tester, container);
  });
}
