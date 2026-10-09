import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/cache.dart';
import '../../core/session.dart';
import 'assistant_api.dart';
import 'chat_meta.dart';
import 'chat_meta_store.dart';
import 'chat_state.dart';

/// The person's assistant chats, shared by the chat drawer, the sidebar and the chat screen. Loaded while signed in, again
/// every 30 seconds and whenever the app comes back to the foreground; remembered so the drawer is never empty on opening.
class ConversationsState {
  const ConversationsState({this.list = const [], this.loaded = false, this.error});
  final List<AssistantConversation> list;

  /// A real answer (from the server or the phone's copy) is in [list].
  final bool loaded;
  final String? error;

  List<ChatItem> get chats => [for (final c in list) ChatItem(id: c.id, title: c.title, createdAt: c.createdAt, updatedAt: c.updatedAt)];
}

const _cache = CachePolicy('ai.conversations', ttl: Duration.zero, maxAge: Duration(days: 30));
const conversationsEvery = Duration(seconds: 30);

class ConversationsNotifier extends Notifier<ConversationsState> {
  Timer? _timer;
  AppLifecycleListener? _life;
  int _generation = 0;

  @override
  ConversationsState build() {
    final signedIn = ref.watch(sessionProvider.select((s) => s.status == SessionStatus.signedIn));
    final userId = ref.watch(sessionProvider.select((s) => s.user?.id));
    ref.onDispose(() {
      _timer?.cancel();
      _life?.dispose();
      _life = null;
      _generation++;
    });
    if (!signedIn || userId == null) return const ConversationsState();
    try {
      _life = AppLifecycleListener(onResume: reload);
    } catch (_) {
      // no binding (pure tests)
    }
    var start = const ConversationsState();
    final hit = readCache(_cache);
    if (hit != null && hit.value is List) {
      try {
        start = ConversationsState(list: [for (final c in hit.value as List) AssistantConversation.fromJson(c)], loaded: true);
      } catch (_) {}
    }
    Future.microtask(reload);
    return start;
  }

  /// Ask the server again now.
  Future<void> reload() async {
    _timer?.cancel();
    final gen = ++_generation;
    try {
      final list = await api.assistantConversations();
      if (gen != _generation) return;
      writeCache(_cache.key, [for (final c in list) c.toJson()]);
      state = ConversationsState(list: list, loaded: true);
      // Forget organisation for chats that no longer exist; only from a real, non-empty list so a bad load never wipes it.
      if (list.isNotEmpty) ref.read(chatMetaProvider.notifier).update((m) => prune(m, [for (final c in list) c.id]));
    } on SessionEnded {
      return;
    } catch (e) {
      if (gen != _generation) return;
      state = ConversationsState(list: state.list, loaded: state.loaded, error: errorText(e));
    }
    if (gen == _generation) _timer = Timer(conversationsEvery, reload);
  }

  /// Delete a chat on the server, and drop it from the list at once. A chat still working is stopped first (servers that do not
  /// stop it themselves on delete would otherwise carry on with a conversation nobody can see).
  Future<void> remove(String id) async {
    try {
      await api.assistantStop(id);
    } catch (_) {
      // nothing running, or it cannot be stopped: delete it anyway
    }
    try {
      await api.assistantRemove(id);
      state = ConversationsState(list: state.list.where((c) => c.id != id).toList(), loaded: state.loaded);
    } finally {
      unawaited(reload());
    }
  }
}

final conversationsProvider = NotifierProvider<ConversationsNotifier, ConversationsState>(ConversationsNotifier.new);

/// Load the chat list again now (after voice mode sent a message into a new chat, for instance).
Future<void> reloadConversations(WidgetRef ref) => ref.read(conversationsProvider.notifier).reload();

/// What to call a chat: the person's own name for it, else the server's title.
String? chatName(String? id, ChatMeta meta, List<AssistantConversation> list) {
  if (id == null) return null;
  return meta.titles[id] ?? list.where((c) => c.id == id).firstOrNull?.title;
}
