import 'dart:math' as math;
import 'dart:typed_data';

import 'package:escanor/features/companion/animals.dart';
import 'package:escanor/features/companion/sounds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('picks a call by the dice, never past the last one', () {
    expect(pickCall(Animal.dog, 0), voices[Animal.dog]![0]);
    expect(pickCall(Animal.dog, 0.99), voices[Animal.dog]![1]);
    expect(pickCall(Animal.cat, 0.99), voices[Animal.cat]![0]);
  });

  for (final a in Animal.values) {
    test('the ${a.name} call is a real, audible WAV of the right length', () {
      final notes = pickCall(a, 0);
      final samples = synthesize(notes, random: math.Random(1));
      final seconds = samples.length / sampleRate;
      expect(seconds * 1000, greaterThanOrEqualTo(callLength(notes)));
      expect(seconds * 1000, lessThan(callLength(notes) + 150));
      final peak = samples.fold<double>(0, (m, s) => math.max(m, s.abs()));
      expect(peak, greaterThan(0.02), reason: 'it can be heard');
      expect(peak, lessThanOrEqualTo(1));
      // the end is quiet: no click when it stops
      expect(samples.last.abs(), lessThan(0.01));

      final wav = renderCall(a, 0);
      final b = ByteData.sublistView(wav);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(b.getUint16(22, Endian.little), 1, reason: 'mono');
      expect(b.getUint32(24, Endian.little), sampleRate);
      expect(b.getUint32(40, Endian.little), wav.length - 44);
      expect(identical(renderCall(a, 0), wav), isTrue, reason: 'made once and kept');
    });
  }

  test('each animal sounds different from the others', () {
    final firsts = Animal.values.map((a) => synthesize(pickCall(a, 0), random: math.Random(1)).take(4000).map((s) => (s * 1000).round()).join(',')).toSet();
    expect(firsts.length, Animal.values.length);
  });
}
