import 'protocol/protocol.dart';

/// How many entries one page holds, and how many more to reveal each time the end of the list scrolls into view.
const activityPage = 20;

String _keyOf(ActivityItem a) => '${a.at}|${a.capabilityId}|${a.caller}|${a.outcome}';

/// Put a newly fetched page together with what is already loaded: no duplicates, newest first.
List<ActivityItem> mergeActivity(List<ActivityItem> current, List<ActivityItem> incoming) {
  final seen = <String>{};
  final all = [...current, ...incoming];
  // a stable sort, newest first (as Array.prototype.sort is)
  final indexed = [for (var i = 0; i < all.length; i++) (i, all[i])]
    ..sort((x, y) {
      final c = y.$2.at.compareTo(x.$2.at);
      return c != 0 ? c : x.$1.compareTo(y.$1);
    });
  return [
    for (final (_, a) in indexed)
      if (seen.add(_keyOf(a))) a,
  ];
}

enum NextStep { reveal, fetch, done }

/// What to do when the end of the list is reached: show more of what is already here, ask the computer for older entries, or
/// nothing. An older computer ignores page sizes and sends everything at once, so [serverMore] is null and only the first applies.
NextStep nextStep(int loaded, int shown, bool? serverMore) {
  if (shown < loaded) return NextStep.reveal;
  return serverMore == true ? NextStep.fetch : NextStep.done;
}

String? oldest(List<ActivityItem> items) => items.isEmpty ? null : items.last.at;
