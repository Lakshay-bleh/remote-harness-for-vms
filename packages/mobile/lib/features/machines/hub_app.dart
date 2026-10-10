import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'chat_view.dart';
import 'hub_login.dart';
import 'hub_scope.dart';
import 'hub_store.dart';
import 'managed.dart';
import 'sidebar.dart';

/// Wide enough to show the machines and a chat side by side.
const hubWideWidth = 768.0;

/// The Remote Harness: Claude Code sessions on the person's machines, through a hub (HubApp in App.tsx).
/// Signed out of the hub: its sign-in. On a phone: the machines list, and a chat opens as a step inside it (the back
/// button returns to the list). Wide: the list and the chat side by side.
class HubApp extends StatefulWidget {
  const HubApp({super.key, this.embedded = false, this.managed, this.onBack});

  /// Inside the signed-in app (the Machines tab) rather than on its own.
  final bool embedded;

  /// Escanor's hosted hub, when that is what this shows.
  final ManagedHub? managed;

  /// "Back to Escanor" on the stand-alone hub's sign-in.
  final VoidCallback? onBack;

  @override
  State<HubApp> createState() => _HubAppState();
}

class _HubAppState extends State<HubApp> {
  final store = HubStore.instance;

  StreamSubscription<ChatTarget>? _opens;
  BuildContext? _listContext;

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
    // A notification or banner asked for a chat: show it (once this screen is laid out, if it was not yet).
    _opens = store.openRequests.listen((_) => _showRequested());
    WidgetsBinding.instance.addPostFrameCallback((_) => _showRequested());
  }

  @override
  void dispose() {
    _opens?.cancel();
    store.removeListener(_changed);
    super.dispose();
  }

  void _showRequested() {
    if (!mounted || !_authed) return;
    if (store.takePendingOpen() == null) return;
    final ctx = _listContext;
    // Side by side (no list context) or a chat page already up: the selected chat is the one shown.
    if (ctx == null || !ctx.mounted || HubChatPage.open > 0) return;
    _openChat(ctx);
  }

  bool _authed = HubStore.instance.state.authed;

  void _changed() {
    if (store.state.authed != _authed && mounted) setState(() => _authed = store.state.authed);
  }

  void _openChat(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= hubWideWidth) return; // already side by side
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HubScope(embedded: widget.embedded, managed: widget.managed, child: const HubChatPage()),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return HubScope(
      embedded: widget.embedded,
      managed: widget.managed,
      child: Builder(builder: (context) {
        if (!_authed) return HubLogin(onBack: widget.onBack);
        final c = context.c;
        return LayoutBuilder(builder: (context, box) {
          if (box.maxWidth >= hubWideWidth) {
            _listContext = null;
            return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                width: 320,
                decoration: BoxDecoration(border: Border(right: BorderSide(color: c.hairline))),
                child: HubSidebar(onSelectSession: () {}),
              ),
              const Expanded(child: ChatView()),
            ]);
          }
          _listContext = context;
          return HubSidebar(onSelectSession: () => _openChat(context));
        });
      }),
    );
  }
}

/// A machine chat as its own page on a phone. Steps back to the list when the hub signs out, or when the screen
/// becomes wide enough to show both.
class HubChatPage extends StatefulWidget {
  const HubChatPage({super.key});

  /// How many chat pages are on screen (a requested chat is shown in the one that is, rather than stacking another).
  static int open = 0;
  @override
  State<HubChatPage> createState() => _HubChatPageState();
}

class _HubChatPageState extends State<HubChatPage> {
  final store = HubStore.instance;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    HubChatPage.open++;
    store.addListener(_changed);
  }

  @override
  void dispose() {
    HubChatPage.open--;
    store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!store.state.authed) _leave();
  }

  void _leave() {
    if (_leaving || !mounted) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= hubWideWidth) _leave();
    final embedded = HubScope.embeddedOf(context);
    final chat = ChatView(onBack: () => Navigator.of(context).maybePop());
    if (embedded) return chat; // the tab already sits inside the app's safe area, above the tab bar
    return Scaffold(backgroundColor: context.c.canvas, body: SafeArea(child: chat));
  }
}
