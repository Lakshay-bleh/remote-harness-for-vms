/// The four-legged companions that share the dog's skeleton: what differs is the ears, tail, snout and a few extras,
/// drawn through the hooks in [Skin]. (The hamster and the pigeon are built differently and have their own files.)
library;

import 'dart:math' as math;

import 'pix.dart';

/// Whether a tail path is held up (rising from its root) or low and flat along the ground.
bool _rising(List<(num, num)> path) => path.last.$2 < path.first.$2;

/// The head's top-left corner, from where the dog's ear starts: the ears of the other animals sit on top of the head.
({num hx, num ht, num w}) _headOrigin(View view, num x, num y, bool blown) => switch (view) {
      View.side => (hx: 19, ht: blown ? y : y - 1, w: 7),
      View.sit => (hx: x + 1, ht: y - 1, w: 8),
      View.sleep => (hx: x + 2, ht: y, w: 7),
      View.dig => (hx: x + 1, ht: y, w: 7),
      _ => (hx: x, ht: y, w: 7),
    };

// ------------------------------------------------------------------------------------------------------------------- cat

/// A pointed ear standing on the head: three rows tall, a pink inside. `lean` tips it back (running into the wind).
void _pointEar(Brush b, num tx, num ht, [int lean = 0, bool tall = true]) {
  b.r(tx, ht - 1, 3, 2, 'f');
  b.p(tx + 1, ht - 1, 't');
  if (!tall) return;
  b.r(tx + lean, ht - 2, 3, 1, 'f');
  b.p(tx + 1 + lean * 2, ht - 3, 'f');
  if (lean != 0) b.p(tx + lean * 3, ht - 2, 'f');
  b.p(tx + 1 + lean, ht - 2, 't');
}

final Skin catSkin = Skin(
  ear: (b, view, x, y, o) {
    if (view == View.front) {
      // the two ears on the corners of the face, pointing up
      final left = o.side == 'left';
      final tx = left ? 9 : 22;
      b.r(tx + 1, 0, 3, 1, 'f');
      b.r(tx, 1, 5, 2, 'f');
      b.r(tx + 1, 1, 3, 1, 't');
      return;
    }
    final h = _headOrigin(view, x, y, o.blown);
    _pointEar(b, h.hx + 1, h.ht, o.blown ? -1 : 0, view != View.sit);
    _pointEar(b, h.hx + 4, h.ht, o.blown ? -1 : 0, view != View.sit);
  },
  tail: (path, view) {
    final last = path.last;
    final cells = <Cell>[for (final (x, y) in path) (x, y, 'f')];
    if (view == View.sleep) {
      return [for (var i = 0; i < cells.length; i++) (cells[i].$1, cells[i].$2, i == cells.length - 1 ? 'd' : cells[i].$3)];
    }
    final List<(num, num)> extra = view == View.dig
        ? const []
        : _rising(path)
            ? [(last.$1, last.$2 - 1), (last.$1 + 1, last.$2 - 2), (last.$1 + 2, last.$2 - 2)]
            : [(last.$1 - 1, last.$2), (last.$1 - 2, last.$2 - 1), (last.$1 - 2, last.$2 - 2)];
    for (final (x, y) in extra) {
      cells.add((x, y, 'f'));
    }
    final n = cells.length;
    cells[n - 1] = (cells[n - 1].$1, cells[n - 1].$2, 'd');
    cells[n - 2] = (cells[n - 2].$1, cells[n - 2].$2, 'd');
    return cells;
  },
  snout: (b, view, x, y) {
    if (view == View.front) {
      for (final (dx, dy) in const [(-4, 3), (-3, 2), (-4, 5), (-2, 4)]) {
        b.p(x + dx, y + dy, 'w');
      }
      for (final (dx, dy) in const [(11, 3), (12, 2), (13, 5), (12, 4)]) {
        b.p(x + dx, y + dy, 'w');
      }
      return;
    }
    b.p(x + 4, y + 1, 'w');
    b.p(x + 5, y + 2, 'w');
    b.p(x + 4, y + 3, 'w');
  },
  body: (b, view, x, y, w, h) {
    // tabby stripes down the back
    final n = view == View.side ? 4 : view == View.dig ? 3 : 2;
    for (var i = 0; i < n; i++) {
      b.r(x + 2 + i * math.max(2, ((w - 3) / n).floor()), y, 1, math.min(2, h), 'd');
    }
  },
);

// --------------------------------------------------------------------------------------------------------------- unicorn

