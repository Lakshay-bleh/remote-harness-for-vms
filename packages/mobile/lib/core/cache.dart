import 'dart:convert';

import 'storage.dart';

/// What the phone remembers between visits to a screen, so opening one shows what it showed last time
/// while the fresh answer loads. Never anything secret. Emptied on sign-out.
const _prefix = 'escanor.cache.v1:';
const _maxEntryChars = 250000;

const second = Duration(seconds: 1);
const minute = Duration(minutes: 1);
const hour = Duration(hours: 1);

class CachePolicy {
  const CachePolicy(this.key, {required this.ttl, this.maxAge = const Duration(hours: 24)});
  final String key;

  /// Trusted without asking again for this long.
  final Duration ttl;

  /// Shown while refreshing for this long; older is ignored.
  final Duration maxAge;
}

class CacheHit<T> {
  CacheHit(this.value, this.age, this.fresh);
  final T value;
  final Duration age;
  final bool fresh;
}

final Map<String, ({Object? v, int at})> _memory = {};

CacheHit<Object?>? readCache(CachePolicy policy, {DateTime? now}) {
  final t = (now ?? DateTime.now()).millisecondsSinceEpoch;
  var entry = _memory[policy.key];
  if (entry == null) {
    try {
      final raw = Storage.instance.getString(_prefix + policy.key);
      if (raw != null) {
        final parsed = jsonDecode(raw);
        if (parsed is Map && parsed['at'] is int && parsed.containsKey('v')) {
          entry = (v: parsed['v'], at: parsed['at'] as int);
          _memory[policy.key] = entry;
        }
      }
    } catch (_) {
      return null;
    }
  }
  if (entry == null) return null;
  final age = t - entry.at;
  if (age < 0 || age > policy.maxAge.inMilliseconds) return null;
  return CacheHit(entry.v, Duration(milliseconds: age), age < policy.ttl.inMilliseconds);
}

/// [value] must be JSON-encodable (maps, lists, strings, numbers).
void writeCache(String key, Object? value, {DateTime? now}) {
  final entry = (v: value, at: (now ?? DateTime.now()).millisecondsSinceEpoch);
  _memory[key] = entry;
  try {
    final raw = jsonEncode({'v': value, 'at': entry.at});
    if (raw.length <= _maxEntryChars) {
      Storage.instance.setString(_prefix + key, raw);
    } else {
      Storage.instance.remove(_prefix + key);
    }
  } catch (_) {
    // not encodable or storage unavailable: the in-memory copy still serves this session
  }
}

/// Forget one entry, or every entry whose key starts with [prefix].
void dropCache(String prefix) {
  _memory.removeWhere((k, _) => k.startsWith(prefix));
  try {
    final prefs = Storage.instance.prefs;
    for (final k in prefs.getKeys().where((k) => k.startsWith(_prefix + prefix)).toList()) {
      prefs.remove(k);
    }
  } catch (_) {}
}

void clearCache() => dropCache('');
