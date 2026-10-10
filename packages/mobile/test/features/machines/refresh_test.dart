import 'dart:async';

import 'package:escanor/core/storage.dart';
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
      expect(sent.map((r) => r.url.path.split('/').last), ['permission-mode', 'messages']);
      store.logout();
    });

    test('a mode picked in a chat is where new chats on that machine start, so it is not picked again every time', () async {
      final store = make();
      expect(store.defaultChoicesFor('v9').mode, 'auto', reason: 'the app default');
      await store.setPermissionMode('v9', 's', 'acceptEdits');
      expect(store.defaultChoicesFor('v9').mode, 'acceptEdits');
      expect(store.defaultChoicesFor('other').mode, 'auto', reason: 'only that machine');
      store.logout();
    });

    test('a new chat in a chosen mode is switched under its temporary id at once, before the machine names it', () async {
      final store = make();
      answer = (req) => req.url.path.endsWith('/sessions') && req.method == 'POST' ? http.Response('{"tempId":"tmp-1"}', 202) : http.Response('{}', 200);
      await store.startNewChat('v', const NewSessionInput(text: 'hi'), choices: const ChatChoices(mode: 'auto'));
      await pumpEventQueue();
      expect(sent.where((r) => r.url.path.endsWith('/permission-mode')).map((r) => r.url.path), ['/api/vms/v/sessions/tmp-1/permission-mode']);
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
