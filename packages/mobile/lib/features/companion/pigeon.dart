/// Riti the pigeon: grey, with a green and purple sheen on the neck and an orange eye. Built from ovals like the
/// hamster, with the same scenes: `run` (a bobbing walk after a crumb), `sniff` (pecking at the ground), `dig`
/// (scratching up a crumb), `sit` (perched, cooing), `sleep` (puffed up, head tucked in), `lick` (pecking at the glass),
/// `react` (puffing up and flapping) and `home` (a window ledge).
library;

import 'dart:math' as math;

import 'pix.dart';
import 'sprites.dart' show Scene, heartStamp, zStamp, lickSweep;

void _ground(Pix p, [int scroll = 0]) {
  for (var x = 0; x < W; x++) {
    p.px(x, groundY, 'l');
  }
  for (var x = 0; x < W; x++) {
    if ((x + scroll) % 7 == 0) p.px(x, groundY + 1, 'l');
  }
}

void _crumb(Pix p, num x, num y) => p.stamp(x, y, const ['xx', 'xX']);

class _Pose {
  const _Pose({this.hx = 0, this.hy = 0, this.lift = 0, this.legs = 0, this.dx = 0, this.dy = 0, this.beak = 'closed', this.tail = 0});

  /// Where the head is, relative to a standing pigeon (0, 0). Negative y is up.
  final num hx;
  final num hy;

  /// Body up this many pixels.
  final num lift;

  /// Legs: which phase of the walk (0 to 3).
  final int legs;

  /// Pixels to move the whole bird.
  final num dx;
  final num dy;

  /// 'closed' or 'open'.
  final String beak;

  /// Tail raised.
  final num tail;
}

/// A pigeon seen from the side, facing right.
void _sidePigeon(Pix p, _Pose o) {
  final dx = o.dx;
  final dy = o.dy - o.lift + 1;
  final hx = o.hx;
  final hy = o.hy;
  void ov(num cx, num cy, num rx, num ry, String c) => p.oval(cx + dx, cy + dy, rx, ry, c);
  void pt(num x, num y, String c) => p.px(x + dx, y + dy, c);
  void rc(num x, num y, num w, num h, String c, [bool round = false]) => p.rect(x + dx, y + dy, w, h, c, round);

  // legs and feet first, behind the body
  final legPhase = const [(0, 0), (2, -2), (0, 0), (-2, 2)][o.legs];
  for (final (i, lx) in const [(0, 13), (1, 17)]) {
    final sway = i == 0 ? legPhase.$1 : legPhase.$2;
    p.line(lx + dx + sway * 0.5, 16 + dy, lx + dx + sway, groundY - 1, 'p');
    p.rect(lx + dx + sway - 1, groundY - 1, 3, 1, 'p');
  }
  // tail, a wedge behind
  final t = o.tail;
  rc(3, 11 - t, 6, 3, 'd', true);
  rc(2, 13 - t, 4, 2, 'd');
  // body, wing, breast
  ov(14, 12, 8, 5, 'f');
  ov(21, 13, 4, 4, 'c');
  ov(13, 12, 5.5, 3, 'd');
  rc(9, 12, 8, 1, 'f');
  // neck, with the sheen, and the head
  final nx = 21 + hx * 0.5;
  final ny = 8 + hy * 0.5;
  ov(21, 9, 3.2, 4, 'f');
  if (hx != 0 || hy != 0) ov(nx, ny, 3.2, 3.2, 'f');
  ov(24 + hx, 5 + hy, 3.2, 2.8, 'f');
  rc(20 + jsRound(hx * 0.4), 7 + jsRound(hy * 0.5), 3, 2, 'M');
  rc(22 + jsRound(hx * 0.6), 8 + jsRound(hy * 0.5), 2, 2, 'N');
  // beak, eye
  rc(27 + hx, 5 + hy, 3, 2, 'y');
  pt(27 + hx, 5 + hy, 'c');
  if (o.beak == 'open') pt(29 + hx, 7 + hy, 'y');
  pt(25 + hx, 4 + hy, 'u');
  pt(25 + hx, 4 + hy, 'n');
  pt(24 + hx, 4 + hy, 'u');
}

// ------------------------------------------------------------------------------------------------------------------- run

List<Frame> _run() {
  const poses = [_Pose(legs: 1, hx: 2, lift: 0), _Pose(legs: 0, hx: 0, lift: 1), _Pose(legs: 3, hx: -1, lift: 0), _Pose(legs: 0, hx: 0, lift: 1)];
  return [
    for (var i = 0; i < poses.length; i++)
      () {
        final pose = poses[i];
        final p = Pix();
        _sidePigeon(p, _Pose(legs: pose.legs, hx: pose.hx, lift: pose.lift, dx: 0, tail: 1));
        p.outline();
        _ground(p, i * 2);
        _crumb(p, 31, groundY - const [3, 5, 6, 5][i]);
        p.rect(0, 9, 3, 1, 'g');
        p.rect(1, 12, 2, 1, 'g');
        return p.frame();
      }(),
  ];
}

