import 'package:escanor/core/busy.dart';
import 'package:escanor/core/storage.dart';
import 'package:escanor/core/theme.dart';
import 'package:escanor/features/companion/animals.dart';
import 'package:escanor/features/companion/buddy.dart';
import 'package:escanor/features/companion/companion.dart';
import 'package:escanor/features/companion/companion_floor.dart';
import 'package:escanor/features/companion/companion_settings_page.dart';
import 'package:escanor/features/companion/dog_spinner.dart';
import 'package:escanor/features/companion/dog_state.dart';
import 'package:escanor/features/companion/pixel_dog.dart';
import 'package:escanor/features/companion/roam.dart';
import 'package:escanor/features/companion/sprites.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {bool reduceMotion = false}) => MaterialApp(
      theme: buildTheme(EscanorColors.of(ThemeName.dark, AccentName.gold), reduceMotion: reduceMotion),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion), child: child!),
      home: child,
    );

/// A phone-sized screen (or [size]) for this test.
Future<void> screen(WidgetTester t, [Size size = const Size(400, 800)]) async {
  t.view.devicePixelRatio = 3;
  t.view.physicalSize = size * 3;
  addTearDown(t.view.reset);
}

/// The scene a PixelDog is showing now.
PixelPainter painterOf(WidgetTester t, [Finder? within]) {
  final paint = t.widget<CustomPaint>(find.descendant(of: within ?? find.byType(PixelDog), matching: find.byType(CustomPaint)).first);
  return paint.painter! as PixelPainter;
}

