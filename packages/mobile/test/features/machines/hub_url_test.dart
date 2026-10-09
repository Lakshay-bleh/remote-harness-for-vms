import 'package:escanor/features/machines/hub_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hubUrlProblem', () {
    test('requires https, because plain http is allowed in the app only for a computer on the local network', () {
      expect(hubUrlProblem('https://hub.example.com'), isNull);
      for (final bad in ['http://hub.example.com', 'http://192.168.1.5:8787', 'hub.example.com', 'ftp://x', 'ws://hub.example.com']) {
        expect(hubUrlProblem(bad), isNotNull, reason: bad);
      }
    });
    test('asks nothing of an empty address', () {
      expect(hubUrlProblem(''), isNull);
      expect(hubUrlProblem('   '), isNull);
    });
  });

  test('the address is stored without spaces or trailing slashes', () {
    expect(cleanHubUrl('  https://hub.example.com///  '), 'https://hub.example.com');
  });

  group('the push channel', () {
    test('is the same host over wss, at /ws', () {
      expect(socketUrl('https://hub.example.test').toString(), 'wss://hub.example.test/ws');
      expect(socketUrl('https://hub.example.test/base/').toString(), 'wss://hub.example.test/base/ws');
    });
    test('is never built from anything but https', () {
      expect(() => socketUrl('http://hub.example.test'), throwsArgumentError);
      expect(() => socketUrl(''), throwsArgumentError);
    });
    test('carries the credential as a subprotocol, not in the URL', () {
      expect(socketProtocols('tok'), ['escanor.hub.v1', 'escanor.auth.tok']);
    });
  });

  test('addresses that only work on a private network are spotted', () {
    for (final u in ['https://localhost:8787', 'https://box.local', 'https://127.0.0.1', 'https://10.0.0.2', 'https://192.168.1.4', 'https://172.20.1.1', 'https://100.64.0.1', 'https://[::1]']) {
      expect(isPrivateAddress(u), isTrue, reason: u);
    }
    for (final u in ['https://hub.example.com', 'https://172.32.0.1', 'https://100.128.0.1', 'not a url']) {
      expect(isPrivateAddress(u), isFalse, reason: u);
    }
  });

  test('reconnecting waits longer each time, up to 30 seconds', () {
    expect([for (var i = 0; i < 7; i++) reconnectDelay(i).inSeconds], [2, 4, 8, 16, 30, 30, 30]);
  });
}
