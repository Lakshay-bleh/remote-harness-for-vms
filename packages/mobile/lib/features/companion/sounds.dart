/// What each companion sounds like when it is tapped, made on the spot (no sound files to download). [voices] is plain
/// data: each animal has a few short "calls", each a handful of notes (a pitch that glides from one value to another,
/// with a waveform, a loudness, and optionally a wobble and a muffling filter). [renderCall] turns one into a WAV file
/// in memory, the same tones the web app makes with its audio graph; `sound_player.dart` plays it.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'animals.dart';

enum Wave { sine, triangle, sawtooth, square }

class Note {
  const Note({required this.at, required this.dur, required this.from, required this.to, required this.wave, required this.gain, this.vibrato, this.lowpass, this.noise});

  /// Seconds after the call starts.
  final double at;
  final double dur;

  /// Pitch in Hz at the start and at the end of the note.
  final double from;
  final double to;
  final Wave wave;
  final double gain;

  /// Wobble: (times a second, how many Hz).
  final (double, double)? vibrato;

  /// Muffle everything above this many Hz.
  final double? lowpass;

  /// A burst of breath or noise mixed in, 0 to 1.
  final double? noise;

  @override
  String toString() => 'Note($at,$dur,$from,$to,${wave.name},$gain,$vibrato,$lowpass,$noise)';
}

Note _bark(double at, double f) => Note(at: at, dur: 0.15, from: f, to: f * 0.5, wave: Wave.sawtooth, gain: 0.45, lowpass: 1500, noise: 0.25);

final Map<Animal, List<List<Note>>> voices = {
  Animal.dog: [
    [_bark(0, 260), _bark(0.24, 240)],
    [_bark(0, 300), _bark(0.2, 280), _bark(0.4, 250)],
  ],
  Animal.unicorn: [
    const [
      Note(at: 0, dur: 0.18, from: 700, to: 1150, wave: Wave.sawtooth, gain: 0.3, vibrato: (20, 40), lowpass: 2600),
      Note(at: 0.18, dur: 0.55, from: 1150, to: 520, wave: Wave.sawtooth, gain: 0.3, vibrato: (22, 45), lowpass: 2600),
      Note(at: 0.7, dur: 0.25, from: 2400, to: 2400, wave: Wave.sine, gain: 0.12, vibrato: (6, 30)),
      Note(at: 0.85, dur: 0.25, from: 3100, to: 3100, wave: Wave.sine, gain: 0.1),
    ],
  ],
  Animal.pigeon: [
    const [
      Note(at: 0, dur: 0.2, from: 320, to: 250, wave: Wave.sine, gain: 0.5, vibrato: (9, 14)),
      Note(at: 0.3, dur: 0.2, from: 320, to: 250, wave: Wave.sine, gain: 0.5, vibrato: (9, 14)),
      Note(at: 0.6, dur: 0.55, from: 300, to: 200, wave: Wave.sine, gain: 0.55, vibrato: (8, 18)),
    ],
  ],
  Animal.hamster: [
    const [
      Note(at: 0, dur: 0.07, from: 2100, to: 3200, wave: Wave.sine, gain: 0.25),
      Note(at: 0.12, dur: 0.07, from: 2200, to: 3300, wave: Wave.sine, gain: 0.25),
      Note(at: 0.3, dur: 0.1, from: 2000, to: 3400, wave: Wave.sine, gain: 0.25),
    ],
  ],
  Animal.cat: [
    const [
      Note(at: 0, dur: 0.25, from: 420, to: 900, wave: Wave.triangle, gain: 0.4, vibrato: (6, 12), lowpass: 2400),
      Note(at: 0.25, dur: 0.4, from: 900, to: 480, wave: Wave.triangle, gain: 0.4, vibrato: (7, 16), lowpass: 2000),
    ],
  ],
  Animal.elephant: [
    const [
      Note(at: 0, dur: 0.35, from: 280, to: 580, wave: Wave.sawtooth, gain: 0.35, vibrato: (7, 12), lowpass: 1900, noise: 0.1),
      Note(at: 0.35, dur: 0.5, from: 580, to: 400, wave: Wave.sawtooth, gain: 0.35, vibrato: (7, 16), lowpass: 1700),
    ],
  ],
};

/// How long a call lasts, in milliseconds.
int callLength(List<Note> notes) => (notes.map((n) => n.at + n.dur).reduce(math.max) * 1000).round();

/// Which call to make for a number from 0 up to 1.
List<Note> pickCall(Animal animal, double pick) {
  final calls = voices[animal]!;
  return calls[math.min(calls.length - 1, (pick * calls.length).floor())];
}

