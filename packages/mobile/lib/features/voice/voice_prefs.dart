import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/storage.dart';

/// What the person chose about voice on this phone.
@immutable
class VoicePrefs {
  const VoicePrefs({this.directCalls = true, this.wakeWord = false, this.controlConsent = false});

  /// Place calls themselves (needs Android's Phone permission); off means the dialer opens with the number filled in.
  final bool directCalls;

  /// Listen for "Hey Escanor" in the background.
  final bool wakeWord;

  /// Read what phone control does and agreed to it, in the app, before being sent to Android's Accessibility settings.
  final bool controlConsent;

  VoicePrefs copyWith({bool? directCalls, bool? wakeWord, bool? controlConsent}) => VoicePrefs(
        directCalls: directCalls ?? this.directCalls,
        wakeWord: wakeWord ?? this.wakeWord,
        controlConsent: controlConsent ?? this.controlConsent,
      );

  Map<String, Object?> toJson() => {'directCalls': directCalls, 'wakeWord': wakeWord, 'controlConsent': controlConsent};

  @override
  bool operator ==(Object other) => other is VoicePrefs && other.directCalls == directCalls && other.wakeWord == wakeWord && other.controlConsent == controlConsent;
  @override
  int get hashCode => Object.hash(directCalls, wakeWord, controlConsent);
  @override
  String toString() => 'VoicePrefs(${toJson()})';
}

const defaultVoicePrefs = VoicePrefs();
const _key = 'escanor.voice.v1';

VoicePrefs parseVoicePrefs(String? raw) {
  Object? v;
  try {
    v = raw == null || raw.isEmpty ? null : jsonDecode(raw);
  } catch (_) {
    v = null;
  }
  final o = v is Map ? v : const {};
  return VoicePrefs(
    directCalls: o['directCalls'] is bool ? o['directCalls'] as bool : defaultVoicePrefs.directCalls,
    wakeWord: o['wakeWord'] is bool ? o['wakeWord'] as bool : defaultVoicePrefs.wakeWord,
    controlConsent: o['controlConsent'] is bool ? o['controlConsent'] as bool : defaultVoicePrefs.controlConsent,
  );
}

/// The voice prefs, live: screens listen to this (ValueListenableBuilder) and change it with [setVoicePrefs].
final ValueNotifier<VoicePrefs> voicePrefs = ValueNotifier<VoicePrefs>(defaultVoicePrefs);
bool _loaded = false;

VoicePrefs getVoicePrefs() {
  if (!_loaded) {
    try {
      voicePrefs.value = parseVoicePrefs(Storage.instance.getString(_key));
      _loaded = true;
    } catch (_) {
      // storage not ready: the defaults for now
    }
  }
  return voicePrefs.value;
}

void setVoicePrefs(VoicePrefs Function(VoicePrefs p) change) {
  final next = change(getVoicePrefs());
  voicePrefs.value = next;
  try {
    Storage.instance.setString(_key, jsonEncode(next.toJson()));
  } catch (_) {
    // kept for this visit only
  }
}

/// For tests (and sign-out): read the stored prefs again next time.
void reloadVoicePrefs() {
  _loaded = false;
  voicePrefs.value = defaultVoicePrefs;
}
