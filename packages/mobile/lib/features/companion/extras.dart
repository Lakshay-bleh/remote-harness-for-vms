/// What only the four-legged companions do beyond the shared scenes:
///  - `react`: what happens when you tap one. Each answers in its own way (the dog spins round, the unicorn prances
///    under a rainbow, the cat arches and pounces, the elephant raises its trunk and sprays).
///  - `home`: each in its own place, with the things it likes (the dog's kennel and bone, the unicorn's cloud and
///    rainbow, the cat's box and yarn, the elephant's pool and palm).
/// The hamster and the pigeon have theirs in their own files.
library;

import 'dart:math' as math;

import 'animals.dart';
import 'pix.dart';
import 'sprites.dart';

/// Points of a ring (angles in degrees, 0 = right, 90 = down).
void ring(Pix p, num cx, num cy, num r, num from, num to, String c) {
  for (var a = from; a <= to; a += 4) {
    p.px(cx + math.cos((a * math.pi) / 180) * r, cy + math.sin((a * math.pi) / 180) * r, c);
  }
}

/// A little four-point star.
void twinkle(Pix p, num x, num y, bool big) {
  p.px(x, y, 's');
  if (big) {
    p.px(x - 1, y, 's');
    p.px(x + 1, y, 's');
    p.px(x, y - 1, 's');
    p.px(x, y + 1, 's');
  }
}

/// Keep decorations on the picture and off its outermost pixels, so nothing is cut off.
bool _inside(num x, num y) => x >= 2 && x <= W - 3 && y >= 2 && y <= H - 3;

// ------------------------------------------------------------------------------------------------------------------ react

typedef _Turn = ({bool mirror, int lift, Legs legs, Tail tail});

/// The dog spins on the spot: it faces one way, then the other, hopping, with dust at its feet and stars going round
/// its head.
List<Frame> _dogReact(Skin sk) {
  const List<_Turn> turns = [
    (mirror: false, lift: 0, legs: Legs.stand, tail: Tail.up),
    (mirror: false, lift: 3, legs: Legs.runA, tail: Tail.mid),
    (mirror: true, lift: 4, legs: Legs.runB, tail: Tail.up),
    (mirror: true, lift: 1, legs: Legs.stand, tail: Tail.mid),
    (mirror: false, lift: 3, legs: Legs.runB, tail: Tail.up),
    (mirror: true, lift: 4, legs: Legs.runA, tail: Tail.mid),
    (mirror: false, lift: 2, legs: Legs.runA, tail: Tail.up),
    (mirror: true, lift: 0, legs: Legs.stand, tail: Tail.up),
  ];
  return [
    for (var i = 0; i < turns.length; i++)
      () {
        final t = turns[i];
        final p = Pix();
        sideDog(p, Side(legs: t.legs, lift: t.lift, tail: t.tail, mouth: 'pant', ears: t.lift > 1 ? 'back' : 'down', head: 0), sk, 2, 0);
        p.outline();
        if (t.mirror) p.mirror();
        ground(p, i);
        // the dust it kicks up, circling its feet
        for (var k = 0; k < 4; k++) {
          final a = (i * 50 + k * 90) * (math.pi / 180);
          p.px(18 + math.cos(a) * (9 + (k % 2)), groundY - 1 - math.sin(a).abs() * 2, 'g');
        }
        // stars going round
        for (var k = 0; k < 3; k++) {
          final a = (i * 45 + k * 120) * (math.pi / 180);
          final x = jsRound(18 + math.cos(a) * 12);
          final y = jsRound(6 + math.sin(a) * 3);
          if (_inside(x, y)) twinkle(p, x, y, k == 0);
        }
        return p.frame();
      }(),
  ];
}

/// The unicorn prances under a rainbow that builds up as it goes, with sparkles round its horn.
List<Frame> _unicornReact(Skin sk) {
  const bands = ['M', 'H', 'G', 'N'];
  const prance = [Legs.runA, Legs.runB, Legs.runA, Legs.runB, Legs.runA, Legs.runB, Legs.stand, Legs.runA];
  return List.generate(8, (i) {
    final p = Pix();
    final shown = math.min(bands.length, 1 + i ~/ 2);
    for (var b = 0; b < shown; b++) {
      ring(p, 18, 22, 14 - b, 196, 344, bands[b]);
    }
    sideDog(p, Side(legs: prance[i], lift: i.isOdd ? 1 : 0, tail: i.isOdd ? Tail.up : Tail.mid, mouth: 'pant', ears: 'back', head: 0), sk, 0, 0);
    p.outline();
    ground(p, i);
    for (final (x, y) in const [(8, 5), (29, 4), (24, 9), (5, 11)]) {
      if ((i + x) % 3 != 0) twinkle(p, x, y, (i + y).isEven);
    }
    return p.frame();
  });
}

