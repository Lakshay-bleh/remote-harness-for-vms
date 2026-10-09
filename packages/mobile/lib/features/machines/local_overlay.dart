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

  Map<String, dynamic> _all() {
    try {
      final raw = Storage.instance.getString(_key);
      final v = raw == null ? null : jsonDecode(raw);
      return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  void _save(Map<String, dynamic> all) {
    try {
      Storage.instance.setString(_key, all.isEmpty ? null : jsonEncode(all));
    } catch (_) {}
  }

  Map<String, dynamic> _section(Map<String, dynamic> all, String name) => all[name] is Map ? Map<String, dynamic>.from(all[name] as Map) : <String, dynamic>{};

  SessionOverlay session(String vmId, String sessionId) => SessionOverlay.from(_section(_all(), 's')[_sid(vmId, sessionId)]);

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

  MachineOverlay machine(String vmId) => MachineOverlay.from(_section(_all(), 'm')[vmId]);

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
    final s = _section(_all(), 's');
    return [
      for (final e in s.entries)
        if (e.key.startsWith(prefix) && SessionOverlay.from(e.value).hidden) e.key.substring(prefix.length),
    ];
  }

  void clear() {
    try {
      Storage.instance.remove(_key);
    } catch (_) {}
  }
}
