import 'package:escanor/core/storage.dart';
import 'package:escanor/features/machines/hub_api.dart';
import 'package:escanor/features/machines/hub_socket.dart';
import 'package:escanor/features/machines/hub_store.dart';
import 'package:escanor/features/machines/machines_start.dart';
import 'package:escanor/features/machines/managed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const creds = HubCredentials();
  const hub = ManagedHub(available: true, hubUrl: 'https://hub.escanor.in', appToken: 'app-1');

  setUp(() => Storage.initForTest());

  test('the hosted hub’s answer is read defensively', () {
    final h = ManagedHub.fromJson({'available': true, 'hub_url': 'https://h', 'agent_url': 'wss://h/agent', 'agent_token': 's', 'app_token': 'a', 'install_command': 'curl', 'guide_url': ''});
    expect((h.available, h.hubUrl, h.agentUrl, h.agentToken, h.appToken, h.installCommand, h.guideUrl), (true, 'https://h', 'wss://h/agent', 's', 'a', 'curl', null));
    expect(ManagedHub.fromJson(null).available, isFalse);
  });

  test('applying the hosted hub, then a rotated token', () {
    expect(applyManaged(hub), isFalse);
    expect((creds.hubUrl, creds.token, creds.managed, isManaged()), ('https://hub.escanor.in', 'app-1', true, true));
    expect(applyManaged(hub), isFalse);
    expect(applyManaged(const ManagedHub(available: true, hubUrl: 'https://hub.escanor.in', appToken: 'app-2')), isTrue);
  });

  test('a hosted hub that is not https is refused', () {
    expect(() => applyManaged(const ManagedHub(available: true, hubUrl: 'http://hub', appToken: 'x')), throwsStateError);
    expect(creds.managed, isFalse);
  });

  test('forgetting the hosted hub only touches its own credentials', () {
    creds.hubUrl = 'https://mine.example';
    creds.token = 'mine';
    expect(clearManaged(), isFalse);
    expect(creds.token, 'mine');
    applyManaged(hub);
    expect(clearManaged(), isTrue);
    expect((creds.token, creds.hubUrl, creds.managed), (null, '', false));
  });

  test('signing out of Escanor drops the hosted hub and its chats', () {
    applyManaged(hub);
    final sockets = <FakeSocket>[];
    final store = HubStore(
      api: HubApi(credentials: creds),
      socket: HubSocket(connector: (u, p) => (sockets..add(FakeSocket(u, p))).last, token: () => creds.token, hubUrl: () => creds.hubUrl),
    );
    HubStore.instance = store;
    expect(store.state.authed, isTrue);
    machinesSignedOut();
    expect(store.state.authed, isFalse);
    expect(creds.token, isNull);
    expect(sockets.single.closed, isTrue);
  });

  group('the phone opens on its own hub', () {
    test('when it has only ever used its own hub', () {
      creds.hubUrl = 'https://mine.example';
      creds.token = 'mine';
      expect(ownHubStartsHere(), isTrue);
    });
    test('not when signed in to Escanor', () async {
      await Storage.initForTest(secrets: {'escanor_refresh': 'r'});
      creds.hubUrl = 'https://mine.example';
      creds.token = 'mine';
      expect(ownHubStartsHere(), isFalse);
    });
    test('never for the hosted hub, whose credentials are dropped without an Escanor sign-in', () {
      applyManaged(hub);
      expect(ownHubStartsHere(), isFalse);
      expect(creds.token, isNull);
    });
    test('not without a hub login', () => expect(ownHubStartsHere(), isFalse));
  });
}
