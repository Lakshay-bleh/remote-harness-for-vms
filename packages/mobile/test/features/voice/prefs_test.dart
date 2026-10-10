import 'package:escanor/core/storage.dart';
import 'package:escanor/features/voice/actions.dart';
import 'package:escanor/features/voice/control_consent.dart';
import 'package:escanor/features/voice/orb_position.dart';
import 'package:escanor/features/voice/phone_control.dart';
import 'package:escanor/features/voice/voice_prefs.dart';
import 'package:escanor/features/voice/wake_status.dart';
import 'package:flutter_test/flutter_test.dart';

const view = OrbView(width: 400, height: 800, insetTop: 40, insetBottom: 20);

WakeStatus s({bool running = false, bool modelReady = true, bool micAllowed = true, bool? opensDirectly, bool? fullScreenDeclared, bool? fullScreenAllowed}) =>
    WakeStatus(
      running: running,
      modelReady: modelReady,
      downloading: false,
      micAllowed: micAllowed,
      opensDirectly: opensDirectly,
      fullScreenDeclared: fullScreenDeclared,
      fullScreenAllowed: fullScreenAllowed,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseVoicePrefs', () {
    test('starts with calling directly on, the wake word off and no consent to phone control', () {
      expect(parseVoicePrefs(null), defaultVoicePrefs);
      expect(defaultVoicePrefs, const VoicePrefs(directCalls: true, wakeWord: false, controlConsent: false));
    });
    test('reads what was saved, field by field, and ignores damage', () {
      expect(parseVoicePrefs('{"directCalls":false,"wakeWord":true,"controlConsent":true}'), const VoicePrefs(directCalls: false, wakeWord: true, controlConsent: true));
      expect(parseVoicePrefs('{"directCalls":"no","wakeWord":1}'), defaultVoicePrefs);
      expect(parseVoicePrefs('not json'), defaultVoicePrefs);
      expect(parseVoicePrefs('[1]'), defaultVoicePrefs);
    });
  });

  group('phone-control consent', () {
    setUp(() async {
      await Storage.initForTest();
      reloadVoicePrefs();
    });

    test('is kept on the phone and sent to the ledger', () async {
      final sent = <bool>[];
      await setControlConsent(true, (g) async => sent.add(g));
      expect(getVoicePrefs().controlConsent, true);
      expect(sent, [true]);
      expect(controlConsentPending(), false);
    });

    test('waits when it cannot be sent, then sends the latest choice once', () async {
      await setControlConsent(true, (_) async => throw Exception('offline'));
      await setControlConsent(false, (_) async => throw Exception('offline'));
      expect(getVoicePrefs().controlConsent, false);
      final sent = <bool>[];
      await flushControlConsent((g) async => sent.add(g));
      await flushControlConsent((g) async => sent.add(g));
      expect(sent, [false]);
    });

    test('voice prefs survive a restart', () async {
      setVoicePrefs((p) => p.copyWith(directCalls: false));
      reloadVoicePrefs();
      expect(getVoicePrefs().directCalls, false);
    });
  });

  group('the voice button position', () {
    test('turns a point on the screen into a fraction of the free space', () {
      expect(posFromPoint(orbSize / 2 + orbMargin, view.insetTop + orbSize / 2 + orbMargin, view), const OrbPos(0, 0));
      expect(posFromPoint(view.width - orbSize / 2 - orbMargin, view.height - view.insetBottom - orbSize / 2 - orbMargin, view), const OrbPos(1, 1));
      final mid = posFromPoint(view.width / 2, (view.height + view.insetTop - view.insetBottom) / 2, view);
      expect((mid.x - 0.5).abs() < 0.01 && (mid.y - 0.5).abs() < 0.01, true);
    });

    test('never lets the button leave the screen, wherever it is dragged', () {
      for (final (x, y) in [(-500.0, -500.0), (9999.0, 9999.0), (-1.0, 9999.0), (9999.0, -1.0)]) {
        final p = posFromPoint(x, y, view);
        expect(p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1, true, reason: '$x,$y -> $p');
      }
    });

    test('places the button inside the screen and clear of the status bar, whatever the position', () {
      final topLeft = orbOffset(const OrbPos(0, 0), view);
      expect(topLeft, (left: orbMargin, top: view.insetTop + orbMargin));
      final bottomRight = orbOffset(const OrbPos(1, 1), view);
      expect(bottomRight.left + orbSize + orbMargin, view.width);
      expect(bottomRight.top + orbSize + orbMargin, view.height - view.insetBottom);
      expect(orbOffset(const OrbPos(5, -3), view), orbOffset(const OrbPos(1, 0), view), reason: 'out-of-range values are clamped');
    });

    test('a drag and a placement agree', () {
      const p = OrbPos(0.3, 0.7);
      final at = orbOffset(p, view);
      final back = posFromPoint(at.left + orbSize / 2, at.top + orbSize / 2, view);
      expect((back.x - p.x).abs() < 1e-9 && (back.y - p.y).abs() < 1e-9, true);
    });

    test('reads a saved position back, and ignores anything else', () {
      expect(parseOrb('{"x":0.25,"y":0.75}'), const OrbPos(0.25, 0.75));
      expect(parseOrb('{"x":9,"y":-2}'), const OrbPos(1, 0));
      for (final bad in [null, '', 'x', '{}', '{"x":"a","y":1}', '{"x":null,"y":1}', '[1,2]']) {
        expect(parseOrb(bad), isNull, reason: '$bad');
      }
    });

    test('starts at the right edge, clear of the send button at the bottom', () {
      expect(defaultOrb.x, 1);
      expect(defaultOrb.y, lessThan(0.6));
    });

    test('tells a tap from a drag', () {
      expect(movedFar(3, 3), false);
      expect(movedFar(10, 0), true);
      expect(movedFar(6, 6), true);
    });
  });

  group('controlStep', () {
    test('waits for the phone to answer', () => expect(controlStep(null, true), ControlStep.checking));
    test('is done once the person switched it on', () {
      expect(controlStep(const ControlStatus(enabled: true, available: true, restricted: true), false), ControlStep.on);
    });
    test('says when this download has no phone control', () {
      expect(controlStep(const ControlStatus(enabled: false, available: false), true), ControlStep.notInBuild);
    });
    test('asks for agreement before anything else', () {
      expect(controlStep(const ControlStatus(enabled: false, available: true, restricted: true), false), ControlStep.disclosure);
      expect(controlStep(const ControlStatus(enabled: false, available: true, restricted: false), false), ControlStep.disclosure);
    });
    test('unlocks the restricted setting before sending them to Accessibility', () {
      expect(controlStep(const ControlStatus(enabled: false, available: true, restricted: true), true), ControlStep.restricted);
    });
    test('goes to Accessibility when nothing is restricted, or Android does not say', () {
      expect(controlStep(const ControlStatus(enabled: false, available: true, restricted: false), true), ControlStep.turnOn);
      expect(controlStep(const ControlStatus(enabled: false, available: true), true), ControlStep.turnOn);
      expect(controlStep(const ControlStatus(enabled: false), true), ControlStep.turnOn);
    });
    test('reads the native answer, null "restricted" included', () {
      final st = ControlStatus.fromJson({'enabled': false, 'available': true, 'restricted': null});
      expect(st.restricted, isNull);
      expect(controlStep(st, true), ControlStep.turnOn);
    });
  });

  group('wakeStep', () {
    test('says "Hey Escanor" is for the Android app only, outside it', () {
      expect(wakeStep(s(), native: false), WakeStep.unsupported);
      expect(wakeStep(null, native: true), WakeStep.unsupported);
    });
    test('walks through what is in the way, in order: model, then microphone, then ready', () {
      expect(wakeStep(s(modelReady: false, micAllowed: false), native: true), WakeStep.download);
      expect(wakeStep(s(micAllowed: false), native: true), WakeStep.microphone);
      expect(wakeStep(s(), native: true), WakeStep.ready);
    });
    test('is listening once it is running', () => expect(wakeStep(s(running: true), native: true), WakeStep.listening));
  });

  group('outsideApp', () {
    test('opens straight away while phone control is on', () {
      final o = outsideApp(s(opensDirectly: true, fullScreenDeclared: true, fullScreenAllowed: false));
      expect(o.best, true);
      expect(o.canAllowFullScreen, false);
    });
    test('falls back to a notification, and offers full-screen notifications where the build has them', () {
      final o = outsideApp(s(opensDirectly: false, fullScreenDeclared: true, fullScreenAllowed: false));
      expect(o.best, false);
      expect(o.canAllowFullScreen, true);
      expect(o.line, contains('Full-screen notifications'));
    });
    test('never offers what the normal download does not have, and never asks to draw over other apps', () {
      final o = outsideApp(s(opensDirectly: false, fullScreenDeclared: false, fullScreenAllowed: false));
      expect(o.canAllowFullScreen, false);
      expect(o.line, isNot(matches(RegExp('over other apps|Full-screen'))));
      expect(o.line, contains('phone control'));
    });
    test('treats an older app that does not report these as a plain notification, not as broken', () {
      final o = outsideApp(s());
      expect(o.best, false);
      expect(o.canAllowFullScreen, false);
    });
    test('reads what the phone reports', () {
      final w = WakeStatus.fromJson({'running': true, 'modelReady': true, 'micAllowed': true, 'opensDirectly': true, 'fullScreenDeclared': false, 'fullScreenAllowed': false});
      expect([w.opensDirectly, w.fullScreenDeclared, w.fullScreenAllowed], [true, false, false]);
      expect(WakeStatus.fromJson({'overlayAllowed': true}).opensDirectly, null, reason: 'the old overlay switch means nothing now');
    });
  });
}
