/// Bubbly the hamster: round, with cheeks full of seeds. Drawn from ovals rather than the dog's skeleton, but with the
/// same scenes: `run` on a wheel, `sniff` after a seed, `dig` a burrow, `sit` nibbling a seed, `sleep` in a ball,
/// `lick` the glass, `react` when tapped and `home` in its cage.
library;

import 'dart:math' as math;

import 'pix.dart';
import 'sprites.dart' show Scene, heartStamp, zStamp, lickSweep, drawTrail;

void _ground(Pix p, [int scroll = 0]) {
  for (var x = 0; x < W; x++) {
    p.px(x, groundY, 'l');
  }
  for (var x = 0; x < W; x++) {
    if ((x + scroll) % 7 == 0) p.px(x, groundY + 1, 'l');
  }
}

/// A sunflower seed lying at a position.
void _seed(Pix p, num x, num y) => p.stamp(x, y, const ['.xx.', 'xxxX', '.XX.']);

// ------------------------------------------------------------------------------------------------------------------- run

/// On the wheel: the wheel turns (its spokes move), the hamster runs on the spot.
List<Frame> _run() {
  final frames = <Frame>[];
  const cx = 18;
  const cy = 10;
  const r = 9;
  for (var i = 0; i < 6; i++) {
    final p = Pix();
    // the stand
    p.line(cx, cy, cx - 6, groundY - 1, 'l');
    p.line(cx, cy, cx + 6, groundY - 1, 'l');
    // the wheel: a ring, and spokes that turn
    for (var a = 0; a < 72; a++) {
      final t = (a / 72) * math.pi * 2;
      p.px(cx + math.cos(t) * r, cy + math.sin(t) * r, 'l');
    }
    for (var k = 0; k < 4; k++) {
      final t = (k / 4) * math.pi * 2 + (i / 6) * (math.pi / 2);
      p.line(cx, cy, cx + math.cos(t) * (r - 1), cy + math.sin(t) * (r - 1), 'g');
    }
    p.px(cx, cy, 'l');
    // the hamster, bouncing a little, legs scissoring
    final bob = i % 2;
    final by = 14 - bob;
    p.oval(16, by + 1, 5, 3.4, 'f'); // body
    p.oval(16, by + 2, 3.5, 2, 'c'); // belly
    p.oval(22, by - 1, 3.4, 3, 'f'); // head
    p.oval(23, by + 1, 2, 1.6, 'c'); // cheek
    p.px(21, by - 4, 'f'); // ear
    p.px(22, by - 4, 'f');
    p.px(22, by - 3, 't');
    p.px(23, by - 1, 'n'); // eye
    p.px(23, by - 2, 'w');
    p.px(25, by, 't'); // nose
    // legs: front reach forward, back push back, swapping
    final f = i % 3;
    p.rect(20 + (f == 0 ? 2 : f == 1 ? 0 : -1), by + 3, 2, 2, 'c');
    p.rect(12 + (f == 0 ? -2 : f == 1 ? 0 : 1), by + 3, 2, 2, 'c');
    p.rect(17 + (f == 0 ? 0 : f == 1 ? 2 : -1), by + 4, 2, 1, 'f');
    p.outline();
    _ground(p);
    frames.add(p.frame());
  }
  return frames;
}

// ----------------------------------------------------------------------------------------------------------------- sniff

