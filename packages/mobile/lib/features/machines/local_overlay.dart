import 'dart:convert';

import '../../core/storage.dart';
import 'chat_choices.dart';

/// What the person changed about a chat on this phone.
class SessionOverlay {
  const SessionOverlay({this.title = '', this.hidden = false});
  final String title;
  final bool hidden;

  bool get isEmpty => title.isEmpty && !hidden;
  Map<String, Object> toJson() => {if (title.isNotEmpty) 't': title, if (hidden) 'h': true};
  static SessionOverlay from(Object? j) => j is Map ? SessionOverlay(title: j['t'] is String ? j['t'] as String : '', hidden: j['h'] == true) : const SessionOverlay();
}

/// What the person set for a machine on this phone: its name here, whether it is shown, and what new chats on it start with.
class MachineOverlay {
  const MachineOverlay({this.name = '', this.hidden = false, this.defaults, this.folder = ''});
  final String name;
  final bool hidden;

  /// Mode, model and effort for new chats on this machine (null: the app-wide defaults).
  final SavedChoices? defaults;
  final String folder;

  bool get isEmpty => name.isEmpty && !hidden && defaults == null && folder.isEmpty;

  MachineOverlay copyWith({String? name, bool? hidden, SavedChoices? Function()? defaults, String? folder}) => MachineOverlay(
        name: name ?? this.name,
        hidden: hidden ?? this.hidden,
        defaults: defaults != null ? defaults() : this.defaults,
        folder: folder ?? this.folder,
      );

  Map<String, Object> toJson() => {
        if (name.isNotEmpty) 'n': name,
        if (hidden) 'h': true,
        if (defaults != null) 'd': defaults!.toJson(),
        if (folder.isNotEmpty) 'f': folder,
      };

  static MachineOverlay from(Object? j) => j is Map
      ? MachineOverlay(
          name: j['n'] is String ? j['n'] as String : '',
          hidden: j['h'] == true,
          defaults: SavedChoices.tryParse(j['d']),
          folder: j['f'] is String ? j['f'] as String : '',
        )
      : const MachineOverlay();
}

/// The phone's own say over the hub's lists: a name it prefers, chats and machines it does not want to see, and what new chats
/// start with per machine. Kept on the phone (the hub may not allow renaming or removing), and emptied on sign-out.
class LocalOverlay {
  const LocalOverlay();

  static const _key = 'escanor.hub.overlay.v1';

  static String _sid(String vmId, String sessionId) => '$vmId::$sessionId';

  /// Bumped on every change, so a list can tell whether what it shows from here may have changed.
  static int version = 0;

  // Every chat row reads its name and hidden flag from here on every build: decode the stored JSON once per change, not per read.
  static String? _cachedRaw;
  static Map<String, dynamic> _cached = const {};

  Map<String, dynamic> _decoded() {
    try {
      final raw = Storage.instance.getString(_key);
      if (identical(raw, _cachedRaw) || raw == _cachedRaw) return _cached;
      final v = raw == null ? null : jsonDecode(raw);
      _cachedRaw = raw;
      _cached = v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
      return _cached;
    } catch (_) {
      return const {};
    }
  }

  /// A copy, for changing.
  Map<String, dynamic> _all() => Map<String, dynamic>.from(_decoded());

  /// One section as stored, for reading only.
  Map<dynamic, dynamic> _read(String name) {
    final v = _decoded()[name];
    return v is Map ? v : const {};
  }

  void _save(Map<String, dynamic> all) {
    version++;
    try {
      Storage.instance.setString(_key, all.isEmpty ? null : jsonEncode(all));
    } catch (_) {}
  }

  Map<String, dynamic> _section(Map<String, dynamic> all, String name) => all[name] is Map ? Map<String, dynamic>.from(all[name] as Map) : <String, dynamic>{};

  SessionOverlay session(String vmId, String sessionId) => SessionOverlay.from(_read('s')[_sid(vmId, sessionId)]);

  void setSession(String vmId, String sessionId, SessionOverlay o) {
    final all = _all();
    final s = _section(all, 's');
    if (o.isEmpty) {
      s.remove(_sid(vmId, sessionId));
    } else {
      s[_sid(vmId, sessionId)] = o.toJson();
    }
    s.isEmpty ? all.remove('s') : all['s'] = s;
    _save(all);
  }

  MachineOverlay machine(String vmId) => MachineOverlay.from(_read('m')[vmId]);

  void setMachine(String vmId, MachineOverlay o) {
    final all = _all();
    final m = _section(all, 'm');
    o.isEmpty ? m.remove(vmId) : m[vmId] = o.toJson();
    m.isEmpty ? all.remove('m') : all['m'] = m;
    _save(all);
  }

  /// Chats of one machine that are hidden on this phone.
  List<String> hiddenSessions(String vmId) {
    final prefix = '$vmId::';
    final s = _read('s');
    return [
      for (final e in s.entries)
        if (e.key.startsWith(prefix) && SessionOverlay.from(e.value).hidden) e.key.substring(prefix.length),
    ];
  }

  void clear() {
    version++;
    try {
      Storage.instance.remove(_key);
    } catch (_) {}
  }
}
