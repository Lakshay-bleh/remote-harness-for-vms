// ignore_for_file: non_constant_identifier_names
/// The Escanor dog, drawn in pixels. Every frame is a grid of characters (one per pixel) built from a few shapes and
/// then outlined automatically, so a pose is "where are the head, tail and legs" rather than hundreds of hand-placed
/// dots. Nothing here touches the screen: the grids are plain data, tested for size and colours, and `PixelDog` plays
/// them.
///
/// Scenes: `run` (loading), `sniff` (looking something up), `dig` (digging up history), `sit` (all clear, wagging),
/// `sleep` (waiting for something to start), `lick` (licking the glass of the screen: "say something"), `home` (each in
/// its own place) and `react` (what it does when tapped).
library;

import 'dart:math' as math;

import 'animals.dart';
import 'extras.dart';
import 'hamster.dart';
import 'pigeon.dart';
import 'pix.dart';
import 'skins.dart';

export 'pix.dart' show W, H, Frame;

enum Scene { run, sniff, dig, sit, sleep, lick, home, react }

const List<Scene> scenes = Scene.values;

/// A scene by name ('sit', 'run', ...); anything unknown is [fallback].
Scene sceneFrom(String name, [Scene fallback = Scene.sit]) {
  for (final s in Scene.values) {
    if (s.name == name) return s;
  }
  return fallback;
}

/// One character per colour (0xRRGGBB). `.` is clear.
const Map<String, int> palette = {
  'f': 0xf2a73b, // fur
  'd': 0xc47f1f, // fur in shade (far legs, ears)
  'c': 0xfff1d1, // cream: muzzle, chest, paws
  'o': 0x2a190b, // outline
  'n': 0x17120c, // eyes and nose
  'w': 0xffffff, // shine
  't': 0xff6f91, // tongue
  'T': 0xd94a70, // tongue shade
  'e': 0x8a6038, // earth
  'E': 0x4a301a, // dark earth (the hole)
  'b': 0xf4efe6, // bone
  'B': 0xc9bba3, // bone shade
  'z': 0xaab4ff, // sleep
  'h': 0xff5d7a, // heart
  's': 0xffe9a8, // sparkle
  'k': 0x4fb3ff, // ball
  'K': 0x2a7fd0, // ball shade
  'l': 0x4b4b55, // ground
  'q': 0xcfe9ff, // smear on the glass
  'g': 0xd9d9e0, // dust
  'M': 0xff7ad9, // accent: a mane, a neck sheen
  'N': 0x7ad7ff, // accent 2
  'H': 0xffd45a, // horn
  'p': 0xff7f9c, // feet
  'y': 0xf2a73b, // beak
  'u': 0xff9d3c, // eye ring
  'j': 0x2b2f3a, // wheel and perch
  'x': 0xffe58a, // seed
  'X': 0xc9a24a, // seed shade
  'r': 0xd9534f, // roof, a toy
  'R': 0x9c3a37, // roof shade
  'a': 0x8fd3ff, // water, glass
  'A': 0x4d9fe0, // deep water
  'W': 0xd9bd8a, // wood, cardboard
  'm': 0x8a6a3c, // wood shade
  'G': 0x6fc27a, // leaf, grass
  'Y': 0x3b8f4f, // leaf shade
  'i': 0xc4ccda, // metal bars
  'I': 0x8892a6, // metal shade
  'S': 0xef6f8f, // yarn
  'Q': 0xf7e9b5, // crumb, peanut
  'P': 0xb97a4a, // brick
  'O': 0x8f5a35, // brick shade
};

const int _ox = 2;
const int _oy = 2;

enum Legs { stand, runA, runB, walkA, walkB }

enum Tail { up, mid, low }

class Side {
  const Side({required this.legs, this.tail, this.head, this.mouth = 'closed', this.lift, this.ears = 'down'});
  final Legs legs;
  final Tail? tail;

  /// Head height: 0 up, 4 level, 8 down (sniffing).
  final num? head;

  /// 'closed' or 'pant'.
  final String mouth;

  /// Whole dog up this many pixels (the airborne part of a gallop).
  final num? lift;

  /// 'down', or 'back' when the wind has blown them back.
  final String ears;
}

const Map<Tail, List<(num, num)>> _tails = {
  Tail.up: [(6, 9), (5, 8), (5, 7), (4, 6), (4, 5)],
  Tail.mid: [(6, 9), (5, 9), (4, 8), (3, 7), (3, 6)],
  Tail.low: [(6, 10), (5, 10), (4, 11), (3, 11), (2, 12)],
};

