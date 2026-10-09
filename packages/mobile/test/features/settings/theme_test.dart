import 'dart:math' as math;

import 'package:escanor/core/theme.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// Port of packages/web/src/escanor/settings/theme.test.ts, against lib/core/theme.dart.
double contrast(Color a, Color b) {
  final la = luminanceOf(a), lb = luminanceOf(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('resolveTheme', () {
    test('follows the phone only when asked to', () {
      expect(resolveTheme(ThemeChoice.system, true), ThemeName.dark);
      expect(resolveTheme(ThemeChoice.system, false), ThemeName.light);
      expect(resolveTheme(ThemeChoice.light, true), ThemeName.light);
      expect(resolveTheme(ThemeChoice.black, false), ThemeName.black);
    });
    test('has a page colour for every theme, the same as the website', () {
      expect(EscanorColors.of(ThemeName.dark, AccentName.gold).canvas, const Color(0xFF050505));
      expect(EscanorColors.of(ThemeName.light, AccentName.gold).canvas, const Color(0xFFFAF8F4));
      expect(EscanorColors.of(ThemeName.black, AccentName.gold).canvas, const Color(0xFF000000));
    });
  });

  group('accents', () {
    test('keeps text on a button readable (WCAG AA, 4.5:1) for every accent on both themes', () {
      for (final name in AccentName.values) {
        for (final bg in [accents[name]!.dark, accents[name]!.light]) {
          expect(contrast(bg, onAccent(bg)) >= 4.5, true, reason: '$name ${contrast(bg, onAccent(bg)).toStringAsFixed(2)}');
        }
      }
    });
    test('sets the accent, its pressed tone and the text on it', () {
      final c = EscanorColors.of(ThemeName.dark, AccentName.teal);
      expect(c.primary, accents[AccentName.teal]!.dark);
      expect(c.onPrimary, onAccent(c.primary));
      expect(luminanceOf(c.primaryActive) < luminanceOf(c.primary), true);
    });
    test('uses the deeper tone on the light theme', () {
      expect(EscanorColors.of(ThemeName.light, AccentName.gold).primary, isNot(EscanorColors.of(ThemeName.dark, AccentName.gold).primary));
    });
    test('every theme choice has a label and a hint', () {
      expect(themeChoices.map((t) => t.$1).toSet(), ThemeChoice.values.toSet());
      for (final t in themeChoices) {
        expect(t.$2.isNotEmpty && t.$3.isNotEmpty, true);
      }
    });
  });
}
