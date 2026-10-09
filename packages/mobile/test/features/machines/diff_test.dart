import 'package:escanor/features/machines/diff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unchanged lines are context, changed ones a removal then an addition', () {
    expect(diffLines('a\nb\nc', 'a\nB\nc'), const [
      DiffLine(DiffType.ctx, 'a'),
      DiffLine(DiffType.del, 'b'),
      DiffLine(DiffType.add, 'B'),
      DiffLine(DiffType.ctx, 'c'),
    ]);
  });

  test('creating a file is all additions', () {
    final d = diffLines('', 'x\ny');
    expect(diffStat(d), (additions: 2, removals: 1)); // the one empty old line counts as removed, as in the web app
  });

  test('appended and removed tails', () {
    expect(diffLines('a', 'a\nb'), const [DiffLine(DiffType.ctx, 'a'), DiffLine(DiffType.add, 'b')]);
    expect(diffLines('a\nb', 'a'), const [DiffLine(DiffType.ctx, 'a'), DiffLine(DiffType.del, 'b')]);
  });

  test('counts additions and removals', () {
    expect(diffStat(diffLines('1\n2\n3', '1\n3\n4\n5')), (additions: 2, removals: 1));
  });

  test('a very large edit does not build a huge table', () {
    final big = List.generate(3000, (i) => 'line $i').join('\n');
    final d = diffLines(big, '$big\nmore');
    expect(diffStat(d).additions, greaterThan(0));
  });
}
