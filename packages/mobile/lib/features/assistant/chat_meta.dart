/// How a person organises their assistant chats: pinned ones on top, their own names, an archive, and search. The server only
/// knows a chat's id, its generated title and when it was last used, so the rest is kept on this phone. Pure: the live store
/// is `chat_meta_store.dart`.
library;

import 'dart:convert';

class ChatMeta {
  const ChatMeta({this.pinned = const [], this.titles = const {}, this.archived = const []});
  final List<String> pinned;

  /// Names the person gave, by chat id.
  final Map<String, String> titles;
  final List<String> archived;

  ChatMeta copyWith({List<String>? pinned, Map<String, String>? titles, List<String>? archived}) =>
      ChatMeta(pinned: pinned ?? this.pinned, titles: titles ?? this.titles, archived: archived ?? this.archived);

  Map<String, dynamic> toJson() => {'pinned': pinned, 'titles': titles, 'archived': archived};

  @override
  bool operator ==(Object other) =>
      other is ChatMeta && _listEq(other.pinned, pinned) && _listEq(other.archived, archived) && _mapEq(other.titles, titles);

  @override
  int get hashCode => Object.hash(Object.hashAll(pinned), Object.hashAll(archived), Object.hashAllUnordered(titles.entries.map((e) => '${e.key}=${e.value}')));

  @override
  String toString() => 'ChatMeta(pinned: $pinned, titles: $titles, archived: $archived)';
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEq(Map<String, String> a, Map<String, String> b) => a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

const emptyMeta = ChatMeta();

/// A chat as the drawer needs it.
class ChatItem {
  const ChatItem({required this.id, required this.title, this.createdAt, this.updatedAt});
  final String id;

  /// What the server calls it.
  final String title;
  final String? createdAt;
  final String? updatedAt;
}

class ChatRow extends ChatItem {
  const ChatRow({required super.id, required super.title, super.createdAt, super.updatedAt, required this.name, required this.pinned, required this.archived});

  /// What to show: the person's own name if they gave one.
  final String name;
  final bool pinned;
  final bool archived;
}

class ChatSection {
  const ChatSection({required this.key, required this.label, required this.rows});
  final String key;
  final String label;
  final List<ChatRow> rows;
}

const chatMetaKey = 'escanor.chats.v1';

List<String> _strings(Object? v) {
  if (v is! List) return [];
  final out = <String>[];
  for (final x in v) {
    if (x is String && x.isNotEmpty && x.length < 200 && !out.contains(x)) out.add(x);
  }
  return out;
}

/// Read stored organisation defensively: anything damaged becomes an empty field instead of an error.
ChatMeta parseMeta(String? raw) {
  Object? v;
  try {
    v = raw == null || raw.isEmpty ? null : jsonDecode(raw);
  } catch (_) {
    v = null;
  }
  final o = v is Map ? v : const {};
  final titles = <String, String>{};
  final t = o['titles'];
  if (t is Map) {
    for (final e in t.entries) {
      final name = e.value;
      if (e.key is String && name is String && name.trim().isNotEmpty && name.length <= 120) titles[e.key as String] = name.trim();
    }
  }
  return ChatMeta(pinned: _strings(o['pinned']), titles: titles, archived: _strings(o['archived']));
}

/// A name for a chat: trimmed, one line, not absurdly long. Empty means "go back to the generated title".
String cleanName(String text) {
  final s = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s.length > 80 ? s.substring(0, 80) : s;
}

ChatMeta togglePinned(ChatMeta m, String id) =>
    m.copyWith(pinned: m.pinned.contains(id) ? m.pinned.where((x) => x != id).toList() : [id, ...m.pinned]);

ChatMeta toggleArchived(ChatMeta m, String id) => m.copyWith(
      archived: m.archived.contains(id) ? m.archived.where((x) => x != id).toList() : [...m.archived, id],
      pinned: m.pinned.where((x) => x != id).toList(),
    );

ChatMeta rename(ChatMeta m, String id, String text) {
  final name = cleanName(text);
  final titles = Map<String, String>.of(m.titles);
  if (name.isNotEmpty) {
    titles[id] = name;
  } else {
    titles.remove(id);
  }
  return m.copyWith(titles: titles);
}

/// Forget everything about chats that no longer exist (deleted here or elsewhere). Returns [m] itself when nothing changes.
ChatMeta prune(ChatMeta m, List<String> liveIds) {
  final live = liveIds.toSet();
  final titles = {for (final e in m.titles.entries) if (live.contains(e.key)) e.key: e.value};
  final pinned = m.pinned.where(live.contains).toList();
  final archived = m.archived.where(live.contains).toList();
  final same = pinned.length == m.pinned.length && archived.length == m.archived.length && titles.length == m.titles.length;
  return same ? m : ChatMeta(pinned: pinned, titles: titles, archived: archived);
}

const _day = Duration(days: 1);

int _when(ChatItem c) {
  final t = DateTime.tryParse(c.updatedAt ?? c.createdAt ?? '');
  return t?.millisecondsSinceEpoch ?? 0;
}

const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ç': 'c', 'č': 'c', 'ć': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', //
  'ë': 'e', 'ē': 'e', 'ę': 'e', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'ñ': 'n', 'ń': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o',
  'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ý': 'y', 'ÿ': 'y', 'š': 's', 'ś': 's',
  'ž': 'z', 'ź': 'z', 'ż': 'z', 'ł': 'l', 'ğ': 'g', 'ő': 'o', 'ű': 'u', 'ř': 'r', 'ď': 'd', 'ť': 't', 'ň': 'n', 'ě': 'e', 'ů': 'u',
};

