import 'dart:convert';

import 'package:escanor/core/prefs.dart';
import 'package:escanor/core/theme.dart';
import 'package:flutter_test/flutter_test.dart';

// Port of packages/web/src/escanor/settings/prefs.test.ts, against lib/core/prefs.dart.
void main() {
  final defaults = defaultPrefs.toJson();

  test('nothing stored gives the defaults', () {
    expect(parsePrefs(null).toJson(), defaults);
    expect(parsePrefs('').toJson(), defaults);
  });

  test('damaged or hostile storage falls back to the defaults instead of throwing', () {
    expect(parsePrefs('{not json').toJson(), defaults);
    expect(parsePrefs('[1,2]').toJson(), defaults);
    expect(parsePrefs('"hello"').toJson(), defaults);
  });

  test('a valid stored value is kept, and an unknown or wrongly-typed one is ignored field by field', () {
    final got = parsePrefs(jsonEncode({'textSize': 'large', 'haptics': false, 'defaultMode': 'plan', 'defaultModel': 42, 'bogus': 1, 'defaultEffort': 'high'}));
    expect(got.textSize, 'large');
    expect(got.haptics, false);
    expect(got.defaultMode, 'plan');
    expect(got.defaultModel, defaultPrefs.defaultModel); // 42 is not a model id
    expect(got.defaultEffort, 'high');
    expect(got.toJson().containsKey('bogus'), false);
  });

  test('only known text sizes and permission modes are accepted', () {
    expect(parsePrefs(jsonEncode({'textSize': 'huge'})).textSize, defaultPrefs.textSize);
    expect(parsePrefs(jsonEncode({'defaultMode': 'rm -rf'})).defaultMode, defaultPrefs.defaultMode);
  });

  test('every text size has a scale, with the default at 100%', () {
    expect(textSizePercent['default'], 100);
    expect(textSizePercent['small']! < 100 && textSizePercent['large']! > 100, true);
  });

  test('theme, accent, motion and start tab are validated field by field', () {
    final got = parsePrefs(jsonEncode({'theme': 'light', 'accent': 'violet', 'reduceMotion': true, 'startTab': 'computers'}));
    expect([got.theme, got.accent, got.reduceMotion, got.startTab], [ThemeChoice.light, AccentName.violet, true, 'machines']);
    final bad = parsePrefs(jsonEncode({'theme': 'neon', 'accent': 'plaid', 'reduceMotion': 'yes', 'startTab': 'settings'}));
    expect([bad.theme, bad.accent, bad.reduceMotion, bad.startTab], [defaultPrefs.theme, defaultPrefs.accent, defaultPrefs.reduceMotion, defaultPrefs.startTab]);
  });

  test('a change keeps every other field, and an empty model means the machine default', () {
    final p = defaultPrefs.copyWith(theme: ThemeChoice.black, defaultModel: 'claude-opus-5-5');
    expect(p.theme, ThemeChoice.black);
    expect(p.defaultModel, 'claude-opus-5-5');
    expect(p.copyWith(defaultModel: '').defaultModel, '');
    expect(p.copyWith(haptics: false).theme, ThemeChoice.black);
  });
}
