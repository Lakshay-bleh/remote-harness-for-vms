import 'package:escanor/features/voice/actions.dart';
import 'package:escanor/features/voice/apps.dart';
import 'package:escanor/features/voice/assistant.dart';
import 'package:escanor/features/voice/commands.dart';
import 'package:escanor/features/voice/contacts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_phone.dart';

void main() {
  group('formatting', () {
    test('says times and durations the way a person would', () {
      expect(formatClock(7, 30), '7:30 AM');
      expect(formatClock(0, 0), '12:00 AM');
      expect(formatClock(18, 5), '6:05 PM');
      expect(formatDuration(300), '5 minutes');
      expect(formatDuration(60), '1 minute');
      expect(formatDuration(5400), '1 hour 30 minutes');
      expect(formatDuration(45), '45 seconds');
    });
  });

  group('runPhoneAction', () {
    test('opens the installed app that matches, and says so', () async {
      final p = FakePhone();
      final r = await runPhoneAction(const OpenApp('whats app'), p);
      expect(r, const ActionOutcome(ok: true, say: 'Opening WhatsApp.'));
      expect(p.find('launchPackage')?.$2, {'package': 'com.wa'});
    });

    test('falls back to the website for a known site that has no app, and says it did not find an app otherwise', () async {
      final p = FakePhone(apps: const []);
      expect(await runPhoneAction(const OpenApp('github'), p), const ActionOutcome(ok: true, say: 'Opening github.com.'));
      expect(p.find('openUrl')?.$2, {'url': 'https://github.com'});
      final r = await runPhoneAction(const OpenApp('tiktok'), p);
      expect(r.ok, false);
      expect(r.say, matches(RegExp(r"couldn.t find an app called tiktok", caseSensitive: false)));
    });

    test('opens the dialer (and says to press call) when the call could not be placed directly', () async {
      final p = FakePhone();
      final r = await runPhoneAction(const Call('9876543210'), p, options: const PhoneOptions(directCalls: false));
      expect(r.ok, true);
      expect(r.say, contains('dialer'));
      expect(r.say, matches(RegExp('press call', caseSensitive: false)));
      expect(p.find('callNumber')?.$2, {'number': '9876543210', 'direct': false});
    });

    test('places the call itself when the phone says it did, and says it is calling', () async {
      final p = FakePhone(onCallNumber: (_, _) async => const PluginResult(ok: true, direct: true));
      expect(await runPhoneAction(const Call('9876543210'), p), const ActionOutcome(ok: true, say: 'Calling 9876543210.'));
      expect(p.find('callNumber'), isNull); // the override replaced the recorder: nothing recorded
    });

    test('asks the phone to call directly unless the person turned that off', () async {
      final a = FakePhone();
      await runPhoneAction(const Call('5551234'), a);
      expect((a.find('callNumber')!.$2 as Map)['direct'], true);
      final b = FakePhone();
      await runPhoneAction(const Call('mom'), b, options: const PhoneOptions(directCalls: false));
      expect((b.find('callContact')!.$2 as Map)['direct'], false);
    });

    test('calls a contact by name, and passes on why it could not', () async {
      final good = FakePhone(onCallContact: (_, _) async => const PluginResult(ok: true, message: 'Mom', direct: true));
      expect(await runPhoneAction(const Call('mom'), good), const ActionOutcome(ok: true, say: 'Calling Mom.'));
      final bad = FakePhone(onCallContact: (_, _) async => const PluginResult(ok: false, message: 'I could not find zed in your contacts.'));
      expect(await runPhoneAction(const Call('zed'), bad), const ActionOutcome(ok: false, say: 'I could not find zed in your contacts.'));
    });

    test('sets alarms and timers and confirms the time', () async {
      final p = FakePhone();
      expect(await runPhoneAction(const SetAlarm(7, 30), p), const ActionOutcome(ok: true, say: 'Alarm set for 7:30 AM.'));
      expect(await runPhoneAction(const SetTimer(300), p), const ActionOutcome(ok: true, say: 'Timer set for 5 minutes.'));
      expect(p.find('setAlarm')?.$2, {'hour': 7, 'minute': 30});
    });

    test('torch, volume, search and settings', () async {
      final p = FakePhone();
      expect((await runPhoneAction(const Torch(true), p)).say, 'Flashlight on.');
      expect((await runPhoneAction(const Volume(VolumeChange.up), p)).say, 'Volume up.');
      expect((await runPhoneAction(const WebSearch('best pizza'), p)).say, 'Searching for best pizza.');
      expect(p.find('openUrl')?.$2, {'url': 'https://www.google.com/search?q=best%20pizza'});
      expect((await runPhoneAction(const OpenSettings(SettingsScreen.wifi), p)).say, 'Opening Wi-Fi settings.');
    });

    test('reports a refusal from the phone in its own words', () async {
      final p = FakePhone(onSetTorch: (_) async => const PluginResult(ok: false, message: 'This phone has no flashlight.'));
      expect(await runPhoneAction(const Torch(true), p), const ActionOutcome(ok: false, say: 'This phone has no flashlight.'));
    });

    test('never throws: a plugin that blows up becomes a spoken problem', () async {
      final p = FakePhone(onSetTimer: (_) async => throw Exception('boom'));
      final r = await runPhoneAction(const SetTimer(60), p);
      expect(r.ok, false);
      expect(r.say, matches(RegExp('could not', caseSensitive: false)));
    });

    test('without the phone side only links work, and it says what is missing', () async {
      final r = await runPhoneAction(const SetAlarm(7, 0), null);
      expect(r.ok, false);
      expect(r.say, contains('Android app'));
      final opened = <String>[];
      final link = await runPhoneAction(const OpenApp('github'), null, openLink: (u) async {
        opened.add(u);
        return true;
      });
      expect(link, const ActionOutcome(ok: true, say: 'Opening github.com.'));
      expect(opened, ['https://github.com']);
    });
  });

  group('using the phone itself', () {
    test('does what was asked with the phone’s own buttons, and says what it did', () async {
      final p = FakePhone();
      expect(await runPhoneAction(const Control(ControlOp.home), p), const ActionOutcome(ok: true, say: 'Going home.'));
      expect(p.find('control')?.$2, {'action': 'global', 'name': 'home'});
      await runPhoneAction(const Control(ControlOp.scrollUp), p);
      expect(p.calls.where((c) => c.$1 == 'control').last.$2, {'action': 'scroll', 'direction': 'up'});
      await runPhoneAction(const Control(ControlOp.quickSettings), p);
      expect(p.calls.where((c) => c.$1 == 'control').last.$2, {'action': 'global', 'name': 'quick_settings'});
    });

    test('taps and types by words, and reads the screen aloud', () async {
      final p = FakePhone(onControl: (r) async => r is ReadControl ? const PluginResult(ok: true, message: 'Inbox. 3 new messages.') : const PluginResult(ok: true));
      expect(await runPhoneAction(const TapText('send'), p), const ActionOutcome(ok: true, say: 'Tapped send.'));
      expect(await runPhoneAction(const TypeText('hello'), p), const ActionOutcome(ok: true, say: 'Typed it.'));
      expect(await runPhoneAction(const ReadScreen(), p), const ActionOutcome(ok: true, say: 'On your screen: Inbox. 3 new messages.'));
    });

    test('says what to turn on, and where, when the Accessibility permission is off', () async {
      final p = FakePhone(
          onControl: (_) async =>
              const PluginResult(ok: false, message: 'Controlling your phone needs Escanor turned on in Accessibility settings.', needs: Needs.accessibility));
      final r = await runPhoneAction(const Control(ControlOp.back), p);
      expect(r.ok, false);
      expect(r.needs, Needs.accessibility);
      expect(r.say, contains('Accessibility'));
    });

    test('says why a tap found nothing', () async {
      final p = FakePhone(onControl: (_) async => const PluginResult(ok: false, message: 'I could not find “pay” on the screen.'));
      expect(await runPhoneAction(const TapText('pay'), p), const ActionOutcome(ok: false, say: 'I could not find “pay” on the screen.'));
    });

    test('opens a website by address', () async {
      final p = FakePhone();
      expect(await runPhoneAction(const OpenUrl('https://github.com'), p), const ActionOutcome(ok: true, say: 'Opening github.com.'));
      expect(p.find('openUrl')?.$2, {'url': 'https://github.com'});
    });

    test('opens the site when an installed app would not start (the "open google" case)', () async {
      final p = FakePhone(
        apps: const [InstalledApp(label: 'Google', package: 'com.google.android.googlequicksearchbox')],
        onLaunch: (_) async => const PluginResult(ok: false, message: 'That app could not be opened.'),
      );
      expect(await runPhoneAction(const OpenApp('google'), p), const ActionOutcome(ok: true, say: 'Opening google.com in the browser.'));
    });
  });

  group('calling by name', () {
    const book = [
      Contact(name: 'Tanishq USICT 2027', numbers: ['+919876500001']),
      Contact(name: 'Aman Gupta', numbers: ['+919876500002']),
      Contact(name: 'Amit Gupta', numbers: ['+919876500003']),
    ];
    Future<({PluginResult result, List<Contact> contacts})> all() async => (result: const PluginResult(ok: true), contacts: book);

    test('finds the contact however the recogniser spelled the name, and calls the number', () async {
      final calls = <Map<String, Object?>>[];
      final p = FakePhone(
        onListContacts: all,
        onCallNumber: (n, d) async {
          calls.add({'number': n, 'direct': d});
          return const PluginResult(ok: true, direct: true);
        },
      );
      for (final said in ['tanishq usic 2027', 'tanishq usict twenty twenty seven']) {
        expect(await runPhoneAction(Call(said), p), const ActionOutcome(ok: true, say: 'Calling Tanishq USICT 2027.'), reason: said);
      }
      expect(calls.first, {'number': '+919876500001', 'direct': true});
    });

    test('asks which one when two fit equally, instead of ringing the wrong person', () async {
      final r = await runPhoneAction(const Call('gupta'), FakePhone(onListContacts: all));
      expect(r.ok, true);
      expect(r.ask, true);
      expect(r.say, matches(RegExp(r'Did you mean (Aman Gupta or Amit Gupta|Amit Gupta or Aman Gupta)\?')));
    });

    test('says so when nobody matches, and passes on a missing permission', () async {
      expect(await runPhoneAction(const Call('zebra'), FakePhone(onListContacts: all)), const ActionOutcome(ok: false, say: 'I couldn’t find zebra in your contacts.'));
      final denied = FakePhone(
          onListContacts: () async =>
              (result: const PluginResult(ok: false, message: 'Allow Escanor to read your contacts so it can find who to call.'), contacts: const <Contact>[]));
      expect(await runPhoneAction(const Call('tanishq'), denied),
          const ActionOutcome(ok: false, say: 'Allow Escanor to read your contacts so it can find who to call.'));
    });
  });

  group('answering "Did you mean …?"', () {
    test('takes the next sentence as the answer: by name, or "the second one"', () async {
      resetPendingChoice();
      final calls = <String>[];
      final device = FakePhone(
        onListContacts: () async => (
          result: const PluginResult(ok: true),
          contacts: const [Contact(name: 'Aman Gupta', numbers: ['111']), Contact(name: 'Amit Gupta', numbers: ['222'])],
        ),
        onCallNumber: (n, _) async {
          calls.add(n);
          return const PluginResult(ok: true, direct: true);
        },
      );
      final deps = AssistantDeps(device: device, hasComputer: false, toComputer: (_) async => '', toAssistant: (_) async => null, go: (_) {});
      final asked = await handleUtterance('call gupta', deps);
      expect(asked.ask, true);
      expect((await handleUtterance('amit', deps)).say, 'Calling Amit Gupta.');
      await handleUtterance('call gupta', deps);
      expect((await handleUtterance('the first one', deps)).say, 'Calling Aman Gupta.');
      expect(calls, ['222', '111']);
    });
  });
}
