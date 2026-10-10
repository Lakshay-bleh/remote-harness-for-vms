import 'dart:async';

import 'package:escanor/features/voice/actions.dart';
import 'package:escanor/features/voice/apps.dart';
import 'package:escanor/features/voice/assistant.dart';
import 'package:escanor/features/voice/commands.dart';
import 'package:escanor/features/voice/server_plan.dart';
import 'package:escanor/features/computers/computer_api.dart' show spokenProblem;
import 'package:flutter_test/flutter_test.dart';

import 'fake_phone.dart';

({AssistantDeps d, List<String> log}) deps({
  bool hasComputer = true,
  Future<String> Function(String text)? toComputer,
  Future<String?> Function(String text)? toAssistant,
  Future<ServerPlan?> Function(String text)? resolve,
  Future<void> Function(String text)? ack,
}) {
  final log = <String>[];
  final d = AssistantDeps(
    device: FakePhone(apps: const [InstalledApp(label: 'YouTube', package: 'com.yt')]),
    hasComputer: hasComputer,
    toComputer: toComputer ??
        (text) async {
          log.add('computer:$text');
          return 'Opening youtube.';
        },
    toAssistant: toAssistant ??
        (text) async {
          log.add('assistant:$text');
          return null;
        },
    go: (tab) => log.add('go:${tab.name}'),
    resolve: resolve,
    ack: ack,
  );
  return (d: d, log: log);
}

ServerPlan plan({String source = 'llm', String say = '', Object? actions = const [], String? needs, bool notDevice = false, bool chat = false, bool delegate = false}) =>
    ServerPlan(source: source, say: say, actions: actions, needs: needs, notDevice: notDevice, chat: chat, delegate: delegate);

({AssistantDeps d, List<String> log}) rig(Future<ServerPlan?> Function(String text)? resolve) {
  final log = <String>[];
  final d = AssistantDeps(
    device: FakePhone(
      apps: const [InstalledApp(label: 'YouTube', package: 'com.yt')],
      onLaunch: (p) async {
        log.add('launch:$p');
        return const PluginResult(ok: true);
      },
      onOpenUrl: (u) async {
        log.add('url:$u');
        return const PluginResult(ok: true);
      },
    ),
    hasComputer: false,
    toComputer: (_) async => '',
    toAssistant: (t) async {
      log.add('assistant:$t');
      return null;
    },
    go: (_) {},
    resolve: resolve,
  );
  return (d: d, log: log);
}