/// Leg positions for each pose: [near front, far front, near back, far back], each a path of 2x2 squares.
const Map<Legs, List<List<(num, num)>>> _legs = {
  Legs.stand: [[(18, 14), (18, 15)], [(15, 14), (15, 15)], [(8, 14), (8, 15)], [(11, 14), (11, 15)]],
  Legs.walkA: [[(19, 14), (19, 15)], [(14, 14), (14, 15)], [(7, 14), (7, 15)], [(12, 14), (12, 15)]],
  Legs.walkB: [[(16, 14), (16, 15)], [(17, 14), (17, 15)], [(10, 14), (10, 15)], [(9, 14), (9, 15)]],
  Legs.runA: [[(18, 14), (20, 15), (22, 16)], [(16, 14), (18, 15), (20, 16)], [(9, 14), (7, 15), (5, 16)], [(12, 14), (10, 15), (8, 16)]],
  Legs.runB: [[(17, 14), (16, 15), (15, 16)], [(15, 14), (14, 15), (13, 16)], [(10, 14), (11, 15), (12, 16)], [(12, 14), (13, 15), (14, 16)]],
};

/// The default tail colours: fur, with a cream tip unless [creamTip] is false.
List<Cell> _plainTail(List<(num, num)> path, {bool creamTip = true}) =>
    [for (var i = 0; i < path.length; i++) (path[i].$1, path[i].$2, i == path.length - 1 && creamTip ? 'c' : 'f')];

/// A standing, walking or running dog facing right, drawn into `p` at the standard place.
void sideDog(Pix p, Side o, Skin sk, [num dx = 0, num dy = 0]) {
  final x0 = _ox + dx;
  final y0 = _oy + dy - (o.lift ?? 0);
  void R(num x, num y, num w, num h, String c, [bool round = false]) => p.rect(x0 + x, y0 + y, w, h, c, round);
  void P(num x, num y, String c) => p.px(x0 + x, y0 + y, c);
  final hy = o.head ?? 0;
  final b = Brush(R, P);
  final legs = _legs[o.legs]!;

  // far legs first, so the body covers their tops
  for (final i in const [1, 3]) {
    final a = legs[i];
    for (var j = 0; j < a.length; j++) {
      R(a[j].$1, a[j].$2, 2, 2, j == a.length - 1 ? 'c' : 'd');
    }
  }
  // tail
  final path = _tails[o.tail ?? Tail.up]!;
  final cells = sk.tail != null ? sk.tail!(path, View.side) : _plainTail(path, creamTip: o.tail != Tail.low);
  for (final (x, y, c) in cells) {
    P(x, y, c);
  }
  // body, belly, haunch
  R(7, 8, 14, 6, 'f', true);
  R(9, 13, 10, 1, 'c');
  R(8, 10, 4, 3, 'd', true);
  sk.body?.call(b, View.side, 7, 8, 14, 6);
  // head
  R(19, 4 + hy, 7, 7, 'f', true);
  R(25, 7 + hy, 4, 4, 'c', true);
  sk.snout?.call(b, View.side, 25, 7 + hy);
  P(28, 7 + hy, 'n');
  P(23, 6 + hy, 'n');
  P(23, 5 + hy, 'w');
  if (o.mouth == 'pant') {
    R(26, 10 + hy, 2, 1, 'n');
    R(26, 11 + hy, 2, 2, 't');
    P(27, 12 + hy, 'T');
  } else {
    R(26, 10 + hy, 2, 1, 'n');
  }
  // ear
  sk.head?.call(b, View.side, 19, 4 + hy, 7, 7);
  final back = o.ears == 'back';
  if (sk.ear != null) {
    sk.ear!(b, View.side, back ? 16 : 18, back ? 4 + hy : 5 + hy, EarOpts(blown: back));
  } else if (back) {
    R(16, 4 + hy, 4, 4, 'd', true);
  } else {
    R(18, 5 + hy, 3, 6, 'd', true);
  }
  // near legs on top
  for (final i in const [0, 2]) {
    final a = legs[i];
    for (var j = 0; j < a.length; j++) {
      R(a[j].$1, a[j].$2, 2, 2, j == a.length - 1 ? 'c' : 'f');
    }
  }
  // the near legs of the standing poses are 2 squares tall: fill the gap so they read as legs, not feet
  if (o.legs == Legs.stand || o.legs == Legs.walkA || o.legs == Legs.walkB) {
    for (final i in const [0, 1, 2, 3]) {
      for (final (x, y) in legs[i]) {
        R(x, y + 1, 2, 1, i.isOdd ? 'd' : 'f');
      }
    }
  }
}