List<Frame> _sniff() {
  final frames = <Frame>[];
  for (var i = 0; i < 4; i++) {
    final p = Pix();
    final step = const [0, 1, 0, -1][i];
    // body
    p.oval(13, 15, 7, 4.5, 'f');
    p.oval(13, 17, 5, 2, 'c');
    p.oval(11, 13, 3, 2, 'd');
    // head low, nose to the ground, twitching
    p.oval(21, 16, 4, 3.5, 'f');
    p.oval(23, 17, 2.4, 2, 'c');
    p.px(20, 12, 'f');
    p.px(21, 12, 'f');
    p.px(20, 13, 't');
    p.px(23, 15, 'n');
    p.px(23, 14, 'w');
    p.px(26 + (i % 2), 18, 't'); // nose
    // little legs walking
    p.rect(8 + step, 18, 2, 2, 'c');
    p.rect(12 - step, 19, 2, 1, 'f');
    p.rect(17 + step, 18, 2, 2, 'c');
    p.rect(20 - step, 19, 2, 1, 'f');
    p.outline();
    _ground(p, i * 2);
    // the seed it is after, and the scent drifting up
    _seed(p, 29, groundY - 3);
    const s = [(27, 16), (28, 14), (27, 12), (29, 11)];
    for (var k = 0; k <= i; k++) {
      p.px(s[k].$1, s[k].$2 - (i - k), k == i ? 's' : 'g');
    }
    frames.add(p.frame());
  }
  return frames;
}

// ------------------------------------------------------------------------------------------------------------------- dig

List<Frame> _dig() {
  final frames = <Frame>[];
  const up = 3;
  const gy = groundY - up;
  for (var i = 0; i < 12; i++) {
    final p = Pix();
    final near = i.isEven;
    final bob = near ? 0 : 1;
    const by = gy - 1;
    final depth = math.min(1 + i ~/ 2, 4);
    p.rect(21, gy, 13, depth + 1, 'E');
    p.rect(22, gy + depth + 1, 11, 1, 'E');
    p.px(20, gy, 'e');
    p.px(34, gy, 'e');
    // rump up, head down at the hole
    p.oval(10, by - 4 + 0, 7, 5, 'f');
    p.oval(10, by - 2, 4, 2.5, 'c');
    p.oval(8, by - 6, 3, 1.6, 'd');
    p.oval(18, by - 2 + bob, 4, 3.5, 'f');
    p.oval(20, by - 1 + bob, 2.4, 2, 'c');
    p.px(17, by - 6 + bob, 'f');
    p.px(18, by - 6 + bob, 'f');
    p.px(17, by - 5 + bob, 't');
    p.px(20, by - 3 + bob, 'n');
    p.px(20, by - 4 + bob, 'w');
    p.px(23, by - 1 + bob, 't');
    // back feet, and front paws scooping into the hole
    p.rect(6, by, 3, 1, 'c');
    p.rect(11, by, 3, 1, 'c');
    p.rect(near ? 19 : 17, by - 1, 3, 2, 'c');
    p.rect(near ? 15 : 17, by, 2, 1, 'c');
    p.outline();
    // dirt flying backward
    const flying = [(14, gy - 8), (11, gy - 11), (8, gy - 12), (5, gy - 9), (3, gy - 5)];
    for (var k = 0; k < 3; k++) {
      final (x, y) = flying[(i + k) % 5];
      p.px(x, y, k == 0 ? 'e' : 'E');
      p.px(x + 1, y, 'e');
    }
    for (var x = 0; x < 21; x++) {
      p.px(x, gy, 'l');
    }
    for (var x = 35; x < W; x++) {
      p.px(x, gy, 'l');
    }
    for (var x = 0; x < 21; x++) {
      if ((x + i) % 7 == 0) p.px(x, gy + 1, 'l');
    }
    // the seed, at the end
    if (i >= 9) {
      final rise = i == 9 ? 0 : i == 10 ? 3 : 5;
      _seed(p, 26, gy - rise - 1);
      p.rect(23, gy, 11, 1, 'E');
      if (i >= 10) {
        p.px(23, gy - 7, 's');
        p.px(30, gy - 8, 's');
        p.px(32, gy - 5, 's');
      }
    }
    frames.add(p.frame());
  }
  return frames;
}

// --------------------------------------------------------------------------------------------------------------------- sit