/// The cat arches its back, crouches and pounces, and says so, with its tail puffed up.
List<Frame> _catReact(Skin sk) {
  const poses = <({Legs legs, int head, Tail tail, int lift})>[
    (legs: Legs.stand, head: 0, tail: Tail.up, lift: 0),
    (legs: Legs.stand, head: 0, tail: Tail.up, lift: 1),
    (legs: Legs.stand, head: 4, tail: Tail.mid, lift: 0),
    (legs: Legs.walkA, head: 7, tail: Tail.low, lift: 0),
    (legs: Legs.runA, head: 0, tail: Tail.up, lift: 1),
    (legs: Legs.runB, head: 0, tail: Tail.mid, lift: 1),
    (legs: Legs.stand, head: 0, tail: Tail.up, lift: 1),
    (legs: Legs.stand, head: 0, tail: Tail.up, lift: 0),
  ];
  return [
    for (var i = 0; i < poses.length; i++)
      () {
        final o = poses[i];
        final p = Pix();
        sideDog(p, Side(legs: o.legs, head: o.head, tail: o.tail, lift: o.lift, mouth: o.head < 5 ? 'pant' : 'closed', ears: o.head >= 4 ? 'back' : 'down'), sk, 0, 0);
        // the arched back: a hump over the body when it is not crouching
        if (o.head < 4) p.rect(12, 7 - o.lift, 8, 2, 'f', true);
        p.outline();
        ground(p, i);
        // "!" over its head, and the wiggle of excitement
        if (i.isEven) p.stamp(30, 3, const ['h', 'h', 'h', '.', 'h']);
        if (i % 3 == 1) {
          p.px(5, 8, 'g');
          p.px(3, 10, 'g');
        }
        return p.frame();
      }(),
  ];
}

List<Cell> _elephantTail(List<(num, num)> path, View view) {
  final cells = <Cell>[for (final (x, y) in path.take(3)) (x, y, 'f')];
  final last = path[math.min(2, path.length - 1)];
  cells.add((last.$1, last.$2 + 1, 'd'));
  return cells;
}

/// The elephant: trunk up in a trumpet, ears flapping, a fountain of water from the tip.
final Skin _elephantUp = Skin(
  ear: (b, view, x, y, o) {
    if (view != View.side) return;
    final lift = o.blown ? -2 : 0;
    b.r(x - 3, y - 1 + lift, 7, 9, 'd', true);
    b.r(x - 2, y + lift, 4, 6, 'c', true);
  },
  snout: (b, view, x, y) {
    if (view != View.side) return;
    // out, then straight up
    const pts = [(1, 0), (3, -1), (4, -3), (4, -5), (3, -7)];
    for (var i = 0; i < pts.length; i++) {
      b.r(x + pts[i].$1, y + pts[i].$2, 2, 2, i == pts.length - 1 ? 'c' : i.isOdd ? 'f' : 'd');
    }
    b.p(x + 1, y + 3, 'w');
  },
  tail: _elephantTail,
);

List<Frame> _elephantReact(Skin base) {
  final sk = base.merge(_elephantUp);
  const legs = [Legs.stand, Legs.walkA, Legs.stand, Legs.walkB, Legs.stand, Legs.walkA, Legs.stand, Legs.walkB];
  return List.generate(8, (i) {
    final p = Pix();
    // the ear flaps through `blown`; the trunk sway is the 2px shift of the whole animal
    sideDog(p, Side(legs: legs[i], lift: 0, tail: i.isOdd ? Tail.mid : Tail.up, mouth: 'closed', ears: i.isOdd ? 'back' : 'down', head: 0), sk, i.isOdd ? 0 : -1, 0);
    p.outline();
    ground(p, i);
    // water thrown from the tip: drops on an arc, raining down
    final tipX = 31 + (i % 2);
    for (var k = 0; k < 5; k++) {
      final t = ((i + k * 2) % 8) / 8;
      final x = jsRound(tipX + (t - 0.3) * 8 * (k.isOdd ? 1 : -0.4) + (k - 2));
      final y = jsRound(2 + t * t * 14);
      if (_inside(x, y)) p.px(x, y, k.isOdd ? 'a' : 'q');
    }
    return p.frame();
  });
}

List<Frame> quadReact(Animal animal, Skin sk) => switch (animal) {
      Animal.unicorn => _unicornReact(sk),
      Animal.cat => _catReact(sk),
      Animal.elephant => _elephantReact(sk),
      _ => _dogReact(sk),
    };