void ground(Pix p, [int scroll = 0, bool dust = false]) {
  for (var x = 0; x < W; x++) {
    p.px(x, groundY, 'l');
  }
  for (var x = 0; x < W; x++) {
    if ((x + scroll) % 7 == 0) p.px(x, groundY + 1, 'l');
  }
  if (dust) {
    p.px(1, groundY - 1, 'g');
    p.px(0, groundY - 3, 'g');
  }
}

// ---------------------------------------------------------------------------------------------------------------- run

List<Frame> _run(Skin sk) {
  Frame make(Legs legs, num lift, Tail tail, int scroll, int ball) {
    final p = Pix();
    sideDog(p, Side(legs: legs, lift: lift, tail: tail, mouth: 'pant', ears: 'back', head: 0), sk, -3, 0);
    p.outline();
    ground(p, scroll, true);
    // the ball it chases, bouncing ahead
    final by = [groundY - 4, groundY - 7, groundY - 9, groundY - 7][ball];
    p.rect(31, by, 3, 3, 'k', true);
    p.px(31, by, 'w');
    p.px(33, by + 2, 'K');
    // speed lines behind
    p.rect(0, 9, 3, 1, 'g');
    p.rect(1, 12, 2, 1, 'g');
    return p.frame();
  }

  return [make(Legs.runA, 1, Tail.up, 0, 0), make(Legs.runB, 0, Tail.mid, 2, 1), make(Legs.runA, 1, Tail.up, 4, 2), make(Legs.runB, 0, Tail.mid, 6, 3)];
}

// --------------------------------------------------------------------------------------------------------------- sniff

List<Frame> _sniff(Skin sk) {
  const legs = [Legs.walkA, Legs.stand, Legs.walkB, Legs.stand];
  return [
    for (var i = 0; i < legs.length; i++)
      () {
        final p = Pix();
        sideDog(p, Side(legs: legs[i], head: 7, tail: i.isOdd ? Tail.mid : Tail.up, mouth: 'closed'), sk, -2, 0);
        p.outline();
        ground(p, i * 2);
        // scent: a few sparkles drifting up from the ground in front of the nose
        const s = [(28, 17), (30, 16), (29, 14), (31, 13)];
        for (var j = 0; j <= i; j++) {
          p.px(s[j].$1, s[j].$2 - (i - j), j == i ? 's' : 'g');
        }
        // the nose twitches
        if (i.isOdd) p.px(27, groundY - 4, 'n');
        return p.frame();
      }(),
  ];
}

// ----------------------------------------------------------------------------------------------------------------- sit

const List<String> heartStamp = ['.h.h.', 'hhhhh', '.hhh.', '..h..'];

class Deco {
  const Deco({this.dx = 0, this.back, this.front, this.ground = true, this.hearts = true});

  /// Whole animal moves this many pixels sideways (to leave room for the scenery).
  final num dx;

  /// Drawn before the animal, so it stands in front of this. `i` is the frame number.
  final void Function(Pix p, int i)? back;

  /// Drawn after the animal and its outline.
  final void Function(Pix p, int i)? front;

  /// Draw the ground line.
  final bool ground;

  /// Hearts above the head.
  final bool hearts;
}

const List<List<(num, num)>> _sitTails = [
  [(4, 15), (3, 15), (2, 14), (1, 14)],
  [(4, 15), (3, 14), (2, 13), (1, 13)],
  [(4, 15), (3, 15), (2, 15), (1, 14)],
  [(4, 15), (3, 14), (2, 13), (2, 12)],
];