/// Sitting up, a seed between its paws, nibbling, cheeks puffed.
List<Frame> _sit() {
  final frames = <Frame>[];
  const beats = <({int nib, int heart, bool blink})>[
    (nib: 0, heart: 0, blink: false),
    (nib: 1, heart: 1, blink: false),
    (nib: 0, heart: 2, blink: false),
    (nib: 1, heart: 3, blink: true),
    (nib: 0, heart: 4, blink: false),
    (nib: 1, heart: 0, blink: false),
  ];
  for (final (:nib, :heart, :blink) in beats) {
    final p = Pix();
    final hy = nib; // the head dips as it nibbles
    // body, belly, feet
    p.oval(16, 13, 7, 5.6, 'f');
    p.oval(16, 14, 4.5, 4, 'c');
    p.rect(10, 19, 4, 1, 't');
    p.rect(18, 19, 4, 1, 't');
    // head with puffed cheeks
    p.oval(16, 7 + hy, 6, 5, 'f');
    p.oval(11, 9 + hy, 3, 2.6, 'c');
    p.oval(21, 9 + hy, 3, 2.6, 'c');
    // ears
    p.rect(10, 2 + hy, 3, 3, 'f', true);
    p.rect(19, 2 + hy, 3, 3, 'f', true);
    p.px(11, 3 + hy, 't');
    p.px(20, 3 + hy, 't');
    // face
    if (blink) {
      p.rect(12, 7 + hy, 2, 1, 'n');
      p.rect(18, 7 + hy, 2, 1, 'n');
    } else {
      p.rect(12, 6 + hy, 2, 2, 'n');
      p.rect(18, 6 + hy, 2, 2, 'n');
      p.px(12, 6 + hy, 'w');
      p.px(18, 6 + hy, 'w');
    }
    p.rect(15, 9 + hy, 2, 1, 't');
    p.px(16, 10 + hy, 'n');
    // paws holding the seed up
    p.rect(11, 12 + hy, 2, 2, 'c');
    p.rect(19, 12 + hy, 2, 2, 'c');
    _seed(p, 14, 12 + hy);
    p.outline();
    _ground(p);
    if (heart > 0) p.stamp(26, 4 - math.min(heart - 1, 3), heartStamp);
    frames.add(p.frame());
  }
  return frames;
}

// ------------------------------------------------------------------------------------------------------------------ sleep

List<Frame> _sleep() {
  Frame make(int breath, int zs) {
    final p = Pix();
    // a ball of hamster, rising and falling with each breath
    p.oval(17, 13 - breath * 0.5, 10, 6 + breath * 0.5, 'f');
    p.oval(17, 16, 7, 2.6, 'c');
    p.oval(14, 10 - breath * 0.5, 5, 2.4, 'd');
    // face tucked in at the front
    p.oval(26, 15, 3, 3, 'f');
    p.oval(27, 17, 2, 1.6, 'c');
    p.px(25, 11, 'f');
    p.px(26, 11, 'f');
    p.px(25, 12, 't');
    p.rect(25, 15, 2, 1, 'n'); // closed eye
    p.px(29, 16, 't');
    // a paw and a foot peeking out
    p.rect(22, 18, 3, 2, 'c');
    p.rect(8, 18, 3, 2, 't');
    p.outline();
    _ground(p);
    if (zs > 0) p.stamp(28, 4 - (zs - 1) * 2 + 2, zStamp);
    if (zs > 1) p.px(25, 5 - zs + 3, 'z');
    return p.frame();
  }

  return [make(0, 0), make(0, 1), make(1, 2), make(1, 3), make(0, 3), make(0, 2), make(1, 1), make(1, 0)];
}

// ------------------------------------------------------------------------------------------------------------------ lick

const int _ly = 2;

