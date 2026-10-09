// Port of computer/qr.test.ts. Decoding itself is native now (mobile_scanner / ML Kit), so these check that the help for poor
// conditions turns a hard frame back into a clean black-on-white code, module for module.
import 'dart:convert';
import 'dart:typed_data';

import 'package:escanor/features/computers/pairing.dart';
import 'package:escanor/features/computers/protocol/secure.dart';
import 'package:escanor/features/computers/qr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart' show QrCode, QrErrorCorrectLevel, QrImage;

/// Rasterise a QR the way a camera frame looks: dark modules on light, with a quiet zone, scaled up.
({Uint8List rgba, int width, int height, QrImage qr, int scale, int margin}) frame(
  String text, {
  int scale = 6,
  int margin = 4,
  int dark = 20,
  int light = 255,
}) {
  final qr = QrImage(QrCode.fromData(data: text, errorCorrectLevel: QrErrorCorrectLevel.M));
  final n = qr.moduleCount;
  final size = (n + margin * 2) * scale;
  final rgba = Uint8List(size * size * 4);
  for (var p = 0; p < size * size; p++) {
    final x = (p % size) ~/ scale - margin, y = (p ~/ size) ~/ scale - margin;
    final v = x >= 0 && y >= 0 && x < n && y < n && qr.isDark(y, x) ? dark : light;
    rgba.setAll(p * 4, [v, v, v, 255]);
  }
  return (rgba: rgba, width: size, height: size, qr: qr, scale: scale, margin: margin);
}

/// Share of modules (sampled at their centres) that read the right way round in a black/white image.
double agreement(Uint8List out, int width, ({QrImage qr, int scale, int margin}) f) {
  final n = f.qr.moduleCount;
  var good = 0;
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final px = (x + f.margin) * f.scale + f.scale ~/ 2, py = (y + f.margin) * f.scale + f.scale ~/ 2;
      final black = out[(py * width + px) * 4] < 128;
      if (black == f.qr.isDark(y, x)) good++;
    }
  }
  return good / (n * n);
}

String payload() => jsonEncode({
  'v': 1,
  'code': formatCode(randomBytes(20)),
  'machine': 'Work Laptop',
  'lan': ['192.168.1.20:47625', '100.101.102.103:47625'],
  'agentId': '6f2c1f0e-1d3a-4d79-9a0e-5b2a6f0c1d11',
});

void main() {
  test('the QR that Escanor Desktop shows carries a valid pairing', () {
    final p = payload();
    expect(parseEntry(p)?.payload?.agentId, '6f2c1f0e-1d3a-4d79-9a0e-5b2a6f0c1d11');
  });

  group('poor conditions', () {
    test('a dim, low-contrast code (a screen turned down, seen in a dark room) is stretched to black and white', () {
      final f = frame(payload(), scale: 5, dark: 55, light: 80);
      final out = stretchContrast(f.rgba, f.width, f.height);
      expect(agreement(out, f.width, (qr: f.qr, scale: f.scale, margin: f.margin)), 1.0);
      expect(out.where((v) => v != 255 && v != 0).length, lessThan(out.length ~/ 4 + 1), reason: 'mostly pure black or white');
    });

    test('a code with a shadow across it (lit from one side) is judged area by area', () {
      final f = frame(payload(), scale: 5);
      for (var y = 0; y < f.height; y++) {
        for (var x = 0; x < f.width; x++) {
          final k = 0.28 + 0.72 * (x / f.width); // a left-to-right ramp from deep shade to full light
          final i = (y * f.width + x) * 4;
          final v = (f.rgba[i] * k).round();
          f.rgba.setAll(i, [v, v, v]);
        }
      }
      // the plain picture cannot be split with one threshold: the shaded "white" is darker than the lit "black"...
      final out = localThreshold(f.rgba, f.width, f.height);
      expect(agreement(out, f.width, (qr: f.qr, scale: f.scale, margin: f.margin)), greaterThan(0.97));
    });

    test('a light-on-dark code (a dark-mode screen) keeps its modules, inverted', () {
      final f = frame(payload(), scale: 5, dark: 250, light: 15);
      final out = stretchContrast(f.rgba, f.width, f.height);
      expect(agreement(out, f.width, (qr: f.qr, scale: f.scale, margin: f.margin)), 0.0); // every module flipped, none lost
    });

    test('a code small in the frame is cropped to the aiming box, clutter left out', () {
      final code = frame(payload(), scale: 4);
      final w = code.width * 2, h = code.height * 2;
      final rgba = Uint8List(w * h * 4);
      for (var i = 0; i < w * h; i++) {
        final v = 90 + ((i * 2654435761) >> 24) % 110;
        rgba.setAll(i * 4, [v, v, v, 255]);
      }
      final ox = (w - code.width) ~/ 2, oy = (h - code.height) ~/ 2;
      for (var y = 0; y < code.height; y++) {
        rgba.setRange(((oy + y) * w + ox) * 4, ((oy + y) * w + ox + code.width) * 4, code.rgba, y * code.width * 4);
      }
      final c = centreCrop(rgba, w, h, 0.5);
      expect(c.width, code.width);
      expect(c.height, code.height);
      expect(c.data, code.rgba, reason: 'exactly the code, nothing around it');
      expect(hardVariants(Rgba(rgba, w, h)).length, 3);
    });

    test('a frame with nothing in it stays featureless', () {
      final blank = Uint8List(240 * 240 * 4)..fillRange(0, 240 * 240 * 4, 128);
      final out = stretchContrast(blank, 240, 240);
      expect(out.toSet().length, lessThanOrEqualTo(2)); // one grey and the alpha
    });
  });
}
