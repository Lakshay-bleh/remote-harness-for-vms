import 'dart:async';
import 'dart:convert';

import 'package:escanor/core/storage.dart';
import 'package:escanor/core/theme.dart';
import 'package:escanor/features/machines/hub_api.dart';
import 'package:escanor/features/machines/hub_socket.dart';
import 'package:escanor/features/machines/hub_store.dart';
import 'package:escanor/features/machines/protocol.dart';
import 'package:escanor/features/machines/session_search.dart';
import 'package:escanor/features/machines/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fakes.dart';

SessionDto chat(String id, String title) => SessionDto(
    id: id, vmId: 'v1', cwd: '/w', title: title, createdAt: '2026-10-07T10:00:00Z', lastMessageAt: '2026-10-07T10:00:00Z', status: 'idle', accountId: 'default');

SessionSearchHit hit(String id, {String snippet = '', double score = 1, String match = 'words'}) =>
    SessionSearchHit(sessionId: id, snippet: snippet, score: score, match: match);

void main() {
  group('mergeSessionSearch', () {
    final chats = [chat('a', 'Deploy staging'), chat('b', 'Lunch plans'), chat('c', 'Fix CI'), chat('d', 'Release deploy notes')];
    List<String> ids(List<SessionSearchResult> r) => [for (final x in r) x.session.id];
    String titleOf(SessionDto s) => s.title;

    test('no query: every chat, in its usual order, without snippets', () {
      final r = mergeSessionSearch(sessions: chats, query: '  ', titleOf: titleOf, hits: [hit('b', snippet: 'x')]);
      expect(ids(r), ['a', 'b', 'c', 'd']);
      expect(r.every((x) => x.snippet == null), isTrue);
    });

    test('before the hub answers (or when it cannot search), titles only', () {
      expect(ids(mergeSessionSearch(sessions: chats, query: 'DEPLOY', titleOf: titleOf)), ['a', 'd']);
    });

    test('title matches first in their usual order, then content hits in the hub\'s order with their snippets', () {
      final r = mergeSessionSearch(
        sessions: chats,
        query: 'deploy',
        titleOf: titleOf,
        hits: [hit('c', snippet: 'the deploy job failed', score: 9), hit('d', snippet: 'also here', score: 8), hit('b', snippet: 'deploy after lunch', score: 3)],
      );
      expect(ids(r), ['a', 'd', 'c', 'b']);
      expect([for (final x in r) x.snippet], [null, null, 'the deploy job failed', 'deploy after lunch']);
    });

    test('hits for chats not listed here are left out, and an empty snippet shows no second line', () {
      final r = mergeSessionSearch(sessions: chats, query: 'zzz', titleOf: titleOf, hits: [hit('gone', snippet: 'x'), hit('b', match: 'title')]);
      expect(ids(r), ['b']);
      expect(r.single.snippet, isNull);
    });

    test('the title used is the one shown (a name given on this phone)', () {
      final r = mergeSessionSearch(sessions: chats, query: 'renamed', titleOf: (s) => s.id == 'c' ? 'Renamed here' : s.title);
      expect(ids(r), ['c']);
    });
  });

  test('hub answers are parsed defensively', () {
    final hits = SessionSearchHit.listFrom([
      {'sessionId': 's1', 'snippet': 'one line', 'score': 12, 'match': 'words'},
      {'sessionId': 's2', 'score': 'high', 'match': 'title'},
      {'snippet': 'no id'},
      'junk',
    ]);
    expect([for (final h in hits) (h.sessionId, h.snippet, h.score, h.match)], [('s1', 'one line', 12.0, 'words'), ('s2', '', 0.0, 'title')]);
    expect(SessionSearchHit.listFrom({'ok': true}), isEmpty);
  });

  group('searching on the hub', () {
    const creds = HubCredentials();
    late List<http.Request> sent;
    late Future<http.Response> Function(http.Request) answer;

    // The machine list, its chats, and whatever [answer] says for a search.
    HubStore make() => HubStore(
          api: HubApi(
            credentials: creds,
            client: MockClient((req) async {
              sent.add(req);
              final p = req.url.path;
              if (p == '/api/vms') {
                return http.Response(jsonEncode([{'id': 'v1', 'name': 'box', 'connected': true, 'lastSeenAt': null, 'accounts': []}]), 200);
              }
              if (p == '/api/vms/v1/sessions') {
                return http.Response(jsonEncode([
                  for (final (id, title) in [('s1', 'Morning chat'), ('s2', 'Deploy notes'), ('s3', 'Lunch')])
                    {'id': id, 'vmId': 'v1', 'cwd': '/w', 'title': title, 'createdAt': '2026-10-07T10:00:00Z', 'lastMessageAt': '2026-10-07T10:00:00Z', 'status': 'idle', 'accountId': 'default'},
                ]), 200);
              }
              if (p == '/api/vms/v1/sessions/search') return answer(req);
              if (p == '/api/mcp-servers') return http.Response(jsonEncode({'servers': [], 'vms': []}), 200);
              return http.Response('{}', 200);
            }),
          ),
          socket: HubSocket(connector: (u, p) => FakeSocket(u, p), token: () => creds.token, hubUrl: () => creds.hubUrl),
          credentials: creds,
        );

    setUp(() async {
      await Storage.initForTest();
      creds.hubUrl = 'https://hub.example.test';
      creds.token = 'tok';
      sent = [];
      answer = (_) async => http.Response('[]', 200);
    });

    test('asks the machine\'s search route, and falls back to nothing when the hub cannot search', () async {
      final store = make();
      answer = (_) async => http.Response(jsonEncode([{'sessionId': 's1', 'snippet': 'we deployed', 'score': 5, 'match': 'words'}]), 200);
      final hits = await store.searchSessions('v1', 'deploy & ship');
      expect(hits.single.snippet, 'we deployed');
      final url = sent.last.url;
      expect(url.path, '/api/vms/v1/sessions/search');
      expect(url.queryParameters, {'q': 'deploy & ship', 'limit': '20'});

      answer = (_) async => http.Response('{"error":"Not found"}', 404); // a hub from before search
      expect(await store.searchSessions('v1', 'deploy'), isEmpty);
      answer = (_) async => throw const SocketLikeException(); // offline
      expect(await store.searchSessions('v1', 'deploy'), isEmpty);
    });

    Widget sidebar() => ProviderScope(
          child: MaterialApp(
            theme: buildTheme(EscanorColors.of(ThemeName.dark, AccentName.gold), reduceMotion: true),
            home: Scaffold(body: HubSidebar(onSelectSession: () {})),
          ),
        );

    testWidgets('typing filters titles at once, then shows chats whose content matched, with the matching line', (tester) async {
      HubStore.instance = make();
      answer = (req) async => http.Response(
          jsonEncode([
            {'sessionId': 's2', 'snippet': '', 'score': 60, 'match': 'title'},
            {'sessionId': 's1', 'snippet': 'how do the deployments work?', 'score': 20, 'match': 'words'},
          ]),
          200);
      await tester.pumpWidget(sidebar());
      await tester.pumpAndSettle();
      expect(find.text('Morning chat'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'deploy');
      await tester.pump();
      // Titles at once; the hub is not asked until typing pauses.
      expect(find.text('Deploy notes'), findsOneWidget);
      expect(find.text('Morning chat'), findsNothing);
      expect(sent.where((r) => r.url.path.endsWith('/search')), isEmpty);

      await tester.pump(contentSearchDelay);
      await tester.pumpAndSettle();
      expect(sent.where((r) => r.url.path.endsWith('/search')).length, 1);
      expect(find.text('Deploy notes'), findsOneWidget);
      expect(find.text('Morning chat'), findsOneWidget);
      expect(find.text('how do the deployments work?'), findsOneWidget);
      expect(find.text('Lunch'), findsNothing);
      HubStore.instance.logout();
    });

    testWidgets('an answer for an older query is ignored, and one letter only filters titles', (tester) async {
      HubStore.instance = make();
      final slow = Completer<http.Response>();
      answer = (req) => req.url.queryParameters['q'] == 'lunch'
          ? slow.future
          : Future.value(http.Response(jsonEncode([{'sessionId': 's3', 'snippet': 'not lunch', 'score': 1, 'match': 'words'}]), 200));
      await tester.pumpWidget(sidebar());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'lunch');
      await tester.pump(contentSearchDelay); // asks for "lunch"; the answer is slow
      await tester.enterText(find.byType(TextField), 'morning');
      await tester.pump(contentSearchDelay);
      await tester.pumpAndSettle();
      slow.complete(http.Response(jsonEncode([{'sessionId': 's2', 'snippet': 'stale line', 'score': 9, 'match': 'words'}]), 200));
      await tester.pumpAndSettle();
      expect(find.text('stale line'), findsNothing);
      expect(find.text('Deploy notes'), findsNothing);
      expect(find.text('Morning chat'), findsOneWidget);
      expect(find.text('not lunch'), findsOneWidget);

      final before = sent.length;
      await tester.enterText(find.byType(TextField), 'm');
      await tester.pump(contentSearchDelay);
      await tester.pumpAndSettle();
      expect(sent.length, before, reason: 'one letter is not sent to the hub');
      expect(find.text('not lunch'), findsNothing, reason: 'hits for "morning" are not shown for "m"');
      HubStore.instance.logout();
    });
  });
}

class SocketLikeException implements Exception {
  const SocketLikeException();
}