const int sampleRate = 22050;

/// A short lead-in, like the web's 20 ms, so the first note is not clipped by the player starting up.
const double _lead = 0.02;

double _osc(Wave wave, double phase) {
  // phase in cycles, 0..1
  final p = phase - phase.floorToDouble();
  return switch (wave) {
    Wave.sine => math.sin(2 * math.pi * p),
    Wave.square => p < 0.5 ? 1.0 : -1.0,
    Wave.sawtooth => 2 * p - 1,
    Wave.triangle => p < 0.5 ? 4 * p - 1 : 3 - 4 * p,
  };
}

/// The samples of one call, -1..1, mono, at [sampleRate]: each note an oscillator gliding from its start pitch to its
/// end pitch (with its wobble), shaped by a quick rise and an exponential fall, muffled if it says so, with its breath
/// of noise; everything at half volume, as on the web.
Float64List synthesize(List<Note> notes, {math.Random? random}) {
  final rnd = random ?? math.Random();
  final seconds = _lead + notes.map((n) => n.at + n.dur).reduce(math.max) + 0.06;
  final out = Float64List((seconds * sampleRate).ceil());
  const master = 0.5;
  for (final n in notes) {
    final start = ((_lead + n.at) * sampleRate).round();
    final len = math.max(1, (n.dur * sampleRate).floor());
    final attack = math.min(0.02, n.dur / 3);
    // the low-pass, a two-pole (biquad) filter like the browser's, Q = 1/sqrt(2)
    double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
    if (n.lowpass != null) {
      final w0 = 2 * math.pi * math.min(n.lowpass!, sampleRate / 2 - 1) / sampleRate;
      final alpha = math.sin(w0) / (2 * math.sqrt1_2);
      final cosw = math.cos(w0);
      final a0 = 1 + alpha;
      b0 = (1 - cosw) / 2 / a0;
      b1 = (1 - cosw) / a0;
      b2 = (1 - cosw) / 2 / a0;
      a1 = -2 * cosw / a0;
      a2 = (1 - alpha) / a0;
    }
    double x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    var phase = 0.0;
    for (var i = 0; i < len && start + i < out.length; i++) {
      final t = i / sampleRate;
      final k = t / n.dur;
      var freq = n.from + (n.to - n.from) * k;
      if (n.vibrato != null) freq += math.sin(2 * math.pi * n.vibrato!.$1 * t) * n.vibrato!.$2;
      phase += freq / sampleRate;
      // the envelope: 0.0001 up to the gain, then an exponential fall back to 0.0001 at the end
      final double env = t < attack
          ? 0.0001 + (n.gain - 0.0001) * (t / attack)
          : n.gain * math.pow(0.0001 / n.gain, (t - attack) / math.max(1e-6, n.dur - attack)).toDouble();
      final x = _osc(n.wave, phase) * env;
      double y = x;
      if (n.lowpass != null) {
        y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        x2 = x1;
        x1 = x;
        y2 = y1;
        y1 = y;
      }
      var s = y;
      if (n.noise != null) s += (rnd.nextDouble() * 2 - 1) * (1 - i / len) * n.gain * n.noise!;
      out[start + i] += s * master;
    }
  }
  for (var i = 0; i < out.length; i++) {
    out[i] = out[i].clamp(-1.0, 1.0);
  }
  return out;
}

/// 16-bit mono PCM samples wrapped as a WAV file.
Uint8List wavBytes(Float64List samples, [int rate = sampleRate]) {
  final dataLen = samples.length * 2;
  final b = ByteData(44 + dataLen);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  b.setUint32(4, 36 + dataLen, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  b.setUint32(16, 16, Endian.little); // the format chunk's size
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * 2, Endian.little); // bytes a second
  b.setUint16(32, 2, Endian.little); // bytes a frame
  b.setUint16(34, 16, Endian.little); // bits a sample
  ascii(36, 'data');
  b.setUint32(40, dataLen, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    b.setInt16(44 + i * 2, (samples[i] * 32767).round(), Endian.little);
  }
  return b.buffer.asUint8List();
}

final Map<String, Uint8List> _rendered = {};

/// One call as a WAV file, made once and kept (each animal has only one or two).
Uint8List renderCall(Animal animal, double pick) {
  final notes = pickCall(animal, pick);
  final key = '${animal.name}:${voices[animal]!.indexOf(notes)}';
  return _rendered.putIfAbsent(key, () => wavBytes(synthesize(notes)));
}
