import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/nav.dart';
import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import 'chat_list.dart';
import 'conversations.dart';

/// The phone's chat drawer (and the chat column of the wide layout): new chat and your chats, with a menu on each to pin,
/// rename, archive or delete. The places themselves are on the tab bar / rail.
class ChatDrawer extends ConsumerWidget {
  const ChatDrawer({super.key, this.inSidebar = false});
  final bool inSidebar;

  void _close(BuildContext context) {
    if (!inSidebar) Scaffold.maybeOf(context)?.closeDrawer();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, String id, String name) async {
    final ok = await confirm(context, title: 'Delete “$name”?', message: 'This cannot be undone.', ok: 'Delete', danger: true);
    if (!ok) return;
    try {
      await ref.read(conversationsProvider.notifier).remove(id);
      if (ref.read(navProvider).conversationId == id) ref.read(navProvider.notifier).setConversation(null);
    } on SessionEnded {
      return;
    } catch (e) {
      if (context.mounted) toast(context, 'Could not delete “$name”. ${errorText(e, 'Try again.')}');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final nav = ref.watch(navProvider);
    final chats = ref.watch(conversationsProvider);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(20, inSidebar ? 16 : 20, 8, 16),
        child: Row(children: [
          if (!inSidebar) ...[const Logo(size: 34), const SizedBox(width: 12)],
          Expanded(child: Text('Chats', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.ink))),
          if (!inSidebar)
            IconButton(tooltip: 'Close chats', onPressed: () => _close(context), icon: Icon(Icons.close_rounded, size: 20, color: c.muted)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Material(
          color: Colors.transparent,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              haptic();
              ref.read(navProvider.notifier).openChat(null);
              _close(context);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                  child: Icon(Icons.edit_rounded, size: 14, color: c.onPrimary),
                ),
                const SizedBox(width: 12),
                Text('New chat', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.ink)),
              ]),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Expanded(
        child: ChatList(
          chats: chats.chats,
          activeId: nav.tab == AppTab.assistant ? nav.conversationId : null,
          hint: true,
          onOpen: (id) {
            haptic();
            ref.read(navProvider.notifier).openChat(id);
            _close(context);
          },
          onDelete: (id, name) => _delete(context, ref, id, name),
        ),
      ),
    ]);
  }
}
