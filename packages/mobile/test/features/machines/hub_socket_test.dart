import 'package:escanor/features/machines/hub_socket.dart';
import 'package:escanor/features/machines/protocol.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  test('reconnects with a growing delay, catches up after, and pings while open', () {
    fakeAsync((async) {
      final sockets = <FakeSocket>[];
      var caughtUp = 0;
      final s = HubSocket(
        connector: (uri, p) => (sockets..add(FakeSocket(uri, p))).last,
        token: () => 'tok',
        hubUrl: () => 'https://hub.example.test',
      )..onReconnected = () => caughtUp++;
      final got = <HubEvent>[];
      s.subscribe(got.add);
      s.connect();
      sockets[0].open();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 25));
      expect(sockets[0].sent, ['ping']);
      sockets[0].message('pong'); // the hub's answer is not an event
      async.flushMicrotasks();
      expect(got, isEmpty);

      sockets[0].drop();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 1999));
      expect(sockets.length, 1);
      async.elapse(const Duration(milliseconds: 1));
      expect(sockets.length, 2);
      sockets[1].drop(); // fails again: waits longer
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      expect(sockets.length, 2);
      async.elapse(const Duration(seconds: 1));
      expect(sockets.length, 3);
      sockets[2].open();
      async.flushMicrotasks();
      expect(caughtUp, 1);
      sockets[2].message('{"type":"session_ended","vmId":"v","sessionId":"s"}');
      async.flushMicrotasks();
      expect(got.single, isA<SessionEndedEvent>());
      s.stop();
      async.elapse(const Duration(minutes: 5));
      expect(sockets.length, 3);
    });
  });

  test('nothing connects without a token or an https hub', () {
    var made = 0;
    HubSocket(connector: (u, p) => (made++, FakeSocket(u, p)).$2, token: () => null, hubUrl: () => 'https://h.test').connect();
    HubSocket(connector: (u, p) => (made++, FakeSocket(u, p)).$2, token: () => 't', hubUrl: () => '').connect();
    HubSocket(connector: (u, p) => (made++, FakeSocket(u, p)).$2, token: () => 't', hubUrl: () => 'http://h.test').connect();
    expect(made, 0);
  });
}
