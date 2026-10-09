import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../ui/parts.dart';
import '../../ui/widgets.dart';

/// What changed in each release, written for the person using the app. It ships inside the app (assets/whats_new.json), so it reads
/// without a connection and every release carries its own news: a test fails the build if the version being built has no entry.
class ReleaseNote {
  const ReleaseNote({required this.version, required this.date, required this.title, required this.items});
  final String version;
  final String date;
  final String title;
  final List<String> items;

  static ReleaseNote? tryParse(Object? j) {
    if (j is! Map) return null;
    final version = j['version'];
    final items = j['items'];
    if (version is! String || version.isEmpty || items is! List) return null;
    return ReleaseNote(
      version: version,
      date: j['date'] is String ? j['date'] as String : '',
      title: j['title'] is String ? j['title'] as String : '',
      items: [for (final i in items) if (i is String && i.trim().isNotEmpty) i],
    );
  }
}

/// The notes in the file, newest first. Anything damaged is skipped.
List<ReleaseNote> parseReleaseNotes(String raw) {
  try {
    final v = jsonDecode(raw);
    return v is List ? [for (final e in v) ?ReleaseNote.tryParse(e)] : const [];
  } catch (_) {
    return const [];
  }
}

/// "1.25.0" and "1.25" are the same release.
String normalizeVersion(String v) {
  var s = v.trim().split('+').first.split(' ').first;
  while (s.endsWith('.0') && s.split('.').length > 2) {
    s = s.substring(0, s.length - 2);
  }
  return s;
}

ReleaseNote? noteFor(List<ReleaseNote> notes, String version) {
  final want = normalizeVersion(version);
  for (final n in notes) {
    if (normalizeVersion(n.version) == want) return n;
  }
  return null;
}

Future<List<ReleaseNote>> loadReleaseNotes() async => parseReleaseNotes(await rootBundle.loadString('assets/whats_new.json'));

const _seenKey = 'escanor.whatsnew.seen';

/// After an update, show what is new once. A fresh install has nothing "new" to catch up on, so it only records the version.
Future<void> maybeShowWhatsNew(BuildContext context) async {
  try {
    final version = normalizeVersion((await PackageInfo.fromPlatform()).version);
    final storage = Storage.instance;
    final seen = storage.getString(_seenKey);
    if (seen == version) return;
    await storage.setString(_seenKey, version);
    if (seen == null) return; // first run of this install
    final note = noteFor(await loadReleaseNotes(), version);
    if (note == null || !context.mounted) return;
    await showESheet<void>(context, title: 'What’s new in ${note.version}', builder: (_) => _NoteBody(note: note));
  } catch (_) {
    // no platform info (tests) or no file: nothing to show
  }
}

class WhatsNewPage extends StatefulWidget {
  const WhatsNewPage({super.key});
  @override
  State<WhatsNewPage> createState() => _WhatsNewPageState();
}

class _WhatsNewPageState extends State<WhatsNewPage> {
  late final Future<List<ReleaseNote>> _notes = loadReleaseNotes();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SettingsPage(title: 'What’s new', children: [
      FutureBuilder<List<ReleaseNote>>(
        future: _notes,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(24), child: Center(child: Spinner()));
          final notes = snap.data ?? const [];
          if (notes.isEmpty) return Text('Nothing to show.', style: TextStyle(fontSize: 14, color: c.muted));
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final n in notes) ...[_NoteBody(note: n, heading: true), const SizedBox(height: 24)],
          ]);
        },
      ),
    ]);
  }
}

class _NoteBody extends StatelessWidget {
  const _NoteBody({required this.note, this.heading = false});
  final ReleaseNote note;
  final bool heading;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (heading) ...[
        Text('Version ${note.version}${note.date.isEmpty ? '' : ' · ${note.date}'}', style: TextStyle(fontSize: 12, letterSpacing: 0.4, color: c.muted)),
        const SizedBox(height: 2),
      ],
      if (note.title.isNotEmpty) Text(note.title, style: TextStyle(fontSize: heading ? 18 : 16, fontWeight: FontWeight.w500, color: c.ink)),
      const SizedBox(height: 8),
      for (final item in note.items)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 7, right: 10), child: Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: c.primary))),
            Expanded(child: Text(item, style: TextStyle(fontSize: 14, height: 1.5, color: c.bodyStrong))),
          ]),
        ),
    ]);
  }
}
