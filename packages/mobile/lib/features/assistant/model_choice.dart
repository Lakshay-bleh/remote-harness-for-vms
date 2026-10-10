import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage.dart';
import 'chat_state.dart';

const _key = 'escanor.assistant.model.v1';

/// Which model Escanor AI answers with on this phone: Auto (it picks for each message) or one model, by id. Kept on this phone,
/// like the model chosen for a chat on a machine.
class AssistantModelNotifier extends Notifier<String> {
  @override
  String build() {
    try {
      final v = Storage.instance.getString(_key);
      return v == null || v.isEmpty ? autoModel : v;
    } catch (_) {
      return autoModel;
    }
  }

  void choose(String id) {
    state = id.isEmpty ? autoModel : id;
    try {
      Storage.instance.setString(_key, state == autoModel ? null : state);
    } catch (_) {
      // not saved, but it still applies until the app is closed
    }
  }
}

final assistantModelProvider = NotifierProvider<AssistantModelNotifier, String>(AssistantModelNotifier.new);

/// The picker's choices: Auto, then every model that can answer now. A chosen model that is not available any more stays listed,
/// so the chip never shows a bare id.
List<({String value, String label})> modelOptions(AssistantModels? models, String chosen) {
  final usable = models?.usable ?? const <AssistantModel>[];
  final out = <({String value, String label})>[(value: autoModel, label: 'Auto')];
  for (final m in usable) {
    out.add((value: m.id, label: m.label));
  }
  if (chosen != autoModel && !out.any((o) => o.value == chosen)) {
    String? label;
    for (final m in models?.models ?? const <AssistantModel>[]) {
      if (m.id == chosen) label = '${m.label} (unavailable)';
    }
    out.add((value: chosen, label: label ?? chosen.split(':').last));
  }
  return out;
}