void main() {
  setUp(resetPendingChoice);

  group('handleUtterance', () {
    test('does phone things on the phone', () async {
      expect(await handleUtterance('hey escanor open youtube', deps().d), const Reply(ok: true, say: 'Opening YouTube.', kind: ReplyKind.phone));
    });

    test('sends "on my computer…" to the computer and speaks its answer', () async {
      final (:d, :log) = deps();
      final r = await handleUtterance('on my laptop open youtube', d);
      expect(log, ['computer:open youtube']);
      expect(r, const Reply(ok: true, say: 'Opening youtube.', kind: ReplyKind.computer));
    });

    test('turns a computer that says "switched off for phones" into one clear sentence that says where to fix it', () async {
      const off =
          '“Open apps and websites” is turned off for phones. On your computer, open Escanor Desktop, go to Settings, then Permissions, and switch it on in the Phone column.';
      final r = await handleUtterance('on my pc open youtube', deps(toComputer: (_) async => off).d);
      expect(r.ok, false);
      expect(r.say, contains('Open apps and websites'));
      expect(r.say, contains('Escanor Desktop'));
      expect(r.say, contains('Permissions'));
    });

    test('explains a computer that cannot be reached, and where to look', () async {
      final r = await handleUtterance('tell my computer to lock', deps(toComputer: (_) async => throw Exception('The computer did not answer. Is it on and online?')).d);
      expect(r.ok, false);
      expect(r.say, matches(RegExp('not answering', caseSensitive: false)));
      expect(r.say, contains('Escanor Desktop'));
    });

    test('says plainly that no computer is paired, and how to add one', () async {
      final r = await handleUtterance('on my computer open youtube', deps(hasComputer: false).d);
      expect(r.ok, false);
      expect(r.say, contains('Computers'));
    });

    test('hands questions to the assistant and says so', () async {
      final (:d, :log) = deps();
      final r = await handleUtterance('why is checkout slow', d);
      expect(log, ['assistant:why is checkout slow']);
      expect(r, const Reply(ok: true, say: 'Asking your Escanor assistant.', kind: ReplyKind.assistant));
    });

    test('moves around the app', () async {
      final (:d, :log) = deps();
      expect(await handleUtterance('go to my computers', d), const Reply(ok: true, say: 'Opening Computers.', kind: ReplyKind.go));
      expect(log, ['go:computers']);
    });

    test('handles silence and cancel without doing anything', () async {
      final (:d, :log) = deps();
      expect((await handleUtterance('', d)).ok, false);
      expect(await handleUtterance('never mind', d), const Reply(ok: true, say: 'Okay.', kind: ReplyKind.stop));
      expect(log, isEmpty);
    });

    test('speaks the assistant’s answer when it comes back with one', () async {
      final r = await handleUtterance('why is checkout slow', deps(toAssistant: (_) async => 'Checkout is slow because the database is overloaded.').d);
      expect(r, const Reply(ok: true, say: 'Checkout is slow because the database is overloaded.', kind: ReplyKind.assistant));
    });

    test('never throws, even if the assistant call blows up', () async {
      final r = await handleUtterance('why is it slow', deps(toAssistant: (_) async => throw Exception('offline')).d);
      expect(r.ok, false);
      expect(r.say, isNotEmpty);
    });
  });

  group('the server’s fast replies', () {
    test('speaks a chat answer straight away, without waking the full assistant', () async {
      final (:d, :log) = deps(resolve: (_) async => plan(source: 'rules', say: "I'm doing great, thanks for asking.", chat: true));
      expect(await handleUtterance('how are you', d), const Reply(ok: true, say: "I'm doing great, thanks for asking.", kind: ReplyKind.chat));
      expect(log.any((l) => l.startsWith('assistant:')), false);
    });

    test('acknowledges a job at once and speaks the assistant’s answer when it arrives', () async {
      final said = <String>[];
      final (:d, log: _) = deps(
        resolve: (_) async => plan(say: 'Checking your services.', delegate: true),
        toAssistant: (_) async => 'Three of your five services are active.',
        ack: (t) async => said.add(t),
      );
      final r = await handleUtterance('can you check how many services are active', d);
      expect(said, ['Checking your services.']);
      expect(r, const Reply(ok: true, say: 'Three of your five services are active.', kind: ReplyKind.assistant));
    });

    test('starts the job while the acknowledgement is still being spoken', () async {
      final order = <String>[];
      final (:d, log: _) = deps(
        resolve: (_) async => plan(say: 'On it.', delegate: true),
        toAssistant: (_) async {
          order.add('job started');
          return 'done';
        },
        ack: (_) {
          order.add('ack began');
          return Future<void>.delayed(const Duration(milliseconds: 20));
        },
      );
      await handleUtterance('check my deployments', d);
      expect(order.take(2).toList(), ['job started', 'ack began']);
    });

    test('still answers with the assistant’s own words if the acknowledgement could not be spoken', () async {
      final (:d, log: _) = deps(
        resolve: (_) async => plan(say: 'On it.', delegate: true),
        toAssistant: (_) async => 'All good.',
        ack: (_) async => throw Exception('no voice'),
      );
      expect((await handleUtterance('check my deployments', d)).say, 'All good.');
    });
  });

  group('planToActions', () {
    test('turns what the server decided into things this phone can do', () {
      final (:actions, :skipped) = planToActions([
        {'type': 'open_app', 'id': 'com.supercell.clashofclans', 'label': 'Clash of Clans'},
        {'type': 'web_search', 'query': 'lo-fi', 'url': 'https://www.youtube.com/results?search_query=lo-fi'},
        {'type': 'alarm', 'hour': 6, 'minute': 30},
      ]);
      expect(actions, const [
        OpenPackage('com.supercell.clashofclans', 'Clash of Clans'),
        OpenUrl('https://www.youtube.com/results?search_query=lo-fi'),
        SetAlarm(6, 30),
      ]);
      expect(skipped, 0);
    });

    test('hands back the spoken name when the phone could not list its apps, so the phone looks it up itself', () {
      expect(
        planToActions([
          {'type': 'open_app', 'id': '', 'label': 'clash of clans', 'unresolved': true},
        ]).actions,
        const [OpenApp('clash of clans')],
      );
    });

    test('never passes on anything that does not look right', () {
      final bad = [
        {'type': 'open_url', 'url': 'javascript:alert(1)'},
        {'type': 'open_url', 'url': 'http://plain.example'},
        {'type': 'open_app', 'id': '', 'label': 'x'},
        {'type': 'alarm', 'hour': 99, 'minute': 0},
        {'type': 'timer', 'seconds': -5},
        {'type': 'volume', 'change': 'max'},
        {'type': 'call'},
        {'type': 'media', 'action': 'next'},
        {'type': 'rm -rf'},
        null,
      ];
      final r = planToActions(bad);
      expect(r.actions, isEmpty);
      expect(r.skipped, 10);
      final none = planToActions('nope');
      expect(none.actions, isEmpty);
      expect(none.skipped, 0);
    });

    test('does at most three things from one sentence', () {
      final many = [for (var i = 0; i < 6; i++) {'type': 'timer', 'seconds': 10 + i}];
      expect(planToActions(many).actions.length, 3);
    });

    test('lists the phone’s apps the way the server wants them', () {
      expect(appsForServer(const [InstalledApp(label: 'YouTube', package: 'com.yt')]), [
        {'id': 'com.yt', 'label': 'YouTube'},
      ]);
    });

    test('reads the server’s answer defensively', () {
      final p = ServerPlan.fromJson({'source': 'llm', 'say': 'Hi', 'needs': null, 'chat': true, 'not_device': true, 'actions': []});
      expect(p.chat, true);
      expect(p.notDevice, true);
      expect(ServerPlan.fromJson('garbage').source, 'none');
    });
  });

  group('a sentence the phone’s own rules do not settle goes to the server', () {
    test('opens the app the server chose, by package (open the game with the clans)', () async {
      final (:d, :log) = rig((_) async => plan(say: 'Opening Clash of Clans.', actions: [
            {'type': 'open_app', 'id': 'com.supercell.clashofclans', 'label': 'Clash of Clans'},
          ]));
      final r = await handleUtterance('start the game where I build a village', d);
      expect(log, ['launch:com.supercell.clashofclans']);
      expect(r, const Reply(ok: true, say: 'Opening Clash of Clans.', kind: ReplyKind.phone));
    });

    test('asks the server when "open <name>" is not found on the phone, because the server may know the app by another name', () async {
      final (:d, :log) = rig((_) async => plan(source: 'rules', say: 'Opening Clash of Clans.', actions: [
            {'type': 'open_app', 'id': 'com.supercell.clashofclans', 'label': 'Clash of Clans'},
          ]));
      final r = await handleUtterance('open coc', d); // the phone's own matching finds no "coc"
      expect(log, ['launch:com.supercell.clashofclans']);
      expect(r.ok, true);
    });

    test('keeps the phone’s own answer when the server cannot be reached, so nothing gets worse', () async {
      final (:d, log: _) = rig((_) async => null);
      final r = await handleUtterance('open coc', d);
      expect(r.ok, false);
      expect(r.say, contains('couldn’t find an app called coc'));
    });

    test('speaks the server’s question and listens again', () async {
      final (:d, :log) = rig((_) async => plan(needs: 'clarify', say: 'Clash of Clans or Clash Royale?'));
      expect(await handleUtterance('play my favourite supercell game', d), const Reply(ok: true, say: 'Clash of Clans or Clash Royale?', kind: ReplyKind.phone, ask: true));
      expect(log, isEmpty);
    });

    test('hands a sentence that is not a device task to the Escanor assistant, as before', () async {
      for (final answer in [plan(notDevice: true), plan(source: 'none', notDevice: true), null]) {
        final (:d, :log) = rig((_) async => answer);
        final r = await handleUtterance('why is production slow', d);
        expect(log, ['assistant:why is production slow']);
        expect(r.kind, ReplyKind.assistant);
      }
    });

    test('speaks what went wrong at the server (a model that is down, a limit reached) instead of staying silent', () async {
      final (:d, :log) = rig((_) async => plan(source: 'error', say: 'I couldn’t reach my AI model just now. Try again in a moment.'));
      final r = await handleUtterance('play the village game', d);
      expect(r.ok, false);
      expect(r.say, contains('couldn’t reach my AI model'));
      expect(log, isEmpty);
    });

    test('refuses to run something the server sent that does not look right', () async {
      final (:d, :log) = rig((_) async => plan(actions: [
            {'type': 'open_url', 'url': 'javascript:alert(1)'},
          ]));
      final r = await handleUtterance('do the odd thing', d);
      expect(r.ok, false);
      expect(r.say, contains('cannot do it yet'));
      expect(log, isEmpty);
    });

    test('works with no server brain at all (older behaviour)', () async {
      final (:d, :log) = rig(null);
      await handleUtterance('why is production slow', d);
      expect(log, ['assistant:why is production slow']);
    });

    test('a server that throws is treated as not there', () async {
      final (:d, :log) = rig((_) async => throw TimeoutException('slow'));
      await handleUtterance('why is production slow', d);
      expect(log, ['assistant:why is production slow']);
    });
  });

  group('spoken problems', () {
    test('every failure says where the fix is', () {
      expect(spokenProblem(Exception('Your Escanor session ended. Please sign in again.')), startsWith('You were signed out of Escanor. In this app:'));
      expect(spokenProblem('Not allowed.'), contains('On your phone and computer'));
      expect(spokenProblem('Update Escanor Desktop to use that.'), startsWith('Your computer’s Escanor Desktop is out of date. On your computer:'));
      expect(spokenProblem(''), startsWith('That did not work.'));
    });
  });
}
