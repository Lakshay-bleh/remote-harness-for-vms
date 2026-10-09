import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage.dart';
import 'chat_meta.dart';

/// The live chat organisation: one value for every screen, saved on this phone (best effort).
class ChatMetaNotifier extends Notifier<ChatMeta> {
  @override
  ChatMeta build() {
    try {
      return parseMeta(Storage.instance.getString(chatMetaKey));
    } catch (_) {
      return emptyMeta;
    }
  }

  void update(ChatMeta Function(ChatMeta) change) {
    final next = change(state);
    if (identical(next, state) || next == state) return;
    state = next;
    try {
      Storage.instance.setString(chatMetaKey, jsonEncode(next.toJson()));
    } catch (_) {
      // not saved, but it still applies until the app is closed
    }
  }

  /// Forget every pin, name and archive (Settings > Developer > Reset app data).
  void reset() {
    state = emptyMeta;
    try {
      Storage.instance.remove(chatMetaKey);
    } catch (_) {}
  }
}

final chatMetaProvider = NotifierProvider<ChatMetaNotifier, ChatMeta>(ChatMetaNotifier.new);

/// Forget the pinned, renamed and archived chats on this phone, outside a widget (the Developer page's "Reset app data").
/// Widgets should prefer `ref.read(chatMetaProvider.notifier).reset()` so open screens update at once.
void resetChatMeta() {
  try {
    Storage.instance.remove(chatMetaKey);
  } catch (_) {}
}
