import 'dart:async';
import 'dart:convert';

import 'package:escanor/core/storage.dart';
import 'package:escanor/features/machines/chat_choices.dart';
import 'package:escanor/features/machines/hub_api.dart';
import 'package:escanor/features/machines/hub_socket.dart';
import 'package:escanor/features/machines/hub_state.dart';
import 'package:escanor/features/machines/hub_store.dart';
import 'package:escanor/features/machines/message_format.dart';
import 'package:escanor/features/machines/protocol.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fakes.dart';

MessageDto row(num id, Object? message, {String at = '2026-10-08T10:00:00.000Z'}) =>
    MessageDto(id: id, sessionId: 's', vmId: 'v', message: message, createdAt: at);

Map<String, dynamic> prompt(String text) => {
      'type': 'user',
      'local': true,
      'message': {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': text}
        ]
      }
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('reducer', () {
    test('a sent message shows at once and the hub echo takes its place', () {
      var s = const HubState(authed: true);
      s = reduceHub(s, SetMessages('s', [row(1, prompt('hello'))]));
      final shown = optimisticPrompt(optimisticRowBase + 1, 's', 'v', 'hello', s.messagesBySession['s']!);
      s = reduceHub(s, AppendMessage('s', shown));
      expect(s.messagesBySession['s']!.length, 2);
      expect(busySince(s.messagesBySession['s']!), isNotNull, reason: 'the chat is working as soon as the message is sent');
      // The same words said earlier are not the echo.
      s = reduceHub(s, AppendMessage('s', row(localRowBase + 1, prompt('hello'))));
      final rows = s.messagesBySession['s']!;
      expect(rows.length, 2);
      expect(rows.any(isOptimisticRow), isFalse);
    });

    test('a refresh keeps an unanswered permission prompt, a prompt just sent, and rows that arrived meanwhile', () {
      var s = const HubState(authed: true);
      final perm = {'type': 'permission_request', 'requestId': 'r1', 'toolName': 'Bash', 'input': <String, dynamic>{}};
      s = reduceHub(s, AppendMessage('s', row(localRowBase + 1, perm)));
      s = reduceHub(s, AppendMessage('s', optimisticPrompt(optimisticRowBase + 1, 's', 'v', 'go', const [])));
      s = reduceHub(s, AppendMessage('s', row(localRowBase + 2, {'type': 'assistant', 'message': {'content': []}})));
      s = reduceHub(s, SetMessages('s', [row(1, prompt('earlier'))], seenLocalUpTo: localRowBase + 1));
      final ids = s.messagesBySession['s']!.map((r) => r.id).toList();
      expect(ids, [1, localRowBase + 1, optimisticRowBase + 1, localRowBase + 2]);
    });

    test('a refresh does not duplicate what the hub list already holds', () {
      var s = const HubState(authed: true);
      final msg = {'type': 'assistant', 'message': {'content': [{'type': 'text', 'text': 'done'}]}};
      s = reduceHub(s, AppendMessage('s', row(localRowBase + 5, msg)));
      s = reduceHub(s, SetMessages('s', [row(9, msg)], seenLocalUpTo: localRowBase));
      expect(s.messagesBySession['s']!.map((r) => r.id), [9]);
    });

    test('a stopped run stays stopped through a refresh until the person sends something new', () {
      var s = const HubState(authed: true, sessionsByVm: {});
      s = reduceHub(s, SetMessages('s', [row(1, prompt('work'))]));
      s = reduceHub(s, const SessionWentIdle('v', 's'));
      expect(busySince(s.messagesBySession['s']!), isNull);
      s = reduceHub(s, SetMessages('s', [row(1, prompt('work'))]));
      expect(busySince(s.messagesBySession['s']!), isNull, reason: 'the hub list has no result yet');
      s = reduceHub(s, SetMessages('s', [row(1, prompt('work')), row(2, prompt('again'))]));
      expect(busySince(s.messagesBySession['s']!), isNotNull, reason: 'a newer prompt is running');
    });

    test('stopping settles every prompt waiting for an answer', () {
      var s = const HubState(authed: true);
      s = reduceHub(s, AppendMessage('s', row(localRowBase + 1, {'type': 'permission_request', 'requestId': 'r1', 'toolName': 'Bash', 'input': <String, dynamic>{}})));
      s = reduceHub(s, const ResolveAllPermissions('s'));
      expect(s.resolvedPermissionIds, {'r1'});
    });
  });

  group('store', () {
    const creds = HubCredentials();
    late List<http.Request> sent;
    late List<FakeSocket> sockets;
    late http.Response Function(http.Request) answer;

    HubStore make() {
      final api = HubApi(credentials: creds, client: MockClient((req) async {
        sent.add(req);
        return answer(req);
      }));
      final socket = HubSocket(connector: (u, p) => (sockets..add(FakeSocket(u, p))).last, token: () => creds.token, hubUrl: () => creds.hubUrl);
      return HubStore(api: api, socket: socket, credentials: creds);
    }

    setUp(() async {
      await Storage.initForTest();
      creds.hubUrl = 'https://hub.example.test';
      creds.token = 'tok';
      sent = [];
      sockets = [];
      answer = (_) => http.Response('{}', 200);
    });

    const session = SessionDto(id: 's', vmId: 'v', cwd: '/w', title: 'T', createdAt: '2026-10-08T10:00:00.000Z', lastMessageAt: '2026-10-08T10:00:00.000Z', status: 'idle', accountId: 'a');

    test('the mode chosen for a chat is kept, and sent again when the chat is opened and when a message goes out', () async {
      final store = make();
      await store.setPermissionMode('v', 's', 'auto');
      expect(store.savedChoices('v', 's')!.mode, 'auto');
      sent.clear();
      answer = (req) => req.method == 'GET' ? http.Response('[]', 200) : http.Response('{}', 200);
      await store.openSession('v', session);
      await pumpEventQueue();
      expect(sent.where((r) => r.url.path.endsWith('/permission-mode')).map((r) => r.body), ['{"mode":"auto"}']);
      expect(sent.any((r) => r.method == 'GET' && r.url.path.endsWith('/messages')), isTrue, reason: 'opening a chat always asks the hub for what is new');
      sent.clear();
      await store.sendMessage('v', 's', const UserInput(text: 'hi'));
      // One request: the mode, model and effort go with the message, so a chat the machine resumes for it keeps them.
      expect(sent.map((r) => r.url.path.split('/').last), ['messages']);
      expect(jsonDecode(sent.single.body), {'text': 'hi', 'permissionMode': 'auto', 'model': '', 'effort': null});
      store.logout();
    });

    test('a chat opened for the first time on this phone is not switched to the defaults behind its back', () async {
      final store = make();
      answer = (req) => req.method == 'GET' ? http.Response('[]', 200) : http.Response('{}', 200);
      await store.openSession('v', session);
      await pumpEventQueue();
      expect(sent.where((r) => r.method == 'POST'), isEmpty, reason: 'nothing chosen here yet: nothing to send until a message goes out');
      expect(store.savedChoices('v', 's'), isNotNull);
      store.logout();
    });

    test('a chat started here and named while the phone was away keeps what was chosen for it', () async {
      final store = make();
      answer = (req) => req.url.path.endsWith('/sessions') && req.method == 'POST'
          ? http.Response(jsonEncode({'tempId': 't1'}), 202)
          : (req.method == 'GET' ? http.Response('[]', 200) : http.Response('{}', 200));
      await store.startNewChat('v', const NewSessionInput(text: 'hi'), choices: const ChatChoices(mode: 'auto', model: 'claude-opus-4-8', effort: 'high'));
      expect(jsonDecode(sent.first.body), {'text': 'hi', 'permissionMode': 'auto', 'model': 'claude-opus-4-8', 'effort': 'high'});
      // The session_created event never arrived; the hub's list says which chat t1 became.
      const named = SessionDto(id: 's9', tempId: 't1', vmId: 'v', cwd: '/w', title: 'hi', createdAt: '2026-10-10T10:00:00.000Z', lastMessageAt: '2026-10-10T10:00:00.000Z', status: 'active', accountId: 'a');
      store.dispatch(const SetSessions('v', [named]));
      expect(store.state.selectedSessionId, 's9');
      expect(store.savedChoices('v', 's9')!.mode, 'auto');
      expect(store.isTemporary('t1'), isFalse);
      store.logout();
    });

    test('even after the app was closed, the temporary id links a chat to what was chosen for it', () async {
      final store = make();
      answer = (req) => req.method == 'POST' && req.url.path.endsWith('/sessions')
          ? http.Response(jsonEncode({'tempId': 't1'}), 202)
          : (req.method == 'GET' ? http.Response('[]', 200) : http.Response('{}', 200));
      await store.startNewChat('v', const NewSessionInput(text: 'hi'), choices: const ChatChoices(mode: 'acceptEdits'));
      store.logout(); // forgets everything in memory... and signing out clears the phone's choices too, so put one back
      final again = make();
      const ChatChoicesProbe().keep('v', 't1', 'plan');
      const named = SessionDto(id: 's9', tempId: 't1', vmId: 'v', cwd: '/w', title: 'hi', createdAt: '2026-10-10T10:00:00.000Z', lastMessageAt: '2026-10-10T10:00:00.000Z', status: 'idle', accountId: 'a');
      await again.openSession('v', named);
      expect(again.savedChoices('v', 's9')!.mode, 'plan');
      again.logout();
    });

    test('a long chat comes a page at a time; then only what is new; earlier pages on request', () async {
      final store = make();
      final page = [for (var i = 701; i <= 1000; i++) {'id': i, 'sessionId': 's', 'vmId': 'v', 'createdAt': 'now', 'message': {'type': 'assistant', 'n': i}}];
      answer = (req) {
        final q = req.url.queryParameters;
        if (q['after'] == '1000') return http.Response(jsonEncode([{'id': 1001, 'sessionId': 's', 'vmId': 'v', 'createdAt': 'now', 'message': {'type': 'assistant', 'n': 1001}}]), 200);
        if (q['before'] == '701') return http.Response(jsonEncode([for (var i = 690; i <= 700; i++) {'id': i, 'sessionId': 's', 'vmId': 'v', 'createdAt': 'now', 'message': {'type': 'assistant'}}]), 200);
        return http.Response(jsonEncode(page), 200);
      };
      await store.refreshSession('v', 's');
      expect(sent.single.url.queryParameters, {'limit': '${HubStore.pageSize}'});
      expect(store.state.messagesBySession['s']!.length, 300);
      expect(store.hasEarlier('s'), isTrue);
      sent.clear();
      await store.refreshSession('v', 's');
      expect(sent.single.url.queryParameters, {'after': '1000'});
      expect(store.state.messagesBySession['s']!.last.id, 1001);
      expect(store.state.messagesBySession['s']!.length, 301);
      await store.loadEarlier('v', 's');
      expect(store.state.messagesBySession['s']!.first.id, 690);
      expect(store.hasEarlier('s'), isFalse, reason: 'fewer than a page came back: that was the start');
      sent.clear();
      await store.refreshSession('v', 's', full: true);
      expect(sent.single.url.queryParameters, {'limit': '${HubStore.pageSize}'});
      store.logout();
    });

    test('showing earlier messages is not a turn that just ended (an autonomous chat does not go round again)', () async {
      final store = make();
      await store.setPermissionMode('v', 's', 'auto');
      Map<String, Object?> r(int id, Object? m) => {'id': id, 'sessionId': 's', 'vmId': 'v', 'createdAt': 'now', 'message': m};
      final result = {'type': 'result', 'subtype': 'success', 'result': 'finished for now'};
      final page = [for (var i = 0; i < HubStore.pageSize; i++) r(1000 + i, i == HubStore.pageSize - 1 ? result : {'type': 'assistant', 'message': {'content': []}})];
      answer = (req) {
        final q = req.url.queryParameters;
        if (q.containsKey('before')) return http.Response(jsonEncode([r(10, prompt('old work')), r(11, {'type': 'assistant', 'message': {'content': [{'type': 'tool_use', 'id': 'x', 'name': 'Bash', 'input': {}}]}}), r(12, {'type': 'result', 'subtype': 'success', 'result': 'stopped'})]), 200);
        if (q.containsKey('after')) return http.Response('[]', 200);
        return http.Response(jsonEncode(page), 200);
      };
      await store.refreshSession('v', 's');
      await store.loadEarlier('v', 's');
      sent.clear();
      await store.refreshSession('v', 's');
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(sent.where((q) => q.method == 'POST'), isEmpty, reason: 'no nudge was sent');
      store.logout();
    });

    test('a hub from before paging (whole chat every time) still works', () async {
      final store = make();
      final all = [for (var i = 1; i <= 5; i++) {'id': i, 'sessionId': 's', 'vmId': 'v', 'createdAt': 'now', 'message': {'type': 'assistant', 'n': i}}];
      answer = (_) => http.Response(jsonEncode(all), 200);
      await store.refreshSession('v', 's');
      expect(store.hasEarlier('s'), isFalse);
      all.add({'id': 6, 'sessionId': 's', 'vmId': 'v', 'createdAt': 'now', 'message': {'type': 'assistant', 'n': 6}});
      await store.refreshSession('v', 's');
      expect(store.state.messagesBySession['s']!.map((r) => r.id), [1, 2, 3, 4, 5, 6]);
      store.logout();
    });

    test('rows for a chat nobody has open are not kept (they are fetched when it is opened)', () async {
      final store = make();
      sockets.single.open();
      sockets.single.message(jsonEncode({'type': 'sdk_message', 'vmId': 'v', 'sessionId': 'elsewhere', 'message': {'type': 'assistant'}, 'createdAt': 'now'}));
      await pumpEventQueue();
      expect(store.state.messagesBySession.containsKey('elsewhere'), isFalse);
      sockets.single.message(jsonEncode({'type': 'permission_request', 'vmId': 'v', 'sessionId': 'asks', 'requestId': 'r1', 'toolName': 'Bash', 'input': {'command': 'ls'}}));
      await pumpEventQueue();
      expect(store.state.messagesBySession['asks']!.length, 1, reason: 'a prompt waiting for the person is kept wherever it is');
      store.dispatch(const Select(vmId: 'v', sessionId: 'open'));
      sockets.single.message(jsonEncode({'type': 'sdk_message', 'vmId': 'v', 'sessionId': 'open', 'message': {'type': 'assistant'}, 'createdAt': 'now'}));
      await pumpEventQueue();
      expect(store.state.messagesBySession['open']!.length, 1);
      store.logout();
    });

    test('a sent message is shown at once and taken back if it did not reach the hub', () async {
      final store = make();
      answer = (_) => http.Response('{"error":"nope"}', 500);
      await expectLater(store.sendMessage('v', 's', const UserInput(text: 'hi')), throwsA(isA<HubError>()));
      expect(store.state.messagesBySession['s'], isEmpty);
      store.logout();
    });

    test('stop ends the spinner at once, even before the hub answers', () async {
      final store = make();
      store.dispatch(SetMessages('s', [row(1, prompt('work'))]));
      expect(busySince(store.state.messagesBySession['s']!), isNotNull);
      final gate = Completer<http.Response>();
      final api = HubApi(credentials: creds, client: MockClient((req) => gate.future));
      final slow = HubStore(api: api, socket: HubSocket(connector: (u, p) => (sockets..add(FakeSocket(u, p))).last, token: () => creds.token, hubUrl: () => creds.hubUrl), credentials: creds);
      slow.dispatch(SetMessages('s', [row(1, prompt('work'))]));
      final stopping = slow.interrupt('v', 's');
      expect(busySince(slow.state.messagesBySession['s']!), isNull);
      gate.complete(http.Response('{}', 200));
      await stopping;
      store.logout();
      slow.logout();
    });

    test('an answer to a prompt that is already gone counts as delivered', () async {
      final store = make();
      answer = (_) => http.Response('{"error":"unknown request"}', 404);
      await store.resolvePermission('v', 's', 'r1', 'allow');
      expect(store.state.resolvedPermissionIds, contains('r1'));
      store.logout();
    });

    test('a control request that never gets an answer is tried again', () async {
      var calls = 0;
      final api = HubApi(credentials: creds, client: MockClient((req) async {
        calls++;
        if (calls < 3) throw TimeoutException('stuck');
        return http.Response('{}', 200);
      }));
      await api.resolvePermission('v', 's', 'r1', 'allow');
      expect(calls, 3);
    });

    test('rename and delete fall back to this phone when the hub cannot', () async {
      final store = make();
      store.dispatch(SetSessions('v', [session]));
      store.dispatch(const SetVms([VmDto(id: 'v', name: 'box', connected: true)]));
      answer = (_) => http.Response('{"error":"not found"}', 404);
      expect(await store.renameSession('v', session, 'Mine'), isFalse);
      expect(store.titleOf(session), 'Mine');
      expect(await store.renameVm(store.state.vms.single, 'My box'), isFalse);
      expect(store.nameOf(store.state.vms.single), 'My box');
      expect(await store.deleteSession('v', session), isFalse);
      expect(store.isSessionHidden('v', 's'), isTrue);
      store.showHiddenSessions('v');
      expect(store.isSessionHidden('v', 's'), isFalse);
      expect(await store.deleteVm(store.state.vms.single), isFalse);
      expect(store.isVmHidden('v'), isTrue);
      answer = (_) => http.Response('', 204);
      expect(await store.renameSession('v', store.state.sessionsByVm['v']!.single, 'Hub name'), isTrue);
      expect(store.state.sessionsByVm['v']!.single.title, 'Hub name');
      expect(store.titleOf(store.state.sessionsByVm['v']!.single), 'Hub name');
      store.logout();
    });
  });

  test('a connection that has gone silent is replaced', () {
    fakeAsync((async) {
      final sockets = <FakeSocket>[];
      final s = HubSocket(
        connector: (uri, p) => (sockets..add(FakeSocket(uri, p))).last,
        token: () => 'tok',
        hubUrl: () => 'https://hub.example.test',
      )..clock = () => async.getClock(DateTime(2026)).now();
      s.connect();
      sockets[0].open();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 20));
      sockets[0].message('pong');
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 40)); // pings go out, nothing comes back
      expect(sockets.length, 1);
      async.elapse(const Duration(seconds: 25));
      expect(sockets.length, 2, reason: 'no word for over 50s: the connection is dead and a new one is opened');
      expect(sockets[0].closed, isTrue);
      s.stop();
    });
  });
}

/// Puts a choice on the phone as an earlier run of the app would have left it.
class ChatChoicesProbe {
  const ChatChoicesProbe();
  void keep(String vmId, String sessionId, String mode) => const ChatChoicesStore().write(vmId, sessionId, SavedChoices(mode: mode));
}