void main() {
  final played = <Animal>[];

  setUp(() async {
    await Storage.initForTest();
    resetCompanionForTest();
    played.clear();
    voicePlayer = (a) {
      played.add(a);
      return 500;
    };
  });

  group('crisp pixels', () {
    test('a sprite pixel is always a whole number of screen pixels, at least one', () {
      expect(crispScale(2, 3), 2);
      expect(crispScale(2, 2.625), 5 / 2.625);
      expect(crispScale(0.3, 2), 0.5);
      expect(crispScale(40 / 36, 3), 1);
    });
  });

  group('PixelDog', () {
    testWidgets('draws the chosen companion at its size and plays the frames', (t) async {
      await screen(t);
      await t.pumpWidget(app(const Center(child: PixelDog(scene: Scene.run, scale: 2))));
      expect(t.getSize(find.byType(CustomPaint).last), const Size(72, 44));
      final first = painterOf(t).frame;
      expect(first, sceneFrames(Scene.run).frames[0]);
      await t.pump(const Duration(milliseconds: 120));
      expect(painterOf(t).frame, sceneFrames(Scene.run).frames[1]);
    });

    testWidgets('holds still for people who asked for less motion', (t) async {
      await screen(t);
      await t.pumpWidget(app(const Center(child: PixelDog(scene: Scene.run, scale: 2)), reduceMotion: true));
      await t.pump(const Duration(milliseconds: 500));
      expect(painterOf(t).frame, sceneFrames(Scene.run).frames[0]);
    });

    testWidgets('answers a tap: its words, its reaction, its sound', (t) async {
      await screen(t);
      setCompanion(Animal.cat);
      String? heard;
      await t.pumpWidget(app(Center(child: PixelDog(scene: Scene.sit, scale: 3, onTap: (s) => heard = s))));
      await t.tap(find.byType(PixelDog));
      await t.pump();
      expect(animalInfo(Animal.cat).says, contains(heard));
      expect(find.text(heard!), findsOneWidget);
      expect(painterOf(t).frame, sceneFrames(Scene.react, Animal.cat).frames[0]);
      expect(played, [Animal.cat]);
      await t.pump(const Duration(milliseconds: reactMs + 10));
      expect(find.text(heard!), findsNothing);
      expect(sceneFrames(Scene.sit, Animal.cat).frames, contains(painterOf(t).frame));
    });

    testWidgets('stays quiet when sounds are off', (t) async {
      await screen(t);
      setCompanionSound(false);
      await t.pumpWidget(app(const Center(child: PixelDog(scene: Scene.sit, scale: 3))));
      await t.tap(find.byType(PixelDog));
      await t.pump();
      expect(played, isEmpty);
      await t.pump(const Duration(seconds: 3));
    });

    testWidgets('tiny ones are not tappable', (t) async {
      await screen(t);
      await t.pumpWidget(app(const Center(child: PixelDog(scene: Scene.run, scale: 1))));
      expect(find.descendant(of: find.byType(PixelDog), matching: find.byType(Listener)), findsNothing);
    });

    testWidgets('follows a change of companion made in Settings', (t) async {
      await screen(t);
      await t.pumpWidget(app(const Center(child: PixelDog(scene: Scene.sit, scale: 2))));
      expect(painterOf(t).frame, sceneFrames(Scene.sit, Animal.dog).frames[0]);
      setCompanion(Animal.hamster);
      await t.pump();
      expect(painterOf(t).frame, sceneFrames(Scene.sit, Animal.hamster).frames[0]);
    });
  });

  group('DogState, DogRunner and DogSpinner', () {
    testWidgets('an empty state: the companion, the title, the text and the action', (t) async {
      await screen(t);
      await t.pumpWidget(app(Scaffold(
        body: DogState(scene: 'dig', title: 'Nothing dug up yet', text: 'Things show up here.', action: TextButton(onPressed: () {}, child: const Text('Refresh'))),
      )));
      expect(find.text('Nothing dug up yet'), findsOneWidget);
      expect(find.text('Things show up here.'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
      expect(painterOf(t).frame, sceneFrames(Scene.dig).frames[0]);
      expect(t.getSize(find.descendant(of: find.byType(PixelDog), matching: find.byType(CustomPaint)).first), const Size(180, 110));
    });

    testWidgets('loading more, and a spinner', (t) async {
      await screen(t);
      await t.pumpWidget(app(const Scaffold(body: Column(children: [DogRunner(label: 'Fetching older activity…'), DogSpinner(size: 40)]))));
      expect(find.text('Fetching older activity…'), findsOneWidget);
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      expect(t.getSize(find.byType(DogSpinner)), const Size(40, 40 * 22 / 36));
    });
  });

  group('Settings > Companion', () {
    testWidgets('picks a companion, previews its scenes, and switches its sound', (t) async {
      await screen(t);
      expect(companionLabel(), 'Shiro');
      await t.pumpWidget(app(const CompanionSettingsPage()));
      expect(find.text('Shiro the dog'), findsOneWidget);
      expect(find.text('Tap Shiro to say hello.'), findsOneWidget);
      for (final label in sceneLabel.values) {
        expect(find.text(label), findsOneWidget);
      }
      await t.tap(find.text('At home'));
      await t.pump();
      expect(painterOf(t).frame, sceneFrames(Scene.home).frames[0]);

      await t.scrollUntilVisible(find.text('Bubbly'), 100, scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('Bubbly'));
      await t.pump();
      expect(getCompanion(), Animal.hamster);
      expect(Storage.instance.getString(companionKey), 'hamster');
      expect(companionLabel(), 'Bubbly');

      await t.scrollUntilVisible(find.text('Sounds'), 100, scrollable: find.byType(Scrollable).first);
      expect(find.text('Woof, meow, toot and the rest when you tap them'), findsOneWidget);
      await t.tap(find.byType(Switch));
      await t.pump();
      expect(getCompanionSound(), isFalse);
      expect(Storage.instance.getString(soundKey), 'off');
      await t.pump(const Duration(seconds: 3));
    });

    test('remembers the choice across launches, and shrugs off a damaged one', () async {
      await Storage.initForTest(prefs: {companionKey: 'unicorn', soundKey: 'off'});
      resetCompanionForTest();
      expect(getCompanion(), Animal.unicorn);
      expect(getCompanionSound(), isFalse);
      await Storage.initForTest(prefs: {companionKey: 'dragon'});
      resetCompanionForTest();
      expect(getCompanion(), Animal.dog);
      expect(getCompanionSound(), isTrue);
    });
  });

  group('Buddy', () {
    Widget shell(Widget buddy, {required void Function() onBehind, bool reduceMotion = false}) => app(
          Scaffold(
            body: Stack(children: [
              Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onBehind)),
              buddy,
            ]),
          ),
          reduceMotion: reduceMotion,
        );

    Rect spriteRect(WidgetTester t) => t.getRect(find.descendant(of: find.byType(Buddy), matching: find.byType(PixelDog)));

    setUp(() {});

    testWidgets('rests bottom left on a phone, bottom right on a wide screen, and lets taps past it', (t) async {
      await screen(t);
      var behind = 0;
      await t.pumpWidget(shell(const Buddy(), onBehind: () => behind++));
      final r = spriteRect(t);
      expect(r.left, 4);
      expect(r.bottom, 800 - 8);
      await t.tapAt(const Offset(200, 300));
      expect(behind, 1, reason: 'the screen under it still takes taps');
      await t.tapAt(r.center);
      await t.pump();
      expect(behind, 1, reason: 'a tap on the companion is its own');
      expect(played, [Animal.dog]);
      await t.pump(const Duration(seconds: 3));

      await screen(t, const Size(1200, 800));
      await t.pumpWidget(shell(const Buddy(), onBehind: () {}));
      final w = spriteRect(t);
      expect(w.right, 1200 - 12);
      expect(w.bottom, 800 - 12);
    });

    testWidgets('runs while anything is loading, sits when all is quiet, sleeps after a minute alone', (t) async {
      await screen(t);
      // (less motion, so no outing gets in the way of the minute alone)
      await t.pumpWidget(shell(const Buddy(), onBehind: () {}, reduceMotion: true));
      expect(sceneFrames(Scene.sit).frames, contains(painterOf(t, find.byType(Buddy)).frame));
      final end = beginBusy();
      await t.pump();
      expect(sceneFrames(Scene.run).frames, contains(painterOf(t, find.byType(Buddy)).frame));
      end();
      await t.pump();
      expect(sceneFrames(Scene.sit).frames, contains(painterOf(t, find.byType(Buddy)).frame));
      await t.pump(const Duration(seconds: 61));
      expect(sceneFrames(Scene.sleep).frames, contains(painterOf(t, find.byType(Buddy)).frame));
      await t.tapAt(const Offset(200, 300)); // a touch wakes it
      await t.pump();
      expect(sceneFrames(Scene.sleep).frames, isNot(contains(painterOf(t, find.byType(Buddy)).frame)));
    });

    testWidgets('goes on an outing along the bottom and comes home', (t) async {
      await screen(t);
      await t.pumpWidget(shell(const Buddy(eager: true, only: Excursion.stroll), onBehind: () {}));
      final home = spriteRect(t);
      await t.pump(const Duration(milliseconds: 1600));
      await t.pump(const Duration(milliseconds: 16));
      await t.pump(const Duration(milliseconds: 1000));
      final out = spriteRect(t);
      expect(out.left, greaterThan(home.left + 50), reason: 'it walked off to the right');
      expect(out.bottom, home.bottom, reason: 'along the floor');
      for (var i = 0; i < 100; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(spriteRect(t), home, reason: 'back in its corner');
    });

    testWidgets('rests above a message box along the bottom, not on it, and back in its corner when it goes', (t) async {
      await screen(t);
      resetCompanionFloor();
      Widget page({required bool composer, bool shown = true}) => app(
            Scaffold(
              body: Stack(children: [
                Positioned.fill(
                  child: TickerMode(
                    enabled: shown,
                    child: Column(children: [
                      const Expanded(child: SizedBox.expand()),
                      if (composer) const CompanionFloor(child: SizedBox(height: 120, width: double.infinity)),
                    ]),
                  ),
                ),
                const Buddy(),
              ]),
            ),
            reduceMotion: true,
          );
      await t.pumpWidget(page(composer: true));
      await t.pump();
      await t.pump();
      expect(companionFloor.value, 800 - 120);
      expect(spriteRect(t).bottom, lessThanOrEqualTo(800 - 120), reason: 'above the message box, not on its buttons');

      // The screen with it is hidden (another tab): back to its corner.
      await t.pumpWidget(page(composer: true, shown: false));
      await t.pump();
      await t.pump();
      expect(companionFloor.value, isNull);
      expect(spriteRect(t).bottom, 800 - 8);

      await t.pumpWidget(page(composer: true));
      await t.pump();
      await t.pump();
      expect(spriteRect(t).bottom, lessThanOrEqualTo(800 - 120));

      await t.pumpWidget(page(composer: false));
      await t.pump();
      await t.pump();
      expect(companionFloor.value, isNull);
      expect(spriteRect(t).bottom, 800 - 8);
    });

    testWidgets('no outings while the keyboard is up, and one under way stops when it comes up', (t) async {
      await screen(t);
      resetCompanionFloor();
      t.view.viewInsets = const FakeViewPadding(bottom: 900); // 300 logical pixels of keyboard
      addTearDown(t.view.resetViewInsets);
      await t.pumpWidget(shell(const Buddy(eager: true, only: Excursion.stroll), onBehind: () {}));
      final typing = spriteRect(t);
      expect(typing.bottom, 800 - 300 - 8, reason: 'in its corner, just above the keyboard');
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 100));
        expect(spriteRect(t), typing, reason: 'it does not run about over what is being typed');
      }

      // The keyboard goes: in its corner at the bottom again, and the outings start again.
      t.view.resetViewInsets();
      await t.pump();
      final home = spriteRect(t);
      expect(home.bottom, 800 - 8);
      var out = false;
      for (var i = 0; i < 300 && !out; i++) {
        await t.pump(const Duration(milliseconds: 100));
        out = spriteRect(t).left > home.left + 50;
      }
      expect(out, isTrue, reason: 'off on its stroll');

      // Mid-stroll the keyboard comes up: straight back to its corner above it, not walking across the middle of the screen.
      t.view.viewInsets = const FakeViewPadding(bottom: 900);
      await t.pump();
      await t.pump();
      expect(spriteRect(t), typing);
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
        expect(spriteRect(t), typing);
      }
    });

    testWidgets('an outing under way follows the floor when the message box under it grows', (t) async {
      await screen(t);
      resetCompanionFloor();
      Widget page(double composer) => app(
            Scaffold(
              body: Stack(children: [
                Positioned.fill(
                  child: Column(children: [
                    const Expanded(child: SizedBox.expand()),
                    CompanionFloor(child: SizedBox(height: composer, width: double.infinity)),
                  ]),
                ),
                const Buddy(eager: true, only: Excursion.stroll),
              ]),
            ),
          );
      await t.pumpWidget(page(60));
      await t.pump();
      await t.pump();
      final home = spriteRect(t);
      var out = false;
      for (var i = 0; i < 60 && !out; i++) {
        await t.pump(const Duration(milliseconds: 100));
        out = spriteRect(t).left > home.left + 50;
      }
      expect(out, isTrue);
      expect(spriteRect(t).bottom, home.bottom);

      await t.pumpWidget(page(160)); // a second line of text, a photo attached
      await t.pump();
      await t.pump();
      final now = spriteRect(t);
      expect(now.left, greaterThan(home.left + 50), reason: 'still out on its stroll');
      expect(now.bottom, lessThanOrEqualTo(800 - 160), reason: 'walking along the top of the bigger box, not through it');
    });

    testWidgets('a lap of the screen turns it sideways and upside down', (t) async {
      await screen(t);
      await t.pumpWidget(shell(const Buddy(eager: true, only: Excursion.patrol), onBehind: () {}));
      await t.pump(const Duration(milliseconds: 1600));
      await t.pump(const Duration(milliseconds: 16));
      final turns = <double>{};
      for (var i = 0; i < 200; i++) {
        await t.pump(const Duration(milliseconds: 100));
        final tf = t.widget<Transform>(find.descendant(of: find.byType(Buddy), matching: find.byType(Transform)).first);
        turns.add(tf.transform.storage[0].roundToDouble() * 10 + tf.transform.storage[1].roundToDouble());
      }
      expect(turns.length, greaterThanOrEqualTo(3), reason: 'floor, walls and ceiling: several ways up');
    });

    testWidgets('stays in its corner for people who asked for less motion', (t) async {
      await screen(t);
      await t.pumpWidget(shell(const Buddy(eager: true, only: Excursion.stroll), onBehind: () {}, reduceMotion: true));
      final home = spriteRect(t);
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 100));
        expect(spriteRect(t), home);
      }
    });
  });
}
