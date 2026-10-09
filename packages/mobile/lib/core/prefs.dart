import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'storage.dart';
import 'theme.dart';

/// The things a person sets on this phone only. (Notification choices live on their account.)
class Prefs {
  const Prefs({
    this.textSize = 'default',
    this.haptics = true,
    this.theme = ThemeChoice.dark,
    this.accent = AccentName.gold,
    this.reduceMotion = false,
    this.startTab = 'assistant',
    this.defaultMode = 'auto',
    this.defaultModel = '',
    this.defaultEffort = '',
  });

  /// small | default | large: scales every size in the app.
  final String textSize;
  final bool haptics;
  final ThemeChoice theme;
  final AccentName accent;
  final bool reduceMotion;

  /// assistant | computers | connections | machines
  final String startTab;

  /// What a new chat on a machine starts with. Empty = the machine's own default.
  final String defaultMode;
  final String defaultModel;
  final String defaultEffort;

  double get textScale => textSizePercent[textSize]! / 100;

  Map<String, dynamic> toJson() => {
        'textSize': textSize,
        'haptics': haptics,
        'theme': theme.name,
        'accent': accent.name,
        'reduceMotion': reduceMotion,
        'startTab': startTab,
        'defaultMode': defaultMode,
        'defaultModel': defaultModel,
        'defaultEffort': defaultEffort,
      };

  Prefs copyWith({
    String? textSize,
    bool? haptics,
    ThemeChoice? theme,
    AccentName? accent,
    bool? reduceMotion,
    String? startTab,
    String? defaultMode,
    String? defaultModel,
    String? defaultEffort,
  }) =>
      parsePrefs(jsonEncode({
        ...toJson(),
        'textSize': ?textSize,
        'haptics': ?haptics,
        if (theme != null) 'theme': theme.name,
        if (accent != null) 'accent': accent.name,
        'reduceMotion': ?reduceMotion,
        'startTab': ?startTab,
        'defaultMode': ?defaultMode,
        'defaultModel': ?defaultModel,
        'defaultEffort': ?defaultEffort,
      }));
}

const defaultPrefs = Prefs();

const textSizePercent = {'small': 93.75, 'default': 100.0, 'large': 112.5};

const startTabs = [
  (value: 'assistant', label: 'Chat'),
  (value: 'machines', label: 'Machines'),
  (value: 'automations', label: 'Automations'),
  (value: 'connections', label: 'Connections'),
];

const permissionModes = [
  (value: 'auto', label: 'Autonomous', hint: 'Does the work on its own: answers its own prompts, checks its work, fixes and tries again until done'),
  (value: 'default', label: 'Ask first', hint: 'Asks before anything that changes things'),
  (value: 'acceptEdits', label: 'Accept edits', hint: 'Edits files without asking'),
  (value: 'plan', label: 'Plan mode', hint: 'Plans first, changes nothing'),
  (value: 'dontAsk', label: "Don't ask", hint: 'Never stops to ask'),
  (value: 'bypassPermissions', label: 'Bypass permissions', hint: 'Skips every check. Use with care'),
];

const models = [
  (value: '', label: 'Machine default'),
  (value: 'claude-sonnet-5-5', label: 'Sonnet 5.5'),
  (value: 'claude-opus-5-5', label: 'Opus 5.5'),
  (value: 'claude-haiku-4-5-20251001', label: 'Haiku 4.5'),
  (value: 'claude-fable-5-1', label: 'Fable 5.1'),
];

const efforts = [
  (value: '', label: 'Machine default'),
  (value: 'low', label: 'Low'),
  (value: 'medium', label: 'Medium'),
  (value: 'high', label: 'High'),
  (value: 'xhigh', label: 'xHigh'),
  (value: 'max', label: 'Max'),
];

const _key = 'escanor.prefs.v1';
const _autonomyMigrated = 'escanor.migrated.autonomy.v1';

T _oneOf<T>(Object? v, List<T> allowed, T fallback) => allowed.contains(v) ? v as T : fallback;

/// Read stored preferences defensively: anything damaged falls back to the default, field by field.
Prefs parsePrefs(String? raw) {
  Object? v;
  try {
    v = raw == null ? null : jsonDecode(raw);
  } catch (_) {
    v = null;
  }
  final o = v is Map ? v : const {};
  ThemeChoice theme = defaultPrefs.theme;
  for (final t in ThemeChoice.values) {
    if (t.name == o['theme']) theme = t;
  }
  AccentName accent = defaultPrefs.accent;
  for (final a in AccentName.values) {
    if (a.name == o['accent']) accent = a;
  }
  return Prefs(
    textSize: _oneOf(o['textSize'], const ['small', 'default', 'large'], defaultPrefs.textSize),
    haptics: o['haptics'] is bool ? o['haptics'] as bool : defaultPrefs.haptics,
    theme: theme,
    accent: accent,
    reduceMotion: o['reduceMotion'] is bool ? o['reduceMotion'] as bool : defaultPrefs.reduceMotion,
    startTab: _oneOf(o['startTab'] == 'computers' ? 'machines' : o['startTab'], startTabs.map((s) => s.value).toList(), defaultPrefs.startTab),
    defaultMode: _oneOf(o['defaultMode'], permissionModes.map((m) => m.value).toList(), defaultPrefs.defaultMode),
    defaultModel: _oneOf(o['defaultModel'], models.map((m) => m.value).toList(), defaultPrefs.defaultModel),
    defaultEffort: _oneOf(o['defaultEffort'], efforts.map((m) => m.value).toList(), defaultPrefs.defaultEffort),
  );
}

class PrefsNotifier extends Notifier<Prefs> {
  @override
  Prefs build() {
    var p = parsePrefs(Storage.instance.getString(_key));
    // Escanor works on its own now. A phone that still asks before everything (the old default) moves over once; after that the
    // choice is theirs, and "Ask first" stays if they pick it.
    if (Storage.instance.getString(_autonomyMigrated) == null) {
      Storage.instance.setString(_autonomyMigrated, '1');
      if (p.defaultMode == 'default') {
        p = p.copyWith(defaultMode: 'auto');
        Storage.instance.setString(_key, jsonEncode(p.toJson()));
      }
    }
    return p;
  }

  void update(Prefs Function(Prefs) change) {
    state = change(state);
    Storage.instance.setString(_key, jsonEncode(state.toJson()));
  }

  void reset() {
    Storage.instance.remove(_key);
    state = defaultPrefs;
  }
}

final prefsProvider = NotifierProvider<PrefsNotifier, Prefs>(PrefsNotifier.new);

/// The current prefs outside a widget (e.g. haptics from a callback).
Prefs currentPrefs() => parsePrefs(Storage.instance.getString(_key));

/// A short tap, if the person wants them.
void haptic() {
  if (!currentPrefs().haptics) return;
  HapticFeedback.selectionClick();
}
