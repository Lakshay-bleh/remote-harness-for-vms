import 'package:escanor/core/busy.dart';
import 'package:escanor/features/companion/busy_scene.dart';
import 'package:escanor/features/companion/sprites.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the shared busy count', () {
    test('goes up while work is running and back down when it ends, even if it fails', () async {
      expect(busyCount.value, 0);
      final end = beginBusy();
      expect(busyCount.value, 1);
      end();
      end(); // ending twice must not count twice
      expect(busyCount.value, 0);
      await expectLater(trackBusy(Future<void>.error(StateError('nope'))), throwsA(isA<StateError>()));
      expect(busyCount.value, 0);
      final p = trackBusy(Future.delayed(const Duration(milliseconds: 5), () => 1));
      expect(busyCount.value, 1);
      expect(await p, 1);
      expect(busyCount.value, 0);
    });
  });

  group('which scene the companion plays', () {
    test('works while anything loads, sleeps when nobody is there, otherwise sits and sniffs', () {
      expect(buddyScene(busy: true, asleep: true, sniffing: true), Scene.run);
      expect(buddyScene(busy: false, asleep: true, sniffing: true), Scene.sleep);
      expect(buddyScene(busy: false, asleep: false, sniffing: true), Scene.sniff);
      expect(buddyScene(busy: false, asleep: false, sniffing: false), Scene.sit);
    });
  });
}
