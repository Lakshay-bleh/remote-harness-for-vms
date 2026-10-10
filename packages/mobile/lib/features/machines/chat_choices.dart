import 'dart:convert';

import '../../core/storage.dart';
import 'protocol.dart';

/// What was picked for one chat: its permission mode, model and effort.
class SavedChoices {
  const SavedChoices({this.mode = 'default', this.model = '', this.effort = ''});
  final String mode;
  final String model;
  final String effort;

  Map<String, String> toJson() => {'mode': mode, 'model': model, 'effort': effort};

  /// As it goes with a message to the hub (packages/shared parseRunChoices): '' model and null effort are the defaults.
  Map<String, Object?> toRunJson() => {
        if (isPermissionMode(mode)) 'permissionMode': mode,
        'model': model,
        'effort': isEffortLevel(effort) ? effort : null,
      };

  static SavedChoices? tryParse(Object? j) {
    if (j is! Map) return null;
    final mode = j['mode'];
    final effort = j['effort'];
    return SavedChoices(
      mode: isPermissionMode(mode) ? mode as String : 'default',
      model: j['model'] is String ? j['model'] as String : '',
      effort: isEffortLevel(effort) ? effort as String : '',
    );
  }

  @override
  bool operator ==(Object other) => other is SavedChoices && other.mode == mode && other.model == model && other.effort == effort;

  @override
  int get hashCode => Object.hash(mode, model, effort);
}

/// The mode, model and effort of each chat, kept on the phone. The hub only knows them while the chat's run is alive, so
/// without this a chat opened again would show (and run with) the defaults instead of what the person chose.
class ChatChoicesStore {
  const ChatChoicesStore();

  static const _key = 'escanor.hub.choices.v1';
  static const _max = 300;

  static String _id(String vmId, String sessionId) => '$vmId::$sessionId';

  Map<String, dynamic> _all() {
    try {
      final raw = Storage.instance.getString(_key);
      final v = raw == null ? null : jsonDecode(raw);
      return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  SavedChoices? read(String vmId, String sessionId) => SavedChoices.tryParse(_all()[_id(vmId, sessionId)]);

  void write(String vmId, String sessionId, SavedChoices choices) {
    try {
      final all = _all();
      final id = _id(vmId, sessionId);
      all.remove(id); // re-insert last: the oldest are dropped first
      all[id] = choices.toJson();
      while (all.length > _max) {
        all.remove(all.keys.first);
      }
      Storage.instance.setString(_key, jsonEncode(all));
    } catch (_) {
      // storage unavailable: the choice still holds for this run of the app
    }
  }

  /// Signing out forgets them.
  void clear() {
    try {
      Storage.instance.remove(_key);
    } catch (_) {}
  }
}