List<Frame> sit(Skin sk, [Deco deco = const Deco()]) {
  var frameNo = 0;
  Frame make(int tail, int heart, bool blink) {
    final i = frameNo++;
    final p = Pix();
    deco.back?.call(p, i);
    final ox = 3 + deco.dx;
    void R(num x, num y, num w, num h, String c, [bool round = false]) => p.rect(x + ox, y + 3, w, h, c, round);
    void P(num x, num y, String c) => p.px(x + ox, y + 3, c);
    final b = Brush(R, P);
    // tail sweeping along the ground behind
    final path = _sitTails[tail];
    for (final (x, y, c) in sk.tail != null ? sk.tail!(path, View.sit) : _plainTail(path)) {
      P(x, y, c);
    }
    // haunch, chest and back
    R(5, 9, 9, 8, 'f', true);
    R(7, 11, 4, 4, 'd', true);
    R(11, 5, 7, 12, 'f', true);
    R(16, 7, 2, 7, 'c');
    // hind paw out front, front legs
    R(12, 15, 5, 2, 'c', true);
    R(16, 13, 2, 4, 'c');
    R(14, 13, 2, 4, 'd');
    // head
    sk.body?.call(b, View.sit, 11, 5, 7, 12);
    R(14, 0, 8, 7, 'f', true);
    R(21, 3, 4, 4, 'c', true);
    sk.snout?.call(b, View.sit, 21, 3);
    P(24, 3, 'n');
    if (blink) {
      R(18, 2, 2, 1, 'n');
    } else {
      P(19, 2, 'n');
      P(19, 1, 'w');
      P(18, 2, 'n');
    }
    R(22, 6, 2, 1, 'n');
    sk.head?.call(b, View.sit, 14, 0, 8, 7);
    if (sk.ear != null) {
      sk.ear!(b, View.sit, 13, 1, const EarOpts());
    } else {
      R(13, 1, 3, 6, 'd', true);
    }
    p.outline();
    if (deco.ground) ground(p);
    deco.front?.call(p, i);
    if (heart > 0 && deco.hearts) {
      final y = 4 - math.min(heart - 1, 3);
      p.stamp(28, y, heartStamp);
    }
    return p.frame();
  }

  return [make(0, 0, false), make(1, 1, false), make(2, 2, false), make(1, 3, true), make(0, 4, false), make(3, 0, false)];
}

// --------------------------------------------------------------------------------------------------------------- sleep

const List<String> zStamp = ['zzz', '..z', '.z.', 'z..', 'zzz'];

List<Frame> _sleep(Skin sk) {
  Frame make(int breath, int zs) {
    final p = Pix();
    void R(num x, num y, num w, num h, String c, [bool round = false]) => p.rect(x + 3, y + 2, w, h, c, round);
    void P(num x, num y, String c) => p.px(x + 3, y + 2, c);
    final b = Brush(R, P);
    // curled tail
    const curl = <(num, num)>[(4, 13), (3, 14), (3, 15), (4, 16)];
    for (final (x, y, c) in sk.tail != null ? sk.tail!(curl, View.sleep) : _plainTail(curl)) {
      P(x, y, c);
    }
    // body lying down, breathing
    R(5, 10 + breath, 16, 7 - breath, 'f', true);
    R(7, 12 + breath, 5, 4 - breath, 'd', true);
    sk.body?.call(b, View.sleep, 5, 10 + breath, 16, 7 - breath);
    // front paws forward, head resting on them
    R(21, 14, 7, 3, 'f', true);
    R(25, 14, 3, 3, 'c', true);
    R(20, 8, 7, 7, 'f', true);
    R(25, 11, 4, 4, 'c', true);
    sk.snout?.call(b, View.sleep, 25, 11);
    P(28, 11, 'n');
    R(22, 11, 2, 1, 'n'); // closed eye
    sk.head?.call(b, View.sleep, 20, 8, 7, 7);
    if (sk.ear != null) {
      sk.ear!(b, View.sleep, 18, 8, const EarOpts());
    } else {
      R(18, 8, 3, 6, 'd', true);
    }
    p.outline();
    ground(p);
    // the Z rising
    if (zs > 0) p.stamp(28, 6 - (zs - 1) * 2, zStamp);
    if (zs > 1) p.px(25, 5 - zs, 'z');
    return p.frame();
  }

  return [make(0, 0), make(0, 1), make(1, 2), make(1, 3), make(0, 3), make(0, 2), make(1, 1), make(1, 0)];
}

// ------------------------------------------------------------------------------------------------------------------ dig