String _fold(String s) {
  final lower = s.toLowerCase().replaceAll(RegExp('[̀-ͯ]'), '');
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    b.write(_accents[ch] ?? ch);
  }
  return b.toString();
}

/// Case- and accent-insensitive "contains every word", on the name the person sees.
bool matchesQuery(String name, String query) {
  final hay = _fold(name);
  return _fold(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).every(hay.contains);
}

/// The list the drawer shows: pinned first, then by how recently each chat was used (Today, Yesterday, the last week, month,
/// older). A search ignores the grouping and shows what matches, archived chats included. Archived chats otherwise stay out of
/// the way, in their own section when asked for.
List<ChatSection> organise(List<ChatItem> chats, ChatMeta meta, {String query = '', bool showArchived = false, DateTime? now}) {
  final t = now ?? DateTime.now();
  final pinned = meta.pinned.toSet();
  final archived = meta.archived.toSet();
  final rows = [
    for (final c in chats)
      ChatRow(
        id: c.id,
        title: c.title,
        createdAt: c.createdAt,
        updatedAt: c.updatedAt,
        name: meta.titles[c.id] ?? c.title,
        pinned: pinned.contains(c.id),
        archived: archived.contains(c.id),
      ),
  ];
  int byRecent(ChatRow a, ChatRow b) => _when(b).compareTo(_when(a));
  List<ChatRow> sorted(Iterable<ChatRow> it) {
    // a stable sort, like the JavaScript one
    final indexed = it.toList().asMap().entries.toList()
      ..sort((x, y) {
        final c = byRecent(x.value, y.value);
        return c != 0 ? c : x.key.compareTo(y.key);
      });
    return [for (final e in indexed) e.value];
  }

  final q = query.trim();
  if (q.isNotEmpty) {
    final hits = sorted(rows.where((r) => matchesQuery(r.name, q)));
    return hits.isEmpty ? [] : [ChatSection(key: 'results', label: '${hits.length} ${hits.length == 1 ? 'result' : 'results'}', rows: hits)];
  }
  final sections = <ChatSection>[];
  final pins = <ChatRow>[];
  for (final id in meta.pinned) {
    final r = rows.where((r) => r.id == id).firstOrNull;
    if (r != null && !archived.contains(r.id)) pins.add(r);
  }
  if (pins.isNotEmpty) sections.add(ChatSection(key: 'pinned', label: 'Pinned', rows: pins));
  final rest = sorted(rows.where((r) => !r.pinned && !r.archived));
  final today = DateTime(t.year, t.month, t.day).millisecondsSinceEpoch;
  final day = _day.inMilliseconds;
  final buckets = <(String, String, bool Function(int))>[
    ('today', 'Today', (w) => w >= today),
    ('yesterday', 'Yesterday', (w) => w >= today - day && w < today),
    ('week', 'Previous 7 days', (w) => w >= today - 7 * day && w < today - day),
    ('month', 'Previous 30 days', (w) => w >= today - 30 * day && w < today - 7 * day),
    ('older', 'Older', (w) => w < today - 30 * day),
  ];
  for (final (key, label, test) in buckets) {
    final inBucket = rest.where((r) => test(_when(r))).toList();
    if (inBucket.isNotEmpty) sections.add(ChatSection(key: key, label: label, rows: inBucket));
  }
  if (showArchived) {
    final old = sorted(rows.where((r) => r.archived));
    if (old.isNotEmpty) sections.add(ChatSection(key: 'archived', label: 'Archived', rows: old));
  }
  return sections;
}
