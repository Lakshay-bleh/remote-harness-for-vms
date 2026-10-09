import 'dart:io';

import 'package:escanor/features/settings/whats_new.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every release must carry its own news, and the app must not send people to the website.
void main() {
  final notes = parseReleaseNotes(File('assets/whats_new.json').readAsStringSync());
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final version = RegExp(r'^version:\s*([0-9][0-9.]*)', multiLine: true).firstMatch(pubspec)!.group(1)!;

  test('the version being built has release notes with something in them', () {
    final note = noteFor(notes, version);
    expect(note, isNotNull, reason: 'Add an entry for $version to assets/whats_new.json before releasing it.');
    expect(note!.title, isNotEmpty);
    expect(note.items, isNotEmpty);
    expect(note.date, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
  });

  test('the newest entry is the version being built, and no release is listed twice', () {
    expect(normalizeVersion(notes.first.version), normalizeVersion(version));
    final seen = <String>{};
    for (final n in notes) {
      expect(seen.add(normalizeVersion(n.version)), isTrue, reason: 'listed twice: ${n.version}');
      expect(n.items, isNotEmpty, reason: n.version);
    }
  });

  test('a release is told apart from the next however its number is written', () {
    expect(normalizeVersion('1.25.0'), '1.25');
    expect(normalizeVersion('1.25.0+125'), '1.25');
    expect(normalizeVersion('1.25 (125)'), '1.25');
    expect(normalizeVersion('1.25.1'), '1.25.1');
    expect(noteFor(notes, '1.24.0')?.version, '1.24');
    expect(noteFor(notes, '9.9'), isNull);
  });

  test('damaged notes are skipped, not fatal', () {
    expect(parseReleaseNotes('not json'), isEmpty);
    expect(parseReleaseNotes('{"a":1}'), isEmpty);
    expect(parseReleaseNotes('[{"version":"1","items":["a"]},{"version":2},{"items":[]},5]').map((n) => n.version), ['1']);
  });

  test('nothing in the app sends the person to the escanor website', () {
    // The API address and the sign-in hand-back are not pages; the contact addresses are email, not links.
    const allowed = {'lib/core/config.dart', 'lib/features/settings/legal_content.dart', 'lib/features/settings/settings_logic.dart'};
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (allowed.contains(f.path)) continue;
      final text = f.readAsStringSync();
      if (RegExp(r'https?://(?:www\.)?escanor\.in|websiteBase').hasMatch(text)) offenders.add(f.path);
    }
    expect(offenders, isEmpty);
  });
}
