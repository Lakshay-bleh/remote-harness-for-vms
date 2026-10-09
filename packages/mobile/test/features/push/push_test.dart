import 'package:escanor/core/nav.dart';
import 'package:escanor/features/push/push_host.dart';
import 'package:escanor/features/push/push_logic.dart';
import 'package:flutter_test/flutter_test.dart';

// Port of packages/web/src/escanor/push.test.ts.
void main() {
  group('routeFor (where tapping a notification goes)', () {
    test('sends each kind to the place that deals with it', () {
      expect(routeFor({'kind': 'deployment_approvals'}), PushDest.assistant);
      expect(routeFor({'kind': 'emergency_alerts'}), PushDest.assistant);
      expect(routeFor({'kind': 'team_pings'}), PushDest.assistant);
      expect(routeFor({'kind': 'server_down'}), PushDest.machines);
    });

    test('falls back to the main screen for anything it does not know, however odd', () {
      for (final odd in <Object?>[null, 5, 'x', <String, Object>{}, {'kind': 42}, {'kind': 'nonsense'}, {'kind': '__proto__'}, {'kind': 'constructor'}]) {
        expect(routeFor(odd), PushDest.assistant, reason: '$odd');
      }
    });

    test('every destination is a tab of the app', () {
      for (final d in PushDest.values) {
        expect(tabForDest(d).name, d.name);
      }
      expect(tabForDest(PushDest.machines), AppTab.machines);
    });
  });

  group('stateFromPermission', () {
    test('reads the phone’s answer', () {
      expect(stateFromPermission('granted'), PushState.on);
      expect(stateFromPermission('denied'), PushState.denied);
      expect(stateFromPermission('prompt'), PushState.off);
      expect(stateFromPermission('prompt-with-rationale'), PushState.off);
      expect(stateFromPermission('something new'), PushState.off);
    });
  });

  group('channelState (is the Alerts channel able to show anything?)', () {
    ({String id, int? importance}) ch(int importance, [String id = 'escanor_alerts']) => (id: id, importance: importance);
    test('is fine at default importance or above', () {
      for (final i in [3, 4, 5]) {
        expect(channelState([ch(i)]), ChannelState.ok, reason: '$i');
      }
      expect(channelState([(id: 'escanor_alerts', importance: null)]), ChannelState.ok);
    });
    test('says blocked when the person switched the channel off', () {
      expect(channelState([ch(0)]), ChannelState.blocked);
    });
    test('says quiet when it can only appear silently', () {
      for (final i in [1, 2]) {
        expect(channelState([ch(i)]), ChannelState.quiet, reason: '$i');
      }
    });
    test('says missing when the channel was never created, and ignores other channels', () {
      expect(channelState([]), ChannelState.missing);
      expect(channelState([ch(4, 'something_else')]), ChannelState.missing);
      expect(channelState(null), ChannelState.missing);
    });
  });

  test('names the platform the way the backend expects', () {
    expect(pushPlatform(ios: false), 'android');
    expect(pushPlatform(ios: true), 'ios');
    expect(channelId, 'escanor_alerts');
  });
}
