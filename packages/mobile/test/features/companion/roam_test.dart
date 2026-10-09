import 'dart:math' as math;

import 'package:escanor/features/companion/roam.dart';
import 'package:escanor/features/companion/sprites.dart';
import 'package:flutter_test/flutter_test.dart';

const g = Geometry(vw: 1280, vh: 800, sw: 72, sh: 44, home: Vec(40, 770), top: 8);

double Function() seeded([int seed = 7]) => () {
      seed = (seed * 16807) % 2147483647;
      return (seed - 1) / 2147483646;
    };

void main() {
  group('orientation', () {
    test('stands on the floor facing either way', () {
      expect(orientation(const Vec(0, 1), const Vec(1, 0)), (rotate: 0, mirror: false));
      expect(orientation(const Vec(0, 1), const Vec(-1, 0)), (rotate: 0, mirror: true));
    });
    test('finds a turn for every edge and direction it can walk', () {
      for (final feet in const [Vec(0, 1), Vec(-1, 0), Vec(0, -1), Vec(1, 0)]) {
        for (final face in const [Vec(1, 0), Vec(-1, 0), Vec(0, 1), Vec(0, -1)]) {
          if (feet.x * face.x + feet.y * face.y != 0) continue; // it cannot face along its own feet
          final o = orientation(feet, face);
          // applying the answer must really put the feet and the face where asked
          final a = (o.rotate * math.pi) / 180;
          Vec rot(Vec p) => Vec((p.x * math.cos(a) - p.y * math.sin(a)).roundToDouble() + 0.0, (p.x * math.sin(a) + p.y * math.cos(a)).roundToDouble() + 0.0);
          expect(rot(const Vec(0, 1)), feet);
          expect(rot(Vec(o.mirror ? -1 : 1, 0)), face);
        }
      }
      expect(cssFor((rotate: 180, mirror: true)), 'rotate(180deg) scaleX(-1)');
    });
  });

  group('excursions', () {
    test('there are five, all different', () {
      expect(excursions.toSet().length, 5);
    });
    for (final kind in excursions) {
      test('${kind.name}: starts at home, ends at home, and every stop is on the screen (or just off its edge)', () {
        final plan = planExcursion(kind, g, seeded());
        expect(plan.legs.length, greaterThanOrEqualTo(3));
        expect(plan.total, greaterThan(3000));
        expect(plan.legs.last.to, g.home);
        for (final l in plan.legs) {
          expect(l.ms, greaterThanOrEqualTo(1));
          expect(l.to.x >= -g.sw && l.to.x <= g.vw + g.sw && l.to.y >= 0 && l.to.y <= g.vh, isTrue, reason: '${kind.name} leaves the screen at ${l.to}');
        }
      });
    }
    test('the patrol goes right round: it is upside down along the top and stands on both walls', () {
      final plan = planExcursion(Excursion.patrol, g, () => 0.1);
      final feet = plan.legs.map((l) => '${l.feet.x.toInt()},${l.feet.y.toInt()}').toList();
      expect(feet, contains('0,-1'), reason: 'ceiling');
      expect(feet.contains('-1,0') && feet.contains('1,0'), isTrue, reason: 'both walls');
      final ceiling = plan.legs.firstWhere((l) => l.feet.y == -1);
      expect(ceiling.to.y, lessThan(40), reason: 'on the top edge');
    });
    test('the patrol can go either way round', () {
      expect(planExcursion(Excursion.patrol, g, () => 0.1).legs[0].to, isNot(planExcursion(Excursion.patrol, g, () => 0.9).legs[0].to));
    });
    test('the peek goes out of sight, comes back half in, and returns from the left', () {
      final plan = planExcursion(Excursion.peek, g, seeded());
      expect(plan.legs.any((l) => l.to.x > g.vw), isTrue, reason: 'goes off the right edge');
      expect(plan.legs.any((l) => l.jump && l.to.x < 0), isTrue, reason: 'comes back from the left');
      final looking = plan.legs.firstWhere((l) => l.scene == Scene.sniff);
      expect(looking.to.x < g.vw && looking.to.x > g.vw - g.sw, isTrue, reason: 'half in view');
    });
    test('the zoomies spin in the middle and the nap sleeps a long while', () {
      expect(planExcursion(Excursion.zoomies, g, seeded()).legs.any((l) => l.scene == Scene.react), isTrue);
      final nap = planExcursion(Excursion.nap, g, seeded()).legs.firstWhere((l) => l.scene == Scene.sleep);
      expect(nap.ms, greaterThanOrEqualTo(8000));
    });
    test('fits a phone-sized screen too', () {
      const phone = Geometry(vw: 390, vh: 844, sw: 72, sh: 44, home: Vec(40, 740), top: 44);
      for (final kind in excursions) {
        final plan = planExcursion(kind, phone, seeded());
        for (final l in plan.legs) {
          expect(l.to.x >= -phone.sw && l.to.x <= phone.vw + phone.sw, isTrue, reason: kind.name);
        }
      }
    });
  });

  group('sample', () {
    final plan = planExcursion(Excursion.stroll, g, seeded());
    test('starts at home, moves along the first leg, and ends at the last stop', () {
      expect(sample(plan, g.home, 0).pos, g.home);
      final mid = sample(plan, g.home, plan.legs[0].ms / 2);
      expect(mid.pos.x > g.home.x && mid.pos.x < plan.legs[0].to.x, isTrue);
      final end = sample(plan, g.home, plan.total + 5);
      expect(end.done, isTrue);
      expect(end.pos, g.home);
    });
    test('stands still while it holds, with the scene of that leg', () {
      final t = plan.legs[0].ms + 500;
      final s = sample(plan, g.home, t);
      expect(s.leg.scene, Scene.sniff);
      expect(s.pos, plan.legs[0].to);
    });
    test('appears at the edge, not sliding across the screen, when a leg is a jump', () {
      final peek = planExcursion(Excursion.peek, g, seeded());
      final i = peek.legs.indexWhere((l) => l.jump);
      final before = peek.legs.take(i).fold<int>(0, (n, l) => n + l.ms);
      final s = sample(peek, g.home, before + 1);
      expect(s.pos.x, lessThan(0));
    });
  });

  group('when', () {
    test('waits 20 to 60 seconds for the first outing and one to three minutes between the rest', () {
      for (final r in const [0.0, 0.5, 0.999]) {
        final first = nextDelay(() => r, true);
        expect(first, inInclusiveRange(20000, 60000));
        final later = nextDelay(() => r);
        expect(later, inInclusiveRange(60000, 180000));
      }
    });
    test('never picks the same outing twice running', () {
      for (final last in excursions) {
        for (final r in const [0.0, 0.3, 0.6, 0.99]) {
          expect(pickExcursion(() => r, last), isNot(last));
        }
      }
    });
  });
}
