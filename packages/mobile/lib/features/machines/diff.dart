/// A line-level diff for the Edit tool's old/new text (diff.ts).
library;

enum DiffType { ctx, add, del }

class DiffLine {
  const DiffLine(this.type, this.text);
  final DiffType type;
  final String text;

  @override
  bool operator ==(Object other) => other is DiffLine && other.type == type && other.text == text;
  @override
  int get hashCode => Object.hash(type, text);
  @override
  String toString() => '${type.name}:$text';
}

/// Minimal O(N*M) LCS diff: old_string/new_string in Edit calls are a few lines to a few dozen. Very large inputs
/// (a whole file) fall back to "all removed, all added" rather than allocating a huge table.
List<DiffLine> diffLines(String oldText, String newText) {
  final a = oldText.split('\n');
  final b = newText.split('\n');
  final n = a.length;
  final m = b.length;
  if (n * m > 4000000) {
    return [for (final l in a) DiffLine(DiffType.del, l), for (final l in b) DiffLine(DiffType.add, l)];
  }
  final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : (lcs[i + 1][j] > lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final out = <DiffLine>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      out.add(DiffLine(DiffType.ctx, a[i]));
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      out.add(DiffLine(DiffType.del, a[i]));
      i++;
    } else {
      out.add(DiffLine(DiffType.add, b[j]));
      j++;
    }
  }
  while (i < n) {
    out.add(DiffLine(DiffType.del, a[i++]));
  }
  while (j < m) {
    out.add(DiffLine(DiffType.add, b[j++]));
  }
  return out;
}

({int additions, int removals}) diffStat(List<DiffLine> lines) {
  var additions = 0;
  var removals = 0;
  for (final l in lines) {
    if (l.type == DiffType.add) {
      additions++;
    } else if (l.type == DiffType.del) {
      removals++;
    }
  }
  return (additions: additions, removals: removals);
}
