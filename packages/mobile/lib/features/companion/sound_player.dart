import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'animals.dart';
import 'sounds.dart';

AudioPlayer? _player;

/// Android: a short sound effect that does not pause the person's music. (iOS keeps the app's audio session as it is,
/// so the voice features' session is left alone.)
final AudioContext _androidQuiet = AudioContext(
  android: const AudioContextAndroid(
    contentType: AndroidContentType.sonification,
    usageType: AndroidUsageType.assistanceSonification,
    audioFocus: AndroidAudioFocus.none,
  ),
);

/// Make a call. Quiet by design, and silent where there is no audio. Returns how long it lasts, in milliseconds.
int playVoice(Animal animal, [double? pick]) {
  final p = pick ?? math.Random().nextDouble();
  final notes = pickCall(animal, p);
  () async {
    try {
      final bytes = renderCall(animal, p);
      final player = _player ??= AudioPlayer();
      await player.stop();
      await player.play(
        BytesSource(bytes, mimeType: 'audio/wav'),
        ctx: !kIsWeb && Platform.isAndroid ? _androidQuiet : null,
      );
    } catch (_) {
      // no sound is better than a broken tap
    }
  }();
  return callLength(notes);
}
