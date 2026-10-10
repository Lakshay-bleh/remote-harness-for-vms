import 'dart:convert';

import 'package:escanor/core/storage.dart';
import 'package:escanor/features/machines/hub_api.dart';
import 'package:escanor/features/machines/hub_socket.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fakes.dart';

/// web/test/privacy.test.ts: nothing from one hub login may reach the next.
void main() {
  const creds = HubCredentials();

  setUp(() async {
    await Storage.initForTest();
    creds.hubUrl = 'https://hub.example.test';
  });

  test('a previous session response cannot populate the next session', () async {
    creds.token = 'old-session';
    final api = HubApi(credentials: creds, client: MockClient((req) async {
      creds.token = 'new-session';
      return http.Response(jsonEncode([{'id': 'private-old-vm', 'name': 'x', 'connected': true, 'accounts': []}]), 200);
    }));
    await expectLater(api.listVms(), throwsA(isA<HubError>().having((e) => e.message, 'message', contains('Session changed'))));
    expect(creds.token, 'new-session');
  });

  test('a late 401 cannot log out a new session', () async {
    creds.token = 'old-session';
    var signedOut = 0;
    final api = HubApi(credentials: creds, client: MockClient((req) async {
      creds.token = 'new-session';
      return http.Response('', 401);
    }))
      ..onSignedOut = () => signedOut++;
    await expectLater(api.listVms(), throwsA(isA<HubError>().having((e) => e.message, 'message', contains('Session changed'))));
    expect(creds.token, 'new-session');
    expect(signedOut, 0);
  });

  test('requests carry the token, and a refused token on a self-hosted hub signs the phone out of it', () async {
    creds.token = 'tok';
    String? auth;
    var signedOut = 0;
    final api = HubApi(credentials: creds, client: MockClient((req) async {
      auth = req.headers['authorization'];
      return http.Response('', 401);
    }))
      ..onSignedOut = () => signedOut++;
    await expectLater(api.listVms(), throwsA(isA<HubError>()));
    expect(auth, 'Bearer tok');
    expect(creds.token, isNull);
    expect(signedOut, 1);
  });

  test('on the hosted hub a refused token asks Escanor for the current one instead', () async {
    creds.token = 'tok';
    creds.managed = true;
    var asked = 0;
    final api = HubApi(credentials: creds, client: MockClient((req) async => http.Response('', 401)))..onManagedUnauthorized = () => asked++;
    await expectLater(api.listVms(), throwsA(isA<HubError>().having((e) => e.message, 'message', 'Reconnecting to your hub…')));
    expect(asked, 1);
    expect(creds.token, 'tok');
  });

  test('the hub’s own error words are shown', () async {
    creds.token = 'tok';
    final api = HubApi(credentials: creds, client: MockClient((req) async => http.Response(jsonEncode({'error': 'VM not connected'}), 503)));
    await expectLater(api.interrupt('v', 's'), throwsA(isA<HubError>().having((e) => e.message, 'message', 'VM not connected')));
  });

  test('a plain-http address is never used', () async {
    await Storage.instance.setString(HubCredentials.hubUrlKey, 'http://hub.example.test');
    expect(creds.hubUrl, '');
    expect(() => creds.hubUrl = 'http://hub.example.test', throwsStateError);
    creds.token = 'tok';
    final api = HubApi(credentials: creds, client: MockClient((req) async => fail('nothing may be sent')));
    await expectLater(api.listVms(), throwsA(isA<HubError>()));
  });

  test('stopped sockets cannot deliver private events after a new connection starts', () async {
    final sockets = <FakeSocket>[];
    creds.token = 'first-session';
    final client = HubSocket(
      connector: (uri, protocols) {
        final s = FakeSocket(uri, protocols);
        sockets.add(s);
        return s;
      },
      token: () => creds.token,
      hubUrl: () => creds.hubUrl,
    );
    var delivered = 0;
    final unsubscribe = client.subscribe((_) => delivered++);
    const frame = '{"type":"vm_status","vmId":"v","name":"box","connected":true,"accounts":[]}';
    try {
      client.connect();
      final first = sockets[0];
      expect(first.url.toString(), 'wss://hub.example.test/ws');
      expect(first.protocols, ['escanor.hub.v1', 'escanor.auth.first-session']);
      client.stop();
      expect(first.closed, isTrue);
      creds.token = 'second-session';
      client.connect();
      expect(sockets.length, 2);
      first.message(frame);
      first.drop();
      await pumpEventQueue();
      expect(delivered, 0);
      sockets[1].message(frame);
      await pumpEventQueue();
      expect(delivered, 1);
      expect(sockets.length, 2, reason: 'the old socket closing must not start another connection');
    } finally {
      unsubscribe();
      client.stop();
    }
  });
}