List<Frame> _dig(Skin sk) {
  final frames = <Frame>[];
  const up = 4; // the whole scene sits higher than the others, to leave room for a hole worth looking at
  const gy = groundY - up;
  // 12 beats: dig, dig, dig... then the bone comes up, shines, and it begins again
  for (var i = 0; i < 12; i++) {
    final p = Pix();
    final near = i.isEven;
    void R(num x, num y, num w, num h, String c, [bool round = false]) => p.rect(x, y - up, w, h, c, round);
    void P(num x, num y, String c) => p.px(x, y - up, c);
    final b = Brush(R, P);
    final bob = near ? 0 : 1;
    // the hole, deeper as it goes
    final depth = math.min(1 + i ~/ 2, 4);
    p.rect(22, gy, 13, depth + 1, 'E');
    p.rect(23, gy + depth + 1, 11, 1, 'E');
    p.px(21, gy, 'e');
    p.px(35, gy, 'e');
    // body: rump up, chest low, head toward the hole
    R(5, 6, 8, 8, 'f', true);
    R(7, 8, 4, 4, 'd', true);
    R(12, 8, 8, 7, 'f', true);
    R(12, 14, 7, 1, 'c');
    sk.body?.call(b, View.dig, 5, 6, 15, 9);
    // tail wagging up high
    final wag = <(num, num)>[for (final (x, y) in const [(4, 8), (3, 7), (3, 6)]) (x + (near ? 0 : 1), y)];
    final tailCells = sk.tail != null ? sk.tail!(wag, View.dig) : [for (var k = 0; k < wag.length; k++) (wag[k].$1, wag[k].$2, k == 2 ? 'c' : 'f')];
    for (final (x, y, c) in tailCells) {
      P(x, y, c);
    }
    // back legs
    R(6, 14, 2, 3, 'f');
    R(10, 14, 2, 3, 'd');
    R(6, 16, 2, 1, 'c');
    R(10, 16, 2, 1, 'c');
    // head down, nose in the dirt, bobbing with each scoop
    R(18, 10 + bob, 7, 7, 'f', true);
    R(24, 13 + bob, 4, 4, 'c', true);
    sk.snout?.call(b, View.dig, 24, 13 + bob);
    P(27, 13 + bob, 'n');
    P(22, 12 + bob, 'n');
    P(22, 11 + bob, 'w');
    sk.head?.call(b, View.dig, 18, 10 + bob, 7, 7);
    if (sk.ear != null) {
      sk.ear!(b, View.dig, 17, 10 + bob, const EarOpts());
    } else {
      R(17, 10 + bob, 3, 5, 'd', true);
    }
    // front legs digging: one reaches into the hole, the other pulls back
    void reach(num x, num y, String c) {
      R(x, y, 2, 2, c);
      R(x + 1, y + 2, 2, 2, c);
      R(x + 2, y + 3, 2, 1, 'c');
    }

    if (near) {
      reach(20, 14, 'f');
      R(16, 15, 2, 3, 'd');
      R(16, 17, 2, 1, 'c');
    } else {
      reach(18, 14, 'd');
      R(21, 15, 2, 3, 'f');
      R(21, 17, 2, 1, 'c');
    }
    p.outline();
    // dirt flying backward over the dog
    const flying = [(17, 11), (13, 6), (9, 3), (5, 5), (2, 9)];
    for (var k = 0; k < 3; k++) {
      final (x, y) = flying[(i + k) % 5];
      P(x, y, k == 0 ? 'e' : 'E');
      P(x + 1, y, 'e');
      P(x, y + 1, 'e');
    }
    // the ground, and the heap beside the hole
    for (var x = 0; x < 22; x++) {
      p.px(x, gy, 'l');
    }
    for (var x = 36; x < W; x++) {
      p.px(x, gy, 'l');
    }
    for (var x = 0; x < W; x++) {
      if (x < 22 && (x + i) % 7 == 0) p.px(x, gy + 1, 'l');
    }
    // the bone, at the end
    if (i >= 9) {
      final rise = i == 9 ? 0 : i == 10 ? 3 : 5;
      p.stamp(26, gy - rise + 1 - 3, const ['b..b', 'bbbb', 'B..B']);
      p.rect(24, gy, 11, 1, 'E');
      if (i >= 10) {
        p.px(24, gy - 7, 's');
        p.px(31, gy - 8, 's');
        p.px(33, gy - 5, 's');
      }
    }
    frames.add(p.frame());
  }
  return frames;
}

// ------------------------------------------------------------------------------------------------------------------ lick

/// A face pressed against the glass, tongue sweeping across it. Drawn two rows down so ears and horns have room above.
const int _ly = 2;

/// The tongue's x position and how far it hangs, per beat; smears are left where it has been.
const List<(int, int)> lickSweep = [(16, 1), (14, 3), (11, 4), (9, 4), (12, 4), (15, 4), (18, 4), (21, 4), (24, 3), (18, 2), (16, 1), (16, 0)];