/// The horn: gold with a bright edge, leaning forward from the forehead.
void _horn(Brush b, num bx, num by, [bool tall = true]) {
  b.r(bx, by - 1, 2, 2, 'H');
  if (tall) {
    b.r(bx, by - 2, 2, 1, 'H');
    b.p(bx + 1, by - 3, 'H');
  }
  if (tall) b.p(bx, by - 2, 'w');
}

final Skin unicornSkin = Skin(
  ear: (b, view, x, y, o) {
    if (view == View.front) {
      final left = o.side == 'left';
      final tx = left ? 9 : 23;
      b.r(tx, 0, 4, 4, 'f', true);
      b.p(tx + 1 + (left ? 0 : 1), 1, 't');
      b.p(tx + 1 + (left ? 0 : 1), 2, 't');
      return;
    }
    final h = _headOrigin(view, x, y, o.blown);
    // a small ear beside the horn
    if (view == View.sit) {
      b.r(h.hx + 1, h.ht - 1, 2, 2, 'f');
    } else {
      b.r(h.hx + 1, h.ht - 2, 2, 3, 'f');
    }
    b.p(h.hx + 1, h.ht - 1, 't');
  },
  head: (b, view, x, y, w, h) {
    if (view == View.front) {
      _horn(b, x + w / 2 - 1, y + 1);
      // the forelock falls over the forehead, in the mane's colours
      b.r(x + 2, y + 1, 3, 4, 'M', true);
      b.r(x + w - 5, y + 1, 3, 4, 'N', true);
      b.p(x + 3, y + 3, 'N');
      b.p(x + w - 4, y + 3, 'M');
      return;
    }
    _horn(b, x + w - 3, y, view != View.sit);
    // the mane runs down the back of the neck
    for (var i = 0; i < math.min(8, 17 - y); i++) {
      b.r(x - 2, y + 1 + i, 2, 1, i.isOdd ? 'N' : 'M');
      if (i < 5) b.p(x + 1, y + 1 + i, i.isOdd ? 'M' : 'N');
    }
    b.p(x + w - 2, y + 1, 'M');
  },
  tail: (path, view) {
    final cells = <Cell>[];
    for (var i = 0; i < path.length; i++) {
      final (x, y) = path[i];
      cells.add((x, y, i.isOdd ? 'N' : 'M'));
      cells.add((view == View.sleep ? x : x + 1, view == View.sleep ? y + 1 : y, i.isOdd ? 'M' : 'N'));
    }
    final last = path.last;
    if (view != View.dig) cells.add((last.$1, last.$2 - 1, 'M'));
    return cells;
  },
);

// -------------------------------------------------------------------------------------------------------------- elephant

final Skin elephantSkin = Skin(
  ear: (b, view, x, y, o) {
    if (view == View.front) {
      final left = o.side == 'left';
      b.r(left ? 2 : 26, 1, 8, 12, 'd', true);
      b.r(left ? 3 : 27, 3, 5, 8, 'f', true);
      return;
    }
    // one big ear, flapping back from the head
    final lift = o.blown ? -2 : 0;
    final eh = math.min(9, 19 - y);
    b.r(x - 3, y - 1 + lift, 7, eh, 'd', true);
    b.r(x - 2, y + lift, 4, math.max(2, eh - 3), 'c', true);
  },
  snout: (b, view, x, y) {
    if (view == View.front) {
      b.r(x + 2, y - 1, 6, 9, 'f', true);
      for (var r = 0; r < 3; r++) {
        b.r(x + 3, y + r * 3 + 1, 4, 1, 'd');
      }
      return;
    }
    // the trunk: out from the muzzle and curling down
    final List<(int, int)> pts = view == View.sit ? const [(1, 1), (2, 3), (2, 5), (1, 7), (0, 8)] : const [(1, 1), (3, 2), (4, 4), (4, 6), (3, 8)];
    final reach = pts.where((p) => !(view == View.side || view == View.sleep) || y + p.$2 <= 16).toList();
    for (var i = 0; i < reach.length; i++) {
      b.r(x + reach[i].$1, y + reach[i].$2, 2, 2, i == reach.length - 1 ? 'c' : i.isOdd ? 'f' : 'd');
    }
    // a small white tusk
    b.p(x + 1, y + 3, 'w');
  },
  tail: (path, view) {
    final first = path.take(3).toList();
    if (view == View.sleep) {
      return [for (var i = 0; i < first.length; i++) (first[i].$1, first[i].$2, i == 2 ? 'd' : 'f')];
    }
    final cells = <Cell>[for (final (x, y) in first) (x, y, 'f')];
    final last = path[math.min(2, path.length - 1)];
    cells.add((last.$1, last.$2 + 1, 'd'));
    return cells;
  },
);