// ----------------------------------------------------------------------------------------------------------------- sniff

/// Pecking: head up, then down to the ground, then up with a crumb.
List<Frame> _sniff() {
  const heads = <({int hx, int hy, int legs, bool open})>[
    (hx: 0, hy: 0, legs: 0, open: false),
    (hx: 3, hy: 5, legs: 1, open: false),
    (hx: 4, hy: 10, legs: 1, open: true),
    (hx: 2, hy: 4, legs: 0, open: false),
  ];
  return [
    for (var i = 0; i < heads.length; i++)
      () {
        final h = heads[i];
        final p = Pix();
        _sidePigeon(p, _Pose(hx: h.hx, hy: h.hy, legs: h.legs, dx: 0, beak: h.open ? 'open' : 'closed', tail: i == 2 ? 2 : 0));
        p.outline();
        _ground(p, i * 2);
        if (i < 3) {
          _crumb(p, 30, groundY - 2);
        } else {
          p.px(29, 12, 'x');
        }
        for (final (x, y) in const [(30, 17), (32, 16)].take(i)) {
          p.px(x, y, 's');
        }
        return p.frame();
      }(),
  ];
}

// ------------------------------------------------------------------------------------------------------------------- dig

/// Scratching up a crumb: head down at a hole, a foot kicking dirt back, and the crumb comes up.
List<Frame> _dig() {
  final frames = <Frame>[];
  const up = 2;
  const gy = groundY - up;
  for (var i = 0; i < 12; i++) {
    final p = Pix();
    final near = i.isEven;
    final depth = math.min(1 + i ~/ 2, 4);
    p.rect(24, gy, 11, depth + 1, 'E');
    p.rect(25, gy + depth + 1, 9, 1, 'E');
    p.px(23, gy, 'e');
    p.px(35, gy, 'e');
    _sidePigeon(p, _Pose(hx: 4, hy: near ? 12 : 10, dx: 0, dy: -up, legs: near ? 1 : 3, beak: near ? 'open' : 'closed', tail: 2));
    p.outline();
    const flying = [(16, gy - 2), (12, gy - 6), (8, gy - 8), (4, gy - 6), (2, gy - 2)];
    for (var k = 0; k < 3; k++) {
      final (x, y) = flying[(i + k) % 5];
      p.px(x, y, k == 0 ? 'e' : 'E');
      p.px(x + 1, y, 'e');
    }
    for (var x = 0; x < 24; x++) {
      p.px(x, gy, 'l');
    }
    for (var x = 35; x < W; x++) {
      p.px(x, gy, 'l');
    }
    for (var x = 0; x < 24; x++) {
      if ((x + i) % 7 == 0) p.px(x, gy + 1, 'l');
    }
    if (i >= 9) {
      final rise = i == 9 ? 0 : i == 10 ? 3 : 5;
      p.stamp(28, gy - rise - 1, const ['.xx.', 'xxxX', 'xXXX']);
      p.rect(26, gy, 8, 1, 'E');
      if (i >= 10) {
        p.px(26, gy - 7, 's');
        p.px(33, gy - 8, 's');
        p.px(34, gy - 5, 's');
      }
    }
    frames.add(p.frame());
  }
  return frames;
}

// --------------------------------------------------------------------------------------------------------------------- sit

