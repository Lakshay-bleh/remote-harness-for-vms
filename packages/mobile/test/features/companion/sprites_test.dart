import 'package:escanor/features/companion/animals.dart';
import 'package:escanor/features/companion/companion.dart';
import 'package:escanor/features/companion/sounds.dart';
import 'package:escanor/features/companion/sprites.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final animal in animals.map((a) => a.id)) {
    group('the ${animal.name}', () {
      final pal = paletteFor(animal);
      for (final scene in scenes) {
        group(scene.name, () {
          final def = sceneFrames(scene, animal);

          test('has every frame the same size, W by H', () {
            for (final f in def.frames) {
              expect(f.length, H);
              for (final row in f) {
                expect(row.length, W);
              }
            }
          });

          test('uses only colours it defines', () {
            for (final f in def.frames) {
              for (final row in f) {
                for (final c in row.split('')) {
                  expect(c == '.' || pal.containsKey(c), isTrue, reason: 'unknown pixel "$c"');
                }
              }
            }
          });

          test('moves: it has several frames and they are not all the same', () {
            expect(def.frames.length, greaterThanOrEqualTo(4));
            expect(def.frames.map((f) => f.join('\n')).toSet().length, greaterThanOrEqualTo(3));
            expect(def.frameMs, inInclusiveRange(80, 600));
          });

          test('is drawn, outlined and not clipped at the edges', () {
            for (final f in def.frames) {
              final body = f.join();
              expect('f'.allMatches(body).length, greaterThan(scene == Scene.home ? 12 : 30), reason: 'fur');
              expect('o'.allMatches(body).length, greaterThan(20), reason: 'outline');
              // the animal itself (outline pixels) never touches the edge of the picture, where it would be cut off
              for (var y = 0; y < f.length; y++) {
                final row = f[y];
                if (y == 0 || y == H - 1) expect(row.contains('o'), isFalse, reason: 'outline on edge row $y');
                expect(row[0], isNot('o'), reason: 'outline on left edge, row $y');
                expect(row[W - 1], isNot('o'), reason: 'outline on right edge, row $y');
              }
            }
          });
        });
      }
    });
  }

  group('the companions', () {
    test('are the six that were promised, each with a name', () {
      expect(animals.map((a) => [a.id.name, a.name]).toList(), [
        ['dog', 'Shiro'],
        ['unicorn', 'Stacy'],
        ['pigeon', 'Riti'],
        ['hamster', 'Bubbly'],
        ['cat', 'Tom'],
        ['elephant', 'Jumbo'],
      ]);
    });
    test('are each drawn differently from the others', () {
      for (final scene in scenes) {
        final pictures = animals.map((a) => sceneFrames(scene, a.id).frames[0].join()).toSet();
        expect(pictures.length, animals.length, reason: 'two animals look the same in ${scene.name}');
      }
    });
    test('keep the dog as the default, and ignore a choice that is not an animal', () {
      expect(defaultAnimal, Animal.dog);
      expect(parseCompanion('unicorn'), Animal.unicorn);
      expect(parseCompanion('dragon'), Animal.dog);
      expect(parseCompanion(null), Animal.dog);
      expect(isAnimal('cat'), isTrue);
      expect(isAnimal('Cat'), isFalse);
      expect(companionKey, contains('companion'));
    });
    test('scenes are found by name, and an unknown one sits', () {
      expect(sceneFrom('dig'), Scene.dig);
      expect(sceneFrom('dance'), Scene.sit);
    });
  });

  group('how each one talks', () {
    test('says its own words when tapped, at least three different ones', () {
      final all = <String>{};
      for (final a in animals) {
        expect(a.says.toSet().length, greaterThanOrEqualTo(3), reason: a.name);
        all.addAll(a.says);
      }
      expect(all.length, greaterThanOrEqualTo(20), reason: 'every animal has its own words');
      expect(animalInfo(Animal.dog).says, contains('Woof!'));
      expect(animalInfo(Animal.cat).says, contains('Meow!'));
    });
    test("makes its own sound: a short call that is not the same as any other animal's", () {
      final seen = <String>{};
      for (final a in animals) {
        final calls = voices[a.id]!;
        expect(calls, isNotEmpty);
        for (final call in calls) {
          expect(callLength(call), inInclusiveRange(200, 1500), reason: '${a.id.name} call is ${callLength(call)}ms');
          for (final n in call) {
            expect(n.from > 50 && n.to > 50 && n.from < 6000 && n.to < 6000 && n.gain > 0 && n.gain <= 0.6 && n.dur > 0, isTrue);
          }
        }
        seen.add(calls.toString());
      }
      expect(seen.length, animals.length);
    });
    test('has a home of its own and a reaction, each well away from the other scenes', () {
      for (final a in animals) {
        expect(sceneFrames(Scene.react, a.id).frames.length, greaterThanOrEqualTo(6), reason: '${a.id.name} react');
        expect(sceneFrames(Scene.home, a.id).frames.length, greaterThanOrEqualTo(6), reason: '${a.id.name} home');
        expect(sceneFrames(Scene.home, a.id).frames[0].join(), isNot(sceneFrames(Scene.sit, a.id).frames[0].join()), reason: '${a.id.name} home is not just sitting');
      }
    });
  });
}
