// Port of computer/chatStore.test.ts, plus the storage of paired computers (keys in the secret store) and of their prefs.
import 'dart:convert';

import 'package:escanor/core/cache.dart';
import 'package:escanor/core/session.dart';
import 'package:escanor/core/storage.dart';
import 'package:escanor/features/computers/chat_store.dart';
import 'package:escanor/features/computers/computer_api.dart';
import 'package:escanor/features/computers/computer_prefs.dart';
import 'package:escanor/features/computers/storage.dart';
import 'package:flutter_test/flutter_test.dart';

Turn said(String text, [int at = 1]) => Turn(who: Who.you, text: text, at: at);

void main() {
  setUp(() async {
    await Storage.initForTest();
    resetComputerPrefsCache();
  });

  group('computer chats', () {
    test('names a chat after the first thing said', () {
      var c = newChat(1, 'a');
      c = addTurn(c, said('What is using my memory?'));
      expect(c.title, 'What is using my memory?');
      c = addTurn(c, const Turn(who: Who.computer, text: 'Chrome.', at: 2));
      c = addTurn(c, said('and disk?', 3));
      expect(c.title, 'What is using my memory?');
      expect(c.updatedAt, 3);
    });

    test('shortens a long title to one line', () {
      expect(titleFrom('x' * 100).length, 42);
      expect(titleFrom('  a \n\n b '), 'a b');
      expect(titleFrom('   '), 'New chat');
    });

    test('keeps the newest turns when a chat gets very long', () {
      var c = newChat(1, 'a');
      for (var i = 0; i < maxTurns + 20; i++) {
        c = addTurn(c, said('m$i', i));
      }
      expect(c.turns.length, maxTurns);
      expect(c.turns.last.text, 'm${maxTurns + 19}');
    });

    test('lists newest first, hides empty chats, and keeps at most maxChats', () {
      final many = [for (var i = 0; i < maxChats + 5; i++) addTurn(newChat(i, 'c$i'), said('hi', i + 10))];
      final t = tidy([...many, newChat(999, 'empty')]);
      expect(t.length, maxChats);
      expect(t.first.id, 'c${maxChats + 4}');
      expect(t.any((c) => c.id == 'empty'), isFalse);
    });

    test('replaces a chat by id when it changes, and removes one', () {
      final a = addTurn(newChat(1, 'a'), said('one', 5));
      var list = upsert([], a);
      list = upsert(list, addTurn(a, said('two', 9)));
      expect(list.length, 1);
      expect(list.first.turns.length, 2);
      expect(removeChat(list, 'a'), isEmpty);
    });

    test('survives a restart: saved per computer, and one computer never sees another’s chats', () {
      saveChats('phone-1', [addTurn(newChat(1, 'a'), said('hi', 2))]);
      saveChats('phone-2', [addTurn(newChat(1, 'b'), said('yo', 2))]);
      expect(loadChats('phone-1').first.id, 'a');
      expect(loadChats('phone-2').first.id, 'b');
      forgetChats('phone-1');
      expect(loadChats('phone-1'), isEmpty);
      expect(loadChats('phone-2').length, 1);
    });

    test('keeps what a turn carries: a problem flag and attached file names', () {
      final c = addTurn(
        addTurn(newChat(1, 'a'), const Turn(who: Who.you, text: 'look', at: 2, files: ['a.txt'])),
        const Turn(who: Who.computer, text: 'Not allowed.', at: 3, problem: true),
      );
      saveChats('p', [c]);
      final back = loadChats('p').single;
      expect(back.turns.first.files, ['a.txt']);
      expect(back.turns.last.problem, isTrue);
    });

    test('ignores damaged storage', () {
      Storage.instance.setString('escanor.computer.chats.v1:x', '{{{not json');
      expect(loadChats('x'), isEmpty);
      Storage.instance.setString(
        'escanor.computer.chats.v1:y',
        jsonEncode([
          {'id': 1},
          {
            'id': 'ok',
            'title': 't',
            'turns': [
              {'who': 'you', 'text': 'hi', 'at': 1},
            ],
            'createdAt': 1,
            'updatedAt': 1,
          },
        ]),
      );
      expect(loadChats('y').map((c) => c.id), ['ok']);
    });

    test('labels days for the history list', () {
      final now = DateTime(2026, 10, 4, 15).millisecondsSinceEpoch;
      expect(dayLabel(DateTime(2026, 10, 4, 8).millisecondsSinceEpoch, now), 'Today');
      expect(dayLabel(DateTime(2026, 10, 3, 23).millisecondsSinceEpoch, now), 'Yesterday');
      expect(dayLabel(DateTime(2026, 10, 1).millisecondsSinceEpoch, now), 'Earlier this week');
      expect(dayLabel(DateTime(2026, 9, 1).millisecondsSinceEpoch, now), '1 Sep');
    });
  });

  group('computer prefs on the phone', () {
    test('are kept per computer, survive a restart and are forgotten', () {
      setComputerPrefs('d1', alias: '  Desk  ');
      setComputerPrefs('d1', route: RoutePref.lan);
      setComputerPrefs('d2', route: RoutePref.cloud);
      resetComputerPrefsCache();
      expect(getComputerPrefs('d1'), const ComputerPrefs(alias: 'Desk', route: RoutePref.lan));
      expect(getComputerPrefs('d2').route, RoutePref.cloud);
      forgetComputerPrefs('d1');
      expect(getComputerPrefs('d1'), const ComputerPrefs());
      expect(getComputerPrefs('nobody'), const ComputerPrefs());
    });
    test('damaged storage starts clean', () {
      Storage.instance.setString('escanor.computer.prefs.v1', '{bad');
      expect(getComputerPrefs('d1'), const ComputerPrefs());
    });
  });

  group('paired computers', () {
    const a = PairedComputer(id: 'dev-a', name: 'Work Laptop', key: 'KEY-A', lan: ['192.168.1.5:47625'], agentId: 'agent-1', pairedAt: '2026-10-01T00:00:00Z');
    const b = PairedComputer(id: 'dev-b', name: 'Home PC', key: 'KEY-B', pairedAt: '2026-10-02T00:00:00Z');

    test('the device key goes in the secret store, never in ordinary preferences', () {
      saveComputer(a);
      expect(Storage.instance.secret('escanor.computer.key.dev-a'), 'KEY-A');
      final prefsText = Storage.instance.prefs.getKeys().map((k) => '${Storage.instance.prefs.get(k)}').join(' ');
      expect(prefsText, isNot(contains('KEY-A')));
      expect(loadComputers(), [a]);
    });

    test('newest first, saving again replaces, and one whose key is gone is left out', () {
      saveComputer(a);
      saveComputer(b);
      expect(loadComputers().map((c) => c.id), ['dev-b', 'dev-a']);
      saveComputer(a);
      expect(loadComputers().map((c) => c.id), ['dev-a', 'dev-b']);
      Storage.instance.setSecret('escanor.computer.key.dev-b', null);
      expect(loadComputers().map((c) => c.id), ['dev-a']);
    });

    test('forgetting one takes its key, prefs, chats and cache', () {
      saveComputer(a);
      setComputerPrefs('dev-a', alias: 'Desk');
      saveChats('dev-a', [addTurn(newChat(1, 'x'), said('hi', 2))]);
      writeCache('computer:dev-a:stats', {'cpu': 1});
      removeComputer('dev-a');
      expect(loadComputers(), isEmpty);
      expect(Storage.instance.secret('escanor.computer.key.dev-a'), isNull);
      expect(getComputerPrefs('dev-a'), const ComputerPrefs());
      expect(loadChats('dev-a'), isEmpty);
      expect(readCache(const CachePolicy('computer:dev-a:stats', ttl: Duration(hours: 1))), isNull);
    });

    test('signing out forgets every computer, through the sign-out hook', () async {
      saveComputer(a);
      saveComputer(b);
      setComputerPrefs('dev-b', route: RoutePref.lan);
      signOutHooks.clear();
      await startComputers();
      for (final h in signOutHooks) {
        await h();
      }
      expect(loadComputers(), isEmpty);
      expect(Storage.instance.secretKeys.where((k) => k.startsWith('escanor.computer.key.')), isEmpty);
      expect(getComputerPrefs('dev-b'), const ComputerPrefs());
    });

    test('a list that changes tells whoever is showing it', () {
      var n = 0;
      void bump() => n++;
      computersChanges.addListener(bump);
      saveComputer(a);
      removeComputer(a.id);
      computersChanges.removeListener(bump);
      expect(n, 2);
    });
  });
}
