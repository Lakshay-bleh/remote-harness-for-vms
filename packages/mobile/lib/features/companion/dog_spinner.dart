import 'package:flutter/material.dart';

import 'pixel_dog.dart';
import 'sprites.dart';

/// Loading, wherever a spinner would go (beside a line of text): a tiny companion running on the spot. [size] is how
/// wide it may be; the picture is drawn at the largest crisp pixel size that fits (36 wide, 22 tall at 1x).
class DogSpinner extends StatelessWidget {
  const DogSpinner({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Loading',
        container: true,
        child: SizedBox(
          width: size,
          height: size * H / W,
          child: Center(child: PixelDog(scene: Scene.run, scale: size / W, interactive: false)),
        ),
      );
}