/// Perched on a branch, puffed up, cooing: a heart for each coo.
List<Frame> _sit() {
  final frames = <Frame>[];
  const beats = <({int puff, int heart, bool blink, int bob})>[
    (puff: 0, heart: 0, blink: false, bob: 0),
    (puff: 1, heart: 1, blink: false, bob: 1),
    (puff: 1, heart: 2, blink: false, bob: 0),
    (puff: 0, heart: 3, blink: true, bob: 1),
    (puff: 0, heart: 4, blink: false, bob: 0),
    (puff: 1, heart: 0, blink: false, bob: 1),
  ];
  for (final (:puff, :heart, :blink, :bob) in beats) {
    final p = Pix();
    // the branch
    p.rect(2, 17, 28, 2, 'e');
    p.rect(2, 18, 28, 1, 'E');
    p.rect(24, 15, 2, 2, 'e');
    // a plump body leaning back, tail down behind
    p.rect(5, 11, 5, 6, 'd', true);
    p.oval(14, 11, 7.5 + puff * 0.5, 6 + puff * 0.5, 'f');
    p.oval(19, 12, 4.5, 4.5, 'c');
    p.oval(13, 11, 5, 3.5, 'd');
    p.rect(9, 12, 8, 1, 'f');
    // neck and head, a little higher than when walking
    p.oval(21, 8 + bob, 3.4, 4, 'f');
    p.oval(23, 5 + bob, 3.4, 3, 'f');
    p.rect(19, 7 + bob, 3, 2, 'M');
    p.rect(21, 8 + bob, 2, 2, 'N');
    p.rect(26, 5 + bob, 3, 2, 'y');
    p.px(26, 5 + bob, 'c');
    if (blink) {
      p.rect(23, 4 + bob, 2, 1, 'n');
    } else {
      p.px(24, 4 + bob, 'n');
      p.px(23, 4 + bob, 'u');
    }
    // feet on the branch
    p.line(13, 17, 13, 16, 'p');
    p.line(17, 17, 17, 16, 'p');
    p.rect(12, 16, 3, 1, 'p');
    p.rect(16, 16, 3, 1, 'p');
    p.outline();
    if (heart > 0) p.stamp(29, 3 - math.min(heart - 1, 2), heartStamp);
    frames.add(p.frame());
  }
  return frames;
}

// ------------------------------------------------------------------------------------------------------------------ sleep

List<Frame> _sleep() {
  Frame make(int breath, int zs) {
    final p = Pix();
    // a feathered ball, its head turned back and tucked in
    p.rect(4, 12, 6, 4, 'd', true);
    p.oval(17, 13 - breath * 0.5, 10, 6 + breath * 0.5, 'f');
    p.oval(21, 15, 6, 3, 'c');
    p.oval(16, 12 - breath * 0.5, 7, 4, 'd');
    p.rect(10, 12, 12, 1, 'f');
    p.oval(24, 9, 3.4, 3, 'f');
    p.rect(21, 11, 3, 2, 'M');
    p.rect(25, 8, 3, 2, 'y');
    p.rect(22, 8, 2, 1, 'n'); // closed eye
    // one foot showing
    p.line(15, 18, 15, 19, 'p');
    p.rect(14, 19, 3, 1, 'p');
    p.outline();
    _ground(p);
    if (zs > 0) p.stamp(28, 4 - (zs - 1) * 2 + 1, zStamp);
    if (zs > 1) p.px(25, 5 - zs + 3, 'z');
    return p.frame();
  }

  return [make(0, 0), make(0, 1), make(1, 2), make(1, 3), make(0, 3), make(0, 2), make(1, 1), make(1, 0)];
}

// ------------------------------------------------------------------------------------------------------------------ lick

const int _ly = 2;

/// Face to the glass, tapping at it with its beak.
List<Frame> _lick() {
  final frames = <Frame>[];
  final taps = <(int, int)>[];
  for (var i = 0; i < lickSweep.length; i++) {
    final (tx, len) = lickSweep[i];
    final p = Pix();
    final shift = jsRound((tx - 16) / 4); // the head follows the pecking
    void q(num x, num y, String c) => p.px(x + shift, y + _ly, c);
    void ov(num cx, num cy, num rx, num ry, String c) => p.oval(cx + shift, cy + _ly, rx, ry, c);
    void rc(num x, num y, num w, num h, String c, [bool round = false]) => p.rect(x + shift, y + _ly, w, h, c, round);
    // the neck's sheen below, the round head, and the eyes with their orange rings
    ov(18, 15, 8, 2.4, 'f');
    rc(10, 13, 6, 3, 'M');
    rc(20, 13, 6, 3, 'N');
    rc(15, 14, 6, 2, 'M');
    ov(18, 9, 9, 7.5, 'f');
    ov(18, 12, 6, 4, 'c');
    ov(12, 8, 2.4, 2.4, 'u');
    ov(24, 8, 2.4, 2.4, 'u');
    rc(12, 7, 2, 3, 'n');
    rc(22, 7, 2, 3, 'n');
    q(12, 7, 'w');
    q(22, 7, 'w');
    // the beak, pushed out as it taps
    final push = len > 2 ? 1 : 0;
    rc(16, 10 + push, 4, 3, 'y');
    rc(16, 10 + push, 4, 1, 'c');
    q(17, 12 + push, 'n');
    p.outline();
    // where it has tapped, marks on the glass
    if (len >= 3) taps.add((tx, 14));
    final a = taps.length > 4 ? taps.sublist(taps.length - 4) : taps;
    for (var k = 0; k < a.length; k++) {
      final (x, y) = a[k];
      p.px(x + shift, y + _ly + 2, k == a.length - 1 ? 'q' : 'g');
      p.px(x + shift + 1, y + _ly + 3, k == a.length - 1 ? 'q' : 'g');
    }
    p.px(2, 2, 'w');
    p.px(3, 2, 'w');
    p.px(2, 3, 'w');
    if (len == 4 && i % 3 == 0) p.px(31, 4, 's');
    frames.add(p.frame());
  }
  return frames;
}

