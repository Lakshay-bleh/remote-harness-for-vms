/// The companion wandering the screen. Pure planning, so every walk can be tested without a device: [planExcursion]
/// turns a kind of outing and the size of the screen into a list of legs (go here, in this scene, facing this way,
/// standing on this edge), and [sample] says where the companion is at any moment of it. Positions are the centre of
/// the picture, in logical pixels.
///
/// The five outings: a `stroll` along the bottom and back; a `patrol` all the way round the edge of the screen (up a
/// side, across the top upside down, down the other side); a `peek` where it leaves, then looks in from the edge;
/// `zoomies` (it spins in the middle and dashes about); and a `nap` in the far corner.
library;

import 'dart:math' as math;

import 'sprites.dart' show Scene;

enum Excursion { stroll, patrol, peek, zoomies, nap }

const List<Excursion> excursions = Excursion.values;

class Vec {
  const Vec(this.x, this.y);
  final double x;
  final double y;
  @override
  bool operator ==(Object other) => other is Vec && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
  @override
  String toString() => '($x, $y)';
}

/// The screen and the picture. [home] is the centre of the picture at rest; [top] is how far down the top edge is (a
/// header, a status bar).
class Geometry {
  const Geometry({required this.vw, required this.vh, required this.sw, required this.sh, required this.home, required this.top});
  final double vw;
  final double vh;
  final double sw;
  final double sh;
  final Vec home;
  final double top;
}

class Leg {
  const Leg({required this.to, required this.ms, required this.scene, required this.feet, required this.face, this.jump = false});
  final Vec to;
  final int ms;
  final Scene scene;

  /// Which way is "down" for the animal: (0,1) on the floor, (-1,0) on the left wall, (0,-1) on the ceiling.
  final Vec feet;

  /// Which way it is facing.
  final Vec face;

  /// Start from [to] instead of sliding there from where the last leg ended (coming in from off the screen).
  final bool jump;
}

class Plan {
  const Plan(this.kind, this.legs, this.total);
  final Excursion kind;
  final List<Leg> legs;
  final int total;
}

/// Walking pace in pixels a millisecond; the dash is twice that.
const double walk = 0.12;
const double dash = 0.26;

const Vec _floorFeet = Vec(0, 1);
const Vec _right = Vec(1, 0);
const Vec _left = Vec(-1, 0);
const Vec _up = Vec(0, -1);
const Vec _down = Vec(0, 1);

double _dist(Vec a, Vec b) => math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

/// How to turn the picture (facing right, feet down) so its feet are on [feet] and it faces [face]: a flip, then a
/// quarter-turn clockwise.
({int rotate, bool mirror}) orientation(Vec feet, Vec face) {
  for (final mirror in const [false, true]) {
    for (final rotate in const [0, 90, 180, 270]) {
      final a = (rotate * math.pi) / 180;
      Vec rot(Vec p) => Vec(
            (p.x * math.cos(a) - p.y * math.sin(a)).roundToDouble() + 0.0,
            (p.x * math.sin(a) + p.y * math.cos(a)).roundToDouble() + 0.0,
          );
      final f = rot(const Vec(0, 1));
      final c = rot(Vec(mirror ? -1 : 1, 0));
      if (f.x == feet.x && f.y == feet.y && c.x == face.x && c.y == face.y) return (rotate: rotate, mirror: mirror);
    }
  }
  return (rotate: 0, mirror: false);
}

/// The transform for an orientation, written the CSS way (the flip happens first, then the turn). The widget applies
/// the same thing as a matrix; this is the readable form, for tests and debugging.
String cssFor(({int rotate, bool mirror}) o) => 'rotate(${o.rotate}deg) scaleX(${o.mirror ? -1 : 1})';

/// The edges: where the picture's centre sits when it is walking along each.
({double floor, double left, double right, double ceiling, double minX, double maxX, double wallTop}) _edges(Geometry g) => (
      floor: g.home.y,
      left: g.sh / 2 + 2,
      right: g.vw - g.sh / 2 - 2,
      ceiling: g.top + g.sh / 2,
      minX: g.sw / 2 + 2,
      maxX: g.vw - g.sw / 2 - 2,
      wallTop: g.top + g.sw / 2,
    );

Leg _leg(Vec from, Vec to, Scene scene, Vec feet, Vec face, [double speed = walk, bool jump = false]) =>
    Leg(to: to, ms: math.max(1, (_dist(from, to) / speed).round()), scene: scene, feet: feet, face: face, jump: jump);

