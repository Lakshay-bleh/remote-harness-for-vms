import 'dart:convert';
import 'dart:math';

import 'package:intl/intl.dart';

import '../../core/storage.dart';

/// The conversations a person has had with one computer, kept on the phone so they are still there tomorrow: a list of chats, each
/// a list of turns. Pure functions over plain data (the screen decides when to save), so the rules are tested.

enum Who { you, computer }

class Turn {
  const Turn({required this.who, required this.text, required this.at, this.problem = false, this.files});
  final Who who;
  final String text;

  /// The computer's reply was a refusal: shown as an explained error with its fix, not as a bubble.
  final bool problem;

  /// Names of files attached to this message.
  final List<String>? files;

  /// ms since epoch.
  final int at;

  Map<String, dynamic> toJson() => {
    'who': who.name,
    'text': text,
    if (problem) 'problem': true,
    if (files != null && files!.isNotEmpty) 'files': files,
    'at': at,
  };

  static Turn? fromJson(Object? j) {
    if (j is! Map || (j['who'] != 'you' && j['who'] != 'computer') || j['text'] is! String) return null;
    return Turn(
      who: j['who'] == 'you' ? Who.you : Who.computer,
      text: j['text'] as String,
      problem: j['problem'] == true,
      files: j['files'] is List ? [for (final f in j['files'] as List) '$f'] : null,
      at: j['at'] is num ? (j['at'] as num).toInt() : 0,
    );
  }
}

class Chat {
  const Chat({required this.id, required this.title, required this.createdAt, required this.updatedAt, required this.turns});
  final String id;
  final String title;
  final int createdAt;
  final int updatedAt;
  final List<Turn> turns;

  Chat copyWith({List<Turn>? turns, int? updatedAt, String? title, String? id}) =>
      Chat(id: id ?? this.id, title: title ?? this.title, createdAt: createdAt, updatedAt: updatedAt ?? this.updatedAt, turns: turns ?? this.turns);

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'turns': [for (final t in turns) t.toJson()],
  };

  /// A chat as stored, or null when it is damaged (a bad turn spoils the chat, as in the TypeScript `valid`).
  static Chat? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String || j['title'] is! String || j['turns'] is! List) return null;
    final turns = <Turn>[];
    for (final t in j['turns'] as List) {
      final turn = Turn.fromJson(t);
      if (turn == null) return null;
      turns.add(turn);
    }
    return Chat(
      id: j['id'] as String,
      title: j['title'] as String,
      createdAt: j['createdAt'] is num ? (j['createdAt'] as num).toInt() : 0,
      updatedAt: j['updatedAt'] is num ? (j['updatedAt'] as num).toInt() : 0,
      turns: turns,
    );
  }
}

const maxChats = 30;
const maxTurns = 200;
String _key(String computerId) => 'escanor.computer.chats.v1:$computerId';

final _rand = Random();
String _shortId() => List.generate(8, (_) => '0123456789abcdefghijklmnopqrstuvwxyz'[_rand.nextInt(36)]).join();

Chat newChat([int? now, String? id]) {
  final t = now ?? DateTime.now().millisecondsSinceEpoch;
  return Chat(id: id ?? _shortId(), title: 'New chat', createdAt: t, updatedAt: t, turns: const []);
}

/// A chat's name: the first thing said, trimmed to a line.
String titleFrom(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return 'New chat';
  return t.length <= 44 ? t : '${t.substring(0, 41).trimRight()}…';
}

Chat addTurn(Chat chat, Turn turn) {
  final all = [...chat.turns, turn];
  final turns = all.length > maxTurns ? all.sublist(all.length - maxTurns) : all;
  return chat.copyWith(turns: turns, updatedAt: turn.at, title: chat.turns.isEmpty && turn.who == Who.you ? titleFrom(turn.text) : chat.title);
}

/// Newest first, nothing empty (a chat nobody typed in is not worth a row), at most [maxChats].
List<Chat> tidy(List<Chat> chats) {
  final indexed = [for (var i = 0; i < chats.length; i++) (i, chats[i])].where((e) => e.$2.turns.isNotEmpty).toList()
    ..sort((a, b) {
      final c = b.$2.updatedAt.compareTo(a.$2.updatedAt);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return [for (final e in indexed.take(maxChats)) e.$2];
}

List<Chat> upsert(List<Chat> chats, Chat chat) => tidy([chat, ...chats.where((c) => c.id != chat.id)]);

List<Chat> removeChat(List<Chat> chats, String id) => chats.where((c) => c.id != id).toList();

List<Chat> loadChats(String computerId) {
  try {
    final raw = jsonDecode(Storage.instance.getString(_key(computerId)) ?? '[]');
    if (raw is! List) return [];
    return tidy([for (final c in raw) ?Chat.fromJson(c)]);
  } catch (_) {
    return [];
  }
}

void saveChats(String computerId, List<Chat> chats) {
  try {
    Storage.instance.setString(_key(computerId), jsonEncode([for (final c in tidy(chats)) c.toJson()]));
  } catch (_) {
    // storage full: the chat stays on screen for this visit
  }
}

void forgetChats(String computerId) {
  try {
    Storage.instance.remove(_key(computerId));
  } catch (_) {
    // nothing to forget
  }
}

/// Every computer's chats (sign-out, reset).
void forgetAllChats() {
  try {
    final prefs = Storage.instance.prefs;
    for (final k in prefs.getKeys().where((k) => k.startsWith('escanor.computer.chats.v1:')).toList()) {
      prefs.remove(k);
    }
  } catch (_) {}
}

/// "Today", "Yesterday", or the date: for grouping the history list.
String dayLabel(int at, [int? now]) {
  DateTime day(int t) {
    final d = DateTime.fromMillisecondsSinceEpoch(t);
    return DateTime(d.year, d.month, d.day);
  }

  final n = now ?? DateTime.now().millisecondsSinceEpoch;
  final diff = (day(n).difference(day(at)).inHours / 24).round();
  if (diff <= 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return 'Earlier this week';
  return DateFormat('d MMM').format(DateTime.fromMillisecondsSinceEpoch(at));
}