List<Frame> _lick(Skin sk) {
  final frames = <Frame>[];
  final trail = <(int, int)>[];
  for (var i = 0; i < lickSweep.length; i++) {
    final (tx, len) = lickSweep[i];
    final p = Pix();
    void R(num x, num y, num w, num h, String c, [bool round = false]) => p.rect(x, y + _ly, w, h, c, round);
    void Q(num x, num y, String c) => p.px(x, y + _ly, c);
    final b = Brush(R, Q);
    // ears, head, muzzle
    if (sk.ear != null) {
      sk.ear!(b, View.front, 6, 2, const EarOpts(side: 'left'));
      sk.ear!(b, View.front, 25, 2, const EarOpts(side: 'right'));
    } else {
      R(6, 2, 5, 11, 'd', true);
      R(25, 2, 5, 11, 'd', true);
    }
    R(9, 2, 18, 15, 'f', true);
    R(13, 10, 10, 7, 'c', true);
    R(16, 9, 4, 2, 'n');
    Q(16, 9, 'n');
    // eyes
    R(12, 6, 2, 3, 'n');
    R(22, 6, 2, 3, 'n');
    Q(12, 6, 'w');
    Q(22, 6, 'w');
    // mouth
    Q(17, 11, 'n');
    Q(18, 11, 'n');
    Q(15, 13, 'n');
    Q(20, 13, 'n');
    R(16, 12, 4, 1, 'n');
    sk.snout?.call(b, View.front, 13, 10);
    sk.head?.call(b, View.front, 9, 2, 18, 15);
    // tongue out, wide and flat
    if (len > 0) {
      R(tx - 1 + 0, 13, 4, len, 't', true);
      Q(tx + 1, 13 + len - 1, 'T');
    }
    p.outline();
    // the smear it leaves on the glass, fading
    if (len >= 3) trail.add((tx, 13 + len));
    drawTrail(p, trail, _ly);
    // glass: a corner highlight
    p.px(2, 2, 'w');
    p.px(3, 2, 'w');
    p.px(2, 3, 'w');
    // little sparkles when it is a good lick
    if (len == 4 && i % 3 == 0) p.px(31, 4, 's');
    frames.add(p.frame());
  }
  return frames;
}

/// The smear left on the glass: the last four places the tongue has been, the newest brightest.
void drawTrail(Pix p, List<(int, int)> trail, int ly) {
  final a = trail.length > 5 ? trail.sublist(trail.length - 5) : trail;
  for (var k = 0; k < a.length; k++) {
    if (k < a.length - 4) continue;
    final (x, y) = a[k];
    for (var j = 0; j < 4; j++) {
      p.px(x - 1 + j, y + ly, k == a.length - 1 ? 'q' : 'g');
    }
  }
}

class SceneDef {
  const SceneDef(this.frames, this.frameMs);
  final List<Frame> frames;

  /// Milliseconds each frame stays up.
  final int frameMs;
}

final Map<Animal, Skin> _skins = {Animal.dog: const Skin(), Animal.cat: catSkin, Animal.unicorn: unicornSkin, Animal.elephant: elephantSkin};

/// How long each frame stays up, per scene (the same for every animal).
const Map<Scene, int> frameMsFor = {
  Scene.run: 110,
  Scene.sniff: 260,
  Scene.dig: 170,
  Scene.sit: 280,
  Scene.sleep: 420,
  Scene.lick: 200,
  Scene.home: 260,
  Scene.react: 120,
};

final Map<String, SceneDef> _cache = {};

/// The colours of one animal (0xRRGGBB): the dog's palette with that animal's own changes.
Map<String, int> paletteFor(Animal animal) => {...palette, ...?paletteOverrides[animal]};

List<Frame> _build(Scene scene, Animal animal) {
  if (animal == Animal.hamster) return hamsterScene(scene);
  if (animal == Animal.pigeon) return pigeonScene(scene);
  final sk = _skins[animal] ?? const Skin();
  return switch (scene) {
    Scene.home => quadHome(animal, sk),
    Scene.react => quadReact(animal, sk),
    Scene.run => _run(sk),
    Scene.sniff => _sniff(sk),
    Scene.dig => _dig(sk),
    Scene.sit => sit(sk),
    Scene.sleep => _sleep(sk),
    Scene.lick => _lick(sk),
  };
}

/// The frames of one scene for one animal, built once and kept.
SceneDef sceneFrames(Scene scene, [Animal animal = defaultAnimal]) =>
    _cache.putIfAbsent('${animal.name}:${scene.name}', () => SceneDef(_build(scene, animal), frameMsFor[scene]!));