/// One outing, starting from home. [rand] gives numbers from 0 up to (not including) 1, so a test can fix the dice.
Plan planExcursion(Excursion kind, Geometry g, [double Function()? rand]) {
  final dice = rand ?? math.Random().nextDouble;
  final e = _edges(g);
  final home = g.home;
  final legs = <Leg>[];
  var at = home;
  void go(Vec to, Scene scene, Vec feet, Vec face, [double speed = walk, bool jump = false]) {
    legs.add(_leg(jump ? to : at, to, scene, feet, face, speed, jump));
    at = to;
  }

  void stay(int ms, Scene scene, Vec feet, Vec face) => legs.add(Leg(to: at, ms: ms, scene: scene, feet: feet, face: face));

  switch (kind) {
    case Excursion.stroll:
      final far = Vec(math.max(home.x + 40, e.maxX - 6), e.floor);
      go(far, Scene.run, _floorFeet, _right);
      stay(3000, Scene.sniff, _floorFeet, _right);
      go(home, Scene.run, _floorFeet, _left);
    case Excursion.patrol:
      // clockwise or the other way round, by the dice
      final clockwise = dice() < 0.5;
      Vec l(double y) => Vec(e.left, y);
      Vec r(double y) => Vec(e.right, y);
      if (clockwise) {
        go(Vec(e.minX, e.floor), Scene.run, _floorFeet, _left);
        go(l(e.wallTop), Scene.run, _left, _up);
        go(Vec(e.left, e.ceiling), Scene.run, _up, _right);
        go(Vec(e.right, e.ceiling), Scene.run, _up, _right);
        go(r(e.floor), Scene.run, _right, _down);
        go(home, Scene.run, _floorFeet, _left);
      } else {
        go(Vec(e.maxX, e.floor), Scene.run, _floorFeet, _right);
        go(r(e.wallTop), Scene.run, _right, _up);
        go(Vec(e.right, e.ceiling), Scene.run, _up, _left);
        go(Vec(e.left, e.ceiling), Scene.run, _up, _left);
        go(l(e.floor), Scene.run, _left, _down);
        go(home, Scene.run, _floorFeet, _right);
      }
    case Excursion.peek:
      final out = Vec(g.vw + g.sw / 2 + 12, e.floor);
      go(out, Scene.run, _floorFeet, _right);
      stay(2500, Scene.sleep, _floorFeet, _left); // out of sight
      go(Vec(g.vw - g.sw * 0.42, e.floor), Scene.sniff, _floorFeet, _left, 0.12);
      stay(3200, Scene.sniff, _floorFeet, _left);
      go(out, Scene.run, _floorFeet, _right, dash);
      go(Vec(-g.sw / 2 - 12, e.floor), Scene.run, _floorFeet, _right, walk, true);
      go(home, Scene.run, _floorFeet, _right);
    case Excursion.zoomies:
      final mid = Vec(math.min(e.maxX - 20, math.max(home.x + 60, g.vw * (0.4 + dice() * 0.25))), e.floor);
      go(mid, Scene.run, _floorFeet, _right);
      stay(3400, Scene.react, _floorFeet, _right);
      go(Vec(e.maxX, e.floor), Scene.run, _floorFeet, _right, dash);
      go(home, Scene.run, _floorFeet, _left, dash);
    case Excursion.nap:
      final bed = Vec(e.maxX - 8, e.floor);
      go(bed, Scene.run, _floorFeet, _right);
      stay(9000, Scene.sleep, _floorFeet, _right);
      stay(1400, Scene.sniff, _floorFeet, _left);
      go(home, Scene.run, _floorFeet, _left);
  }
  return Plan(kind, legs, legs.fold(0, (n, l) => n + l.ms));
}

class Sample {
  const Sample(this.pos, this.leg, this.done);
  final Vec pos;
  final Leg leg;
  final bool done;
}

/// Where the companion is [t] milliseconds into an outing.
Sample sample(Plan plan, Vec home, num t) {
  var from = home;
  var start = 0;
  for (final l in plan.legs) {
    final begin = l.jump ? l.to : from;
    if (t < start + l.ms) {
      final k = ((t - start) / l.ms).clamp(0.0, 1.0);
      return Sample(Vec(begin.x + (l.to.x - begin.x) * k, begin.y + (l.to.y - begin.y) * k), l, false);
    }
    start += l.ms;
    from = l.to;
  }
  final last = plan.legs.last;
  return Sample(last.to, last, true);
}

/// How long to wait before the next outing, in milliseconds: the first comes sooner, then every one to three minutes.
int nextDelay(double Function() rand, [bool first = false]) =>
    first ? (20000 + rand() * 40000).round() : (60000 + rand() * 120000).round();

/// Which outing next: any, but never the same twice running.
Excursion pickExcursion(double Function() rand, [Excursion? last]) {
  final choices = excursions.where((k) => k != last).toList();
  return choices[math.min(choices.length - 1, (rand() * choices.length).floor())];
}
