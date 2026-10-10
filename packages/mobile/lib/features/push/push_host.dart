import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/nav.dart';
import '../../core/theme.dart';
import '../machines/hub_store.dart';
import 'push_service.dart';

/// The app tab a notification points to.
AppTab tabForDest(PushDest dest) => tabFromName(dest.name);

/// Push: registers this phone, takes the person where a tapped notification points, and shows one that
/// arrives while the app is open as a banner.
class PushHost extends ConsumerStatefulWidget {
  const PushHost({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<PushHost> createState() => _PushHostState();
}

class _PushHostState extends ConsumerState<PushHost> {
  VoidCallback? _stop;
  StreamSubscription<HubNotice>? _notices;
  ForegroundPush? _banner;
  Timer? _hide;

  /// Prompts already shown from the machines' own connection, so the push about the same one is not shown again.
  final Set<String> _shownPrompts = {};

  @override
  void initState() {
    super.initState();
    // Register this phone again if they already allowed it (Android or Apple may have changed the address). Never asks.
    resumePush().catchError((_) {});
    _stop = listenPush(_go, _show);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        // Claude on a machine asking for permission: a banner straight from the hub's connection, push or no push.
        _notices = HubStore.instance.notices.listen((n) {
          if (n.requestId != null) _shownPrompts.add(n.requestId!);
          _show(ForegroundPush(
            title: n.title,
            body: n.body,
            dest: PushDest.machines,
            data: {'kind': 'machine_chats', 'vm_id': n.vmId, 'session_id': n.sessionId, 'request_id': n.requestId ?? ''},
          ));
        });
      } catch (_) {}
    });
  }

  void _go(PushDest dest, [Map<String, dynamic> data = const {}]) {
    if (!mounted) return;
    final tab = tabForDest(dest);
    final chat = machineChatFor(data);
    if (chat != null) machinesSegment.value = 0; // servers, where machine chats are
    tabNavigatorKeys[tab]?.currentState?.popUntil((r) => r.isFirst);
    final nav = ref.read(navProvider.notifier);
    if (ref.read(navProvider).tab != tab) nav.go(tab);
    if (chat != null) unawaited(HubStore.instance.openChat(chat.vmId, chat.sessionId).catchError((_) {}));
  }

  /// Is this about the machine chat the person is looking at right now? Then the chat itself shows it.
  bool _onScreen(Map<String, dynamic> data) {
    final chat = machineChatFor(data);
    if (chat == null || !HubStore.created) return false;
    return ref.read(navProvider).tab == AppTab.machines && HubStore.instance.viewingSessionId == chat.sessionId;
  }

  /// Android and iOS show nothing themselves for a message that arrives while the app is open: show it here, for six seconds.
  void _show(ForegroundPush n) {
    if (!mounted) return;
    if (_onScreen(n.data)) return;
    final prompt = n.data['request_id'];
    if (n.data['event'] == 'approval' && prompt is String) {
      if (_shownPrompts.contains(prompt)) return; // already shown from the hub's connection
      // Already answered (a chat that works on its own answers its prompts while the app is open).
      if (HubStore.created && HubStore.instance.state.resolvedPermissionIds.contains(prompt)) return;
    }
    _hide?.cancel();
    setState(() => _banner = n);
    _hide = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _banner = null);
    });
  }

  @override
  void dispose() {
    _stop?.call();
    _notices?.cancel();
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = _banner;
    return Stack(fit: StackFit.expand, children: [
      widget.child,
      if (b != null)
        Positioned(
          left: 12,
          right: 12,
          top: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: PushBanner(
                    title: b.title,
                    body: b.body,
                    onTap: () {
                      _hide?.cancel();
                      setState(() => _banner = null);
                      _go(b.dest, b.data);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// The banner for a notification that arrived while the app was open. Tapping it goes where it points.
class PushBanner extends StatelessWidget {
  const PushBanner({super.key, required this.title, required this.body, required this.onTap});
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      liveRegion: true,
      button: true,
      child: Material(
        color: c.surfaceCard,
        elevation: 8,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg), side: BorderSide(color: c.lineStrong)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.ink)),
              if (body.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(body, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.body)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
