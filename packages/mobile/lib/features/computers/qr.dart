import 'dart:math';
import 'dart:typed_data';

/// Port of qr.ts's image work. The camera is read by mobile_scanner (Google's ML Kit / Apple's Vision: native autofocus, exposure
/// and both polarities), so the decoding itself is native. What is kept from the web version is the help for poor conditions: a
/// photo whose code could not be read as it is is tried again with its contrast stretched, then judged area by area, then cropped
/// to its middle (see [hardVariants]). Pure: RGBA bytes in, RGBA bytes out.

class Rgba {
  const Rgba(this.data, this.width, this.height);
  final Uint8List data;
  final int width;
  final int height;
}

double _luma(Uint8List rgba, int i) => (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) / 1000;

Uint8List _grey(int w, int h, double Function(int p) pick) {
  final out = Uint8List(w * h * 4);
  for (var p = 0; p < w * h; p++) {
    final v = pick(p).round().clamp(0, 255);
    out[p * 4] = v;
    out[p * 4 + 1] = v;
    out[p * 4 + 2] = v;
    out[p * 4 + 3] = 255;
  }
  return out;
}

/// Stretch a dim or washed-out frame to the full range: the darkest 2% becomes black and the lightest 2% white. A code seen in poor
/// light often differs from its background by only a few shades, which is too little for a decoder.
Uint8List stretchContrast(Uint8List rgba, int width, int height) {
  final n = width * height;
  final hist = List<int>.filled(256, 0);
  for (var p = 0; p < n; p++) {
    hist[_luma(rgba, p * 4).round()]++;
  }
  final cut = n * 0.02;
  var lo = 0;
  var hi = 255;
  for (var acc = 0; lo < 255 && (acc += hist[lo]) < cut; lo++) {}
  for (var acc = 0; hi > 0 && (acc += hist[hi]) < cut; hi--) {}
  final span = max(24, hi - lo);
  return _grey(width, height, (p) => ((_luma(rgba, p * 4) - lo) / span) * 255);
}

/// Black or white for each pixel against the average of the area around it, not of the whole frame. That is what copes with a
/// shadow across the screen, glare on one side, or a camera that exposes for the brightest part.
Uint8List localThreshold(Uint8List rgba, int width, int height) {
  final w = width + 1;
  final sum = Float64List(w * (height + 1));
  for (var y = 0; y < height; y++) {
    var row = 0.0;
    for (var x = 0; x < width; x++) {
      row += _luma(rgba, (y * width + x) * 4);
      sum[(y + 1) * w + x + 1] = sum[y * w + x + 1] + row;
    }
  }
  final r = max(8, (min(width, height) / 16).round());
  return _grey(width, height, (p) {
    final x = p % width;
    final y = p ~/ width;
    final x0 = max(0, x - r), x1 = min(width, x + r + 1), y0 = max(0, y - r), y1 = min(height, y + r + 1);
    final area = (x1 - x0) * (y1 - y0);
    final mean = (sum[y1 * w + x1] - sum[y0 * w + x1] - sum[y1 * w + x0] + sum[y0 * w + x0]) / area;
    return _luma(rgba, p * 4) < mean * 0.92 ? 0 : 255;
  });
}

/// The middle of a frame, cropped (the code is held in the aiming box, and the rest is only noise to the decoder).
Rgba centreCrop(Uint8List rgba, int width, int height, [double fraction = 0.7]) {
  final w = max(1, (width * fraction).round());
  final h = max(1, (height * fraction).round());
  final x0 = (width - w) ~/ 2;
  final y0 = (height - h) ~/ 2;
  final data = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    final from = ((y0 + y) * width + x0) * 4;
    data.setRange(y * w * 4, (y + 1) * w * 4, rgba, from);
  }
  return Rgba(data, w, h);
}

/// Everything that helps in poor conditions, cheapest first (after the picture as it is): the contrast stretched, then judged area
/// by area, then the middle on its own, stretched.
List<Rgba> hardVariants(Rgba img) {
  final mid = centreCrop(img.data, img.width, img.height);
  return [
    Rgba(stretchContrast(img.data, img.width, img.height), img.width, img.height),
    Rgba(localThreshold(img.data, img.width, img.height), img.width, img.height),
    Rgba(stretchContrast(mid.data, mid.width, mid.height), mid.width, mid.height),
  ];
}
