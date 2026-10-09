import 'package:escanor/core/storage.dart';
import 'package:escanor/features/voice/device.dart';
import 'package:escanor/features/voice/phone_control_setup.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../assistant/harness.dart';
import 'fake_phone.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async => Storage.initForTest());

  group('the device channel', () {
    final asked = <MethodCall>[];
    Object? callStatus;
    setUp(() {
      asked.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(deviceChannel, (call) async {
        asked.add(call);
        if (call.method == 'callStatus') return callStatus;
        if (call.method == 'controlTurnOff') return {'ok': true};
        return null;
      });
    });
    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(deviceChannel, null));

    test('the normal download says calls always open the dialer', () async {
      callStatus = {'granted': false, 'available': false};
      expect(await ChannelDevice.instance.callStatus(), (granted: false, available: false));
      callStatus = {'granted': true, 'available': true};
      expect(await ChannelDevice.instance.callStatus(), (granted: true, available: true));
      callStatus = {'granted': true}; // an older build does not say
      expect(await ChannelDevice.instance.callStatus(), (granted: true, available: null));
    });

    test('phone control can be switched off from the app', () async {
      expect((await ChannelDevice.instance.controlTurnOff()).ok, true);
      expect(asked.single.method, 'controlTurnOff');
    });
  });

  testWidgets('with phone control on, it says payment apps switch it off, and it can be switched off here', (tester) async {
    final phone = FakePhone();
    await tester.pumpWidget(themed(PhoneControlSetup(dev: phone)));
    await tester.pump();
    expect(find.textContaining('Payment and banking apps do not run while it is'), findsOneWidget);
    await tester.tap(find.text('Switch phone control off'));
    await tester.pump();
    expect(phone.calls.map((c) => c.$1), contains('controlTurnOff'));
  });
}