List<Frame> _lick() {
  final frames = <Frame>[];
  final trail = <(int, int)>[];
  for (var i = 0; i < lickSweep.length; i++) {
    final (tx, len) = lickSweep[i];
    final p = Pix();
    void o(num cx, num cy, num rx, num ry, String c) => p.oval(cx, cy + _ly, rx, ry, c);
    void q(num x, num y, String c) => p.px(x, y + _ly, c);
    // round ears, a round face, cheeks puffed out with seeds
    o(10, 3, 3, 3, 'f');
    o(26, 3, 3, 3, 'f');
    o(10, 3, 1.4, 1.4, 't');
    o(26, 3, 1.4, 1.4, 't');
    o(18, 9, 10, 8, 'f');
    o(9, 12, 4.5, 4, 'c');
    o(27, 12, 4.5, 4, 'c');
    o(18, 13, 4, 3, 'c');
    // eyes, nose, mouth
    p.rect(12, 7 + _ly, 2, 3, 'n');
    p.rect(22, 7 + _ly, 2, 3, 'n');
    q(12, 7, 'w');
    q(22, 7, 'w');
    p.rect(17, 10 + _ly, 2, 1, 't');
    q(18, 11, 'n');
    p.rect(16, 12 + _ly, 4, 1, 'n');
    // whiskers
    for (final (x, y) in const [(5, 11), (4, 13), (30, 11), (31, 13)]) {
      q(x, y, 'w');
    }
    if (len > 0) {
      p.rect(tx - 1, 13 + _ly, 4, len, 't', true);
      q(tx + 1, 13 + len - 1, 'T');
    }
    p.outline();
    if (len >= 3) trail.add((tx, 13 + len));
    drawTrail(p, trail, _ly);
    p.px(2, 2, 'w');
    p.px(3, 2, 'w');
    p.px(2, 3, 'w');
    if (len == 4 && i % 3 == 0) p.px(31, 4, 's');
    frames.add(p.frame());
  }
  return frames;
}

// -------------------------------------------------------------------------------------------------------------------- react

/// Tapped: it stuffs its cheeks, hops, and squeaks, spitting seeds, with its ears going.
List<Frame> _react() {
  const beats = <({int hop, double cheek, bool open})>[
    (hop: 0, cheek: 2.6, open: false),
    (hop: 1, cheek: 3.4, open: false),
    (hop: 1, cheek: 4, open: true),
    (hop: 0, cheek: 4, open: true),
    (hop: 1, cheek: 3.6, open: true),
    (hop: 0, cheek: 3, open: false),
    (hop: 1, cheek: 2.8, open: true),
    (hop: 0, cheek: 2.6, open: false),
  ];
  return [
    for (var i = 0; i < beats.length; i++)
      () {
        final (:hop, :cheek, :open) = beats[i];
        final p = Pix();
        final y = -hop;
        p.oval(16, 14.5 + y, 7, 4.6, 'f');
        p.oval(16, 15.5 + y, 4.5, 3.4, 'c');
        p.rect(10, 18, 4, 1, 't');
        p.rect(18, 18, 4, 1, 't');
        p.oval(16, 8 + y, 6, 5, 'f');
        p.oval(11, 10 + y, cheek, cheek - 0.2, 'c');
        p.oval(21, 10 + y, cheek, cheek - 0.2, 'c');
        p.rect(10, 3 + y + (i % 2), 3, 3, 'f', true);
        p.rect(19, 3 + y + ((i + 1) % 2), 3, 3, 'f', true);
        p.px(11, 4 + y + (i % 2), 't');
        p.px(20, 4 + y + ((i + 1) % 2), 't');
        p.rect(12, 7 + y, 2, 2, 'n');
        p.rect(18, 7 + y, 2, 2, 'n');
        p.px(12, 7 + y, 'w');
        p.px(18, 7 + y, 'w');
        if (open) {
          p.rect(15, 10 + y, 3, 2, 'n'); // a squeak
          p.px(16, 11 + y, 't');
        } else {
          p.rect(15, 10 + y, 2, 1, 't');
          p.px(16, 11 + y, 'n');
        }
        p.rect(11, 13 + y, 2, 2, 'c');
        p.rect(19, 13 + y, 2, 2, 'c');
        p.outline();
        _ground(p);
        // seeds spat out of its cheeks, and the "!" of a squeak
        if (open) {
          for (var k = 0; k < 3; k++) {
            p.px(24 + k * 3 + (i % 2), 6 + k * 3 - (i % 3), k.isOdd ? 'x' : 'X');
          }
        }
        if (open) p.stamp(27, 2, const ['h', 'h', 'h', '.', 'h']);
        return p.frame();
      }(),
  ];
}

