import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'pixel_dog.dart';
import 'sprites.dart';

/// CONTRACT (owned by the companion feature; keep these signatures).
/// A screen with nothing to show yet, or still loading: the companion doing its own thing, a line saying what is going
/// on, and what to do next. [scene] is one of the sprite scenes (run, sniff, dig, sit, sleep, lick, home, react).
/// [live] announces changes (a loading state); an empty state is read once.
class DogState extends StatelessWidget {
  const DogState({super.key, this.scene = 'sit', required this.title, this.text, this.action, this.scale = 5, this.live = false});
  final String scene;
  final String title;
  final String? text;
  final Widget? action;
  final double scale;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        PixelDog(scene: sceneFrom(scene), scale: scale),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 20, color: c.ink)),
        if (text != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(text!, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.6, color: c.muted)),
            ),
          ),
        if (action != null) Padding(padding: const EdgeInsets.only(top: 16), child: action),
      ]),
    );
    return live ? Semantics(liveRegion: true, container: true, child: body) : body;
  }
}

/// A small companion trotting along a line, for "loading more" at the end of a list.
class DogRunner extends StatelessWidget {
  const DogRunner({super.key, this.label = 'Loading more…'});
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        container: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const PixelDog(scene: Scene.run, scale: 2),
            const SizedBox(width: 8),
            Flexible(child: Text(label, style: TextStyle(fontSize: 12, color: context.c.muted))),
          ]),
        ),
      );
}
