import 'dart:convert';

import 'package:escanor/features/assistant/chat_meta.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 3, 15);
String at(int daysAgo, [int hour = 9]) => DateTime(now.year, now.month, now.day, hour).subtract(Duration(days: daysAgo)).toUtc().toIso8601String();
final chats = [
  ChatItem(id: 'a', title: 'Fix the failing build', updatedAt: at(0, 10), createdAt: at(0, 9)),
  ChatItem(id: 'b', title: 'Deploy to Vercel', updatedAt: at(1), createdAt: at(1)),
  ChatItem(id: 'c', title: 'Cost report', updatedAt: at(4), createdAt: at(4)),
  ChatItem(id: 'd', title: 'Old idea', updatedAt: at(20), createdAt: at(20)),
  ChatItem(id: 'e', title: 'Ancient', updatedAt: at(90), createdAt: at(90)),
];

void main() {
  test('chats are grouped by when they were last used, newest first', () {
    final s = organise(chats, emptyMeta, now: now);
    expect(s.map((x) => x.label), ['Today', 'Yesterday', 'Previous 7 days', 'Previous 30 days', 'Older']);
    expect(s.map((x) => x.rows.map((r) => r.id).toList()), [
      ['a'],
      ['b'],
      ['c'],
      ['d'],
      ['e'],
    ]);
  });

  test('pinned chats lead, in the order they were pinned, and do not repeat below', () {
    var m = togglePinned(emptyMeta, 'd');
    m = togglePinned(m, 'b');
    final s = organise(chats, m, now: now);
    expect(s[0].label, 'Pinned');
    expect(s[0].rows.map((r) => r.id), ['b', 'd']);
    expect(s.skip(1).any((x) => x.rows.any((r) => r.id == 'b' || r.id == 'd')), false);
    expect(togglePinned(m, 'b').pinned, ['d']); // a second tap unpins
  });

  test('a name the person gave replaces the generated title, and clearing it brings the title back', () {
    final m = rename(emptyMeta, 'a', '  My   build   fix ');
    expect(organise(chats, m, now: now)[0].rows[0].name, 'My build fix');
    expect(organise(chats, rename(m, 'a', '   '), now: now)[0].rows[0].name, 'Fix the failing build');
    expect(cleanName('x' * 200).length, 80);
  });

  test('archived chats are hidden unless asked for, and archiving unpins', () {
    final m = toggleArchived(togglePinned(emptyMeta, 'c'), 'c');
    expect(m.pinned.length, 0);
    expect(organise(chats, m, now: now).any((s) => s.rows.any((r) => r.id == 'c')), false);
    final withArchive = organise(chats, m, now: now, showArchived: true);
    expect(withArchive.last.rows.map((r) => r.id), ['c']);
  });

  test('search matches every word in any order, ignores case and accents, and looks through archived chats', () {
    expect(matchesQuery('Fix the failing build', 'BUILD fix'), true);
    expect(matchesQuery('Café report', 'cafe'), true);
    expect(matchesQuery('Fix the failing build', 'deploy'), false);
    final m = toggleArchived(emptyMeta, 'c');
    final hits = organise(chats, m, now: now, query: 'report');
    expect(hits[0].rows.map((r) => r.id), ['c']);
    expect(hits[0].label, '1 result');
    expect(organise(chats, m, now: now, query: 'nothing like this'), isEmpty);
    expect(organise(chats, rename(emptyMeta, 'e', 'Launch plan'), now: now, query: 'launch')[0].rows[0].id, 'e'); // by the name the person sees
  });

  test('stored organisation survives damage, and forgets chats that are gone', () {
    expect(parseMeta('{oops'), emptyMeta);
    expect(
      parseMeta(jsonEncode({
        'pinned': ['a', 5, 'a'],
        'titles': {'a': ' Hi ', 'b': 7, 'c': ''},
        'archived': 'no',
      })),
      const ChatMeta(pinned: ['a'], titles: {'a': 'Hi'}, archived: []),
    );
    const m = ChatMeta(pinned: ['a', 'gone'], titles: {'a': 'A', 'gone': 'G'}, archived: ['gone']);
    expect(prune(m, ['a']), const ChatMeta(pinned: ['a'], titles: {'a': 'A'}, archived: []));
    expect(identical(prune(m, ['a', 'gone']), m), true); // nothing to forget: same object, so no needless save
  });

  test('what is saved reads back the same', () {
    final m = rename(togglePinned(toggleArchived(emptyMeta, 'x'), 'y'), 'y', 'Mine');
    expect(parseMeta(jsonEncode(m.toJson())), m);
  });

  group('search', () {
    test('names first, then chats found inside by the server, each with what matched', () {
      final m = rename(emptyMeta, 'c', 'Vercel bill');
      final hits = [(id: 'd', snippet: '…we moved the site off Vercel…'), (id: 'b', snippet: 'deploy it to Vercel'), (id: 'zz', snippet: 'gone')];
      final r = searchResults(chats, m, 'vercel', hits, now: now);
      expect([for (final x in r) x.row.id], ['b', 'c', 'd'], reason: 'b and c match by name (b ranked by the server); d only inside; an unknown id is skipped');
      expect(r[0].snippet, 'deploy it to Vercel');
      expect(r[1].snippet, '', reason: 'a name only this phone knows: the server did not find it');
      expect(r[2].snippet, '…we moved the site off Vercel…');
    });

    test('without the server (not back yet, offline) the names still match; archived chats are included', () {
      final m = toggleArchived(emptyMeta, 'a');
      expect([for (final x in searchResults(chats, m, 'build', null, now: now)) x.row.id], ['a']);
      expect(searchResults(chats, m, '  ', [(id: 'a', snippet: 'x')], now: now), isEmpty);
    });

    test('a chat found only by meaning shows even when no word matches its name', () {
      final r = searchResults(chats, emptyMeta, 'money spent', [(id: 'c', snippet: 'Your AWS spend was \$41 this month')], now: now);
      expect([for (final x in r) (x.row.id, x.row.name)], [('c', 'Cost report')]);
    });
  });
}