// ------------------------------------------------------------------------------------------------------------------- react

/// Tapped: it puffs up and flaps, hops, and coos, with feathers coming loose.
List<Frame> _react() {
  const beats = <({int wing, int lift, int hy})>[
    (wing: 0, lift: 0, hy: 0),
    (wing: 1, lift: 1, hy: 0),
    (wing: 2, lift: 1, hy: 0),
    (wing: 1, lift: 1, hy: 2),
    (wing: 0, lift: 0, hy: 3),
    (wing: 1, lift: 1, hy: 0),
    (wing: 2, lift: 1, hy: 0),
    (wing: 0, lift: 0, hy: 0),
  ];
  return [
    for (var i = 0; i < beats.length; i++)
      () {
        final b = beats[i];
        final p = Pix();
        _sidePigeon(p, _Pose(hx: 1, hy: b.hy, lift: b.lift, legs: 0, beak: i.isOdd ? 'open' : 'closed', tail: 2));
        // the wing: raised and spread over the back, then down
        if (b.wing > 0) {
          p.oval(12, 9 - b.lift - b.wing, 7, 1.8 + b.wing * 0.4, 'd');
          p.oval(11, 9 - b.lift - b.wing * 1.2, 5, 1.2 + b.wing * 0.4, 'f');
        }
        p.outline();
        _ground(p, i);
        // loose feathers and the "coo" notes
        for (var k = 0; k < 3; k++) {
          p.px(6 + k * 4 + (i % 2), 4 + ((i + k * 2) % 6), 'g');
        }
        if (i.isOdd) p.stamp(29, 2, const ['.hh', '.h.', 'hh.']);
        return p.frame();
      }(),
  ];
}

// ---------------------------------------------------------------------------------------------------------------------- home

/// At home: a window ledge, a brick wall behind, a pot with a plant, and crumbs to peck at.
List<Frame> _home() => List.generate(8, (i) {
      final p = Pix();
      // the wall: bricks in rows
      for (var y = 2; y < 19; y++) {
        for (var x = 0; x < W; x++) {
          final row = y ~/ 3;
          final off = row.isOdd ? 4 : 0;
          p.px(x, y, y % 3 == 0 || (x + off) % 8 == 0 ? 'O' : 'P');
        }
      }
      // the window on the right, with a cross frame and a bit of sky
      p.rect(23, 3, 10, 13, 'm');
      p.rect(24, 4, 8, 11, 'a');
      p.rect(27, 4, 2, 11, 'm');
      p.rect(24, 9, 8, 1, 'm');
      p.px(25, 5, 'w');
      p.px(26, 6, 'w');
      // the ledge: a thick stone slab along the bottom
      p.rect(0, 19, W, 3, 'i');
      p.rect(0, 21, W, 1, 'I');
      // a flower pot in the corner
      p.rect(2, 13, 5, 1, 'R');
      p.rect(3, 14, 3, 5, 'r');
      for (final (x, y) in const [(4, 8), (3, 9), (5, 9), (4, 10), (2, 10), (6, 10), (4, 11), (4, 12)]) {
        p.px(x, y, (x + y).isOdd ? 'G' : 'Y');
      }
      p.px(4, 7, i.isOdd ? 'h' : 'S');
      // the pigeon, pecking at the crumbs on the ledge
      final hy = const [0, 2, 8, 8, 2, 0, 0, 0][i];
      final bird = Pix();
      _sidePigeon(bird, _Pose(hx: hy > 4 ? 2 : 0, hy: hy, legs: i % 3 == 1 ? 1 : 0, beak: hy > 6 ? 'open' : 'closed', tail: 0, dx: 1));
      bird.outline();
      p.stamp(0, 0, bird.frame());
      // crumbs, and one that has just been taken
      for (final x in const [27, 21, 19]) {
        p.px(x, 18, 'Q');
      }
      if (i < 3) _crumb(p, 24, 17);
      return p.frame();
    });

List<Frame> pigeonScene(Scene scene) => switch (scene) {
      Scene.run => _run(),
      Scene.sniff => _sniff(),
      Scene.dig => _dig(),
      Scene.sit => _sit(),
      Scene.sleep => _sleep(),
      Scene.lick => _lick(),
      Scene.home => _home(),
      Scene.react => _react(),
    };
