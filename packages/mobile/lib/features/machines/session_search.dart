import 'protocol.dart';

/// Searching a machine's chats by what was said in them, not only by title. Titles are matched on the phone as the
/// person types; the hub's content search (GET /vms/:vmId/sessions/search) adds the chats whose messages matched.

/// How long typing must pause before the hub is asked.
const contentSearchDelay = Duration(milliseconds: 300);

/// Shorter queries match titles only: one letter would match nearly every chat.
const contentSearchMinLength = 2;

/// One chat the hub found, by its title or by what was said in it.
class SessionSearchHit {
  const SessionSearchHit({required this.sessionId, required this.snippet, required this.score, required this.match});
  final String sessionId;

  /// One line from the best-matching message, or empty when only the title matched.
  final String snippet;
  final double score;

  /// 'title' or 'words'.
  final String match;

  static SessionSearchHit? tryParse(Object? j) {
    if (j is! Map || j['sessionId'] is! String || (j['sessionId'] as String).isEmpty) return null;
    final score = j['score'];
    return SessionSearchHit(
      sessionId: j['sessionId'] as String,
      snippet: j['snippet'] is String ? j['snippet'] as String : '',
      score: score is num ? score.toDouble() : 0,
      match: j['match'] == 'title' ? 'title' : 'words',
    );
  }

  static List<SessionSearchHit> listFrom(Object? j) => j is List ? [for (final x in j) ?tryParse(x)] : const [];
}

/// A row of the chat list: the chat and, when it was found by what was said in it, the line that matched.
class SessionSearchResult {
  const SessionSearchResult(this.session, [this.snippet]);
  final SessionDto session;
  final String? snippet;
}

/// The chats to list for [query], in order. With no query, all of [sessions] as they are. Otherwise the chats whose
/// title contains the query come first, in their usual order, then the chats the hub found ([hits], best first, as the
/// hub ranked them) that the title did not catch, each with its snippet. Hits for chats not in [sessions] (hidden,
/// another account's, not loaded yet) are left out. [hits] is null while the hub has not answered, or cannot search.
List<SessionSearchResult> mergeSessionSearch({
  required List<SessionDto> sessions,
  required String query,
  required String Function(SessionDto) titleOf,
  List<SessionSearchHit>? hits,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return [for (final s in sessions) SessionSearchResult(s)];
  final byTitle = [for (final s in sessions) if (titleOf(s).toLowerCase().contains(q)) s];
  final shown = {for (final s in byTitle) s.id};
  final byId = {for (final s in sessions) s.id: s};
  return [
    for (final s in byTitle) SessionSearchResult(s),
    for (final h in hits ?? const <SessionSearchHit>[])
      if (byId[h.sessionId] != null && shown.add(h.sessionId)) SessionSearchResult(byId[h.sessionId]!, h.snippet.isEmpty ? null : h.snippet),
  ];
}