// ---------------------------------------------------------------------------------------------------------------------- home

/// At home: its cage, with a wheel that turns, a water bottle, a dish of seeds and bedding. It nibbles a seed by the
/// dish.
List<Frame> _home() {
  final frames = <Frame>[];
  for (var i = 0; i < 8; i++) {
    final p = Pix();
    // the tray and the bedding
    p.rect(3, 18, 30, 2, 'm');
    for (var x = 4; x < 32; x++) {
      p.px(x, 18, (x * 5 + 2) % 7 < 3 ? 'Q' : 'W');
    }
    // the wheel on the right, spokes turning
    const cx = 25;
    const cy = 11;
    for (var a = 0; a < 72; a++) {
      final t = (a / 72) * math.pi * 2;
      p.px(cx + math.cos(t) * 6, cy + math.sin(t) * 6, 'I');
    }
    for (var k = 0; k < 3; k++) {
      final t = (k / 3) * math.pi * 2 + (i / 8) * (math.pi * 2 / 3);
      p.line(cx, cy, cx + math.cos(t) * 5.5, cy + math.sin(t) * 5.5, 'g');
    }
    p.px(cx, cy, 'I');
    p.line(cx, cy, cx - 3, 18, 'I');
    p.line(cx, cy, cx + 3, 18, 'I');
    // the dish with seeds
    p.rect(5, 16, 5, 2, 'e');
    for (final (x, y) in const [(6, 15), (8, 15), (7, 14)]) {
      p.px(x, y, 'x');
    }
    // the hamster by the dish, chewing a seed, cheeks pulsing
    final t = Pix();
    final nib = i % 2;
    final puff = i % 4 < 2 ? 0.4 : 0;
    t.oval(14, 14, 4, 3.4, 'f');
    t.oval(14, 15, 2.6, 2, 'c');
    t.oval(14, 10 + nib, 3.2, 2.8, 'f');
    t.oval(11.5, 11 + nib, 1.8 + puff, 1.7, 'c');
    t.oval(16.5, 11 + nib, 1.8 + puff, 1.7, 'c');
    t.rect(11, 7 + nib, 2, 2, 'f', true);
    t.rect(16, 7 + nib, 2, 2, 'f', true);
    t.px(12, 8 + nib, 't');
    t.px(17, 8 + nib, 't');
    if (i == 3 || i == 7) {
      t.rect(12, 10, 2, 1, 'n');
    } else {
      t.px(12, 10 + nib, 'n');
      t.px(16, 10 + nib, 'n');
    }
    t.px(14, 12 + nib, 't');
    t.rect(13, 13, 2, 1, 'x');
    t.rect(11, 16, 2, 1, 'c');
    t.rect(16, 16, 2, 1, 'c');
    t.outline();
    p.stamp(0, 0, t.frame());
    // the bottle hanging on the outside, on the left
    p.rect(1, 6, 3, 9, 'a');
    p.rect(1, 5, 3, 1, 'I');
    p.px(2, 15, 'I');
    p.px(2, 16, 'A');
    p.px(2, 9 + (i % 3), 'w');
    // the cage: a rail at the top, bars across the front (over everything), a handle
    p.rect(3, 3, 30, 1, 'I');
    p.rect(3, 2, 30, 1, 'i');
    p.rect(14, 1, 8, 1, 'I');
    for (var x = 6; x < 33; x += 4) {
      for (var y = 4; y < 18; y++) {
        p.px(x, y, y % 5 == 0 ? 'I' : 'i');
      }
    }
    p.rect(3, 4, 1, 14, 'I');
    p.rect(32, 4, 1, 14, 'I');
    _ground(p);
    frames.add(p.frame());
  }
  return frames;
}

List<Frame> hamsterScene(Scene scene) => switch (scene) {
      Scene.run => _run(),
      Scene.sniff => _sniff(),
      Scene.dig => _dig(),
      Scene.sit => _sit(),
      Scene.sleep => _sleep(),
      Scene.lick => _lick(),
      Scene.home => _home(),
      Scene.react => _react(),
    };