// ------------------------------------------------------------------------------------------------------------------- home

const List<String> _kennel = [
  '....R....',
  '...RRR...',
  '..RRRRR..',
  '.RRRRRRR.',
  'RRRRRRRRR',
  '.WWWWWWW.',
  '.WWEEEWW.',
  '.WWEEEWW.',
  '.WWEEEWW.',
  '.WWEEEWW.',
];

/// The dog by its kennel, with a bone to chew and a ball.
List<Frame> _dogHome(Skin sk) => sit(
      sk,
      Deco(
        dx: -2,
        back: (p, i) {
          p.stamp(26, 10, _kennel);
          p.rect(28, 12, 5, 1, 'r'); // a name board over the door
        },
        front: (p, i) {
          p.stamp(23, 18, const ['b..b', 'bbbb']);
          p.rect(23, 19, 4, 1, 'B');
          if (i.isOdd) p.px(25, 17, 's');
        },
      ),
    );

/// The unicorn on a cloud, in front of a rainbow, under twinkling stars.
List<Frame> _unicornHome(Skin sk) => sit(
      sk,
      Deco(
        dx: -2,
        ground: false,
        back: (p, i) {
          const bands = ['M', 'H', 'G', 'N'];
          for (var b = 0; b < bands.length; b++) {
            ring(p, 23, 19, 10 - b, 180, 360, bands[b]);
          }
          for (final (x, y) in const [(4, 4), (11, 2), (33, 3), (30, 12)]) {
            if ((i + x) % 3 != 0) twinkle(p, x, y, (i + x).isEven);
          }
        },
        front: (p, i) {
          // the cloud it sits on, over its hooves
          for (var x = 0; x < W; x++) {
            final h = 1 + ((x * 7) % 5 < 2 ? 1 : 0);
            for (var y = groundY - h; y <= groundY; y++) {
              p.px(x, y, y == groundY ? 'g' : 'w');
            }
          }
          p.rect(0, groundY + 1, W, 1, 'g');
        },
      ),
    );

/// The cat by its box, with a ball of yarn that it has unrolled across the floor.
List<Frame> _catHome(Skin sk) => sit(
      sk,
      Deco(
        dx: -2,
        back: (p, i) {
          // the box, its flaps open
          p.rect(25, 12, 10, 8, 'W');
          p.rect(25, 12, 10, 1, 'm');
          p.rect(26, 14, 8, 5, 'm');
          p.rect(24, 10, 4, 2, 'W');
          p.rect(32, 10, 4, 2, 'W');
          p.px(i.isOdd ? 29 : 30, 13, 'f'); // ears of something in the box, watching
          p.px(i.isOdd ? 31 : 30, 13, 'f');
        },
        front: (p, i) {
          final x = 22 + (i % 3);
          p.oval(x, groundY - 2, 2, 2, 'S');
          p.px(x - 1, groundY - 3, 'w');
          for (var k = 0; k < 7; k++) {
            p.px(x + 2 + k * 0.5, groundY - 1 + (k.isOdd ? 0 : -0.4), 'S'); // the thread
          }
        },
      ),
    );

/// The elephant by a small pool, under a palm, with a peanut.
List<Frame> _elephantHome(Skin sk) => sit(
      sk,
      Deco(
        dx: -2,
        back: (p, i) {
          // a palm: trunk and fronds
          for (var y = 8; y < groundY; y++) {
            p.px(32 + (y % 4 == 0 ? 0 : 1), y, 'm');
          }
          for (final (x, y) in const [(29, 6), (30, 5), (31, 5), (33, 5), (34, 5), (35, 6), (30, 7), (34, 7)]) {
            p.px(x, y, (x + y).isOdd ? 'G' : 'Y');
          }
          p.rect(31, 6, 4, 1, 'G');
        },
        front: (p, i) {
          // the pool in front of its feet, and a drop falling into it
          for (var x = 14; x < 31; x++) {
            for (var y = groundY - 1; y <= groundY; y++) {
              p.px(x, y, (x + i + y) % 5 == 0 ? 'a' : 'A');
            }
          }
          final dropY = 12 + ((i * 3) % 7);
          p.px(22, dropY, 'a');
          p.px(22, dropY - 1, 'q');
          p.px(31, groundY - 2, 'Q'); // a peanut
          p.px(32, groundY - 2, 'Q');
        },
      ),
    );

List<Frame> quadHome(Animal animal, Skin sk) => switch (animal) {
      Animal.unicorn => _unicornHome(sk),
      Animal.cat => _catHome(sk),
      Animal.elephant => _elephantHome(sk),
      _ => _dogHome(sk),
    };
