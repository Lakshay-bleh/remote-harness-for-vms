import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/storage.dart';
import 'protocol/client.dart';

/// What this phone remembers about ONE computer: a name of the person's choosing, and how to reach it. Kept on this phone only.
enum RoutePref { auto, cloud, lan }

class ComputerPrefs {
  const ComputerPrefs({this.alias = '', this.route = RoutePref.auto});
  final String alias;
  final RoutePref route;

  Map<String, dynamic> toJson() => {'alias': alias, 'route': route.name};

  @override
  bool operator ==(Object other) => other is ComputerPrefs && other.alias == alias && other.route == route;
  @override
  int get hashCode => Object.hash(alias, route);
  @override
  String toString() => 'ComputerPrefs($alias, ${route.name})';
}

const defaultComputerPrefs = ComputerPrefs();
const _key = 'escanor.computer.prefs.v1';

/// A name as typed: control characters out, spaces collapsed, at most 40 characters.
String cleanName(String raw) {
  final s = raw.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return s.length <= 40 ? s : s.substring(0, 40);
}

ComputerPrefs _fromObject(Object? v) {
  final o = v is Map ? v : const {};
  final route = switch (o['route']) {
    'cloud' => RoutePref.cloud,
    'lan' => RoutePref.lan,
    _ => RoutePref.auto,
  };
  return ComputerPrefs(alias: o['alias'] is String ? cleanName(o['alias'] as String) : '', route: route);
}

ComputerPrefs parseComputerPrefs(String? raw) {
  Object? v;
  try {
    v = raw == null || raw.isEmpty ? null : jsonDecode(raw);
  } catch (_) {
    v = null;
  }
  return _fromObject(v);
}

String displayName(PairedComputer c, ComputerPrefs p) => p.alias.isNotEmpty ? p.alias : c.name;

/// The computer to connect to, and whether the cloud route may be used, for a connection preference. Never changes the stored
/// computer.
({PairedComputer computer, bool cloud}) applyRoute(PairedComputer c, RoutePref route) => switch (route) {
  RoutePref.cloud => (computer: c.copyWith(lan: const []), cloud: true),
  RoutePref.lan => (computer: c, cloud: false),
  RoutePref.auto => (computer: c, cloud: true),
};

// ---- storage: one small record per computer id

/// Fires whenever any computer's prefs change (rename, route).
final ValueNotifier<int> computerPrefsChanges = ValueNotifier<int>(0);
Map<String, ComputerPrefs>? _cache;

Map<String, ComputerPrefs> _readAll() {
  final hit = _cache;
  if (hit != null) return hit;
  final out = <String, ComputerPrefs>{};
  try {
    final v = jsonDecode(Storage.instance.getString(_key) ?? '{}');
    if (v is Map) {
      v.forEach((id, p) => out['$id'] = _fromObject(p));
    }
  } catch (_) {
    // damaged: start clean
  }
  return _cache = out;
}

void _write(Map<String, ComputerPrefs> all) {
  _cache = all;
  try {
    Storage.instance.setString(_key, jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}));
  } catch (_) {
    // not saved, but it applies until the app closes
  }
  computerPrefsChanges.value++;
}

ComputerPrefs getComputerPrefs(String id) => _readAll()[id] ?? defaultComputerPrefs;

void setComputerPrefs(String id, {String? alias, RoutePref? route}) {
  final cur = getComputerPrefs(id);
  final next = ComputerPrefs(alias: cleanName(alias ?? cur.alias), route: route ?? cur.route);
  _write({..._readAll(), id: next});
}

void forgetComputerPrefs(String id) => _write({..._readAll()}..remove(id));

void forgetAllComputerPrefs() {
  _cache = {};
  try {
    Storage.instance.remove(_key);
  } catch (_) {}
  computerPrefsChanges.value++;
}

/// Tests: drop what is held in memory.
@visibleForTesting
void resetComputerPrefsCache() => _cache = null;
